#!/usr/bin/env bash
# Lints the skill the way the dfinity/icskills CI does, plus every code block in it.
# Needs: shellcheck, php, python3, node >= 22, npm >= 11 (for the icskills project checks), git, curl.
source "$(dirname "$0")/lib.sh"
need shellcheck php python3 node curl git

bash "$ROOT/tests/test-cli-output.sh"
python3 "$ROOT/tests/test-wordpress-export.py"

section "shell blocks (ShellCheck) and PHP blocks (php -l)"
bad=0; total=0
for f in "$SKILL/SKILL.md" "$SKILL"/references/*.md; do
  n=$(python3 -c "import re,sys; print(len(re.findall(r'\`\`\`bash\n(.*?)\`\`\`', open(sys.argv[1]).read(), re.S)))" "$f")
  for ((i=0; i<n; i++)); do
    total=$((total + 1)); extract_block "$f" bash "$i" "$WORK/block.sh"
    if ! shellcheck -S warning -s bash "$WORK/block.sh" >/dev/null 2>&1; then bad=$((bad + 1)); echo "  ShellCheck: $(basename "$f") bash block $i"; shellcheck -S warning -s bash "$WORK/block.sh" | head -8; fi
  done
  m=$(python3 -c "import re,sys; print(len(re.findall(r'\`\`\`php\n(.*?)\`\`\`', open(sys.argv[1]).read(), re.S)))" "$f")
  for ((i=0; i<m; i++)); do
    total=$((total + 1)); extract_block "$f" php "$i" "$WORK/block.php"
    php -l "$WORK/block.php" >/dev/null 2>&1 || { bad=$((bad + 1)); echo "  PHP syntax: $(basename "$f") php block $i"; }
  done
done
assert_eq "all $total shell and PHP blocks are clean" "$bad" "0"

SV_VERSION="${SV_VERSION:-1.5.1}"
section "skill-validator $SV_VERSION (the icskills CI tool)"
if ! command -v skill-validator >/dev/null 2>&1; then
  mkdir -p "$WORK/bin"; curl -sL "https://github.com/agent-ecosystem/skill-validator/releases/download/v${SV_VERSION}/skill-validator_${SV_VERSION}_linux_amd64.tar.gz" | tar xz -C "$WORK/bin" skill-validator
  export PATH="$WORK/bin:$PATH"
fi
# The downloadable/installable package carries its legal license. Check that
# exact layout and license bytes before permitting the validator's flat file layout.
python3 - "$SKILL" "$ROOT/LICENSE.txt" <<'PYLAYOUT'
from pathlib import Path
import sys
skill, license_file = map(Path, sys.argv[1:])
assert {p.name for p in skill.iterdir()} == {"SKILL.md", "LICENSE.txt", "references"}, "unexpected skill-root entry"
assert (skill / "references").is_dir(), "missing references directory"
assert (skill / "LICENSE.txt").read_bytes() == license_file.read_bytes(), "packaged license differs from source"
PYLAYOUT
validator_status=0
skill-validator check "$SKILL" --skip links --allow-flat-layouts -o markdown > "$WORK/sv.md" 2>&1 || validator_status=$?
cat "$WORK/sv.md"
assert_eq "skill-validator exits successfully" "$validator_status" "0"
assert_contains "skill-validator passes with no warnings" "$(grep -o 'Result: [a-z 0-9]*' "$WORK/sv.md")" "Result: passed"
assert_contains "SKILL.md body under 5000 tokens" "$(grep -E 'SKILL.md body' "$WORK/sv.md" | head -1)" "SKILL.md body | [0-4],"

section "dfinity/icskills project checks (fresh clone)"
if command -v npm >/dev/null 2>&1; then
  R="$WORK/icskills"; [ -d "$R" ] || git clone -q --depth 1 https://github.com/dfinity/icskills "$R"
  rm -rf "$R/skills/migrating-php-apps" && cp -r "$SKILL" "$R/skills/migrating-php-apps" && cp "$ROOT/evaluations/migrating-php-apps.json" "$R/evaluations/"
  (cd "$R" && npm ci --no-audit --no-fund --loglevel=error >/dev/null 2>&1 || true)
  out=$(cd "$R" && node scripts/check-project.js migrating-php-apps 2>&1 | tail -1)
  assert_contains "check-project.js passes" "$out" "Project checks passed"
  if [ "${BUILD_SITE:-0}" = "1" ]; then
    (cd "$R" && npm run build > "$WORK/astro.log" 2>&1) && ok "skills site builds with the skill" || fail "skills site build (see $WORK/astro.log)"
  fi
else
  echo "  (npm not found: skipping the icskills project checks)"
fi
summary
