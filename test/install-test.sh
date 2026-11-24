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

# --local: nothing the factory adds shows in git status, .gitignore untouched, and updates stay local.
git init -q "$T/l"; (cd "$T/l" && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init)
bash "$SRC/install.sh" "$T/l" --local --ponytail >/dev/null
[ ! -e "$T/l/.gitignore" ] || fail "--local wrote .gitignore"
[ -z "$(git -C "$T/l" status --porcelain)" ] || fail "--local install shows in git status: $(git -C "$T/l" status --porcelain)"
grep -q PONYTAIL_SUBAGENT_MATCHER "$T/l/.claude/settings.local.json" || fail "--local ponytail not in settings.local.json"
[ ! -e "$T/l/.claude/settings.json" ] || fail "--local wrote settings.json"
echo note > "$T/l/CLAUDE.local.md"; mkdir -p "$T/l/.worktrees/x" "$T/l/factory/jobs/x"; touch "$T/l/.worktrees/x/f" "$T/l/factory/jobs/x/job.json"
bash "$SRC/install.sh" "$T/l" >/dev/null
[ -z "$(git -C "$T/l" status --porcelain)" ] || fail "update of a local install shows in git status"
[ "$(grep -cxF "factory/" "$T/l/.git/info/exclude")" = 1 ] || fail "exclude duplicated"

echo "install-test: OK"
