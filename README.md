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

It runs inside your own Claude Code session (`/factory run`); no CI, no server. `/factory dashboard` serves a live status page.

**[How it works](docs/how-it-works.md)**: the whole factory as a diagram, then one feature followed step by step from the issue to the merged PR.

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

The first install refuses to overwrite a project's own file with the same path (for example its own `implement` skill) unless the user agrees (`--force`).

Requirements: git, a GitHub remote, `gh` logged in, Python 3.

## Per-project files

- **`factory/checks.sh`**: the gate. It runs from the main checkout inside the job's worktree, so a branch can never change the checks it is judged by. Until `"checks_configured": true` in `config.json`, nothing auto-merges.
- **`factory/risk.md`**: what is high risk in this project. High-risk PRs are always merged by a human.
- **`factory/config.json`**: base branch, concurrency, rounds, labels, `auto_merge_max_risk`, model and effort per step, `protected_paths` (agents never touch them), `context_files` (glossary, ADRs: what the planner reads).

## Developing the factory

The repository's own files live in `files/` (copied as is) and `templates/` (copied when missing). `install.sh <project> [--force] [--ponytail]` is the installer the skill calls; `bash test/install-test.sh` checks it.

The design follows the ideas in ZazenCodes' "Software Factory for Claude Code v2" and Matt Pocock's `software-factory` skill; the code is written from scratch.
