# Software factory

A local software factory for Claude Code. It turns GitHub issues labelled `factory` into merged pull requests, with the user involved at exactly two gates:

```
spec     factory-planner    BUILD/REJECT, risk, phased plan, ALL open questions at once
clarify  GATE 1 (you)       answer the questions in one sitting
build    factory-builder    implements the plan in a worktree, draft PR "Closes #n"
gate     factory/bin/gate   the project's factory/checks.sh; FAIL -> build again
review   factory-reviewer   Spec, Standards (+ Simplicity with Ponytail); CHANGES -> build again
finish   factory/bin/job    low/medium risk -> merged by the factory; high risk -> you merge
stuck    GATE 2 (you)       needs-human-feedback: waits for `/factory <your feedback>`
```

`/factory sync` brings PRs that wait for your merge up to date with the base branch; on a conflict the builder resolves it and reports where it was, how it was resolved and why, and the factory never merges there. The resolution may touch only the conflicted files and must pass the checks, or the branch is left as it was.

It runs inside your own Claude Code session (`/factory run`); no CI, no server. `/factory dashboard` serves a live status page.

**[How it works](docs/how-it-works.md)**: the whole factory as a diagram, then one feature followed step by step from the issue to the merged PR. Po polsku, jako opowieść: **[Jak działa fabryka](docs/jak-dziala.md)**.

## Two modes

`/install-factory` asks which one; switch later in `factory/config.json`.

| | Queue mode | Manual mode |
| --- | --- | --- |
| Starting a job | `/factory run` picks up every open issue labelled `factory` | you name each job: `/factory run 123` (any open issue) or `/factory run "<what to build>"` (no issue at all) |
| GitHub labels | creates and sets `factory`, `factory:needs-human-feedback`, `factory:awaiting-merge` | never touched |
| Merging | the factory merges PRs up to `auto_merge_max_risk`; high risk goes to you | never; every PR that passes review is handed to you |
| Config | `"use_labels": true`, `"auto_merge": true` | `"use_labels": false`, `"auto_merge": false` |

Planning with questions up front, building in a worktree, the checks, the review rounds and the dashboard work the same in both.

## Install

### For an agent

When a user gives you this repository's link and asks you to install it, install the `install-factory` skill for them, then run it:

1. `gh repo clone davidwesolowski/software-factory "$(mktemp -d)/sf"` (the repo is private: this needs a `gh` login with access).
2. Copy `skills/install-factory/` from the clone to `~/.claude/skills/install-factory/` (ask first if that folder exists; it may be an older copy you are replacing).
3. Tell the user to type `/install-factory` in the project where they want the factory. The skill is user-invoked only, and new skills load in a new session, so the user may need to start one.

### By hand

Do the same three steps yourself. Then, in any project, `/install-factory` installs the factory, and later updates it (`/install-factory <ref>` for a specific tag or commit).

## What gets installed

| In the project | Owner | On update |
| --- | --- | --- |
| `factory/bin/{job,gate,dashboard}`, `factory/dashboard/` | factory | replaced |
| `.claude/agents/factory-{planner,builder,reviewer}.md` | factory | replaced |
| `.claude/skills/{factory,plan-feature,implement,review-change}/` | factory | replaced |
| `factory/config.json` | project | kept; new keys added |
| `factory/checks.sh` | project | kept |
| `factory/risk.md` | project | kept |
| `factory/VERSION` | factory | the installed commit |
| `.gitignore`: `factory/jobs/`, `.worktrees/` | | appended if missing |
| `.claude/settings.json`: Ponytail, pinned (optional) | | merged |

**Only on this machine:** `/install-factory` asks whether the factory goes into the repo or stays local. Local (`install.sh --local`) puts every factory path into `.git/info/exclude`, git's own ignore list that is never committed, so `git status` never shows it and `.gitignore` is untouched; Ponytail goes into `.claude/settings.local.json` and the CLAUDE.md section into `CLAUDE.local.md`.

**Screenshots:** with `screenshots.start` and `screenshots.url` set in `config.json` (a web app), the builder photographs every screen a round changed with `npx playwright screenshot`, the reviewer checks the pictures, and the dashboard shows them. Without them, the builder lists what to check by hand.

The first install refuses to overwrite a project's own file with the same path (for example its own `implement` skill) unless the user agrees (`--force`).

Requirements: git, a GitHub remote, `gh` logged in, Python 3.

## Per-project files

- **`factory/checks.sh`**: the gate. It runs from the main checkout inside the job's worktree, so a branch can never change the checks it is judged by. Until `"checks_configured": true` in `config.json`, nothing auto-merges.
- **`factory/risk.md`**: what is high risk in this project. High-risk PRs are always merged by a human.
- **`factory/config.json`**: base branch, concurrency, rounds, labels, `auto_merge_max_risk`, model and effort per step, `protected_paths` (agents never touch them), `context_files` (glossary, ADRs: what the planner reads).

## Developing the factory

The repository's own files live in `files/` (copied as is) and `templates/` (copied when missing). `install.sh <project> [--force] [--ponytail]` is the installer the skill calls. Tests: `bash test/install-test.sh` (the installer) and `bash test/manual-mode-test.sh` (manual mode end to end, with a fake `gh`) and `bash test/sync-test.sh` (sync with real git conflicts).

The design follows the ideas in ZazenCodes' "Software Factory for Claude Code v2" and Matt Pocock's `software-factory` skill; the code is written from scratch.
