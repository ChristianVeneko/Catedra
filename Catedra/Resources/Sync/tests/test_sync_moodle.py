import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import sync_moodle as sm  # noqa: E402


class FakeResponse:
    def __init__(self, body=b"\x89PNG", content_type="image/png", status=200):
        self.body, self.headers, self.status = body, {"Content-Type": content_type}, status

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def raise_for_status(self):
        if self.status >= 400:
            raise RuntimeError(f"HTTP {self.status}")

    def iter_content(self, size):
        yield self.body


class FixMojibakeTests(unittest.TestCase):
    def test_double_encoded_with_c1_control(self):
        self.assertEqual(sm.fix_mojibake("vÃ\u0083Â­deo"), "vídeo")

    def test_double_encoded_when_control_char_was_lost(self):
        self.assertEqual(sm.fix_mojibake("vÃÂ­deo"), "vídeo")

    def test_single_encoded(self):
        self.assertEqual(sm.fix_mojibake("informaciÃ³n y pÃ¡gina"), "información y página")

    def test_triple_encoded(self):
        text = "í"
        for _ in range(3):
            text = text.encode("utf-8").decode("latin-1")
        self.assertEqual(sm.fix_mojibake(f"v{text}deo"), "vídeo")

    def test_correct_text_unchanged(self):
        for text in ("vídeo", "Ñandú", "Ángel Ñoño", "plain ascii", "", "emoji 😀 ok"):
            self.assertEqual(sm.fix_mojibake(text), text)

    def test_only_broken_run_is_fixed(self):
        self.assertEqual(sm.fix_mojibake("Ñandú y vÃ©deo 😀"), "Ñandú y véeo 😀".replace("véeo", "vÃ©deo".encode("latin-1").decode("utf-8")))

    def test_html_to_text_applies_fix(self):
        self.assertEqual(sm.html_to_text("<p>vÃ\u0083Â­deo</p>"), "vídeo")


class ImageFilenameTests(unittest.TestCase):
    def test_keeps_extension_and_drops_query(self):
        url = "https://saia.uft.edu.ve/pluginfile.php/1/mod_assign/intro/0/blobid0.jpg?forcedownload=1"
        self.assertEqual(sm.image_filename(url), "blobid0.jpg")

    def test_sanitises_unsafe_characters(self):
        self.assertEqual(sm.image_filename("https://x.org/a%20b/we ird:name.PNG"), "we-ird-name.png")

    def test_missing_extension_gets_placeholder(self):
        self.assertTrue(sm.image_filename("https://x.org/render?id=3").endswith(".img"))

    def test_collision_adds_url_hash(self):
        taken = {}
        a = sm.image_filename("https://a.org/x/pic.jpg", taken)
        b = sm.image_filename("https://b.org/y/pic.jpg", taken)
        again = sm.image_filename("https://a.org/x/pic.jpg", taken)
        self.assertEqual(a, "pic.jpg")
        self.assertNotEqual(a, b)
        self.assertTrue(b.startswith("pic-") and b.endswith(".jpg"))
        self.assertEqual(again, a)


class ImageRewriteTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        sm.TOKEN = "SECRET"
        self.addCleanup(self.tmp.cleanup)
        self.addCleanup(setattr, sm, "TOKEN", "")

    def test_saia_image_downloaded_with_token_and_rewritten(self):
        url = "https://saia.uft.edu.ve/pluginfile.php/9/mod_assign/intro/blobid0.jpg"
        with mock.patch.object(sm.session, "get", return_value=FakeResponse()) as get:
            md = sm.html_to_text(f'<p>Hola <img src="{url}" alt="foto"></p>', sm.ImageSink(self.dir, True))
        self.assertIn("![foto](_imagenes/blobid0.jpg)", md)
        self.assertTrue((self.dir / "_imagenes" / "blobid0.jpg").exists())
        called = get.call_args[0][0]
        self.assertIn("/webservice/pluginfile.php", called)
        self.assertTrue(called.endswith("token=SECRET"))

    def test_external_image_has_no_token(self):
        with mock.patch.object(sm.session, "get", return_value=FakeResponse()) as get:
            md = sm.html_to_text('<img src="https://cdn.example.com/y.jpg" alt="b">', sm.ImageSink(self.dir, True))
        self.assertEqual(md, "![b](_imagenes/y.jpg)")
        self.assertNotIn("token", get.call_args[0][0])

    def test_failure_keeps_remote_url(self):
        with mock.patch.object(sm.session, "get", side_effect=RuntimeError("boom SECRET")):
            md = sm.html_to_text('<img src="https://cdn.example.com/y.jpg" alt="b">', sm.ImageSink(self.dir, True))
        self.assertEqual(md, "![b](https://cdn.example.com/y.jpg)")
        self.assertFalse((self.dir / "_imagenes" / "y.jpg").exists())

    def test_html_error_page_is_not_saved(self):
        with mock.patch.object(sm.session, "get", return_value=FakeResponse(b"<html>", "text/html")):
            md = sm.html_to_text('<img src="https://cdn.example.com/y.jpg">', sm.ImageSink(self.dir, True))
        self.assertEqual(md, "![](https://cdn.example.com/y.jpg)")

    def test_existing_file_is_not_downloaded_again(self):
        (self.dir / "_imagenes").mkdir()
        (self.dir / "_imagenes" / "y.jpg").write_bytes(b"x")
        with mock.patch.object(sm.session, "get") as get:
            md = sm.html_to_text('<img src="https://cdn.example.com/y.jpg" alt="b">', sm.ImageSink(self.dir, True))
        get.assert_not_called()
        self.assertEqual(md, "![b](_imagenes/y.jpg)")

    def test_no_files_keeps_remote_but_reuses_local(self):
        with mock.patch.object(sm.session, "get") as get:
            md = sm.html_to_text('<img src="https://cdn.example.com/y.jpg" alt="b">', sm.ImageSink(self.dir, False))
            self.assertEqual(md, "![b](https://cdn.example.com/y.jpg)")
            (self.dir / "_imagenes").mkdir()
            (self.dir / "_imagenes" / "y.jpg").write_bytes(b"x")
            md = sm.html_to_text('<img src="https://cdn.example.com/y.jpg" alt="b">', sm.ImageSink(self.dir, False))
            self.assertEqual(md, "![b](_imagenes/y.jpg)")
        get.assert_not_called()

    def test_two_consecutive_images_and_name_collision(self):
        html = '<img src="https://a.org/pic.jpg" alt="a"><img src="https://b.org/pic.jpg" alt="b">'
        with mock.patch.object(sm.session, "get", return_value=FakeResponse()):
            md = sm.html_to_text(html, sm.ImageSink(self.dir, True))
        first, second = md.split(")![")
        self.assertTrue(first.endswith("(_imagenes/pic.jpg"))
        self.assertNotIn("(_imagenes/pic.jpg", second)
        self.assertEqual(len(list((self.dir / "_imagenes").iterdir())), 2)

    def test_relative_source_resolved_against_html_folder(self):
        sub = self.dir / "chapter"
        sub.mkdir()
        (sub / "fig.png").write_bytes(b"x")
        md = sm.html_to_text('<img src="fig.png" alt="f">', sm.ImageSink(self.dir, False, base=sub))
        self.assertEqual(md, "![f](chapter/fig.png)")

    def test_data_uri_and_no_sink_untouched(self):
        self.assertEqual(sm.html_to_text('<img src="data:image/png;base64,AAA" alt="d">', sm.ImageSink(self.dir, True)),
                         "![d](data:image/png;base64,AAA)")
        self.assertEqual(sm.html_to_text('<img src="https://x.org/a.jpg" alt="d">'), "![d](https://x.org/a.jpg)")

    def test_error_messages_never_contain_the_token(self):
        self.assertNotIn("SECRET", sm.redact("failed https://x/?token=SECRET"))


class RootTests(unittest.TestCase):
    def test_set_root_derives_data(self):
        old = (sm.ROOT, sm.DATA)
        self.addCleanup(lambda: (setattr(sm, "ROOT", old[0]), setattr(sm, "DATA", old[1])))
        with tempfile.TemporaryDirectory() as tmp:
            sm.set_root(tmp)
            self.assertEqual(sm.ROOT, Path(tmp).resolve())
            self.assertEqual(sm.DATA, Path(tmp).resolve() / "_sistema" / "data")


if __name__ == "__main__":
    unittest.main()


# ---------------------------------------------------------------- phase 4: richer data

GRADE_RES = {"usergrades": [{"gradeitems": [
    {"itemname": "Tarea 1", "itemtype": "mod", "itemmodule": "assign", "cmid": 77, "graderaw": 8.5,
     "gradeformatted": "8,50", "grademin": 0, "grademax": 10, "weightraw": 20.0,
     "percentageformatted": "85 %", "feedback": "<p>Buen <b>trabajo</b></p>",
     "gradedatesubmitted": 100, "gradedategraded": 200},
    {"itemname": "Quiz &amp; co", "itemtype": "mod", "itemmodule": "quiz", "cmid": "88", "graderaw": None,
     "grademax": 20, "percentageformatted": "-"},
    {"itemname": None, "itemtype": "course", "graderaw": 8.5, "grademax": 100, "percentageformatted": "8.5 %"},
]}]}


class DataDirCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.old = (sm.ROOT, sm.DATA)
        self.addCleanup(lambda: setattr(sm, "ROOT", self.old[0]) or setattr(sm, "DATA", self.old[1]))
        sm.set_root(self.tmp.name)


class GradesTests(DataDirCase):
    def test_normalize_splits_total_and_strips_feedback(self):
        out = sm.normalize_grades(5, GRADE_RES)
        self.assertEqual(out["courseid"], 5)
        self.assertEqual([i["itemname"] for i in out["items"]], ["Tarea 1", "Quiz & co"])
        first = out["items"][0]
        self.assertEqual((first["graderaw"], first["grademax"], first["weightraw"], first["cmid"]), (8.5, 10, 20.0, 77))
        self.assertEqual(first["feedback"], "Buen trabajo")
        self.assertEqual((first["gradedatesubmitted"], first["gradedategraded"]), (100, 200))
        self.assertIsNone(out["items"][1]["graderaw"])
        self.assertIsNone(out["items"][1]["weightraw"])
        self.assertEqual(out["items"][1]["cmid"], 88)
        self.assertEqual(out["total"]["graderaw"], 8.5)

    def test_grade_formatted_drops_icon_markup(self):
        icon = '<i class="icon fa fa-xmark text-danger fa-fw inline" title="Suspenso" role="img" aria-label="Suspenso"></i>2,00'
        row = sm.normalize_grade_item({"itemtype": "mod", "gradeformatted": icon})
        self.assertEqual(row["gradeformatted"], "2,00")
        self.assertIn("| 2,00 |", sm.grades_table({"id": 5}, 1, {"usergrades": [{"gradeitems": [{"itemname": "Q", "gradeformatted": icon}]}]}))

    def test_write_grades_json_and_empty(self):
        sm.write_grades_json({"id": 5}, GRADE_RES)
        data = json.loads((sm.DATA / "grades_5.json").read_text())
        self.assertEqual(len(data["items"]), 2)
        sm.write_grades_json({"id": 6}, {})
        self.assertFalse((sm.DATA / "grades_6.json").exists())

    def test_markdown_table_unchanged_and_single_call(self):
        with mock.patch.object(sm, "ws", return_value=GRADE_RES) as m:
            table = sm.grades_table({"id": 5}, 1)
        self.assertEqual(m.call_count, 1)
        self.assertTrue(table.startswith("| Item | Nota | Max | % |"))
        self.assertIn("| Quiz & co | - | 20 | - |", table)
        self.assertIn("| Total del curso | - | 100 | 8.5 % |", table)
        with mock.patch.object(sm, "ws") as m:
            sm.grades_table({"id": 5}, 1, GRADE_RES)
        m.assert_not_called()

    def test_grades_by_cmid_excludes_total(self):
        self.assertEqual(set(sm.grades_by_cmid(GRADE_RES)), {77, 88})


class ActivityExtrasTests(DataDirCase):
    def test_extras_full(self):
        item = sm.grades_by_cmid(GRADE_RES)[77]
        extra = sm.activity_extras(10, 30, "77", item, "")
        self.assertEqual(extra, {"opens": 10, "cutoff": 30, "cmid": 77, "gradeRaw": 8.5, "gradeMax": 10,
                                 "gradedAt": 200, "feedback": "Buen trabajo"})

    def test_extras_omit_missing(self):
        self.assertEqual(sm.activity_extras(0, None, 5, None, ""), {"cmid": 5})
        self.assertEqual(sm.activity_extras(None, None, None, None, ""), {})

    def test_submission_feedback_wins_over_grade_feedback(self):
        item = sm.grades_by_cmid(GRADE_RES)[77]
        self.assertEqual(sm.activity_extras(0, 0, 77, item, "Del docente")["feedback"], "Del docente")

    def test_extract_feedback_comments_only(self):
        st = {"feedback": {"plugins": [
            {"type": "comments", "editorfields": [{"name": "comments", "text": "<p>Revisa la <i>sec. 2</i></p>"}]},
            {"type": "editpdf", "fileareas": [{"area": "download", "files": [{"filename": "a.pdf"}]}]}]}}
        self.assertEqual(sm.extract_feedback(st), "Revisa la sec. 2")
        self.assertEqual(sm.extract_feedback({}), "")
        self.assertEqual(sm.extract_feedback(None), "")

    def test_sync_assignments_adds_fields_and_keeps_old(self):
        a = {"id": 1, "cmid": 77, "name": "Tarea 1", "duedate": 500, "allowsubmissionsfromdate": 100,
             "cutoffdate": 900, "grade": 10, "configs": [], "intro": "x"}
        course = {"key": "Control", "fullname": "Control", "id": 5}
        st = {"lastattempt": {"submission": {"status": "submitted"}},
              "feedback": {"gradefordisplay": "8,50 / 10", "plugins": [
                  {"type": "comments", "editorfields": [{"text": "Bien"}]}]}}
        with mock.patch.object(sm, "ws", return_value=st):
            items = sm.sync_assignments(course, sm.ROOT / "c", [a], False, sm.grades_by_cmid(GRADE_RES))
        it = items[0]
        for key in ("course", "type", "name", "due", "status", "grade", "url", "folder"):
            self.assertIn(key, it)
        self.assertEqual((it["opens"], it["cutoff"], it["cmid"], it["gradeRaw"], it["gradeMax"], it["feedback"]),
                         (100, 900, 77, 8.5, 10, "Bien"))

    def test_sync_assignments_without_grades_has_no_new_grade_keys(self):
        a = {"id": 1, "cmid": 77, "name": "T", "duedate": 0, "configs": []}
        with mock.patch.object(sm, "ws", return_value={}):
            it = sm.sync_assignments({"key": "k", "fullname": "k", "id": 1}, sm.ROOT / "c", [a], False)[0]
        self.assertEqual(set(it) - {"course", "type", "name", "due", "status", "grade", "url", "folder"}, {"cmid"})


class CalendarTests(DataDirCase):
    EVENTS = {"events": [
        {"id": 1, "name": "T1 &amp; due", "course": {"id": 5, "fullname": "Control"}, "eventtype": "due",
         "modulename": "assign", "timestart": 999, "timeduration": 0,
         "url": "https://saia.uft.edu.ve/mod/assign/view.php?id=77&action=editsubmission"},
        {"id": 2, "name": "Sin curso", "courseid": 6, "timestart": "1000"},
    ]}

    def test_normalize(self):
        ev = sm.normalize_events(self.EVENTS, {6: "Otra"})
        self.assertEqual(ev[0]["name"], "T1 & due")
        self.assertEqual((ev[0]["courseid"], ev[0]["course"], ev[0]["cmid"]), (5, "Control", 77))
        self.assertEqual((ev[1]["course"], ev[1]["timestart"], ev[1]["cmid"], ev[1]["url"]), ("Otra", 1000, None, ""))

    def test_sync_calendar_writes_and_requests_week_back(self):
        with mock.patch.object(sm, "ws", return_value=self.EVENTS) as m:
            out = sm.sync_calendar([{"id": 6, "fullname": "Otra"}])
        self.assertEqual(len(out), 2)
        self.assertEqual(m.call_args.kwargs["timesortfrom"], sm.NOW - 7 * 86400)
        # Moodle rejects limitnum outside 1..50 ("Limit must be between 1 and 50").
        self.assertTrue(1 <= m.call_args.kwargs["limitnum"] <= 50)
        self.assertEqual(len(json.loads((sm.DATA / "calendar.json").read_text())), 2)

    def test_failed_call_writes_nothing(self):
        for bad in (None, [], {"events": "x"}):
            with mock.patch.object(sm, "ws", return_value=bad):
                self.assertIsNone(sm.sync_calendar([]))
        self.assertFalse((sm.DATA / "calendar.json").exists())


class RubricTests(DataDirCase):
    RUBRIC = {"areas": [{"cmid": 77, "areaname": "submissions", "definitions": [{
        "method": "rubric", "name": "Rubrica de informe", "description": "<p>Desc</p>",
        "rubric": {"rubric_criteria": [
            {"sortorder": 2, "description": "Formato", "levels": [{"score": 1, "definition": "Pobre"}]},
            {"sortorder": 1, "description": "<b>Contenido</b>", "levels": [
                {"score": 0, "definition": "Nulo"}, {"score": 4.5, "definition": "Completo"}]}]}}]}]}
    GUIDE = {"areas": [{"cmid": 78, "definitions": [{
        "method": "guide", "name": "Guia", "guide": {
            "guide_criteria": [{"sortorder": 1, "shortname": "Analisis", "description": "Describe",
                                "descriptionmarkers": "Ver pauta", "maxscore": 5}],
            "guide_comments": [{"description": "Citar fuentes"}]}}]}]}
    ITEMS = [{"type": "Tarea", "cmid": 77, "folder": "c/actividades/Tarea - A"},
             {"type": "Tarea", "cmid": 78, "folder": "c/actividades/Tarea - B"},
             {"type": "Examen", "folder": "c/actividades/Examen - C"}]

    def run_sync(self, res):
        with mock.patch.object(sm, "ws", return_value=res) as m:
            n = sm.sync_rubrics(self.ITEMS)
        return n, m

    def test_rubric_written_sorted_and_rendered(self):
        n, m = self.run_sync(self.RUBRIC)
        self.assertEqual(n, 1)
        self.assertEqual(m.call_args.kwargs, {"cmids": [77, 78], "areaname": "submissions", "activeonly": 1})
        data = json.loads((sm.DATA / "rubrics" / "77.json").read_text())
        self.assertEqual([c["description"] for c in data["criteria"]], ["Contenido", "Formato"])
        md = (sm.ROOT / "c/actividades/Tarea - A/rubrica.md").read_text()
        self.assertIn("# Rubrica - Rubrica de informe", md)
        self.assertIn("## Contenido", md)
        self.assertIn("- **4.5 pts**: Completo", md)

    def test_guide_rendered(self):
        n, _ = self.run_sync(self.GUIDE)
        self.assertEqual(n, 1)
        md = (sm.ROOT / "c/actividades/Tarea - B/rubrica.md").read_text()
        self.assertIn("## Analisis (max. 5 pts)", md)
        self.assertIn("Ver pauta", md)
        self.assertIn("- Citar fuentes", md)

    def test_no_definitions_or_bad_shape_writes_nothing(self):
        for res in (None, {"areas": []}, {"areas": "x"}, {"areas": [{"cmid": 77, "definitions": [{"method": "points"}]}]}):
            n, _ = self.run_sync(res)
            self.assertEqual(n, 0)
        self.assertFalse((sm.DATA / "rubrics").exists())

    def test_no_assignments_makes_no_call(self):
        with mock.patch.object(sm, "ws") as m:
            self.assertEqual(sm.sync_rubrics([{"type": "Examen", "folder": "x"}]), 0)
        m.assert_not_called()


class OptionalTests(unittest.TestCase):
    def test_exception_logged_once_and_swallowed(self):
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            out = sm.optional("calendar", lambda: 1 / 0)
        self.assertIsNone(out)
        lines = err.getvalue().strip().splitlines()
        self.assertEqual(len(lines), 1)
        self.assertIn("calendar skipped", lines[0])

    def test_moodle_exception_response_is_swallowed(self):
        class R:
            def json(self):
                return {"exception": "webservice_access_exception", "message": "Access control exception"}
        with mock.patch.object(sm.session, "post", return_value=R()), contextlib.redirect_stderr(io.StringIO()) as err:
            self.assertIsNone(sm.ws("core_grading_get_definitions"))
            self.assertEqual(sm.optional("rubrics", sm.sync_rubrics, [{"type": "Tarea", "cmid": 1, "folder": "f"}]), 0)
        self.assertIn("core_grading_get_definitions", err.getvalue())

    def test_unexpected_shape_is_swallowed(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertIsNone(sm.optional("grades json", sm.write_grades_json, {"id": 1}, {"usergrades": "oops"}))
