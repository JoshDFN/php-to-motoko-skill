"""Move to Motoko presentation for the shared, parsed skill documents."""
import html


DOC_DESCRIPTIONS = {
    "SKILL.md": "The six-phase PHP migration workflow: inventory, plan, rebuild, reconcile data, reconnect users and verify cutover on the Internet Computer.",
    "references/inventory.md": "Read-only inventory guidance for mapping an existing PHP application before planning its move to Motoko and the Internet Computer.",
    "references/data-import.md": "Back up, export, convert, import and reconcile application data during a planned PHP-to-Motoko migration.",
    "references/backend-example.md": "A tested Motoko backend example for content storage, data imports and access checks to adapt to an application's migration plan.",
    "references/old-urls.md": "Preserve established URLs with redirect rules, legacy route mapping and checks for each old link during migration.",
    "references/frameworks.md": "Migration notes for PHP content systems and frameworks, with platform-specific decisions for a Motoko rebuild.",
    "references/delivery.md": "Choose delivery behavior for migrated pages and HTTP APIs, with explicit response-certification decisions.",
}


def move_page(title, html_body, toc, heading_id, raw_rel, nav, root, page_url, source_url, social_image):
    page_title = html.escape(title + " · Move to Motoko", quote=True)
    description = html.escape(DOC_DESCRIPTIONS[raw_rel], quote=True)
    page_url = html.escape(page_url, quote=True)
    social_image = html.escape(social_image, quote=True)
    source_url = html.escape(source_url, quote=True)
    heading_id = html.escape(heading_id or 'document-title', quote=True)
    return f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{page_title}</title>
<meta name="description" content="{description}"><link rel="canonical" href="{page_url}">
<meta property="og:type" content="website"><meta property="og:site_name" content="Move to Motoko"><meta property="og:title" content="{page_title}"><meta property="og:description" content="{description}"><meta property="og:url" content="{page_url}">
<meta property="og:image" content="{social_image}"><meta property="og:image:type" content="image/jpeg"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="og:image:alt" content="Move to Motoko. Move beyond the patch cycle. Start with the PHP migration skill.">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="{page_title}"><meta name="twitter:description" content="{description}"><meta name="twitter:image" content="{social_image}"><meta name="twitter:image:alt" content="Move to Motoko. Move beyond the patch cycle. Start with the PHP migration skill.">
<link rel="icon" href="{root}/assets/favicon.svg" type="image/svg+xml">
<link rel="stylesheet" href="{root}/assets/fonts.css"><link rel="stylesheet" href="{root}/assets/site.css">
<link rel="stylesheet" href="{root}/skills/migrating-php-apps/docs.css"><script src="{root}/skills/migrating-php-apps/docs.js" defer></script></head>
<body class="skill-docs"><a class="skip-link" href="#main">Skip to content</a>
<header class="doc-top"><div class="wrap doc-site-nav">
<a class="doc-brand" href="{root}/"><img src="{root}/assets/move-to-motoko-mark.svg" width="34" height="34" alt=""><span>Move to Motoko</span></a>
<nav class="doc-site-links" aria-label="Site"><a href="{root}/#why-move">Why Motoko</a><a href="{root}/#the-process">The migration</a><a href="{root}/#skill">Get the skill ↗</a></nav></div>
<div class="wrap doc-head"><p class="doc-kicker">migrating-php-apps · {html.escape(raw_rel)}</p>
<h1 id="{heading_id}">{html.escape(title)}</h1><p class="doc-deck">An agent skill for moving a PHP website or application to the Internet Computer with a Motoko backend. This is the readable version; agents load the Markdown file.</p>
<div class="doc-actions"><a href="{root}/skills/migrating-php-apps/{raw_rel}">Raw Markdown for agents ↗</a><a href="{root}/skills/migrating-php-apps.zip" download>Download skill ZIP ↓</a></div>
<div class="doc-companion"><span>Install the PHP migration skill</span><code>npx skills add JoshDFN/php-to-motoko-skill</code></div>
<nav class="doc-nav" aria-label="Skill documents">{nav}</nav></div></header>
<main class="wrap doc" id="main" tabindex="-1"><article class="doc-body">{html_body}</article><aside class="doc-toc" aria-label="On this page"><details class="doc-outline" open><summary><span>On this page</span><span class="doc-outline-icon" aria-hidden="true"></span></summary><div class="doc-outline-label" aria-hidden="true">On this page</div><nav aria-label="Document sections">{toc}</nav></details></aside></main>
<footer class="doc-footer"><div class="wrap"><p>Licensed <a href="{root}/skills/migrating-php-apps/LICENSE.txt">Apache-2.0</a>. <a href="{source_url}">View the skill source on GitHub</a>. Agents use the accompanying Markdown files.</p><a href="{root}/#skill">Return to your migration brief ↗</a></div></footer>
</body></html>"""
