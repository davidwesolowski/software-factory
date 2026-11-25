#!/usr/bin/env bash
# Self-check for manual mode (use_labels false, auto_merge false), with a fake `gh` that logs its calls:
# a job from text runs to the end and is handed to the user; an issue without a label is accepted;
# no label is ever touched and nothing is merged.
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; [ -f "$T/gh.log" ] && sed 's/^/  gh /' "$T/gh.log" >&2; exit 1; }

mkdir "$T/bin"
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "api user") echo tester ;;
  "api repos/{owner}/{repo}/issues/5/dependencies/blocked_by") echo "[]" ;;
  "issue view") echo '{"number":5,"title":"Add export","body":"Export to CSV","author":{"login":"tester"},"comments":[],"url":"https://example.test/5","labels":[],"state":"OPEN"}' ;;
  "pr view") echo '{"number":12,"state":"OPEN","isDraft":true,"url":"https://example.test/pr/12"}' ;;
esac
EOF
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH" GH_LOG="$T/gh.log"

git init -q --bare -b main "$T/origin.git"
git clone -q "$T/origin.git" "$T/p" 2>/dev/null
cd "$T/p"
git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init && git push -q origin main
bash "$SRC/install.sh" . >/dev/null
python3 - <<'EOF'
import json
c = json.load(open("factory/config.json"))
c.update(use_labels=False, auto_merge=False, checks_configured=True)
json.dump(c, open("factory/config.json", "w"))
EOF
job=factory/bin/job

# A job from text: no issue, no gh call.
id=$(printf 'Dodaj eksport\nDo pliku CSV.\n' | $job create --text)
[ "$id" = "t01-dodaj-eksport" ] || fail "text job id: $id"
grep -q "Do pliku CSV" "factory/jobs/$id/issue.md" || fail "issue.md from text"
[ -d ".worktrees/$id" ] || fail "no worktree"
[ ! -s "$T/gh.log" ] || fail "gh called while creating a text job"

# job agent prints the OpenCode model id with its variant; a bad id is refused.
[ "$($job agent $id planner)" = "anthropic/claude-opus-5-5#high" ] || fail "job agent: $($job agent $id planner)"
python3 -c "import json;p='factory/config.json';c=json.load(open(p));c['steps']['builder']={'model':'opencode/big-pickle'};json.dump(c,open(p,'w'))"
[ "$($job agent $id builder)" = "opencode/big-pickle" ] || fail "job agent without variant"
python3 -c "import json;p='factory/config.json';c=json.load(open(p));c['steps']['builder']={'model':'sonnet'};json.dump(c,open(p,'w'))"
if $job agent $id builder >/dev/null 2>&1; then fail "job agent accepted a model without provider"; fi

# An issue without the factory label is accepted in manual mode.
[ "$($job create 5)" = "005-add-export" ] || fail "unlabelled issue refused"

# Drive the text job: spec -> build -> gate -> review -> finish.
d=factory/jobs/$id
printf 'DECISION: BUILD\nRISK: low\nSTATUS: READY\n\n## Summary\n- x\n\n## Risk\n- small\n' > $d/planning.md
mkdir -p ".worktrees/$id/context/$id" && echo "# plan" > ".worktrees/$id/context/$id/plan.md"
$job advance $id build >/dev/null
(cd ".worktrees/$id" && git add context && git -c user.name=t -c user.email=t@t commit -q -m plan && git push -q -u origin "factory/$id" 2>/dev/null)
printf 'STATUS: READY\n' > $d/build.md
$job advance $id gate >/dev/null
mkdir -p $d/round-1 && printf 'GATE: PASS\n' > $d/round-1/checks.md
$job advance $id review >/dev/null
printf 'VERDICT: PASS\n' > $d/round-1/review.md
$job finish $id >/dev/null

stage=$(python3 -c "import json;print(json.load(open('$d/job.json'))['stage'])")
[ "$stage" = "awaiting-merge" ] || fail "finish moved to $stage, not awaiting-merge"
! grep -q "pr merge" "$T/gh.log" || fail "the factory merged"
! grep -qE -- "-label|^label " "$T/gh.log" || fail "a label was touched"
! grep -q "issue comment" "$T/gh.log" || fail "commented on an issue for a text job"
grep -q "pr comment 12" "$T/gh.log" || fail "no hand-over comment on the PR"
$job status | grep -q "^$id *text" || fail "status does not show the text job"
$job queue | grep -q "wait .*$id" || fail "queue does not list the waiting job"

# Queue mode still refuses an issue without the label.
python3 -c "import json;p='factory/config.json';c=json.load(open(p));c['use_labels']=True;json.dump(c,open(p,'w'))"
rm -rf factory/jobs/005-add-export && git worktree remove --force .worktrees/005-add-export
if factory/bin/job create 5 2>/dev/null; then fail "queue mode accepted an unlabelled issue"; fi

echo "manual-mode-test: OK"
