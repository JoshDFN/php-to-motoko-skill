# Tests

The scripts check components using code **from the skill's own documentation**. They exercise fixture snapshots, imports and selected runtime behavior; they do not establish that an application's forms, checkout, access rules or integrations have been rebuilt. They print `ok` / `FAIL` per check and exit non-zero on any failure.

| Script | What it checks | Needs |
|---|---|---|
| `test-lint.sh` | every shell and PHP block is valid; `skill-validator` (the icskills CI tool) passes; the icskills project checks pass | shellcheck, php, node 22, npm 11, git |
| `test-backend.sh` | the documented Motoko backend type-checks, deploys, imports the plain-PHP fixture, reconciles, is idempotent, refuses non-controllers, keeps data across upgrades, runs timers, and takes a post-go-live migration | icp-cli, mops |
| `test-wordpress.sh` | a real WordPress site with the common plugins (Contact Form 7, Yoast, WooCommerce, ACF, Elementor, Polylang) goes through inventory, export, import and comes out at its old permalinks | php, MariaDB or MySQL, icp-cli, mops |
| `test-drupal.sh` | a real Composer-layout Drupal site does the same, with alias paths and `/node/<nid>` redirects | php, composer, MariaDB or MySQL, icp-cli, mops |
| `test-notes.sh` | the Joomla, Laravel, Symfony, CodeIgniter and Magento facts in the platform notes are true | php, composer, MariaDB or MySQL |

Run one: `bash tests/test-backend.sh`. Run all: `bash tests/run-all.sh`. Work files go to `$WORK` (default `/tmp/mpa-tests`).

## Setup on Ubuntu

```bash
sudo apt-get install -y php-cli php-mysql php-xml php-mbstring php-curl php-zip php-gd php-intl php-sqlite3 mariadb-server shellcheck unzip
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
npm install -g @icp-sdk/icp-cli @icp-sdk/ic-wasm ic-mops npm@11
```

Database: the scripts use a running server on 127.0.0.1 (`DB_ROOT` / `DB_ROOT_PASS` for the root account; GitHub's runners use `root` / `root`). If none is running and `mariadbd` is installed, `test-*.sh` starts one under `$WORK`.

icp-cli downloads its local network launcher on first `icp network start`; the tests need outbound network access for that, for Composer and for WordPress.

## Pitfall the tests guard against

A fresh icp-cli deploys as the `anonymous` identity, which then controls the local canister, so access-control tests pass vacuously. `test-backend.sh` hands the canister to a named identity before testing rejections (skill pitfall 18).
