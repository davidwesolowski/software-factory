---
name: review-change
description: Devil's-advocate, read-only review of a PR, branch, or local uncommitted work on two separate axes — Spec (does it deliver what it claims?) and Standards (does it follow this repo's conventions?) — each run by its own subagent, every finding verified before it's reported.
disable-model-invocation: true
---

Review the change since a **fixed point** on two axes, each owned by its own subagent:

- **Spec** — the change delivers its stated **intent**. Fails as _standards pass, spec fail_: clean code that implements the wrong thing.
- **Standards** — the change follows this repo's documented conventions. Fails as _spec pass, standards fail_: right behaviour that breaks project conventions.

The axes get separate subagents on purpose: a reviewer that just judged the code clean is primed to believe it works, and vice versa. Keep them independent all the way to the report.

Play **devil's advocate** throughout: assume the change does not deliver its claim until the code proves it does. Step 5 is the counterweight — nothing reaches the report unverified.

**Hard guardrail: the review is read-only.** Never change a single line of code, test, config or doc, and never stage, commit, stash, checkout, switch, reset or `gh pr checkout`. `HEAD`, the index and the working tree end exactly as they started. Express every fix as a suggestion in the report; the author applies it.
Allowed, because they leave all three untouched: `git fetch` (updates remote refs only), `git show <sha>:<path>` to read files at any commit, and running the project's existing checks (typecheck, lint, tests) without fix or snapshot-update flags (`--fix`, `-u`, `--write`).

When you need something from the user (the base of a stacked branch, the intent of a change), ask with AskUserQuestion, your recommended answer first.

## 1. Pin the fixed point and mode

`git fetch` the base first, so a stale local `origin/<base>` doesn't pull other people's commits into the diff.

Pick the **mode** from what the user gave and what exists:

- **PR mode** — the user linked a PR, or `gh pr view --json number,url,baseRefName,headRefName,headRefOid` finds one for the current branch. The fixed point is `git merge-base origin/<baseRefName> <head>`.
  The head is the PR's `headRefOid`. If that isn't your `HEAD` (the PR is for another branch, or the local branch is behind), fetch it with `git fetch origin pull/<n>/head` and review that SHA — read its files with `git show <sha>:<path>`, never by checking it out.
- **Local mode** — no PR yet, or the user wants their working tree reviewed. The change is everything since the merge-base: commits, staged, unstaged and untracked work. The fixed point is `git merge-base <base-ref> HEAD`, where the base ref is the one the user named, else the remote's default branch (`git symbolic-ref --short refs/remotes/origin/HEAD`), else whichever of `origin/main`, `origin/master`, `origin/develop` exists.

If the user names a ref, that ref wins. If the base might be a stacked parent rather than trunk (the merge-base is far behind, or another open PR's head sits between), ask the user.
If the current branch has a PR **and** uncommitted or unpushed work, review it in local mode and say so in the report — the PR alone would miss that work.

Collect the change:

- **PR mode:** `git log <fixed-point>..<head> --oneline` and `git diff --stat <fixed-point> <head>`.
- **Local mode:** `git log <fixed-point>..HEAD --oneline`, `git diff --stat <fixed-point>` (commits plus staged and unstaged work), and `git ls-files --others --exclude-standard` for untracked files.

If the change is empty, say so and stop.

**Done when:** you have the mode, fixed-point SHA, head SHA (or "working tree"), the exact diff command, commit list, changed-file list (untracked files included), and a starting `git status --short` snapshot.

## 2. Reconstruct the intent

Collect the spec, in this order:

1. What the user said the change is for, in this conversation.
2. A plan under `context/` matching the branch or feature (from `plan-feature`: its Goal, Scope, Out of scope, Decisions and each phase's Definition of done), or a spec / PRD the user names or one under `docs/` or `specs/`.
3. Issues linked from commit messages, the PR body, or the PR timeline (`gh api repos/{owner}/{repo}/issues/<pr>/timeline`).
4. The PR title, body, and "how to test" scenarios (PR mode).
5. If nothing turns up, ask the user what the change is for. If they don't give one, the Spec axis is skipped — without a claim there is nothing to disprove.

Classify the change by **kind**. When parts of it differ, classify each part on its own (e.g. a feature plus the tests for it). Then write down the old behaviour (read it at the fixed point) and the claim for each part:

| Kind | Claim to disprove | Devil's-advocate hunt |
| --- | --- | --- |
| **Fix** | The failure is gone, at its root cause. | The fix only masks the symptom; sibling callers of the same code are still broken; the fix breaks behaviour that worked before. |
| **Feature** | Every requirement works for its users. | Requirements that are missing or only partly done; empty, error, loading and permission states; integration with the flows around it; behaviour nobody asked for; existing paths that changed. |
| **Maintenance** (refactor, deps, docs) | Observable behaviour is unchanged, or changes as documented. | Behaviour that drifted; breaking changes in upgraded dependencies; docs or comments that no longer match the code. |
| **Tests** | The tests would catch the behaviour they name. | Assertions that pass even when the code is broken; testing implementation details instead of behaviour; flakiness; claimed coverage that doesn't exist. |

Treat docs the change adds or edits as claims too.

In PR mode, fetch existing review feedback — both the conversation (`gh pr view <pr> --comments`) and inline review comments, which that command omits (`gh api repos/{owner}/{repo}/pulls/<pr>/comments`). Check each against the current code: still open, or resolved. The subagents get only the open ones, so they don't re-report settled concerns.

**Done when:** every part of the change has a kind, a claim and its old behaviour, and every quoted requirement and manual test scenario is written down — or the Spec axis is marked skipped.

## 3. Collect the standards

List every documented convention that governs a changed file:

- root `CLAUDE.md`, `AGENTS.md` and `CONTRIBUTING.md`
- the `CLAUDE.md`, `AGENTS.md` or README nearest each changed file, and every one between it and the root
- `.github/instructions/*.instructions.md` — these apply by their `applyTo` glob, not by directory
- lint, type and formatting configs

Apart from root files and glob-scoped instructions, a rule only governs files under its own directory.

**Done when:** every changed file maps to the list of standards files that cover it.

## 4. Run the axes in parallel

Dispatch both axis subagents in one message (skip the Spec one if the axis is skipped). Each **owns its axis**: the Spec subagent judges intent only, the Standards subagent conventions only. Either may spawn helper subagents when the work is too big for one context (e.g. one per caller chain, or per component), and stays responsible for merging their results.

Each starts with a fresh context, so give each a self-contained prompt with:

- the mode, fixed-point and head SHAs, the exact diff command from step 1, commits, and changed files. In local mode also the untracked files, which it reads directly because `git diff` omits them; in PR mode with a head that isn't `HEAD`, the instruction to read files via `git show <sha>:<path>`;
- the hard guardrail and its allowed list, verbatim, to pass on to any helpers;
- the output contract — findings ordered by priority, one per line:
  - Spec: `P1|P2|P3 path:line — problem (trigger → consequence). Spec: "<quoted line>". Fix: …`
  - Standards: `P1|P2|P3 path:line — problem (rule: <standards file> — <rule>). Fix: …`
  - plus an **Unknown** list for anything it could not settle from the code: `path:line — open question. Settle by: …` (the test, runtime check or answer that would decide it);
- the priorities:
  - **P1** — data loss, security, a broken core flow, or a regression;
  - **P2** — the spec is violated or a convention is breached;
  - **P3** — minor, non-blocking.

**Spec subagent** — also give it each part's kind, claim and old behaviour, the quoted requirements from step 2, and the still-open review comments. Brief it as devil's advocate, to disprove each claim:

- Run the hunt from the kind table for each part (paste the matching rows).
- Trace every caller and the full data flow across layers (UI, API, storage, background jobs — whatever the change crosses).
- Hunt for **regressions** against the old behaviour.
- Push each lifecycle edge that applies: cancel, failure part-way through, overwrite, retry, shutdown, crash, concurrent use.
- Report (a) requirements missing or partial, (b) behaviour nobody asked for, and (c) requirements that look implemented but are wrong.

**Standards subagent** — also give it the file-to-standards map from step 3.

- Each finding cites the standards file and the rule.
- Fowler code smells (_Refactoring_, ch. 3) — e.g. Duplicated Code, Feature Envy, Speculative Generality — may be reported as P3 judgement calls. A documented repo rule overrides them.
- A missing-tests finding needs a cited rule, and must name which behaviour would regress unnoticed.
- Skip anything tooling already enforces — the linter will report it anyway, and duplicates bury the findings only a human reviewer would catch.

**Done when:** every axis subagent has returned.

## 5. Verify every finding

Devil's advocate inflates; this step deflates. For each finding, open the cited lines yourself and confirm its trigger is reachable in the code. Drop a finding you disprove; move one you can neither confirm nor disprove to Unknown; lower a priority when the consequence is weaker than claimed. Where an Unknown can be settled by running an existing test or check (within the allowed list), run it and move the item accordingly.

Finally compare `git status --short` with the step 1 snapshot. If anything changed, don't try to undo it (that would be a write) — put it at the top of the report.

**Done when:** every finding is confirmed, dropped, or moved to Unknown, and the snapshot check is done.

## 6. Report

Report in this format:

```
## Spec
P1 path:line — problem (trigger → consequence). Spec: "<quoted line>". Fix: …

## Standards
P2 path:line — problem (rule: <standards file> — <rule>). Fix: …

## Unknown
[Spec] path:line — open question. Settle by: …

Summary: at most two sentences.
```

- Start with one line naming the mode, fixed point and head (e.g. `Local mode · origin/main@a1b2c3d → working tree`), so the reader knows exactly what was reviewed.
- Order each axis by priority. Keep the axes apart: never merge or rerank findings across them.
- Tag each Unknown item with its axis.
- An empty section reads `None.`; a skipped axis reads `Skipped: <reason>.`
- The summary is the only prose: the overall verdict and the worst finding within each axis, in two sentences at most.
