# migrating-php-apps

An agent skill that moves an existing PHP website or application to the Internet Computer with a Motoko backend: WordPress, Drupal, Joomla, Magento, Laravel, Symfony, CodeIgniter or plain PHP, with its data, users and links. Six phases with approval gates before anything irreversible: inventory, plan, build, move the data, move the users, switch over. It builds on the official ICP skills at https://skills.internetcomputer.org.

## Install

```bash
npx skills add JoshDFN/php-to-motoko-skill --skill migrating-php-apps
```

Install the official ICP skills it builds on: `npx skills add dfinity/icskills`.

## Use

Give your coding agent, in the PHP project:

> Load the migrating-php-apps skill and the ICP skills listed at https://skills.internetcomputer.org/llms.txt. Then move this PHP app to the Internet Computer: the backend in Motoko and the frontend on ICP, with its data, users and links. Inventory everything first, propose the plan, and wait for my approval before changing anything.

## Reported testing

The following results are reports from the supplied source package’s author. They have not been independently rerun for this GitHub update. This repository includes the supplied fixtures and repeatable test suite; check the [GitHub Actions results](https://github.com/JoshDFN/php-to-motoko-skill/actions) for the checks executed against each revision.

Full migrations of real WordPress 7.1 (including Contact Form 7, Yoast SEO, WooCommerce, Advanced Custom Fields, Elementor and Polylang) and Drupal 11.4 sites on a local ICP network; the platform notes checked against real Joomla 6, Laravel 13, Symfony 7.4 and CodeIgniter 4.7 installs and Magento 2.4's schema; Motoko timers, post-launch data-model changes, browser bindings and both deployment targets verified. `PR-DESCRIPTION.md` preserves the supplied author’s detailed test report and reported CI results.

## Websites that carry the skill

The public migration site is [Move to Motoko](https://www.movetomotoko.com/). It carries the readable workflow, raw Markdown and skill ZIP generated from this repository.

This repository is the only place the skill is edited. A website gets a copy: run `tools/sync-site.sh <site>/dist` before every deploy of that site. It copies the raw files (which agents read), rebuilds the download zip, and renders the readable pages into `<site>/dist/skills/migrating-php-apps/`. Never edit the files under a site's `skills/` folder; the next sync overwrites them.

## Tests

`tests/` is the supplied suite for exercising the documented migration steps on a fresh machine: the Motoko backend on a local ICP network (import, access control, upgrades, timers, a post-go-live migration), a real WordPress site with the common plugins, a real Drupal site, and the platform notes against Joomla, Laravel, Symfony, CodeIgniter and Magento. `bash tests/run-all.sh` runs them all; `.github/workflows/tests.yml` runs them on every push. See `tests/README.md`.

## Repository maintenance

```bash
git clone git@github.com:JoshDFN/php-to-motoko-skill.git
cd php-to-motoko-skill
# Make and review changes, then commit and push to main.
```

The workflow runs on pushes to `main` and pull requests; results appear under the repository’s Actions tab. `npx skills add JoshDFN/php-to-motoko-skill --skill migrating-php-apps` installs the published skill.

## Layout

- `skills/migrating-php-apps/SKILL.md` and `references/`: the skill
- `evaluations/migrating-php-apps.json`: trigger and output evaluations in the dfinity/icskills format
- `PR-DESCRIPTION.md`: text for the pull request to dfinity/icskills
- `tests/`: the test suite; `.github/workflows/tests.yml`: the CI workflow
- `tools/sync-site.sh`: copies the skill, its zip and the readable pages into a website folder
- `tools/render-skill-pages.py`: renders the skill as readable pages in the website's design (`python3 tools/render-skill-pages.py skills/migrating-php-apps <site>/dist/skills/migrating-php-apps`); the Markdown files stay next to the pages because agents read those. GitHub renders the Markdown itself, so the repository carries no generated HTML.
- `community-index-entry.json`: the entry for listing the skill as an ecosystem skill on skills.internetcomputer.org

Licensed Apache-2.0.
