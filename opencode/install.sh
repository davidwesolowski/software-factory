#!/usr/bin/env bash
# Install or update the software factory for OpenCode in a project.
#
#   install.sh <project> [--force] [--ponytail] [--local]
#
# files/      the factory's own files; copied over the project on every install and update
# templates/  the project's own files (config.json, checks.sh, risk.md); copied only when missing.
#             On update, top-level keys new in templates/config.json are added to the project's.
# --force     first install only: overwrite project files that are in the way (e.g. an own plan-feature skill)
# --ponytail  add the Ponytail plugin to .opencode/opencode.json, pinned to PONYTAIL_VERSION
# --local     keep the factory out of git: its paths go to .git/info/exclude (never committed) instead of
#             .gitignore, and .opencode/factory.md joins the config's instructions (what CLAUDE.local.md
#             is in Claude Code). Updates stay local once installed so.
# Always:     .opencode/opencode.json gets experimental.subagent_depth 3, so the builder and the reviewer
#             can run their own subagents, and those their helpers, as in Claude Code.
set -euo pipefail

PONYTAIL_VERSION=5.3.3

SRC="$(cd "$(dirname "$0")" && pwd)"
PROJECT="" FORCE=0 PONYTAIL=0 LOCAL=0
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;;
    --ponytail) PONYTAIL=1 ;;
    --local) LOCAL=1 ;;
    -*) echo "unknown option $a" >&2; exit 64 ;;
    *) PROJECT="$a" ;;
  esac
done
[ -n "$PROJECT" ] || { echo "usage: install.sh <project> [--force] [--ponytail] [--local]" >&2; exit 64; }
PROJECT="$(cd "$PROJECT" && git rev-parse --show-toplevel)" || { echo "$PROJECT is not a git repository" >&2; exit 1; }
[ "$PROJECT" != "$(git -C "$SRC" rev-parse --show-toplevel 2>/dev/null)" ] || { echo "refusing to install the factory into its own repo" >&2; exit 1; }
EXCLUDE="$(git -C "$PROJECT" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
LOCAL_MARK="# software factory (local install)"
grep -qxF "$LOCAL_MARK" "$EXCLUDE" 2>/dev/null && LOCAL=1

cd "$SRC/files"
FILES=$(find . -type f | sed 's|^\./||' | sort)

# First install: never overwrite a project's own file silently.
if [ ! -f "$PROJECT/factory/VERSION" ] && [ "$FORCE" = 0 ]; then
  conflicts=""
  for f in $FILES; do
    if [ -e "$PROJECT/$f" ] && ! cmp -s "$f" "$PROJECT/$f"; then conflicts="$conflicts  $f"$'\n'; fi
  done
  if [ -n "$conflicts" ]; then
    printf 'These project files differ from the factory'"'"'s and would be overwritten:\n%sRe-run with --force to overwrite them.\n' "$conflicts" >&2
    exit 2
  fi
fi

for f in $FILES; do
  mkdir -p "$PROJECT/$(dirname "$f")"
  cp "$f" "$PROJECT/$f"
done
chmod +x "$PROJECT"/factory/bin/*

for t in config.json checks.sh risk.md; do
  [ -e "$PROJECT/factory/$t" ] || cp "$SRC/templates/$t" "$PROJECT/factory/$t"
done
chmod +x "$PROJECT/factory/checks.sh"

python3 - "$SRC/templates/config.json" "$PROJECT/factory/config.json" <<'EOF'
import json, sys
tpl, path = (json.load(open(p)) for p in sys.argv[1:3])
added = [k for k in tpl if k not in path]
if added:
    path.update({k: tpl[k] for k in added})
    open(sys.argv[2], "w").write(json.dumps(path, indent=2) + "\n")
    print("config.json: added " + ", ".join(added))
EOF

if [ "$LOCAL" = 1 ]; then
  # Everything the factory adds, so `git status` never shows it. Applies to untracked files only.
  IGNORE="$EXCLUDE"
  lines="factory/ .worktrees/ .opencode/opencode.json .opencode/factory.md"
  lines="$lines $(printf '%s\n' $FILES | sed -n 's|^\(\.opencode/skills/[^/]*/\).*|\1|p; s|^\(\.opencode/agents/.*\)|\1|p; s|^\(\.opencode/commands/.*\)|\1|p' | sort -u | tr '\n' ' ')"
else
  IGNORE="$PROJECT/.gitignore"
  lines="factory/jobs/ .worktrees/"
fi
mkdir -p "$(dirname "$IGNORE")" && touch "$IGNORE"
[ "$LOCAL" = 0 ] || grep -qxF "$LOCAL_MARK" "$IGNORE" || printf '%s\n' "$LOCAL_MARK" >> "$IGNORE"
for line in $lines; do
  grep -qxF "$line" "$IGNORE" || printf '%s\n' "$line" >> "$IGNORE"
done

mkdir -p "$PROJECT/.opencode"
python3 - "$PROJECT/.opencode/opencode.json" "$PONYTAIL" "$PONYTAIL_VERSION" "$LOCAL" <<'EOF'
import json, os, sys
path, ponytail, version, local = sys.argv[1:5]
try:
    s = json.load(open(path)) if os.path.exists(path) else {}
except ValueError:
    sys.exit("%s is not plain JSON (comments?): add the factory's keys by hand, see install.sh" % path)
s.setdefault("$schema", "https://opencode.ai/config.json")
exp = s.setdefault("experimental", {})
exp["subagent_depth"] = max(exp.get("subagent_depth", 1), 3)
if local == "1" and ".opencode/factory.md" not in s.setdefault("instructions", []):
    s["instructions"].append(".opencode/factory.md")
if ponytail == "1":
    plugins = [p for p in s.get("plugins", []) if not str(p).startswith("@dietrichgebert/ponytail")]
    s["plugins"] = plugins + ["@dietrichgebert/ponytail@" + version]
open(path, "w").write(json.dumps(s, indent=2) + "\n")
EOF

git -C "$SRC" rev-parse HEAD > "$PROJECT/factory/VERSION" 2>/dev/null || echo unknown > "$PROJECT/factory/VERSION"
echo "Installed the software factory for OpenCode $(cut -c1-12 "$PROJECT/factory/VERSION") into $PROJECT"
