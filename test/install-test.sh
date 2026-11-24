#!/usr/bin/env bash
# Self-check for install.sh: fresh install, conflict refusal, update keeps project files.
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

git init -q "$T/p"
bash "$SRC/install.sh" "$T/p" --ponytail >/dev/null
for f in factory/bin/job factory/config.json factory/checks.sh factory/risk.md factory/VERSION \
         .claude/agents/factory-planner.md .claude/skills/factory/SKILL.md; do
  [ -e "$T/p/$f" ] || fail "missing $f"
done
[ -x "$T/p/factory/bin/job" ] || fail "job not executable"
grep -qxF "factory/jobs/" "$T/p/.gitignore" || fail ".gitignore"
grep -q PONYTAIL_SUBAGENT_MATCHER "$T/p/.claude/settings.json" || fail "ponytail settings"
(cd "$T/p" && python3 factory/bin/job concurrency) | grep -qx 3 || fail "job script does not run"

# Update keeps project files and adds new config keys.
echo "# mine" > "$T/p/factory/risk.md"
python3 -c "import json;p='$T/p/factory/config.json';c=json.load(open(p));del c['context_files'];json.dump(c,open(p,'w'))"
bash "$SRC/install.sh" "$T/p" >/dev/null
grep -qx "# mine" "$T/p/factory/risk.md" || fail "update overwrote risk.md"
grep -q context_files "$T/p/factory/config.json" || fail "new config key not added"
[ "$(grep -cxF ".worktrees/" "$T/p/.gitignore")" = 1 ] || fail ".gitignore duplicated"

# First install refuses to overwrite a project's own skill.
git init -q "$T/q"; mkdir -p "$T/q/.claude/skills/implement"; echo own > "$T/q/.claude/skills/implement/SKILL.md"
if bash "$SRC/install.sh" "$T/q" 2>/dev/null; then fail "overwrote own skill"; fi
grep -qx own "$T/q/.claude/skills/implement/SKILL.md" || fail "own skill changed"
[ ! -e "$T/q/factory" ] || fail "partial install after refusal"

echo "install-test: OK"
