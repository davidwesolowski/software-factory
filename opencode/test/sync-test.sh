#!/usr/bin/env bash
# Self-check for `job sync`, with real git conflicts and a fake `gh` that logs its calls:
# up to date, a clean merge, a resolved conflict with its report on the PR, and the three ways a sync stops
# (a resolution that touches another file, checks that fail, the builder giving up) leaving the branch unchanged.
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; [ -f "$T/gh.log" ] && sed 's/^/  gh /' "$T/gh.log" >&2; exit 1; }

mkdir "$T/bin"
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
[ "$1 $2" = "pr comment" ] && cat >> "$GH_LOG"
[ "$1 $2" = "pr view" ] && echo '{"number":12,"state":"OPEN","isDraft":true,"url":"https://example.test/pr/12"}'
exit 0
EOF
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH" GH_LOG="$T/gh.log"
G() { git -c user.name=t -c user.email=t@t "$@"; }

git init -q --bare -b main "$T/origin.git"
git clone -q "$T/origin.git" "$T/p" 2>/dev/null
git clone -q "$T/origin.git" "$T/other" 2>/dev/null   # someone else merging into main
cd "$T/p"
printf 'one\ntwo\nthree\n' > a.txt && echo x > b.txt && G add a.txt b.txt && G commit -q -m init && git push -q origin main
bash "$SRC/install.sh" . >/dev/null
python3 - <<'EOF'
import json
c = json.load(open("factory/config.json"))
c.update(use_labels=False, auto_merge=False, checks_configured=True)
json.dump(c, open("factory/config.json", "w"))
EOF
printf '#!/usr/bin/env bash\n! grep -q BROKEN a.txt\n' > factory/checks.sh
job=factory/bin/job
stage() { python3 -c "import json;print(json.load(open('$d/job.json'))['stage'])"; }
head_of() { git -C "$wt" rev-parse HEAD; }
main_change() { (cd "$T/other" && git pull -q origin main && eval "$1" && G commit -q -am "$2" && git push -q origin main); }

# A job at awaiting-merge whose branch changed line two of a.txt.
id=$(printf 'Change two\n' | $job create --text)
d=factory/jobs/$id wt=.worktrees/$id
printf 'DECISION: BUILD\nRISK: low\nSTATUS: READY\n\n## Summary\n- x\n\n## Risk\n- small\n' > $d/planning.md
mkdir -p "$wt/context/$id" && echo "# plan" > "$wt/context/$id/plan.md"
$job advance $id build >/dev/null
(cd "$wt" && sed -i.bak 's/^two$/TWO from the PR/' a.txt && rm a.txt.bak && G add context a.txt && G commit -q -m pr && git push -q -u origin "factory/$id" 2>/dev/null)
printf 'STATUS: READY\n' > $d/build.md
$job advance $id gate >/dev/null
mkdir -p $d/round-1 && printf 'GATE: PASS\n' > $d/round-1/checks.md
$job advance $id review >/dev/null
printf 'VERDICT: PASS\n' > $d/round-1/review.md
$job finish $id >/dev/null
[ "$(stage)" = awaiting-merge ] || fail "setup: $(stage)"

# 1. Up to date: nothing happens.
$job sync $id | grep -q "already up to date" || fail "up to date"

# 2. Main changed another file: a clean merge, checked, pushed, reported.
main_change "echo y > b.txt" "main b"
$job sync $id >/dev/null
[ "$(stage)" = awaiting-merge ] || fail "clean sync ended in $(stage)"
[ "$(git -C "$wt" rev-parse HEAD)" = "$(git -C "$wt" rev-parse origin/factory/$id)" ] || fail "clean sync not pushed"
grep -q "synced with \`main\`" "$T/gh.log" || fail "no PR comment for the clean sync"

# 3. Main changed the same line: CONFLICT, resolved, checked, pushed, the report on the PR.
main_change "sed -i.bak 's/^two\$/two from main/' a.txt && rm a.txt.bak" "main a"
out=$($job sync $id)
echo "$out" | grep -q "^CONFLICT a.txt$" || fail "conflict not reported: $out"
[ "$(stage)" = syncing ] || fail "conflict left $(stage)"
(cd "$wt" && printf 'one\nTWO from the PR, from main\nthree\n' > a.txt && git add a.txt && G commit -q --no-edit)
rep=$(echo "$out" | sed -n 's/^report: //p')
printf 'SYNC: RESOLVED\n\n## Conflicts\n### a.txt, line 2\n- Resolution: KEPT-BOTH\n\n## Check by hand\nNothing.\n' > "$rep"
$job sync $id --done >/dev/null
[ "$(stage)" = awaiting-merge ] || fail "resolved sync ended in $(stage)"
[ "$(git -C "$wt" rev-parse HEAD)" = "$(git -C "$wt" rev-parse origin/factory/$id)" ] || fail "resolution not pushed"
grep -q "KEPT-BOTH" "$T/gh.log" || fail "report not posted on the PR"
grep -q "remerge-diff" "$T/gh.log" || fail "no remerge-diff hint"

# 4. A resolution that also edits a file without a conflict is refused; the branch goes back.
main_change "sed -i.bak 's/^one\$/ONE/; s/^TWO.*/two again/' a.txt && rm a.txt.bak" "main a2"
out=$($job sync $id); rep=$(echo "$out" | sed -n 's/^report: //p'); before=$(cd "$wt" && git rev-parse HEAD)
(cd "$wt" && printf 'ONE\nmerged\nthree\n' > a.txt && echo sneaky > b.txt && git add a.txt b.txt && G commit -q --no-edit)
printf 'SYNC: RESOLVED\n\n## Conflicts\n- x\n' > "$rep"
$job sync $id --done >/dev/null
[ "$(stage)" = needs-human-feedback ] || fail "extra file accepted: $(stage)"
[ "$(cd "$wt" && git rev-parse HEAD)" = "$before" ] || fail "branch not reset after the refusal"
grep -q "changed files that had no conflict: b.txt" "$T/gh.log" || fail "refusal not explained"

# 5. Checks that fail after the resolution: the branch goes back.
out=$($job sync $id); rep=$(echo "$out" | sed -n 's/^report: //p')
(cd "$wt" && printf 'ONE\nBROKEN\nthree\n' > a.txt && git add a.txt && G commit -q --no-edit)
printf 'SYNC: RESOLVED\n\n## Conflicts\n- x\n' > "$rep"
$job sync $id --done >/dev/null
[ "$(stage)" = needs-human-feedback ] || fail "failing checks accepted: $(stage)"
[ "$(cd "$wt" && git rev-parse HEAD)" = "$before" ] || fail "branch not reset after failing checks"

# 6. The builder gives up: --abort, the branch unchanged, the reasons on the PR.
out=$($job sync $id); rep=$(echo "$out" | sed -n 's/^report: //p')
printf 'SYNC: UNRESOLVED\n\n## Conflicts\n- NEEDS-YOUR-CALL\n' > "$rep"
$job sync $id --abort >/dev/null
[ "$(stage)" = needs-human-feedback ] || fail "abort ended in $(stage)"
[ "$(cd "$wt" && git rev-parse HEAD)" = "$before" ] && [ -z "$(cd "$wt" && git status --porcelain)" ] || fail "abort left the branch changed"
grep -q "NEEDS-YOUR-CALL" "$T/gh.log" || fail "abort report not posted"
! grep -q "pr merge" "$T/gh.log" || fail "sync merged a PR"

# A job that is not waiting for a merge is refused.
id2=$(printf 'Other\n' | $job create --text)
if $job sync $id2 2>/dev/null; then fail "synced a job in spec"; fi

echo "sync-test: OK"
