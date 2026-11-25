---
name: implement
description: Implement a code change from what the user provides — a plan (e.g. context/<feature-name>/plan.md from plan-feature), ticket, spec, design or plain description — phase by phase in subagents, verify it with typecheck, lint and tests, then offer a conventional commit. Use whenever the user asks to implement, build, code up or execute a plan, feature, fix or phase ("zaimplementuj", "zrób fazę 2", "wykonaj plan", "build this"), even if they don't say "implement".
disable-model-invocation: true
---

# Implement a change

Turn the user's sources (plan, task, ticket, spec, design, code) into working code, verified by the project's own checks. Change only what the sources call for: unrequested refactors make the diff harder to review and to revert.

## Ask rule

- **A fact about the code** — look it up yourself; don't ask the user what the codebase can answer.
- **A choice only the user can make** (behaviour, scope, a trade-off the sources leave open) — ask with AskUserQuestion before writing the affected code, your recommended answer first, labelled "(Recommended)". Independent questions can share one call (up to 4).
- If the plan turns out wrong while you work (a listed file doesn't exist, an approach can't work, a phase needs files it doesn't list), stop and ask rather than quietly improvising. Plans are reviewed by the user; silent deviations aren't.

## Steps

1. **Gather the sources.** Read everything the user pointed to, plus `CLAUDE.md` / `AGENTS.md` for the areas involved. If the user names a feature but no file, look for `context/<feature-name>/plan.md`. Resolve unclear expected behaviour by the ask rule.

2. **Record the baseline.** If the project is a git repo, note `git status` and the current HEAD before touching anything. The user may already have uncommitted work; the baseline is what lets you later revert or commit *only your* changes without destroying theirs. Also find the project's check commands (`package.json` scripts, Makefile, CI config, CLAUDE.md) and run them once, so pre-existing failures aren't later blamed on this change.

3. **Settle the phases.** Use the plan's phases, in order, honouring each phase's **Depends on**. Without a plan, define phases yourself: each with its files and true/false acceptance criteria, small enough for one subagent. For a change that is a single small phase (a few files, one area), skip subagents and do it yourself — a cold subagent costs more than it saves there.

4. **Run each phase in a subagent.** A subagent starts with none of your context, so its brief must be self-contained:
   - the plan path and phase number (or, without a plan, the phase written out),
   - the phase's files, notes and definition of done,
   - the relevant decisions and any answers the user gave you,
   - what it must not touch (files outside its phase, git — no commits, no stash, no checkout),
   - to run the checks named in its definition of done and report: files changed, each criterion true/false with evidence, anything it couldn't do.

   Phases run one after another by default. Run two in parallel only when neither depends on the other and their file lists don't overlap.

5. **Verify each phase yourself** before starting the next. A subagent's report is a claim, not proof: read its diff and re-run its checks. If a criterion is false, send the subagent (or a new one) back with the specific failure. When a plan file exists, tick the phase's checkboxes in `plan.md` as they become true, so a later session can resume where this one stopped.

6. **Verify the whole change.** Run the relevant typecheck, lint and tests (targeted first, then the full suite if it's reasonably fast). A phase may have been allowed to leave things mid-change; after the last phase, everything should pass.

7. **Handle failures.** First diagnose, compared against the baseline from step 2:
   - **Pre-existing failure** — not yours; report it, don't fix it unasked.
   - **Bug in the new code** — fix it (a couple of focused attempts) and re-run.
   - **Test asserts the old behaviour that the change intentionally replaced**, or you can't get it green — ask with AskUserQuestion, giving the failing test and your diagnosis:
     - Adjust the tests to the new behaviour (recommended when the change is the intended behaviour),
     - Revert the implementation — restore only the files this change touched, using the baseline, never the user's pre-existing work,
     - Leave it as is with the failing test.

8. **Offer a commit.** If the project is a git repo, ask with AskUserQuestion whether to commit, showing the proposed message in conventional commit format (`feat(scope): …`, `fix: …`; body summarising what changed and why). On a yes, stage only the files this change touched (by name, not `git add -A`) and commit. Never push. If there's no git repo, skip this step and say so.

Finish with a short report: what was implemented, check results, any failures left or deviations from the plan, and the commit (if made).
