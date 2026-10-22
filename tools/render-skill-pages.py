#!/usr/bin/env python3
# Needs: pip install markdown pymdown-extensions
"""Render SKILL.md and its references as pages in the site's design.
Usage: render_skill.py <skill folder> <output folder: dist/skills/migrating-php-apps> [site root for asset links]
The raw Markdown files are left untouched next to the pages, because agents read those."""
import html, re, sys, pathlib, posixpath
from urllib.parse import urlsplit, urlunsplit
import markdown

skill, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
root = sys.argv[3] if len(sys.argv) > 3 else ""
fm = re.compile(r"^---\n(.*?)\n---\n", re.S)
site_index = out.parents[1] / "index.html"
move_to_motoko = site_index.is_file() and bool(re.search(
    r"www\.movetomotoko\.com|Move(?:\s|<[^>]+>)*to(?:\s|<[^>]+>)*Motoko",
    site_index.read_text()))

REFS = [("inventory.md", "Inventory script"), ("data-import.md", "Data export and import"), ("backend-example.md", "Tested backend example"),
        ("old-urls.md", "Keeping old URLs"), ("frameworks.md", "Platform notes"), ("delivery.md", "Dynamic delivery")]

DOC_DESCRIPTIONS = {
    "SKILL.md": "The six-phase PHP migration workflow: inventory, plan, rebuild, reconcile data, reconnect users and verify cutover on the Internet Computer.",
    "references/inventory.md": "Read-only inventory guidance for mapping an existing PHP application before planning its move to Motoko and the Internet Computer.",
    "references/data-import.md": "Back up, export, convert, import and reconcile application data during a planned PHP-to-Motoko migration.",
    "references/backend-example.md": "A tested Motoko backend example for content storage, data imports and access checks to adapt to an application's migration plan.",
    "references/old-urls.md": "Preserve established URLs with redirect rules, legacy route mapping and checks for each old link during migration.",
    "references/frameworks.md": "Migration notes for PHP content systems and frameworks, with platform-specific decisions for a Motoko rebuild.",
    "references/delivery.md": "Choose delivery behavior for migrated pages and HTTP APIs, with explicit response-certification decisions.",
}

DOC_JS = """(() => {
  const desktop = window.matchMedia('(min-width: 901px)');
  const outlines = document.querySelectorAll('.doc-outline');
  const syncOutline = () => {
    outlines.forEach(outline => { outline.open = desktop.matches; });
  };
  syncOutline();
  desktop.addEventListener('change', syncOutline);
  outlines.forEach(outline => {
    outline.addEventListener('click', event => {
      const link = event.target.closest('a[href^="#"]');
      if (!link || !outline.contains(link) || desktop.matches) return;
      const target = document.getElementById(decodeURIComponent(link.hash.slice(1)));
      if (!target) return;
      outline.open = false;
      // Keep native hash navigation and move keyboard focus out of the closed panel.
      window.requestAnimationFrame(() => {
        if (!target.hasAttribute('tabindex')) target.setAttribute('tabindex', '-1');
        target.focus({ preventScroll: true });
      });
    });
  });
})();
"""

DOC_CSS = """
.skill-docs { --doc-ink: #14171b; --doc-text: #292929; --doc-muted: #5f5f5f; --doc-line: #dedede; --doc-link: #235ba6; background: #fff; }
.skill-docs .wrap { width: min(1180px, calc(100% - 64px)); }
.skill-docs a:focus-visible, .skill-docs pre:focus-visible, .skill-docs table:focus-visible { outline: 3px solid #4d77a6; outline-offset: 5px; }
.doc-top { background: var(--doc-ink); color: #fff; }
.doc-site-nav { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 16px 28px; padding-block: 20px; border-bottom: 1px solid #40464f; }
.doc-brand { display: inline-flex; gap: 10px; align-items: center; min-height: 44px; font: 600 22px/1.2 var(--display); letter-spacing: -.04em; color: #fff; }
.doc-brand img { display: block; width: 34px; height: 34px; object-fit: contain; }
.doc-site-links { display: flex; gap: 8px 28px; flex-wrap: wrap; }
.doc-site-links a { display: inline-flex; align-items: center; min-height: 44px; font-size: 14px; color: #e0e4ea; }
.doc-site-links a:hover, .doc-actions a:hover { text-decoration: underline; text-underline-offset: 5px; }
.doc-head { padding-block: 40px 32px; }
.doc-kicker { margin-bottom: 16px; font: 12px/1.8 var(--mono); color: #c8cfd8; overflow-wrap: anywhere; }
.doc-head h1 { max-width: 23ch; font-size: clamp(32px, 4.6vw, 58px); line-height: 1.1; letter-spacing: -.045em; color: #fff; }
.doc-deck { margin-top: 20px; max-width: 70ch; color: #d3d9e1; font-size: 17px; }
.doc-actions { display: flex; flex-wrap: wrap; gap: 8px 28px; align-items: center; margin-top: 22px; }
.doc-actions a { display: inline-flex; align-items: center; min-height: 44px; color: #fff; font-size: 14px; font-weight: 500; }
.doc-companion { display: flex; flex-wrap: wrap; gap: 8px 16px; align-items: center; margin-top: 12px; color: #c8cfd8; font-size: 12px; }
.doc-companion code { padding: 8px 10px; border: 1px solid #58616e; color: #e0e4ea; font: 12px/1.7 var(--mono); overflow-wrap: anywhere; }
.doc-nav { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 24px; }
.doc-nav a { display: inline-flex; align-items: center; min-height: 44px; padding: 9px 13px; border: 1px solid #626b77; border-radius: 4px; color: #e0e4ea; font-size: 13px; }
.doc-nav a:hover { background: #2a3039; }
.doc-nav a[aria-current="page"] { background: #fff; border-color: #fff; color: #14171b; font-weight: 600; }
.doc { display: grid; grid-template-columns: minmax(0, 1fr) 245px; align-items: start; gap: 56px; padding-block: 48px 72px; }
.doc-body { min-width: 0; font-size: 17px; line-height: 1.75; }
.doc-body h2 { font-size: clamp(26px, 3vw, 34px); margin: 42px 0 16px; padding-top: 24px; border-top: 1px solid var(--doc-line); line-height: 1.2; letter-spacing: -.03em; }
.doc-body h2:first-child { border-top: 0; margin-top: 0; padding-top: 0; }
.doc-body h3 { font-size: 22px; margin: 32px 0 12px; line-height: 1.3; letter-spacing: -.02em; }
.doc-body h4 { font-size: 19px; margin: 28px 0 10px; line-height: 1.4; letter-spacing: -.01em; }
.doc-body p, .doc-body li { color: var(--doc-text); }
.doc-body p + p { margin-top: 14px; }
.doc-body ul, .doc-body ol { padding-left: 24px; margin: 12px 0; }
.doc-body li + li { margin-top: 7px; }
.doc-body li > ul, .doc-body li > ol { margin-top: 7px; }
.doc-body a { color: var(--doc-link); text-decoration: underline; text-underline-offset: 3px; }
.doc-body a, .doc-body p, .doc-body li, .doc-body h2, .doc-body h3, .doc-body h4 { overflow-wrap: anywhere; }
.doc-body :not(pre) > code { font: .84em/1.6 var(--mono); background: #f1f2f3; padding: 2px 4px; border-radius: 3px; overflow-wrap: anywhere; }
.doc-body pre { max-width: 100%; margin: 20px 0; padding: 18px 20px; overflow: auto; background: #14171b; color: #e6ebf2; border-radius: 5px; font: 12px/1.75 var(--mono); tab-size: 4; }
.doc-body pre code { color: inherit; background: none; font: inherit; padding: 0; white-space: pre; overflow-wrap: normal; }
.doc-body table { width: 100%; max-width: 100%; display: block; overflow-x: auto; border-collapse: collapse; margin: 20px 0; font-size: 14px; }
.doc-body th, .doc-body td { text-align: left; vertical-align: top; padding: 10px 12px; border-bottom: 1px solid var(--doc-line); }
.doc-body th { color: #292929; background: #f6f6f4; font-weight: 600; }
.doc-body blockquote { margin: 20px 0; padding: 4px 18px; border-left: 3px solid var(--doc-link); }
.doc-body hr { border: 0; border-top: 1px solid var(--doc-line); margin: 32px 0; }
.doc-body img { max-width: 100%; height: auto; }
.doc-toc { position: sticky; top: 24px; max-height: calc(100vh - 48px); overflow-y: auto; padding: 4px 8px; font-size: 14px; }
.doc-toc p { color: var(--doc-muted); font: 12px/1.7 var(--mono); margin-bottom: 12px; }
.doc-outline > summary { display: flex; align-items: center; justify-content: space-between; gap: 16px; min-height: 44px; color: var(--doc-muted); font: 12px/1.7 var(--mono); cursor: pointer; list-style: none; }
.doc-outline > summary::-webkit-details-marker { display: none; }
.doc-outline-icon { color: var(--doc-link); font: 24px/1 var(--sans); }
.doc-outline-icon::before { content: '+'; }
.doc-outline[open] .doc-outline-icon::before { content: '−'; }
.doc-outline-label { display: none; color: var(--doc-muted); font: 12px/1.7 var(--mono); margin-bottom: 12px; }
.doc-toc ul { list-style: none; padding: 0; margin: 0; }
.doc-toc ul ul { padding-left: 14px; }
.doc-toc a { display: block; padding: 8px 0; color: #454b54; text-decoration: none; overflow-wrap: anywhere; }
.doc-toc a:hover { color: var(--doc-link); text-decoration: underline; text-underline-offset: 3px; }
.doc-footer { background: #f6f6f4; border-top: 1px solid var(--doc-line); padding-block: 26px; }
.doc-footer .wrap { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 16px 32px; }
.doc-footer p { color: #5f5f5f; font-size: 13px; max-width: 75ch; }
.doc-footer a { display: inline-block; color: var(--doc-link); padding-block: 8px; font-size: 14px; text-decoration: underline; text-underline-offset: 3px; }
@media (min-width: 901px) { .doc-outline > summary { display: none; } .doc-outline-label { display: block; } }
@media (max-width: 900px) { .doc { grid-template-columns: minmax(0, 1fr); gap: 24px; } .doc-toc { position: static; max-height: none; order: -1; padding: 0 0 12px; border-bottom: 1px solid var(--doc-line); } .doc-outline .toc > ul { columns: 2; column-gap: 28px; } .doc-toc li { break-inside: avoid; } .doc-toc a { min-height: 44px; } }
@media (max-width: 600px) { .skill-docs .wrap { width: calc(100% - 40px); } .doc-site-nav { gap: 12px; padding-block: 16px; } .doc-brand { font-size: 21px; } .doc-site-links { gap: 8px 20px; } .doc-site-links a { font-size: 13px; } .doc-head { padding-block: 28px; } .doc-deck, .doc-body { font-size: 16px; } .doc-kicker { font-size: 11px; } .doc-actions { gap: 6px 20px; } .doc { padding-block: 32px 48px; } .doc-outline .toc > ul { columns: 1; } .doc-body pre { padding: 14px; font-size: 11px; } }
"""

def readable_links(html_body, this_file):
    def link(match):
        value = urlsplit(html.unescape(match.group(1)))
        if this_file == "references/frameworks.md" and not value.scheme and not value.netloc and value.path == "" and value.fragment == "joomla-4-and-5":
            return 'href="#joomla-4-to-6"'
        if value.scheme or value.netloc or not value.path.endswith(".md"):
            return match.group(0)
        source = posixpath.normpath(posixpath.join(posixpath.dirname(this_file), value.path))
        if source != "SKILL.md" and source not in {"references/" + f for f, _ in REFS}:
            return match.group(0)
        path = root + "/skills/migrating-php-apps/" + ("" if source == "SKILL.md" else source[:-3] + ".html")
        fragment = "joomla-4-to-6" if source == "references/frameworks.md" and value.fragment == "joomla-4-and-5" else value.fragment
        return 'href="' + html.escape(urlunsplit(("", "", path, value.query, fragment)), quote=True) + '"'
    return re.sub(r'href="([^"]+)"', link, html_body)

def readable_markdown(body):
    # Source lists use two-space continuation blocks. Python Markdown also needs
    # a blank line when a list resumes after a continuation paragraph. Normalize
    # only this rendered copy; fenced example contents stay byte-for-byte intact.
    lines, fence = [], None
    for line in body.splitlines(keepends=True):
        marker = re.match(r'^\s*(`{3,}|~{3,})', line)
        if fence:
            lines.append(line)
            if marker and marker.group(1)[0] == fence[0] and len(marker.group(1)) >= len(fence) and not line[marker.end():].strip():
                fence = None
            continue
        if marker:
            fence = marker.group(1)
        elif re.match(r'^(?:[-+*]|\d+\.)\s', line) and lines and re.match(r'^ {2,}\S', lines[-1]):
            lines.append('\n')
        lines.append(line)
    return ''.join(lines)

def move_page(title, html_body, toc, raw_rel, current):
    page_url = "https://www.movetomotoko.com/skills/migrating-php-apps/" + ("" if raw_rel == "SKILL.md" else raw_rel[:-3] + ".html")
    page_title = html.escape(title + " · Move to Motoko", quote=True)
    description = html.escape(DOC_DESCRIPTIONS[raw_rel], quote=True)
    social_image = "https://www.movetomotoko.com/assets/move-to-motoko-social-v3.jpg"
    nav = "".join(f'<a href="{root}/skills/migrating-php-apps/{"" if f == "SKILL.md" else "references/" + f[:-3] + ".html"}"{" aria-current=\"page\"" if f == current else ""}>{html.escape(t)}</a>'
                  for f, t in [("SKILL.md", "The workflow")] + REFS)
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{page_title}</title>
<meta name="description" content="{description}"><link rel="canonical" href="{page_url}">
<meta property="og:type" content="website"><meta property="og:site_name" content="Move to Motoko"><meta property="og:title" content="{page_title}"><meta property="og:description" content="{description}"><meta property="og:url" content="{page_url}">
<meta property="og:image" content="{social_image}"><meta property="og:image:type" content="image/jpeg"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="og:image:alt" content="Move to Motoko. Move beyond the patch cycle. Start with the PHP migration skill.">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="{page_title}"><meta name="twitter:description" content="{description}"><meta name="twitter:image" content="{social_image}"><meta name="twitter:image:alt" content="Move to Motoko. Move beyond the patch cycle. Start with the PHP migration skill.">
<link rel="icon" href="{root}/assets/favicon.svg" type="image/svg+xml">
<link rel="stylesheet" href="{root}/assets/fonts.css"><link rel="stylesheet" href="{root}/assets/site.css">
<link rel="stylesheet" href="{root}/skills/migrating-php-apps/docs.css"><script src="{root}/skills/migrating-php-apps/docs.js" defer></script></head>
<body class="skill-docs"><a class="skip-link" href="#doc-content">Skip to content</a>
<header class="doc-top"><div class="wrap doc-site-nav">
<a class="doc-brand" href="{root}/"><img src="{root}/assets/move-to-motoko-mark.svg" width="34" height="34" alt=""><span>Move to Motoko</span></a>
<nav class="doc-site-links" aria-label="Site"><a href="{root}/#why-move">Why Motoko</a><a href="{root}/#the-process">The migration</a><a href="{root}/#skill">Get the skill ↗</a></nav></div>
<div class="wrap doc-head"><p class="doc-kicker">migrating-php-apps · {html.escape(raw_rel)}</p>
<h1>{html.escape(title)}</h1><p class="doc-deck">An agent skill for moving a PHP website or application to the Internet Computer with a Motoko backend. This is the readable version; agents load the Markdown file.</p>
<div class="doc-actions"><a href="{root}/skills/migrating-php-apps/{raw_rel}">Raw Markdown for agents ↗</a><a href="{root}/skills/migrating-php-apps.zip" download>Download skill ZIP ↓</a></div>
<div class="doc-companion"><span>Install the companion ICP skills</span><code>npx skills add dfinity/icskills</code></div>
<nav class="doc-nav" aria-label="Skill documents">{nav}</nav></div></header>
<main class="wrap doc" id="doc-content" tabindex="-1"><article class="doc-body">{html_body}</article><aside class="doc-toc" aria-label="On this page"><details class="doc-outline" open><summary><span>On this page</span><span class="doc-outline-icon" aria-hidden="true"></span></summary><div class="doc-outline-label" aria-hidden="true">On this page</div><nav aria-label="Document sections">{toc}</nav></details></aside></main>
<footer class="doc-footer"><div class="wrap"><p>Licensed Apache-2.0. Readable pages are generated from the repository; agents use the accompanying Markdown files.</p><a href="{root}/#skill">Return to your migration brief ↗</a></div></footer>
</body></html>"""

def render(md_text, this_file):
    body = fm.sub("", md_text, count=1)
    # links between the markdown files become links between the pages; the raw files stay available
    if not move_to_motoko:
        body = re.sub(r"\]\(references/([\w-]+)\.md\)", lambda m: f"](references/{m.group(1)}.html)", body)
        body = re.sub(r"\]\(([\w-]+)\.md\)", lambda m: f"]({m.group(1)}.html)", body)
    else:
        body = readable_markdown(body)
    md = markdown.Markdown(extensions=["pymdownx.superfences", "tables", "toc", "sane_lists"], extension_configs={"toc": {"toc_depth": "2-3"}}, tab_length=2 if move_to_motoko else 4)
    html_body = md.convert(body)
    if move_to_motoko:
        html_body = readable_links(html_body, this_file)
        # The page header supplies the document title. Remove only its duplicate,
        # and preserve any later source H1 sections as visible H2 headings.
        html_body = re.sub(r'^\s*<h1\b[^>]*>.*?</h1>\s*', '', html_body, count=1, flags=re.S)
        html_body = re.sub(r'<(/?)h1\b', r'<\1h2', html_body)
    # scrollable blocks must be reachable by keyboard
    html_body = re.sub(r'<pre\b([^>]*)>', lambda m: m.group(0) if re.search(r'\btabindex\s*=', m.group(1)) else '<pre tabindex="0"' + m.group(1) + '>', html_body)
    html_body = html_body.replace("<table>", '<table tabindex="0">')
    return html_body, md.toc

def page(title, html_body, toc, raw_rel, current):
    if move_to_motoko:
        return move_page(title, html_body, toc, raw_rel, current)
    nav = "".join(f'<a href="{root}/skills/migrating-php-apps/{"" if f == "SKILL.md" else "references/" + f[:-3] + ".html"}"{" aria-current=\"page\"" if f == current else ""}>{html.escape(t)}</a>'
                  for f, t in [("SKILL.md", "The skill")] + REFS)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)} · migrating-php-apps · PHP to Motoko</title>
<meta name="description" content="The migrating-php-apps skill for coding agents: moving a PHP site or application to the Internet Computer with a Motoko backend.">
<link rel="icon" href="{root}/favicon.svg" type="image/svg+xml">
<link rel="stylesheet" href="{root}/assets/fonts.css">
<link rel="stylesheet" href="{root}/assets/site.css">
<style>
.doc-top {{ background: var(--ink); color: var(--on-ink); }}
.doc-top .nav {{ padding-block: 14px; }}
.doc-head {{ padding: clamp(32px, 5vw, 64px) 0 clamp(24px, 4vw, 40px); }}
.doc-head h1 {{ font-size: clamp(32px, 4.6vw, 60px); font-weight: 800; letter-spacing: -0.035em; line-height: 1; }}
.doc-head p {{ margin-top: 14px; max-width: 70ch; color: var(--on-ink-2); }}
.doc-actions {{ display: flex; flex-wrap: wrap; gap: 10px 20px; align-items: center; margin-top: 22px; }}
.doc-actions code {{ background: var(--ink-3); color: var(--on-ink); border: 1px solid var(--ink-line); padding: 8px 12px; font-size: 13.5px; }}
.doc-actions .text-link {{ min-height: 40px; font-size: 15px; }}
.doc-nav {{ display: flex; flex-wrap: wrap; gap: 6px; margin-top: 24px; }}
.doc-nav a {{ display: inline-flex; align-items: center; min-height: 40px; padding: 0 14px; border: 1px solid var(--ink-line); border-radius: 999px; color: var(--on-ink-2); font-size: 14px; text-decoration: none; }}
.doc-nav a:hover {{ border-color: var(--on-ink-2); color: var(--on-ink); }}
.doc-nav a[aria-current="page"] {{ background: var(--marker); border-color: var(--marker); color: var(--ink); font-weight: 700; }}
.doc {{ display: grid; grid-template-columns: minmax(0, 1fr) 260px; gap: 48px 64px; padding-block: clamp(32px, 5vw, 56px) clamp(56px, 7vw, 96px); }}
.doc-body {{ min-width: 0; font-size: 17px; line-height: 1.6; }}
.doc-body h1 {{ display: none; }}
.doc-body h2 {{ font-size: clamp(26px, 3vw, 36px); margin: 48px 0 14px; letter-spacing: -0.025em; line-height: 1.1; padding-top: 18px; border-top: 1px solid var(--line); }}
.doc-body h2:first-of-type {{ border-top: 0; margin-top: 0; padding-top: 0; }}
.doc-body h3 {{ font-size: 21px; margin: 32px 0 10px; letter-spacing: -0.015em; line-height: 1.2; }}
.doc-body p, .doc-body li {{ color: var(--text-2); }}
.doc-body p + p {{ margin-top: 12px; }}
.doc-body ul, .doc-body ol {{ padding-left: 22px; margin: 10px 0; }}
.doc-body li + li {{ margin-top: 6px; }}
.doc-body li > ul, .doc-body li > ol {{ margin-top: 6px; }}
.doc-body strong {{ color: var(--text); }}
.doc-body code {{ font-size: 0.84em; overflow-wrap: anywhere; }}
.doc-body a, .doc-body li, .doc-body p, .doc-body h2, .doc-body h3 {{ overflow-wrap: anywhere; }}
.doc-body li > pre, .doc-body li > table {{ max-width: 100%; }}
.doc-body pre {{ margin: 16px 0; padding: 18px 20px; overflow-x: auto; background: var(--ink); color: var(--on-ink); border-radius: 10px; font-family: var(--mono); font-stretch: 75%; font-size: 13px; line-height: 1.65; }}
.doc-body pre code {{ background: none; padding: 0; font-size: inherit; color: inherit; font-stretch: inherit; }}
.doc-body table {{ width: 100%; border-collapse: collapse; margin: 16px 0; font-size: 15px; display: block; overflow-x: auto; }}
.doc-body th, .doc-body td {{ text-align: left; vertical-align: top; padding: 10px 12px; border-bottom: 1px solid var(--line); }}
.doc-body th {{ font-family: var(--mono); font-stretch: 87.5%; font-size: 12px; font-weight: 500; color: var(--text-3); }}
.doc-body a {{ font-weight: 600; }}
.doc-body blockquote {{ margin: 16px 0; padding: 4px 18px; border-left: 3px solid var(--marker); color: var(--text-2); }}
.doc-toc {{ position: sticky; top: 24px; align-self: start; font-size: 14px; }}
.doc-toc p {{ font-family: var(--mono); font-stretch: 87.5%; font-size: 12px; color: var(--text-3); margin-bottom: 10px; }}
.doc-toc ul {{ list-style: none; margin: 0; padding: 0; }}
.doc-toc ul ul {{ padding-left: 14px; }}
.doc-toc li {{ margin: 0; }}
.doc-toc a {{ display: block; padding: 5px 0; color: var(--text-2); text-decoration: none; border-left: 2px solid transparent; padding-left: 10px; margin-left: -12px; }}
.doc-toc a:hover {{ color: var(--text); border-color: var(--line); }}
@media (max-width: 980px) {{ .doc {{ grid-template-columns: minmax(0, 1fr); }} .doc-toc {{ position: static; order: -1; padding-bottom: 18px; border-bottom: 1px solid var(--line); }} }}
</style>
</head>
<body>
<div class="page">
<header class="doc-top">
<div class="wrap nav">
<a class="brand" href="{root}/"><svg class="mark" viewBox="0 0 28 28" aria-hidden="true"><rect x="3" y="7" width="22" height="5" rx="1" style="fill: #f3f3ef"></rect><rect x="3" y="16" width="15" height="5" rx="1" style="fill: #ffe15a"></rect></svg><span>PHP to Motoko</span></a>
<nav class="nav-links" aria-label="Site"><a class="nl" href="{root}/#problem">The problem</a><a class="nl" href="{root}/#steps">How it works</a><a class="nav-cta" href="{root}/skills/migrating-php-apps.zip">Download the skill</a></nav>
</div>
<div class="wrap doc-head">
<p style="font-family: var(--mono); font-stretch: 87.5%; font-size: 12px; color: var(--on-ink-2); margin: 0 0 10px">migrating-php-apps · {html.escape(raw_rel)}</p>
<h1>{html.escape(title)}</h1>
<p>An agent skill for moving a PHP website or application to the Internet Computer with a Motoko backend. This page is the readable version; agents load the Markdown file.</p>
<div class="doc-actions">
<a class="text-link" href="{root}/skills/migrating-php-apps/{raw_rel}">Raw Markdown for agents</a>
<a class="text-link" href="{root}/skills/migrating-php-apps.zip">Download (.zip)</a>
<code>npx skills add dfinity/icskills</code>
</div>
<nav class="doc-nav" aria-label="Skill documents">{nav}</nav>
</div>
</header>
<main class="wrap doc">
<article class="doc-body">{html_body}</article>
<aside class="doc-toc" aria-label="On this page"><p>On this page</p>{toc}</aside>
</main>
<footer class="foot"><div class="wrap foot-bottom"><p>Licensed Apache-2.0. The Markdown files next to these pages are the source.</p><p><a href="{root}/">PHP to Motoko</a></p></div></footer>
</div>
</body>
</html>
"""

out.mkdir(parents=True, exist_ok=True); (out / "references").mkdir(exist_ok=True)
if move_to_motoko:
    (out / "docs.css").write_text(DOC_CSS)
    (out / "docs.js").write_text(DOC_JS)
text = (skill / "SKILL.md").read_text(); title = re.search(r"^\s*title: \"(.*)\"$", text, re.M).group(1)
body, toc = render(text, "SKILL.md"); (out / "index.html").write_text(page(title, body, toc, "SKILL.md", "SKILL.md"))
for f, t in REFS:
    body, toc = render((skill / "references" / f).read_text(), "references/" + f)
    (out / "references" / (f[:-3] + ".html")).write_text(page(t, body, toc, "references/" + f, f))
print("rendered:", "index.html +", len(REFS), "reference pages")
