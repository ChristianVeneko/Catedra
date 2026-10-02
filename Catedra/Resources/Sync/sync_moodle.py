#!/usr/bin/env python3
"""Synchronize Moodle (SAIA UFT) course content and activities into a local folder tree.

Authentication (in order of precedence):
  1. MOODLE_TOKEN environment variable
  2. --token-file PATH (JSON with a "token" key, as returned by /login/token.php)
  3. MOODLE_USER / MOODLE_PASS environment variables, or an interactive prompt

Workspace root (in order of precedence): --root PATH, CATEDRA_WORKSPACE, or the parent of this
script's folder (`<root>/_sistema/sync_moodle.py`). Data lives in `<root>/_sistema/data`.

Usage:
  python3 sync_moodle.py                 # full sync (content + activities + dashboard)
  python3 sync_moodle.py --no-files      # refresh metadata and dashboard only
  python3 sync_moodle.py --root PATH     # use PATH as the workspace root
"""

import argparse
import datetime as dt
import getpass
import hashlib
import html
import json
import os
import re
import sys
import time
import urllib.parse
from html.parser import HTMLParser
from pathlib import Path

import requests

SITE = "https://saia.uft.edu.ve"
WS = f"{SITE}/webservice/rest/server.php"
ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "_sistema" / "data"
IMAGES_DIR = "_imagenes"
IMAGE_TIMEOUT = 30


def set_root(path):
    """Point ROOT and DATA at a workspace folder."""
    global ROOT, DATA
    ROOT = Path(path).expanduser().resolve()
    DATA = ROOT / "_sistema" / "data"
NOW = int(time.time())
TZ = dt.timezone(dt.timedelta(hours=-4))  # America/Caracas

# Short, stable folder names per course shortname prefix.
COURSE_NAMES = {
    "ALFC733": "01 - Automatas y Lenguajes Formales",
    "DISC733": "02 - Diseno de Software",
    "SIOC733": "03 - Sistemas Operativos",
    "CIDC742": "04 - Circuitos Digitales",
    "LCIC742": "05 - Laboratorio de Circuitos Digitales",
    "ELEC742": "06 - Electronica II",
    "LELC742": "07 - Laboratorio de Electronica II",
    "TECC732": "08 - Teoria de Control II",
    "SECC0132": "09 - Servicio Comunitario",
}

session = requests.Session()
TOKEN = ""


# ---------------------------------------------------------------- helpers

def ws(function, **params):
    data = {"wstoken": TOKEN, "wsfunction": function, "moodlewsrestformat": "json"}
    data.update(flatten(params))
    for attempt in range(3):
        try:
            r = session.post(WS, data=data, timeout=60)
            out = r.json()
            if isinstance(out, dict) and out.get("exception"):
                print(f"  ! {function}: {out.get('message')}", file=sys.stderr)
                return None
            return out
        except Exception as exc:  # network hiccup
            if attempt == 2:
                print(f"  ! {function} failed: {exc}", file=sys.stderr)
                return None
            time.sleep(2)


def flatten(params, prefix=""):
    flat = {}
    for key, value in params.items():
        name = f"{prefix}[{key}]" if prefix else key
        if isinstance(value, dict):
            flat.update(flatten(value, name))
        elif isinstance(value, (list, tuple)):
            for i, item in enumerate(value):
                if isinstance(item, dict):
                    flat.update(flatten(item, f"{name}[{i}]"))
                else:
                    flat[f"{name}[{i}]"] = item
        else:
            flat[name] = value
    return flat


def safe(name, limit=90):
    name = html.unescape(name or "sin-nombre")
    name = re.sub(r'[\\/:*?"<>|\n\r\t]+', " ", name)
    name = re.sub(r"\s+", " ", name).strip(" .")
    return (name[:limit].strip() or "sin-nombre")


def fmt(ts):
    if not ts:
        return "-"
    return dt.datetime.fromtimestamp(ts, TZ).strftime("%Y-%m-%d %H:%M")


def download(url, dest: Path, size=None, mtime=None, fetch=True):
    """Download a Moodle file URL to dest, skipping unchanged files."""
    if not fetch:
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and (size is None or dest.stat().st_size == size):
        if mtime is None or int(dest.stat().st_mtime) >= int(mtime):
            return
    url = with_token(url)
    try:
        with session.get(url, stream=True, timeout=120) as r:
            r.raise_for_status()
            tmp = dest.with_suffix(dest.suffix + ".part")
            with open(tmp, "wb") as fh:
                for chunk in r.iter_content(1 << 16):
                    fh.write(chunk)
            tmp.replace(dest)
        if mtime:
            os.utime(dest, (mtime, mtime))
    except Exception as exc:
        print(f"  ! download failed {dest.name}: {redact(exc)}", file=sys.stderr)


def redact(message):
    """Never let the token reach the logs (requests errors include the URL)."""
    text = str(message)
    return text.replace(TOKEN, "***") if TOKEN else text


def is_pluginfile(url):
    return "/pluginfile.php" in url


def with_token(url):
    """Route a SAIA pluginfile URL through the webservice endpoint and append the token."""
    sep = "&" if "?" in url else "?"
    if "/pluginfile.php" in url and "/webservice/pluginfile.php" not in url:
        url = url.replace("/pluginfile.php", "/webservice/pluginfile.php")
    return f"{url}{sep}token={TOKEN}"


# ---------------------------------------------------------------- mojibake

_SUSPICIOUS = re.compile("[\u00c3\u00c2]")
# A run that starts at a likely lead character and continues through Latin-1 / cp1252 high characters.
_MOJIBAKE_RUN = re.compile("[\u00c3\u00c2][\u0080-\u00ff\u0152\u0153\u0160\u0161\u0178\u017d\u017e\u0192\u02c6\u02dc\u2013-\u203a\u20ac\u2122]*")
_LOST_C1 = re.compile("\u00c3(?=\u00c2)")


def _suspicion(text):
    return len(_SUSPICIOUS.findall(text))


def _redecode(run):
    best = run
    for encoding in ("latin-1", "cp1252"):
        try:
            candidate = best.encode(encoding).decode("utf-8")
        except (UnicodeEncodeError, UnicodeDecodeError):
            continue
        if _suspicion(candidate) < _suspicion(best):
            return candidate
    return best


def fix_mojibake(text):
    """Undo UTF-8 text that was decoded as Latin-1/cp1252 one or more times ("vÃÂ­deo" -> "vídeo").

    Only runs that contain the telltale lead characters (Ã, Â) are touched, and a candidate is accepted
    only when it reduces them, so correct text ("Ñandú") is returned unchanged.
    """
    if not text or not _SUSPICIOUS.search(text):
        return text

    def fix_run(match):
        run = _LOST_C1.sub("\u00c3\u0083", match.group(0))
        for _ in range(4):
            fixed = _redecode(run)
            if fixed == run:
                break
            run = fixed
        return run

    return _MOJIBAKE_RUN.sub(fix_run, text)


# ---------------------------------------------------------------- images

def image_filename(url, taken=None):
    """Safe local filename for an image URL; `taken` maps already used names to the URL that owns them.

    The extension is kept; when another URL already owns the plain name, a short URL hash is added.
    """
    path = urllib.parse.unquote(urllib.parse.urlparse(url).path)
    base = os.path.basename(path.rstrip("/")) or "imagen"
    stem, ext = os.path.splitext(base)
    ext = re.sub(r"[^A-Za-z0-9.]", "", ext)[:8].lower() or ".img"
    stem = re.sub(r"[^\w.-]+", "-", stem, flags=re.UNICODE).strip("-.")[:60] or "imagen"
    name = stem + ext
    digest = hashlib.sha1(url.encode("utf-8")).hexdigest()[:8]
    if taken is not None:
        owner = taken.get(name)
        if owner is not None and owner != url:
            name = f"{stem}-{digest}{ext}"
        taken[name] = url
    return name


def fetch_image(url, dest: Path):
    """Download one image. SAIA files get the token; external URLs are fetched anonymously. True on success."""
    request_url = with_token(url) if is_pluginfile(url) else url
    try:
        with session.get(request_url, stream=True, timeout=IMAGE_TIMEOUT) as r:
            r.raise_for_status()
            if "text/html" in (r.headers.get("Content-Type") or "").lower():
                return False
            dest.parent.mkdir(parents=True, exist_ok=True)
            tmp = dest.with_suffix(dest.suffix + ".part")
            with open(tmp, "wb") as fh:
                for chunk in r.iter_content(1 << 16):
                    fh.write(chunk)
            tmp.replace(dest)
        return True
    except Exception as exc:
        print(f"  ! image failed {dest.name}: {redact(exc)}", file=sys.stderr)
        return False


class ImageSink:
    """Localizes the images of the HTML that becomes a Markdown file stored in `folder`.

    Images land in `<folder>/_imagenes/`. With fetch=False nothing is downloaded: images already on disk
    are still used, the others keep their remote URL. `base` resolves relative sources of an HTML file.
    """

    def __init__(self, folder: Path, fetch=True, base: Path = None, taken=None):
        self.folder = Path(folder)
        self.fetch = fetch
        self.base = Path(base) if base else None
        self.taken = {} if taken is None else taken

    def localize(self, src):
        src = (src or "").strip()
        if not src or src.startswith(("data:", "#")):
            return src
        if src.startswith("//"):
            src = "https:" + src
        elif src.startswith("/"):
            src = SITE + src
        if not re.match(r"https?://", src, re.I):
            return self._relative(src)
        name = image_filename(src, self.taken)
        dest = self.folder / IMAGES_DIR / name
        if not dest.exists():
            if not self.fetch or not fetch_image(src, dest):
                return src
        return f"{IMAGES_DIR}/{name}"

    def _relative(self, src):
        if not self.base:
            return src
        candidate = (self.base / urllib.parse.unquote(src.split("?")[0])).resolve()
        if candidate.is_file():
            return Path(os.path.relpath(candidate, self.folder.resolve())).as_posix()
        return src


class _Text(HTMLParser):
    BLOCK = {"p", "div", "br", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "table", "ul", "ol"}

    def __init__(self, images=None):
        super().__init__()
        self.out, self.href = [], None
        self.images = images

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in self.BLOCK:
            self.out.append("\n")
        if tag == "li":
            self.out.append("- ")
        if tag in {"h1", "h2", "h3", "h4"}:
            self.out.append("#" * (int(tag[1]) + 2) + " ")
        if tag == "a":
            self.href = attrs.get("href")
        if tag == "img" and attrs.get("src"):
            src = self.images.localize(attrs["src"]) if self.images else attrs["src"]
            alt = (attrs.get("alt") or "").replace("[", "(").replace("]", ")")
            self.out.append(f"![{alt}]({src.replace(' ', '%20')})")
        if tag in {"td", "th"}:
            self.out.append(" | ")

    def handle_endtag(self, tag):
        if tag == "a" and self.href:
            self.out.append(f" ({self.href})")
            self.href = None
        if tag in self.BLOCK:
            self.out.append("\n")

    def handle_data(self, data):
        self.out.append(data)


def html_to_text(raw, images=None):
    if not raw:
        return ""
    parser = _Text(images)
    parser.feed(raw)
    text = fix_mojibake("".join(parser.out))
    text = re.sub(r"[ \t\xa0]+", " ", text)
    text = re.sub(r"\n\s*\n\s*\n+", "\n\n", text)
    return text.strip()


def write(path: Path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


# ---------------------------------------------------------------- auth

def resolve_token(args):
    if os.environ.get("MOODLE_TOKEN"):
        return os.environ["MOODLE_TOKEN"]
    if args.token_file and Path(args.token_file).exists():
        return json.loads(Path(args.token_file).read_text())["token"]
    user = os.environ.get("MOODLE_USER") or input("Moodle user: ")
    password = os.environ.get("MOODLE_PASS") or getpass.getpass("Moodle password: ")
    r = session.post(f"{SITE}/login/token.php",
                     data={"username": user, "password": password, "service": "moodle_mobile_app"})
    data = r.json()
    if "token" not in data:
        sys.exit(f"Login failed: {data.get('error')}")
    return data["token"]


# ---------------------------------------------------------------- content

def sync_contents(course, cdir: Path, fetch):
    sections = ws("core_course_get_contents", courseid=course["id"]) or []
    write(DATA / f"contents_{course['id']}.json", json.dumps(sections, ensure_ascii=False, indent=1))
    outline = []
    for idx, sec in enumerate(sections):
        sname = f"{idx:02d} - {safe(sec.get('name'), 70)}"
        sdir = cdir / "contenidos" / sname
        notes, links = [], []
        img = ImageSink(sdir, fetch)
        summary = html_to_text(sec.get("summary"), img)
        if summary:
            notes.append(summary)
        outline.append(f"\n### {sname}\n")
        for mod in sec.get("modules", []):
            kind, name = mod["modname"], safe(mod.get("name"))
            hidden = "" if mod.get("uservisible", True) else " (no disponible)"
            outline.append(f"- [{kind}] {html.unescape(mod.get('name', ''))}{hidden}")
            if mod.get("availabilityinfo"):
                outline.append(f"  - Restriccion: {html_to_text(mod['availabilityinfo'])}")
            if kind == "label":
                text = html_to_text(mod.get("description"), img)
                if text:
                    notes.append(text)
                continue
            if kind in {"assign", "quiz"}:
                continue  # handled in activities
            if kind == "url":
                for c in mod.get("contents", []):
                    links.append(f"- [{html.unescape(mod['name'])}]({c.get('fileurl')})")
                continue
            if kind == "forum":
                continue  # handled separately
            contents = [c for c in mod.get("contents", []) if c.get("type") == "file"]
            if not contents:
                if mod.get("description"):
                    write(sdir / f"{name}.md", f"# {html.unescape(mod['name'])}\n\n{html_to_text(mod['description'], img)}\n")
                continue
            single = kind == "resource" and len(contents) == 1
            mdir = sdir if single else sdir / f"{name}"
            for c in contents:
                rel = (c.get("filepath") or "/").strip("/")
                dest = mdir / rel / safe(c["filename"], 120) if rel else mdir / safe(c["filename"], 120)
                download(c["fileurl"], dest, c.get("filesize"), c.get("timemodified"), fetch)
            if kind in {"page", "book"}:
                htmls = sorted(mdir.rglob("index.html")) if mdir.exists() else []
                mimg = ImageSink(mdir, fetch)
                parts = [f"# {html.unescape(mod['name'])}\n"]
                if mod.get("description"):
                    parts.append(html_to_text(mod["description"], mimg))
                for h in htmls:
                    parts.append(f"\n---\n<!-- {h.relative_to(mdir)} -->\n")
                    parts.append(html_to_text(h.read_text(encoding="utf-8", errors="ignore"),
                                              ImageSink(mdir, fetch, base=h.parent, taken=mimg.taken)))
                write(mdir / "_texto.md", "\n".join(parts) + "\n")
        if notes:
            write(sdir / "_notas.md", f"# {sname}\n\n" + "\n\n---\n\n".join(notes) + "\n")
        if links:
            write(sdir / "_enlaces.md", f"# Enlaces - {sname}\n\n" + "\n".join(links) + "\n")
    return sections, outline


def sync_forums(course, cdir: Path, sections, fetch=True):
    forums = [m for s in sections for m in s.get("modules", []) if m["modname"] == "forum"]
    for mod in forums:
        res = ws("mod_forum_get_forum_discussions", forumid=mod["instance"], perpage=100) or {}
        discussions = res.get("discussions", [])
        if not discussions:
            continue
        img = ImageSink(cdir / "foros", fetch)
        lines = [f"# Foro: {html.unescape(mod['name'])}\n"]
        for d in discussions:
            posts = (ws("mod_forum_get_discussion_posts", discussionid=d["discussion"]) or {}).get("posts", [])
            lines.append(f"\n## {html.unescape(d.get('name', ''))}  ({fmt(d.get('created'))})\n")
            for p in sorted(posts, key=lambda x: x.get("timecreated", 0)):
                author = (p.get("author") or {}).get("fullname", "?")
                lines.append(f"**{author}** - {fmt(p.get('timecreated'))}\n")
                lines.append(html_to_text(p.get("message"), img) + "\n")
                for a in p.get("attachments") or []:
                    download(a["url"], cdir / "foros" / safe(mod["name"]) / safe(a["filename"], 120),
                             a.get("filesize"), None, True)
        write(cdir / "foros" / f"{safe(mod['name'])}.md", "\n".join(lines))


# ---------------------------------------------------------------- activities

def assignment_status(a):
    st = ws("mod_assign_get_submission_status", assignid=a["id"]) or {}
    sub = ((st.get("lastattempt") or {}).get("submission") or {})
    graded = (st.get("feedback") or {}).get("gradefordisplay")
    status = sub.get("status", "new")
    if graded:
        label = "Calificada"
    elif status == "submitted":
        label = "Entregada"
    elif a.get("duedate") and a["duedate"] < NOW:
        cutoff = a.get("cutoffdate") or 0
        label = "Vencida (aun acepta)" if (not cutoff or cutoff > NOW) else "Vencida sin entregar"
    else:
        label = "Pendiente"
    return label, html_to_text(graded) if graded else "", st


def sync_assignments(course, cdir, assigns, fetch):
    items = []
    for a in assigns:
        label, grade, st = assignment_status(a)
        adir = cdir / "actividades" / f"Tarea - {safe(a['name'], 70)}"
        img = ImageSink(adir, fetch)
        for f in a.get("introattachments", []):
            download(f["fileurl"], adir / "material" / safe(f["filename"], 120),
                     f.get("filesize"), f.get("timemodified"), fetch)
        cfg = {c["name"]: c["value"] for c in a.get("configs", [])}
        body = [
            f"# {html.unescape(a['name'])}",
            "",
            f"- Materia: {course['fullname']}",
            f"- Tipo: Tarea (assign)",
            f"- Estado: **{label}**" + (f" - Nota: {grade}" if grade else ""),
            f"- Apertura: {fmt(a.get('allowsubmissionsfromdate'))}",
            f"- Entrega: {fmt(a.get('duedate'))}",
            f"- Fecha limite (corte): {fmt(a.get('cutoffdate'))}",
            f"- Calificacion maxima: {a.get('grade')}",
            f"- Envio de archivos: {'si' if cfg.get('enabled') == '1' else 'ver Moodle'}",
            f"- Enlace: {SITE}/mod/assign/view.php?id={a['cmid']}",
            "",
            "## Enunciado",
            "",
            html_to_text(a.get("intro"), img) or "_Sin descripcion en Moodle._",
        ]
        if a.get("activity"):
            body += ["", "## Instrucciones de la actividad", "", html_to_text(a["activity"], img)]
        write(adir / "enunciado.md", "\n".join(body) + "\n")
        (adir / "entrega").mkdir(parents=True, exist_ok=True)
        write(DATA / "assign" / f"{a['id']}_status.json", json.dumps(st, ensure_ascii=False, indent=1))
        items.append({"course": course["key"], "type": "Tarea", "name": html.unescape(a["name"]),
                      "due": a.get("duedate") or 0, "status": label, "grade": grade,
                      "url": f"{SITE}/mod/assign/view.php?id={a['cmid']}",
                      "folder": str(adir.relative_to(ROOT))})
    return items


def sync_quizzes(course, cdir, quizzes, fetch=True):
    items = []
    for q in quizzes:
        attempts = (ws("mod_quiz_get_user_attempts", quizid=q["id"], status="all") or {}).get("attempts", [])
        finished = [x for x in attempts if x.get("state") == "finished"]
        best = (ws("mod_quiz_get_user_best_grade", quizid=q["id"]) or {})
        grade = f"{best.get('grade'):.2f}/{q.get('grade')}" if best.get("hasgrade") else ""
        close, open_ = q.get("timeclose") or 0, q.get("timeopen") or 0
        if finished:
            label = "Realizado"
        elif close and close < NOW:
            label = "Cerrado sin intento"
        elif open_ and open_ > NOW:
            label = "Proximo (aun no abre)"
        else:
            label = "Pendiente"
        kind = "Examen" if re.search(r"parcial|examen|sustitutiv|diferid", q["name"], re.I) else "Cuestionario"
        qdir = cdir / "actividades" / f"{kind} - {safe(q['name'], 70)}"
        img = ImageSink(qdir, fetch)
        body = [
            f"# {html.unescape(q['name'])}",
            "",
            f"- Materia: {course['fullname']}",
            f"- Tipo: {kind} (quiz)",
            f"- Estado: **{label}**" + (f" - Nota: {grade}" if grade else ""),
            f"- Abre: {fmt(open_)}",
            f"- Cierra: {fmt(close)}",
            f"- Tiempo limite: {int(q['timelimit'] / 60)} min" if q.get("timelimit") else "- Tiempo limite: sin limite",
            f"- Intentos permitidos: {q.get('attempts') or 'ilimitados'}",
            f"- Intentos realizados: {len(finished)}",
            f"- Enlace: {SITE}/mod/quiz/view.php?id={q['coursemodule']}",
            "",
            "## Descripcion",
            "",
            html_to_text(q.get("intro"), img) or "_Sin descripcion en Moodle._",
        ]
        write(qdir / "enunciado.md", "\n".join(body) + "\n")
        (qdir / "preparacion").mkdir(parents=True, exist_ok=True)
        items.append({"course": course["key"], "type": kind, "name": html.unescape(q["name"]),
                      "due": close, "status": label, "grade": grade,
                      "url": f"{SITE}/mod/quiz/view.php?id={q['coursemodule']}",
                      "folder": str(qdir.relative_to(ROOT))})
    return items


def grades_table(course, userid):
    res = ws("gradereport_user_get_grade_items", courseid=course["id"], userid=userid) or {}
    rows = []
    for g in (res.get("usergrades") or [{}])[0].get("gradeitems", []):
        rows.append(f"| {html.unescape(g.get('itemname') or 'Total del curso')} | "
                    f"{g.get('gradeformatted') or '-'} | {g.get('grademax', '-')} | "
                    f"{g.get('percentageformatted') or '-'} |")
    if not rows:
        return "_Sin calificaciones publicadas._"
    return "| Item | Nota | Max | % |\n|---|---|---|---|\n" + "\n".join(rows)


# ---------------------------------------------------------------- dashboard

PENDING = {"Pendiente", "Vencida (aun acepta)", "Proximo (aun no abre)"}


def render_dashboard(items, courses):
    def row(i):
        days = (i["due"] - NOW) / 86400 if i["due"] else None
        when = fmt(i["due"]) + (f" ({days:+.0f} d)" if days is not None else "")
        return (f"| {when} | {i['course']} | {i['type']} | [{i['name']}]({i['url']}) | "
                f"{i['status']} | [carpeta](<{i['folder']}/enunciado.md>) |")

    header = "| Fecha | Materia | Tipo | Actividad | Estado | Local |\n|---|---|---|---|---|---|"
    key = lambda i: (i["due"] or 10**12)
    pending = sorted([i for i in items if i["status"] in PENDING], key=key)
    soon = [i for i in pending if i["due"] and i["due"] - NOW < 14 * 86400]
    done = sorted([i for i in items if i["status"] not in PENDING], key=key)

    lines = [
        "# 7mo Semestre - Panel de actividades",
        "",
        f"_Ultima sincronizacion: {fmt(NOW)} (hora de Venezuela). Regenerado por `_sistema/sync_moodle.py`._",
        "",
        "## Proximas 2 semanas",
        "",
        header, *([row(i) for i in soon] or ["| - | - | - | Nada urgente | - | - |"]),
        "",
        "## Todas las pendientes",
        "",
        header, *[row(i) for i in pending],
        "",
        "## Historial (entregadas, calificadas, cerradas)",
        "",
        header, *[row(i) for i in done],
        "",
        "## Materias",
        "",
        *[f"- [{c['key']}](<{c['folder']}/README.md>) - {c['fullname']}" for c in courses],
        "",
    ]
    write(ROOT / "PENDIENTES.md", "\n".join(lines))
    write(DATA / "activities.json", json.dumps(items, ensure_ascii=False, indent=1))


# ---------------------------------------------------------------- main

def main():
    global TOKEN
    ap = argparse.ArgumentParser()
    ap.add_argument("--token-file")
    ap.add_argument("--no-files", action="store_true", help="skip file and image downloads")
    ap.add_argument("--root", help="workspace root (default: $CATEDRA_WORKSPACE or the parent of this script's folder)")
    args = ap.parse_args()
    root = args.root or os.environ.get("CATEDRA_WORKSPACE")
    if root:
        set_root(root)
    TOKEN = resolve_token(args)
    fetch = not args.no_files

    site = ws("core_webservice_get_site_info")
    userid = site["userid"]
    courses = ws("core_enrol_get_users_courses", userid=userid)
    ids = [c["id"] for c in courses]
    assigns = {c["id"]: c["assignments"] for c in (ws("mod_assign_get_assignments", courseids=ids) or {}).get("courses", [])}
    quizzes = {}
    for q in (ws("mod_quiz_get_quizzes_by_courses", courseids=ids) or {}).get("quizzes", []):
        quizzes.setdefault(q["course"], []).append(q)

    all_items, summary = [], []
    for course in sorted(courses, key=lambda c: COURSE_NAMES.get(c["shortname"].split("-")[0], c["shortname"])):
        prefix = course["shortname"].split("-")[0]
        folder = COURSE_NAMES.get(prefix, safe(course["fullname"]))
        course["key"] = folder.split(" - ", 1)[-1]
        course["folder"] = folder
        cdir = ROOT / folder
        print(f"> {folder}")
        sections, outline = sync_contents(course, cdir, fetch)
        sync_forums(course, cdir, sections, fetch)
        items = sync_assignments(course, cdir, assigns.get(course["id"], []), fetch)
        items += sync_quizzes(course, cdir, quizzes.get(course["id"], []), fetch)
        for i in items:
            i["folder"] = str(Path(i["folder"]))
        all_items += items
        acts = "\n".join(
            f"| {fmt(i['due'])} | {i['type']} | [{i['name']}](<{Path(i['folder']).relative_to(folder)}/enunciado.md>) | {i['status']} | {i['grade'] or '-'} |"
            for i in sorted(items, key=lambda i: i["due"] or 10**12)) or "| - | - | Sin actividades evaluadas en Moodle | - | - |"
        readme = [
            f"# {course['fullname']}",
            "",
            f"- Codigo: {course['shortname']}",
            f"- Aula virtual: {SITE}/course/view.php?id={course['id']}",
            "",
            "## Actividades evaluadas",
            "",
            "| Fecha | Tipo | Actividad | Estado | Nota |",
            "|---|---|---|---|---|",
            acts,
            "",
            "## Calificaciones",
            "",
            grades_table(course, userid),
            "",
            "## Estructura del aula",
            *outline,
            "",
        ]
        write(cdir / "README.md", "\n".join(readme))
        summary.append(course)

    render_dashboard(all_items, summary)
    print(f"Done: {len(all_items)} activities, dashboard at {ROOT / 'PENDIENTES.md'}")


if __name__ == "__main__":
    main()
