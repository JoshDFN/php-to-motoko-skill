#!/usr/bin/env python3
# Dependencies are managed by sync-site.sh in the checkout's .venv-site.
"""Render SKILL.md and its references as pages in the site's design.
Usage: render-skill-pages.py <skill folder> <output folder> [site URL prefix] [--site-dist dist]
The raw Markdown files are left untouched next to the pages, because agents read those."""
import argparse
import html
from html.parser import HTMLParser
import pathlib
import posixpath
import re
from urllib.parse import unquote, urljoin, urlsplit, urlunsplit
import xml.etree.ElementTree as etree

import markdown
from markdown.extensions import Extension
from markdown.extensions.toc import slugify
from markdown.treeprocessors import Treeprocessor
from move_docs import DOC_DESCRIPTIONS, move_page

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("skill", type=pathlib.Path)
parser.add_argument("out", type=pathlib.Path)
parser.add_argument("root", nargs="?", help="URL prefix for links and existing site assets")
parser.add_argument("--site-dist", type=pathlib.Path, help="Site folder containing index.html")
args = parser.parse_args()
skill, out = args.skill, args.out
fm = re.compile(r"\A---\r?\n(.*?)\r?\n---(?:\r?\n|$)", re.S)
SOURCE_URL = "https://github.com/JoshDFN/php-to-motoko-skill"

REFS = [("inventory.md", "Inventory script"), ("data-import.md", "Data export and import"), ("backend-example.md", "Tested backend example"),
        ("old-urls.md", "Keeping old URLs"), ("frameworks.md", "Platform notes"), ("delivery.md", "Dynamic delivery")]
PAGES = {"SKILL.md": "index.html", **{"references/" + name: "references/" + name[:-3] + ".html" for name, _ in REFS}}


class SiteMetadata(HTMLParser):
    """Use the destination site's own canonical URL; no hostname is assumed."""

    canonical = ""
    social_image = ""

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "link" and "canonical" in attrs.get("rel", "").lower().split():
            candidate = attrs.get("href", "")
            parsed = urlsplit(candidate)
            if parsed.scheme in ("https", "http") and parsed.netloc:
                self.canonical = urlunsplit((parsed.scheme, parsed.netloc, parsed.path, "", ""))
        elif tag == "meta" and attrs.get("property") == "og:image":
            self.social_image = attrs.get("content", "")


site_meta = SiteMetadata()
site_index = (args.site_dist or out.resolve().parents[1]) / "index.html"
if site_index.is_file():
    site_meta.feed(site_index.read_text(encoding="utf-8"))
site_url = site_meta.canonical.rstrip("/") + "/" if site_meta.canonical else ""
move_to_motoko = urlsplit(site_url).hostname in {"movetomotoko.com", "www.movetomotoko.com"}
root = args.root.rstrip("/") if args.root is not None else urlsplit(site_url).path.rstrip("/")
root = html.escape(root, quote=True)


def heading_slug(value, separator):
    slug = slugify(value, separator)
    return slug if slug[:1].isalpha() else "section" + separator + slug


class ReadableTree(Treeprocessor):
    def __init__(self, md, source_name):
        super().__init__(md)
        self.source_name = source_name
        self.heading_id = ""

    def run(self, tree):
        # Work on parsed links only: fenced and inline code examples stay literal.
        for link in tree.iter("a"):
            target = urlsplit(link.get("href", ""))
            if target.scheme or target.netloc:
                continue
            fragment = target.fragment
            if fragment and unquote(fragment)[:1].isdigit():
                fragment = "section-" + fragment
            if not target.path:
                link.set("href", urlunsplit(("", "", "", target.query, fragment)))
                continue
            source_path = posixpath.normpath(posixpath.join(posixpath.dirname(self.source_name), unquote(target.path)))
            if source_path in PAGES:
                readable_path = posixpath.relpath(PAGES[source_path], posixpath.dirname(PAGES[self.source_name]) or ".")
                link.set("href", urlunsplit(("", "", readable_path, target.query, fragment)))
        # The page header supplies the one visible h1. Keep its Markdown anchor.
        for heading in list(tree):
            if heading.tag == "h1":
                self.heading_id = heading.get("id", "")
                tree.remove(heading)
                break
        for heading in tree.iter("h1"):
            heading.tag = "h2"
        for pre in tree.iter("pre"):
            pre.set("tabindex", "0")
            pre.set("aria-label", "Code example")
        table_number = 0
        for parent in list(tree.iter()):
            for index, child in enumerate(list(parent)):
                if child.tag == "table":
                    table_number += 1
                    scroll = etree.Element("section", {"class": "table-scroll", "tabindex": "0", "aria-label": f"Scrollable table {table_number}"})
                    parent.remove(child)
                    parent.insert(index, scroll)
                    scroll.append(child)
                    for th in child.iter("th"):
                        th.set("scope", "col")


class ReadableExtension(Extension):
    def __init__(self, source_name):
        super().__init__()
        self.source_name = source_name

    def extendMarkdown(self, md):
        self.processor = ReadableTree(md, self.source_name)
        # After inline links and TOC IDs have been parsed, before serialization.
        md.treeprocessors.register(self.processor, "readable-pages", 4)

def render(md_text, this_file):
    body = fm.sub("", md_text, count=1)
    readable = ReadableExtension(this_file)
    md = markdown.Markdown(extensions=["pymdownx.superfences", "tables", "toc", "sane_lists", readable],
                           extension_configs={"toc": {"toc_depth": "2-3", "slugify": heading_slug}}, output_format="html")
    html_body = md.convert(body)
    # SuperFences restores stashed code HTML after tree processing.
    html_body = re.sub(r'<pre(?![^>]*\btabindex=)(?=[\s>])', '<pre tabindex="0" aria-label="Code example"', html_body)
    return html_body, md.toc, readable.processor.heading_id

def page(title, html_body, toc, heading_id, raw_rel, current):
    nav_links = []
    for name, label in [("SKILL.md", "The workflow" if move_to_motoko else "The skill")] + REFS:
        target = "" if name == "SKILL.md" else "references/" + name[:-3] + ".html"
        current_attr = ' aria-current="page"' if name == current else ""
        nav_links.append(f'<a href="{root}/skills/migrating-php-apps/{target}"{current_attr}>{html.escape(label)}</a>')
    nav = "".join(nav_links)
    page_path = "" if raw_rel == "SKILL.md" else PAGES[raw_rel]
    canonical_url = urljoin(site_url, "skills/migrating-php-apps/" + page_path) if site_url else ""
    if move_to_motoko:
        social_image = urljoin(site_url, site_meta.social_image or "assets/move-to-motoko-social-v3.jpg")
        return move_page(title, html_body, toc, heading_id, raw_rel, nav, root, canonical_url, SOURCE_URL, social_image)
    canonical = f'<link rel="canonical" href="{html.escape(canonical_url, quote=True)}">' if canonical_url else ""
    description = html.escape(DOC_DESCRIPTIONS[raw_rel], quote=True)
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)} · migrating-php-apps · PHP to Motoko</title>
<meta name="description" content="{description}">
{canonical}
<link rel="icon" href="{root}/favicon.svg" type="image/svg+xml">
<link rel="stylesheet" href="{root}/assets/fonts.css">
<link rel="stylesheet" href="{root}/assets/site.css">
<style>
.doc-top {{ background: var(--ink); color: var(--on-ink); }}
.doc-top .nav {{ padding-block: 14px; flex-wrap: wrap; }}
.doc-head {{ padding-block: clamp(32px, 5vw, 64px) clamp(24px, 4vw, 40px); }}
.doc-head h1 {{ font-size: clamp(32px, 4.6vw, 60px); font-weight: 800; letter-spacing: -0.035em; line-height: 1; overflow-wrap: anywhere; }}
.doc-head p {{ margin-top: 14px; max-width: 70ch; color: var(--on-ink-2); }}
.doc-head .doc-kicker {{ font-family: var(--mono); font-stretch: 87.5%; font-size: 12px; color: var(--on-ink-2); margin: 0 0 10px; overflow-wrap: anywhere; }}
.doc-actions {{ display: flex; flex-wrap: wrap; gap: 10px 20px; align-items: center; margin-top: 22px; }}
.doc-actions code {{ background: var(--ink-3); color: var(--on-ink); border: 1px solid var(--ink-line); padding: 8px 12px; font-size: 13.5px; min-width: 0; max-width: 100%; overflow-wrap: anywhere; }}
.doc-actions .text-link {{ min-height: 40px; font-size: 15px; }}
.doc-nav {{ display: flex; flex-wrap: wrap; gap: 6px; margin-top: 24px; }}
.doc-nav a {{ display: inline-flex; align-items: center; min-height: 40px; max-width: 100%; padding: 6px 14px; border: 1px solid var(--ink-line); border-radius: 999px; color: var(--on-ink-2); font-size: 14px; text-decoration: none; }}
.doc-nav a:hover {{ border-color: var(--on-ink-2); color: var(--on-ink); }}
.doc-nav a[aria-current="page"] {{ background: var(--marker); border-color: var(--marker); color: var(--ink); font-weight: 700; }}
.doc {{ display: grid; grid-template-columns: minmax(0, 1fr) 260px; gap: 48px 64px; padding-block: clamp(32px, 5vw, 56px) clamp(56px, 7vw, 96px); }}
.doc-body {{ min-width: 0; font-size: 17px; line-height: 1.6; }}
.doc-body h2 {{ font-size: clamp(26px, 3vw, 36px); margin: 48px 0 14px; letter-spacing: -0.025em; line-height: 1.1; padding-top: 18px; border-top: 1px solid var(--line); }}
.doc-body h2:first-of-type {{ border-top: 0; margin-top: 0; padding-top: 0; }}
.doc-body h3 {{ font-size: 21px; margin: 32px 0 10px; letter-spacing: -0.015em; line-height: 1.2; }}
.doc-body p, .doc-body li {{ color: var(--text-2); }}
.doc-body p + p {{ margin-top: 12px; }}
.doc-body ul, .doc-body ol {{ padding-left: 22px; margin: 10px 0; }}
.doc-body li + li {{ margin-top: 6px; }}
.doc-body li > ul, .doc-body li > ol {{ margin-top: 6px; }}
.doc-body strong {{ color: var(--text); }}
.doc-body :focus-visible, .doc-toc :focus-visible {{ outline-color: var(--ink); }}
.doc-body code {{ font-size: 0.84em; overflow-wrap: anywhere; }}
.doc-body a, .doc-body li, .doc-body p, .doc-body h2, .doc-body h3 {{ overflow-wrap: anywhere; }}
.doc-body .highlight {{ min-width: 0; max-width: 100%; }}
.doc-body pre {{ max-width: 100%; margin: 16px 0; padding: 18px 20px; overflow-x: auto; background: var(--ink); color: var(--on-ink); border-radius: 10px; font-family: var(--mono); font-stretch: 75%; font-size: 13px; line-height: 1.65; }}
.doc-body pre:focus-visible {{ outline-color: var(--marker); outline-offset: -4px; }}
.doc-body pre code {{ background: none; padding: 0; font-size: inherit; color: inherit; font-stretch: inherit; }}
.doc-body .table-scroll {{ max-width: 100%; overflow-x: auto; margin: 16px 0; padding: 0; }}
.doc-body table {{ width: 100%; border-collapse: collapse; font-size: 15px; }}
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
<a class="skip-link" href="#main">Skip to content</a>
<div class="page">
<header class="doc-top">
<div class="wrap nav">
<a class="brand" href="{root}/"><svg class="mark" viewBox="0 0 28 28" aria-hidden="true"><rect x="3" y="7" width="22" height="5" rx="1" fill="#f3f3ef"></rect><rect x="3" y="16" width="15" height="5" rx="1" fill="#ffe15a"></rect></svg><span>PHP to Motoko</span></a>
<nav class="nav-links" aria-label="Site"><a class="nl" href="{root}/#problem">The problem</a><a class="nl" href="{root}/#steps">How it works</a><a class="nav-cta" href="{root}/skills/migrating-php-apps.zip">Download the skill</a></nav>
</div>
<div class="wrap doc-head">
<p class="doc-kicker">migrating-php-apps · {html.escape(raw_rel)}</p>
<h1 id="{html.escape(heading_id or 'document-title', quote=True)}">{html.escape(title)}</h1>
<p>An agent skill for moving a PHP website or application to the Internet Computer with a Motoko backend. This page is the readable version; agents load the Markdown file.</p>
<div class="doc-actions">
<a class="text-link" href="{root}/skills/migrating-php-apps/{raw_rel}">Raw Markdown for agents</a>
<a class="text-link" href="{root}/skills/migrating-php-apps.zip">Download (.zip)</a>
<code>npx skills add JoshDFN/php-to-motoko-skill</code>
</div>
<nav class="doc-nav" aria-label="Skill documents">{nav}</nav>
</div>
</header>
<main class="wrap doc" id="main" tabindex="-1">
<article class="doc-body">{html_body}</article>
<aside class="doc-toc" aria-label="On this page"><p>On this page</p>{toc}</aside>
</main>
<footer class="foot"><div class="wrap foot-bottom"><p>Licensed <a href="{root}/skills/migrating-php-apps/LICENSE.txt">Apache-2.0</a>. <a href="{SOURCE_URL}">View the skill source on GitHub</a>.</p><p><a href="{root}/">PHP to Motoko</a></p></div></footer>
</div>
</body>
</html>
"""

out.mkdir(parents=True, exist_ok=True); (out / "references").mkdir(exist_ok=True)
if move_to_motoko:
    for source_name, output_name in (("move-docs.css", "docs.css"), ("move-docs.js", "docs.js")):
        (out / output_name).write_bytes((pathlib.Path(__file__).parent / source_name).read_bytes())
text = (skill / "SKILL.md").read_text(encoding="utf-8")
title_match = re.search(r'^\s*title:\s*"(.*)"\s*$', fm.match(text).group(1) if fm.match(text) else "", re.M)
heading_match = re.search(r"^#\s+(.+)$", fm.sub("", text, count=1), re.M)
title = title_match.group(1) if title_match else heading_match.group(1) if heading_match else "Migrating PHP Apps to Motoko"
body, toc, heading_id = render(text, "SKILL.md")
(out / "index.html").write_text(page(title, body, toc, heading_id, "SKILL.md", "SKILL.md"), encoding="utf-8")
for f, t in REFS:
    body, toc, heading_id = render((skill / "references" / f).read_text(encoding="utf-8"), "references/" + f)
    (out / "references" / (f[:-3] + ".html")).write_text(page(t, body, toc, heading_id, "references/" + f, f), encoding="utf-8")
print("rendered:", "index.html +", len(REFS), "reference pages")
