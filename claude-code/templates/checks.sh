#!/usr/bin/env bash
# The project's checks. factory/bin/gate runs this file from the MAIN checkout
# inside a job's worktree, so a branch can never change the checks it is judged by.
# Any non-zero exit fails the gate. Set "checks_configured": true in
# factory/config.json once this file runs real checks; until then nothing auto-merges.
set -euo pipefail

step() { printf '\n==> %s\n' "$*"; }

# Replace with the project's own checks, for example:
# step "install";    npm ci
# step "typecheck";  npm run typecheck
# step "lint";       npm run lint
# step "tests";      npm test

# The checks must not leave tracked files changed (a formatter, a snapshot update).
step "working tree unchanged by the checks"
if ! git diff --quiet; then
  echo "The checks changed tracked files:"
  git diff --stat
  exit 1
fi

exit 0
