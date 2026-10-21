# PHP to Motoko migration skill

A migration workflow for an existing PHP application: inventory real behavior, agree a target, rebuild capabilities, import data and validate ongoing operations. It does not execute PHP plugins unchanged or convert every plugin automatically.

## Repository layout

- `skills/migrating-php-apps/SKILL.md`: concise core instructions.
- `skills/migrating-php-apps/references/`: optional examples and platform/protocol details.
- `evaluations/migrating-php-apps.json`: behavioral and trigger evaluation cases; these are not recorded passes.
- `LICENSE.txt`: Apache 2.0.

## Install

Requires Node.js 22.20 or later. Install the migration skill into your project and choose your coding agent when prompted:

For a local installation from another project directory:

```sh
npx skills add JoshDFN/php-to-motoko-skill --skill migrating-php-apps
```

For Codex, add `--agent codex`. To inspect the available skill without installing it:

```sh
npx skills add JoshDFN/php-to-motoko-skill --list
```

Ask your agent to use `migrating-php-apps` for a read-only inventory and migration plan first. Review the plan before authorizing application changes or deployment. The agent can load relevant supporting [ICP skills](https://skills.internetcomputer.org/) as needed.

You can also [read the workflow](skills/migrating-php-apps/SKILL.md) or visit [phptomotoko.com](https://www.phptomotoko.com/).

## Validation and provenance

The supplied `.skill` archive contains newer plugin/export guidance than the separate supplied repository ZIP. Author-reported WordPress 7.1, Drupal and component tests are preserved as provenance; fixtures, export outputs and raw migration logs were not included. They are not presented as tests rerun by this project.

The merged revision includes dynamic HTTP and certification guidance. Component checks covered syntax, synthetic inventory/export/converter fixtures, Motoko compilation, package consistency and local skills-CLI installation. This repository does not include a repeatable end-to-end migration test suite. Application compatibility still requires the actual extensions, roles, publishing and integration journeys to pass.

## Evaluation with the ICP skills project

The current upstream project supports `skill-validator score evaluate --provider claude-cli skills/migrating-php-apps`. It requires the skill-validator binary and an authenticated Claude CLI. No novelty score has been run or invented here.

For an official contribution, copy this skill and its evaluation file into the corresponding directories of `dfinity/icskills` and use that project's validation/evaluation scripts. The supplied evaluation file has been updated so it no longer rewards the obsolete ban on dynamic Motoko HTTP.

An ecosystem listing needs a real repository URL and the current `community/index.json` schema in `dfinity/icskills`. Submit it after the repository URL is chosen; no placeholder URL is shipped as a real listing.
