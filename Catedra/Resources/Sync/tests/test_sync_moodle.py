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
