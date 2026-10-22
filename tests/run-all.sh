#!/usr/bin/env bash
# Runs every test; each test is independent and prints its own pass/fail summary.
cd "$(dirname "$0")" || exit 1; status=0
for t in test-lint.sh test-backend.sh test-wordpress.sh test-drupal.sh test-notes.sh; do
  echo; echo "########## $t"; bash "$t" || { status=1; echo "########## $t FAILED"; }
done
exit $status
