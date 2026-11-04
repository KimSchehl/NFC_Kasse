"""Builds PDF (Chromium) and Word (pandoc) from the manuals' Markdown.
Usage: python build.py [OUTDIR]   (default: the anleitungen folder itself)"""
import asyncio, os, re, subprocess, sys, tempfile
from pathlib import Path
from playwright.async_api import async_playwright

HERE = Path(__file__).resolve().parent
SRC = HERE.parent
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else SRC
DOCS = ["Bedieneranleitung", "Handbuch_Systemadministratoren", "Kurzanleitung_Standpersonal", "Zusatzfunktionen_Pager_Leaderboard"]
# Optional: path to a Chromium binary; without it Playwright uses its own browser.
CHROME = os.environ.get("CHROME_PATH")

def prepared_markdown(name: str) -> str:
    md = (SRC / f"{name}.md").read_text(encoding="utf-8")
    # Title and date line go into the template's title block (above the TOC).
    lines = md.splitlines()
    md = "\n".join(lines[3:])
    # Links to sibling manuals stay readable text in PDF/Word.
    md = re.sub(r"\[([^\]]+)\]\((?:[A-Za-z_]+)\.md\)", r"\1", md)
    return md

def build(name: str, tmp: Path) -> Path:
    md_file = tmp / f"{name}.md"
    md_file.write_text(prepared_markdown(name), encoding="utf-8")
    head = (SRC / f"{name}.md").read_text(encoding="utf-8").splitlines()
    title, date = head[0].lstrip("# ").strip(), head[2].strip()
    common = ["--resource-path", str(SRC), "-f", "markdown-implicit_figures+implicit_figures", "--metadata", f"title={title}", "--metadata", f"date={date}", "--metadata", "lang=de-DE"]
    html = tmp / f"{name}.html"
    toc = ["--toc", "--toc-depth=2"] if name not in ("Kurzanleitung_Standpersonal",) else []
    subprocess.run(["pandoc", str(md_file), "-o", str(html), "--standalone", "--embed-resources",
                    "--css", str(HERE / "style.css"), "--template", str(HERE / "template.html"), *toc, *common], check=True)
    subprocess.run(["pandoc", str(md_file), "-o", str(OUT / f"{name}.docx"), *toc, *common,
                    "--reference-doc", str(HERE / "reference.docx")], check=True)
    return html

async def to_pdf(htmls):
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path=CHROME) if CHROME else await p.chromium.launch()
        page = await b.new_page()
        for name, html in htmls:
            await page.goto(html.as_uri()); await page.wait_for_timeout(300)
            await page.pdf(path=str(OUT / f"{name}.pdf"), format="A4", print_background=True,
                           display_header_footer=True, header_template="<span></span>",
                           footer_template='<div style="font-size:8px;color:#888;width:100%;text-align:center">NFC-Kasse · Seite <span class="pageNumber"></span> von <span class="totalPages"></span></div>',
                           margin={"top": "16mm", "bottom": "18mm", "left": "16mm", "right": "16mm"})
        await b.close()

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        htmls = [(n, build(n, tmp)) for n in DOCS]
        asyncio.run(to_pdf(htmls))
    print("ok", OUT)
