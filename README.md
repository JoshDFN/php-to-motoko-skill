# migrating-php-apps

An agent skill that moves an existing PHP website or application to the Internet Computer with a Motoko backend: WordPress, Drupal, Joomla, Magento, Laravel, Symfony, CodeIgniter or plain PHP, with its data, users and links. Six phases with approval gates before anything irreversible: inventory, plan, build, move the data, move the users, switch over. It builds on the official ICP skills at https://skills.internetcomputer.org.

## Install

```bash
npx skills add JoshDFN/php-to-motoko-skill
```

The skills CLI requires Node.js 22.20 or later. Run from your PHP project folder and select your coding agent. Relevant supporting ICP skills are available with `npx skills add dfinity/icskills`; load only the guidance needed for the application.

## Use

Give your coding agent, in the PHP project:

> Load the migrating-php-apps skill and the ICP skills listed at https://skills.internetcomputer.org/llms.txt. Then move this PHP app to the Internet Computer: the backend in Motoko and the frontend on ICP, with its data, users and links. Inventory everything first, propose the plan, and wait for my approval before changing anything.

## Validation scope

The supplied source package reports local WordPress and Drupal migrations, platform-note checks, timers, state upgrades and both frontend-hosting targets. `PR-DESCRIPTION.md` records those author-reported observations. They are not new results from generating the website copies. The repository includes repeatable tests, but an export/import snapshot does not establish that every form, checkout, access rule or plugin behavior has been rebuilt. Validate the actual application's agreed journeys.

## Websites that carry the skill

The published websites are [PHP to Motoko](https://www.phptomotoko.com/) and [Move to Motoko](https://www.movetomotoko.com/). Both carry the readable workflow, raw Markdown and skill ZIP generated from this repository.

This repository is the only place the skill is edited. A website gets a copy: run `tools/sync-site.sh <site>/dist` before every deploy of that site. It copies the raw files (which agents read), rebuilds the download zip, and renders the readable pages into `<site>/dist/skills/migrating-php-apps/`. Never edit the files under a site's `skills/` folder; the next sync overwrites them. The command uses Python 3 and `zip`; renderer packages are installed into the ignored `.venv-site` in this checkout.

Use the generated readable pages for human-facing workflow and reference links. Keep the agent prompt and AI notes linked to the raw `.md` files. Run the site's own build/versioning step after syncing, check its links and browser output, and review the result before publishing.

The renderer supports PHP to Motoko and Move to Motoko using each site's existing
fonts and assets. It selects the design from the homepage's canonical hostname,
so a cross-link between the sites cannot switch the design. Both designs share
the same Markdown parsing and raw skill files. Move's documentation CSS and script
are generated locally alongside its readable pages.

## Tests

`tests/` checks documented components: the Motoko backend on a local ICP network, WordPress and Drupal fixtures, and platform notes. `bash tests/run-all.sh` runs the suite; `.github/workflows/tests.yml` defines the CI run. These checks have explicit limits and do not prove universal CMS/plugin compatibility. See `tests/README.md` for prerequisites and individual checks.

## Repository updates

```bash
git pull --ff-only
bash tools/sync-site.sh /absolute/path/to/site/dist
```

The canonical repository is [JoshDFN/php-to-motoko-skill](https://github.com/JoshDFN/php-to-motoko-skill). Syncing generates local website files; it does not publish the repository or deploy the site. Commit and publish reviewed source changes through the repository's normal process.

## Layout

- `skills/migrating-php-apps/SKILL.md` and `references/`: the skill
- `evaluations/migrating-php-apps.json`: trigger and output evaluations in the dfinity/icskills format
- `PR-DESCRIPTION.md`: text for the pull request to dfinity/icskills
- `tests/`: the test suite; `.github/workflows/tests.yml`: the CI workflow
- `tools/sync-site.sh`: copies the skill, its zip and the readable pages into a website folder
- `tools/render-skill-pages.py`: renders the skill as readable pages in the website's design (`python3 tools/render-skill-pages.py skills/migrating-php-apps <site>/dist/skills/migrating-php-apps`); the Markdown files stay next to the pages because agents read those. GitHub renders the Markdown itself, so the repository carries no generated HTML.
- `community-index-entry.json`: the entry for listing the skill as an ecosystem skill on skills.internetcomputer.org

Licensed Apache-2.0.
