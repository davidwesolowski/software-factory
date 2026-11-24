# How the factory works

Two diagrams: first the factory as a whole, then one feature followed from the issue to the merged pull request.

## Words used below

- **Issue**: a task on GitHub ("Add dark mode"). The factory only takes issues that carry the label `factory`.
- **Label**: a coloured tag on an issue. Only people with triage or write access to the repository can add one, so the label decides who can give the factory work.
- **Branch / worktree**: each job gets its own git branch, `factory/<job>`, checked out in its own folder `.worktrees/<job>/`. Your own checkout is never touched while the factory works.
- **Pull request (PR)**: the proposed change, shown on GitHub. The builder opens it as a **draft** (not ready to merge yet). Its description says `Closes #<issue>`, so merging it closes the issue.
- **Merge**: putting the PR's changes into the main branch (`base_branch` in `factory/config.json`, usually `main`).
- **Risk**: the planner rates every job `low`, `medium` or `high`. `factory/risk.md` says what is high risk in your project. High-risk PRs are never merged by the factory.
- **Checks**: `factory/checks.sh`, the project's own tests, lint, build. The **gate** runs them.
- **Round**: one pass of build → gate → review. A job gets at most `max_rounds` (default 3) before it stops and asks you.
- **Agent**: a Claude subagent with one job: the **planner**, the **builder** or the **reviewer**. The **orchestrator** is your own Claude Code session after you type `/factory run`; it starts the agents and runs the scripts, but writes no code itself.

## 1. The whole factory

```mermaid
flowchart TD
    queue["Issue labelled factory<br/>(and not blocked by an open issue)"] --> spec

    spec["SPEC<br/>planner: build or reject? risk? plan + all open questions"]
    spec -->|reject| rejected(["REJECTED<br/>reason posted on the issue"])
    spec -->|has questions| clarify
    spec -->|nothing open| build

    clarify{{"GATE 1 - you<br/>answer every question in one sitting"}}
    clarify -->|answers| spec

    build["BUILD<br/>builder: code + tests in its worktree,<br/>commit, push, draft PR"]
    build -->|STATUS: READY| gate
    build -->|STATUS: BLOCKED| stuck

    gate["GATE<br/>runs factory/checks.sh,<br/>refuses changes to protected files"]
    gate -->|PASS| review
    gate -->|FAIL, rounds left| build

    review["REVIEW<br/>reviewer: does it do what the plan says?<br/>does it follow the project's rules? (+ simplicity)"]
    review -->|CHANGES, rounds left| build
    review -->|PASS| finish
    review -->|HUMAN| stuck

    finish{"risk at most auto_merge_max_risk<br/>and checks configured?"}
    finish -->|yes| merging["MERGING<br/>update from main, checks again, merge PR"]
    finish -->|no, e.g. high risk| awaiting{{"AWAITING MERGE - you<br/>read the PR and merge it"}}
    merging -->|ok| merged(["MERGED<br/>issue closed, worktree removed"])
    merging -->|conflict or checks fail| stuck
    awaiting -->|you merge| merged
    awaiting -->|you give feedback| build

    gate -->|FAIL, no rounds left| stuck
    review -->|CHANGES, no rounds left| stuck
    stuck{{"GATE 2 - NEEDS HUMAN FEEDBACK<br/>label on the issue, the job waits"}}
    stuck -->|/factory your feedback| build
    stuck -->|/factory your feedback, no PR yet| spec
    stuck -->|you drop it| rejected
```

What to read from it:

- **You are needed in three places only**, the hexagons: answering questions before any code is written (gate 1), merging high-risk PRs, and unblocking a stuck job (gate 2). Everything else runs without asking you.
- **Between gate 1 and the end nothing interrupts you.** A job that can't continue does not ask a question; it stops, gets the label `factory:needs-human-feedback`, and waits until you answer with `/factory <your words>`. The other jobs keep going.
- **Up to `concurrency` jobs run at once** (default 3), each in its own worktree.
- **Every state change goes through `factory/bin/job`.** It checks the files that justify a move (no PR → no gate, no `GATE: PASS` → no review) and refuses the move otherwise.

## 2. An example: "Add dark mode"

You open issue #4 *"Add dark mode"* with the label `factory`, then type `/factory run` in Claude Code in that project.

```mermaid
sequenceDiagram
    autonumber
    actor You
    participant GH as GitHub
    participant F as Factory (your Claude session)
    participant P as Planner
    participant B as Builder
    participant G as Gate (checks.sh)
    participant R as Reviewer

    You->>GH: Open issue 4 "Add dark mode", label factory
    You->>F: /factory run
    F->>GH: Which factory issues are open?
    F->>F: Create job 004-add-dark-mode, branch factory/004-add-dark-mode, folder .worktrees/004-add-dark-mode

    Note over F,P: SPEC
    F->>P: Plan job 004
    P->>P: Read the issue, CLAUDE.md, context files, the code
    P-->>F: BUILD, risk medium, 2 questions

    Note over You,F: GATE 1 - the only time you are asked before the end
    F->>You: Q1 Follow the system setting or a toggle? (Recommended - system setting)
    F->>You: Q2 Remember the choice after restart? (Recommended - yes)
    You-->>F: Q1 system setting, Q2 yes
    F->>GH: Post the answers as a comment on issue 4
    F->>P: Revise the plan with the answers
    P-->>F: BUILD, risk medium, READY (plan.md committed on the branch)

    Note over F,B: BUILD, round 1
    F->>B: Build the plan
    B->>B: Code and tests in the worktree, run checks.sh itself
    B->>GH: Push the branch, open draft PR 12 "Closes #4"
    B-->>F: STATUS READY

    F->>G: Run the gate for round 1
    G-->>F: GATE PASS (all checks green, no protected file changed)

    Note over F,R: REVIEW, round 1
    F->>R: Review PR 12 against the plan
    R-->>F: VERDICT CHANGES - the setting is not saved when the app closes
    F->>F: Keep the review in factory/jobs/004-add-dark-mode/round-1/review.md (shown on the dashboard)

    Note over F,B: BUILD, round 2
    F->>B: Fix the required findings
    B->>GH: Push the fix
    B-->>F: STATUS READY
    F->>G: Run the gate for round 2
    G-->>F: GATE PASS
    F->>R: Review round 2
    R-->>F: VERDICT PASS

    Note over F,GH: FINISH - risk medium, so the factory may merge
    F->>F: Update the branch from main, run checks.sh again
    F->>GH: Mark PR 12 ready, merge it
    GH-->>GH: Issue 4 closes (the PR says "Closes #4")
    F->>F: Remove the worktree, job 004 is MERGED
    F-->>You: 004-add-dark-mode #4 merged PR #12
```

What happened, step by step:

1. **You** wrote what you want as an issue and added the label `factory`. You can write it in any language; the planner asks its questions in the issue's language.
2. **The factory** found the issue and created job `004-add-dark-mode`: a branch and a separate folder, so your own checkout stays as it was.
3. **The planner** read the issue, the project's `CLAUDE.md`, the files in `context_files` and the code. It decided to build it, rated it `medium` (several files, nothing hard to undo) and found two things only you can decide.
4. **Gate 1.** You got both questions at once, each with a recommended answer you can accept in one click. Your answers were posted on the issue, so the decision is recorded on GitHub too.
5. **The planner** rewrote the plan (`context/004-add-dark-mode/plan.md` on the branch): phases, the files each phase changes, and acceptance criteria that can be checked as true or false.
6. **The builder** wrote the code and tests in the job's folder, ran the checks itself, pushed the branch and opened a draft PR.
7. **The gate** ran `factory/checks.sh` from your main checkout, not from the branch, so the builder can't change the checks it is judged by. It also failed the round if a protected file (the factory itself, the checks, settings) had changed.
8. **The reviewer** compared the PR with the plan and your answers and found a real gap: the choice was not saved. That is a **required** finding, so the job went back to the builder for round 2. You weren't asked. The review stays in the job's folder (`factory/jobs/004-add-dark-mode/round-1/review.md`, also on the dashboard); it is not posted on GitHub.
9. **Round 2** fixed it; checks and review passed.
10. **Finish.** The risk was `medium` and `auto_merge_max_risk` is `medium`, so the factory merged the PR itself, after updating it from `main` and running the checks once more. Merging closed the issue.

How the same issue could have ended differently:

- **Rated `high`** (say it changed a stored data format): after step 9 the factory marks the PR ready, adds the label `factory:awaiting-merge`, and posts on the PR what is risky and what to check by hand. **You** merge it.
- **Checks or review fail 3 rounds in a row**, the builder is **blocked** (the plan can't work as written), or the reviewer answers **HUMAN** (only you can settle it): the job stops with the label `factory:needs-human-feedback` and a comment explaining why. You answer with `/factory 004: <your words>`, and it starts a new round with a fresh round budget.
- **The planner rejects it** (it doesn't belong in this project, or it already exists): the reason is posted on the issue, the label `factory` is removed, and no code is written.
- **The checks are not configured yet** (`checks_configured: false`): the factory never merges by itself, whatever the risk; every PR waits for you.

Watch it live with `/factory dashboard`, or ask `/factory status`.
