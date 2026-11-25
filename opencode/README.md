# Software factory for OpenCode

A local software factory for OpenCode 2, the same as [the one for Claude Code](../claude-code/README.md). It turns GitHub issues labelled `factory` into merged pull requests, with the user involved at exactly two gates:

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

It runs inside your own OpenCode session (`/factory run`); no CI, no server. `/factory dashboard` serves a live status page.

**[How it works](../claude-code/docs/how-it-works.md)**: the whole factory as a diagram, then one feature followed step by step from the issue to the merged PR. Po polsku, jako opowieść: **[Jak działa fabryka](../claude-code/docs/jak-dziala.md)**.

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
2. Copy `opencode/skills/install-opencode-factory/` from the clone to `~/.config/opencode/skills/install-opencode-factory/`, and `opencode/commands/install-factory.md` to `~/.config/opencode/commands/install-factory.md` (ask first if either exists; it may be an older copy you are replacing).
3. Tell the user to type `/install-factory` in the project where they want the factory. New commands and skills load in a new session, so the user may need to start one.

### By hand

Do the same three steps yourself. Then, in any project, `/install-factory` installs the factory, and later updates it (`/install-factory <ref>` for a specific tag or commit).

## What gets installed

| In the project | Owner | On update |
| --- | --- | --- |
| `factory/bin/{job,gate,dashboard}`, `factory/dashboard/` | factory | replaced |
| `.opencode/agents/factory-{planner,builder,reviewer}.md` | factory | replaced |
| `.opencode/skills/{factory,plan-feature,implement,review-change}/` | factory | replaced |
| `.opencode/commands/factory.md` (the `/factory` command) | factory | replaced |
| `factory/config.json` | project | kept; new keys added |
| `factory/checks.sh` | project | kept |
| `factory/risk.md` | project | kept |
| `factory/VERSION` | factory | the installed commit |
| `.gitignore`: `factory/jobs/`, `.worktrees/` | | appended if missing |
| `.opencode/opencode.json`: `experimental.subagent_depth: 3`, Ponytail pinned (optional) | | merged |

**Only on this machine:** `/install-factory` asks whether the factory goes into the repo or stays local. Local (`install.sh --local`) puts every factory path into `.git/info/exclude`, git's own ignore list that is never committed, so `git status` never shows it and `.gitignore` is untouched; `.opencode/opencode.json` is excluded too, and the factory section goes into `.opencode/factory.md`, which that config loads through `instructions`.

**Screenshots:** with `screenshots.start` and `screenshots.url` set in `config.json` (a web app), the builder photographs every screen a round changed with `npx playwright screenshot`, the reviewer checks the pictures, and the dashboard shows them. Without them, the builder lists what to check by hand.

The first install refuses to overwrite a project's own file with the same path (for example its own `implement` skill) unless the user agrees (`--force`).

Requirements: git, a GitHub remote, `gh` logged in, Python 3.

## Per-project files

- **`factory/checks.sh`**: the gate. It runs from the main checkout inside the job's worktree, so a branch can never change the checks it is judged by. Until `"checks_configured": true` in `config.json`, nothing auto-merges.
- **`factory/risk.md`**: what is high risk in this project. High-risk PRs are always merged by a human.
- **`factory/config.json`**: base branch, concurrency, rounds, labels, `auto_merge_max_risk`, model and variant per step (`provider/model`, `effort` = the `#variant`), `protected_paths` (agents never touch them), `context_files` (glossary, ADRs: what the planner reads).

## Developing the factory

This factory's own files live in `opencode/files/` (copied as is) and `opencode/templates/` (copied when missing). `install.sh <project> [--force] [--ponytail]` is the installer the skill calls. Tests: `bash opencode/test/install-test.sh` (the installer) and `bash opencode/test/manual-mode-test.sh` (manual mode end to end, with a fake `gh`) and `bash opencode/test/sync-test.sh` (sync with real git conflicts).

## How it maps to Claude Code

| Claude Code | OpenCode 2 |
| --- | --- |
| Agent tool with `model` and `effort`, in the background | `subagent` tool with `model: "provider/model#variant"`; always in the background |
| SendMessage to resume the builder | `subagent` with the builder's `sessionID` |
| subagents of subagents | `experimental.subagent_depth: 3` in `.opencode/opencode.json` |
| the `/factory` skill | the `factory` skill, started by `.opencode/commands/factory.md` |
| AskUserQuestion | the `question` tool |
| Bash `run_in_background` | the shell tool's `background: true` |
| `CLAUDE.md`, `CLAUDE.local.md` | `AGENTS.md`; for a local install `.opencode/factory.md` through `instructions` |
| Ponytail plugin, all agents but the planner (`PONYTAIL_SUBAGENT_MATCHER`) | `@dietrichgebert/ponytail` plugin, all agents; the planner's instructions keep the full scope |

An agent that waits for its own subagents ends its turn with `WAITING`; the orchestrator ignores it until the one-line reply arrives.

The design follows the ideas in ZazenCodes' "Software Factory for Claude Code v2" and Matt Pocock's `software-factory` skill; the code is written from scratch.
