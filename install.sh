#!/usr/bin/env bash
# Install or update the software factory in a project.
#
#   install.sh <project> [--force] [--ponytail] [--local]
#
# files/      the factory's own files; copied over the project on every install and update
# templates/  the project's own files (config.json, checks.sh, risk.md); copied only when missing.
#             On update, top-level keys new in templates/config.json are added to the project's.
# --force     first install only: overwrite project files that are in the way (e.g. an own plan-feature skill)
# --ponytail  add the Ponytail plugin to .claude/settings.json, pinned to PONYTAIL_REF
# --local     keep the factory out of git: its paths go to .git/info/exclude (never committed) instead of
#             .gitignore, and Ponytail to .claude/settings.local.json. Updates stay local once installed so.
set -euo pipefail

PONYTAIL_REF=7801d061243d7b753bad0e0b3c057cd250b11755 # v5.3.3

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
[ "$PROJECT" != "$SRC" ] || { echo "refusing to install the factory into its own repo" >&2; exit 1; }
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
  IGNORE="$EXCLUDE" SETTINGS=.claude/settings.local.json
  lines="factory/ .worktrees/ CLAUDE.local.md $SETTINGS"
  lines="$lines $(printf '%s\n' $FILES | sed -n 's|^\(\.claude/skills/[^/]*/\).*|\1|p; s|^\(\.claude/agents/.*\)|\1|p' | sort -u | tr '\n' ' ')"
else
  IGNORE="$PROJECT/.gitignore" SETTINGS=.claude/settings.json
  lines="factory/jobs/ .worktrees/"
fi
mkdir -p "$(dirname "$IGNORE")" && touch "$IGNORE"
[ "$LOCAL" = 0 ] || grep -qxF "$LOCAL_MARK" "$IGNORE" || printf '%s\n' "$LOCAL_MARK" >> "$IGNORE"
for line in $lines; do
  grep -qxF "$line" "$IGNORE" || printf '%s\n' "$line" >> "$IGNORE"
done

if [ "$PONYTAIL" = 1 ]; then
  mkdir -p "$PROJECT/.claude"
  python3 - "$PROJECT/$SETTINGS" "$PONYTAIL_REF" <<'EOF'
import json, os, sys
path, ref = sys.argv[1:3]
s = json.load(open(path)) if os.path.exists(path) else {}
# Ponytail's rules reach every subagent except the planner, so the plan keeps the scope the user asked for.
s.setdefault("env", {})["PONYTAIL_SUBAGENT_MATCHER"] = "^(?!factory-planner$)"
s.setdefault("enabledPlugins", {})["ponytail@ponytail"] = True
s.setdefault("extraKnownMarketplaces", {})["ponytail"] = {
    "source": {"source": "github", "repo": "DietrichGebert/ponytail", "ref": ref},
    "autoUpdate": False,
}
open(path, "w").write(json.dumps(s, indent=2) + "\n")
EOF
fi

git -C "$SRC" rev-parse HEAD > "$PROJECT/factory/VERSION" 2>/dev/null || echo unknown > "$PROJECT/factory/VERSION"
echo "Installed the software factory $(cut -c1-12 "$PROJECT/factory/VERSION") into $PROJECT"
