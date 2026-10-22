# Add the migrating-php-apps workflow and site sync tools

The skill guides an agent through a PHP application inventory, an owner-approved feature map, a Motoko rebuild, data and URL migration, sign-in decisions, and a verified cutover. Plugins and integrations need explicit feature decisions and acceptance checks.

The repository is the only editable skill source. `tools/sync-site.sh <site-dist>` copies the raw files, rebuilds the download ZIP, and renders a readable skill page and six readable references. Website prompts and AI notes keep raw Markdown links; human links use the readable pages.

The package also includes component test scripts, WordPress and Drupal fixtures, a GitHub Actions workflow, and 11 model-evaluation definitions. These do not establish universal CMS or plugin compatibility.

## Validation for this review candidate

- Skill metadata validation passed.
- Scoped PHP exporter syntax and synthetic access/approval checks passed.
- Native macOS Bash inventory fixtures, conversion precision and bounds, and 22 synthetic import-driver checks passed.
- The backend example compiled without warnings using moc 1.15.1 and core 2.6.2.
- Generated HTML, internal links, raw/ZIP parity and responsive browser checks are recorded in the website review package.

Historical migration reports retained in the references describe earlier runs. The full CMS suite, live sign-in and upgrade paths, GitHub Actions, and model evaluations were not rerun for this website sync. Publication and deployment are separate release steps; consult the repository history and the site release records for their status.
