---
name: install-opencode-factory
description: Install or update the local software factory for OpenCode (/factory run: GitHub issues labelled `factory` → plan → build → checks → review → merged PR) in the current git repository, from github.com/davidwesolowski/software-factory. Use when the user types /install-opencode-factory, or asks to install, set up or update the software factory in a project.
disable-model-invocation: true
argument-hint: "[git ref, default main]"
---

# Install the software factory for OpenCode

You install the factory into the project in the current directory, or update it. The deterministic part (copying files, `.gitignore`, settings) is done by `install.sh` from the factory repo; you do the parts that need the project's knowledge and the user's decisions: the checks, the risk rubric, the context files.

Ask the user with the `question` tool, your recommended answer first labelled "(Recommended)", in the language they write in. Independent questions go in one call.

## 1. Preconditions

Run these in the project, and stop with the reason if one fails:

- `git rev-parse --show-toplevel`: this is `<project>`. Work from it.
- `gh auth status`, and `gh repo view --json nameWithOwner` succeeds: the factory works through GitHub issues and PRs, so the project needs a GitHub remote.
- `python3 --version`: the factory's scripts are Python 3 (stdlib only).
- `opencode --version` prints 2.x: the factory needs OpenCode 2 (the `subagent` tool with a `model` parameter). On 1.x, stop and tell the user to upgrade.
- `git status --short`: if files the install touches (`factory/`, `.opencode/`, `.gitignore`, `AGENTS.md`) have uncommitted changes, tell the user and ask whether to continue.

`<mode>` is **update** when `<project>/factory/VERSION` exists, else **install**. On update, the install is **local** when `.git/info/exclude` (in `git rev-parse --git-common-dir`) has the line `# software factory (local install)`; the installer keeps it local on its own.

## 2. Fetch the factory

```bash
src="$(mktemp -d)/software-factory"
gh repo clone davidwesolowski/software-factory "$src" -- --quiet
git -C "$src" checkout --quiet "${ref:-main}"   # ref: the skill's argument, if given
```

The repo is private: if the clone fails with a permission error, tell the user their `gh` account needs access to it.

On **update**, show what changed since the installed version: `git -C "$src" log --oneline "$(cat factory/VERSION)..HEAD" -- opencode/`. If it prints nothing, say the factory is up to date and stop.

## 3. Decide with the user (install only)

Ask in one call:

1. **Mode**:
   - **Manual** (recommended when the user can't or doesn't want to add labels to the repo, or wants to merge every PR): no label queue and no labels ever touched; jobs start with `/factory run <issue>` or `/factory run "<text>"`; the factory never merges, every PR waits for the user.
   - **Queue**: issues labelled `factory` are picked up by `/factory run`, the factory creates three labels, and PRs up to `auto_merge_max_risk` are merged by the factory.
   - Recommend manual unless the user said they want the label queue or auto-merge.
2. **Ponytail** (a plugin for the smallest change that works: its rules apply to the builder and its phase subagents while they write the code, and it gives the reviewer its Simplicity axis; in OpenCode it reaches every agent, so the planner's own instructions tell it to plan the full scope anyway): add it to `.opencode/opencode.json`, pinned. Recommended: yes. Skip this question if that file's `plugins` already has `@dietrichgebert/ponytail`.
3. **Base branch**: what PRs target and the factory merges into. Recommended: the remote default (`gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`).
4. **In git or only on this machine**:
   - **Only on this machine** (recommended when the user doesn't want the factory in the repo, or can't change its `.gitignore`): `--local`. Every factory path goes into `.git/info/exclude`, git's own ignore list that is never committed, so `git status` never shows the factory and `.gitignore` stays untouched. `.opencode/opencode.json` is excluded too, and the factory section goes into `.opencode/factory.md`, which that config loads through `instructions` (OpenCode's way to keep `CLAUDE.local.md`-style notes out of the repo). Nothing to commit; teammates don't get the factory. It only hides files git doesn't track yet.
   - **In the repo**: the factory is committed like any other code, and the whole team gets it; `.gitignore` gets `factory/jobs/` and `.worktrees/`.

## 4. Run the installer

```bash
bash "$src/opencode/install.sh" <project> [--ponytail] [--local]
```

If it exits 1 saying `.opencode/opencode.json` is not plain JSON, the project's config has comments: add `experimental.subagent_depth: 3` (and the Ponytail plugin, and for a local install `instructions: [".opencode/factory.md"]`) to it by hand with the user, then run the installer again.

If it exits 2, it lists project files that differ from the factory's (for example the project's own `implement` skill). Show the list and ask: overwrite them (`--force`; the factory's agents depend on its own versions) or stop. Never pass `--force` without that answer.

On **update**, the installer replaced only the factory's own files and kept `config.json`, `checks.sh` and `risk.md`; it adds config keys that are new. Report what it printed, run step 7, and stop.

## 5. Configure the project (install only)

Edit only these files, under `<project>/factory/`:

- **`config.json`**: set `base_branch` to the answer from step 3. For manual mode set `"use_labels": false` and `"auto_merge": false`; for queue mode leave both `true`. Set `context_files` to the files that hold the project's domain knowledge and that exist (a glossary, `docs/adr/`, `CONTRIBUTING.md`, a spec folder); `[]` if none.
- **`steps`** in `config.json`: the model each agent runs on, as an OpenCode id (`provider/model`), with the variant (OpenCode's `#variant`, the reasoning effort) in `effort`. The template has Anthropic's: Opus for the planner and the reviewer, Sonnet for the builder. Look up what the user has with the `models` tool, propose the strongest model of their provider for `planner_spec`, `planner_revise` and `reviewer` and a fast one for `builder`, with variants those models really have (omit `effort` for a model without variants), and write them after the user agrees. Copy the ids exactly from the `models` tool: a wrong id fails only when the first agent is spawned.
- **`checks.sh`**: find the project's real checks (package.json scripts and lockfile, Makefile, pyproject/tox, Cargo, go.mod, CI workflows in `.github/workflows/`). Propose them to the user as the list of commands the gate will run: a clean install from the lockfile, typecheck, lint, tests, build, e2e if present. Keep the final "working tree unchanged" step. After the user confirms, write them as `step "<name>"` lines and run `bash factory/checks.sh` once. If it passes, ask whether to set `"checks_configured": true` (without it the gate's PASS carries a warning, and nothing ever auto-merges). If it fails, show the failure and leave `checks_configured` false.
- **`screenshots`** in `config.json`: for a web app, the builder photographs each changed screen with `npx playwright screenshot` and the reviewer looks at the pictures. Find how the app's dev server starts and propose `"start"` with `{port}` where the port goes (e.g. `npm run dev -- --port {port}`) and `"url"` (e.g. `http://localhost:{port}`); the builder picks a free port, since jobs run at the same time. Try it once: start it on a free port, wait for the url, run `npx --yes playwright screenshot <url> /tmp/factory-shot.png` (if the browser is missing, ask before `npx --yes playwright install chromium`, it downloads about 150 MB), stop the app, show the user the picture. Write both after the user agrees. Leave them empty when the app is not reachable in a browser (a desktop, mobile or CLI app); the builder then lists what to check by hand.
- **`risk.md`**: read the code enough to draft the "High in this project" list: what in this project is hard to undo or easy to get subtly wrong (the user's files, money, the public API, output formats, hardware). Show the draft and write it after the user agrees or corrects it.

## 6. Document it in AGENTS.md (install only)

If `<project>/AGENTS.md` (or `CLAUDE.md`, when the project has that and no `AGENTS.md`: OpenCode then reads it instead) has no `## Software factory` section, append the one for the chosen mode. For a **local** install write it to `<project>/.opencode/factory.md` instead (create it); the installer has already added that file to `instructions` in `.opencode/opencode.json`, so OpenCode loads it, and the repo's own files stay as they are.

Manual mode:

```markdown
## Software factory

`/factory run <issue>` or `/factory run "<what to build>"` runs the local software factory on one job: spec (the planner asks all its questions at once, gate 1) → build in its own worktree → checks → review → a PR that you merge; the factory never merges and never touches labels. A stuck job waits for `/factory <your feedback>` (gate 2). `/factory run` resumes unfinished jobs, `/factory status` lists them, `/factory dashboard` serves a live status page. Configuration is in `factory/config.json`, the checks in `factory/checks.sh`, the risk rubric in `factory/risk.md`, runtime state in `factory/jobs/` (gitignored), the agents in `.opencode/agents/factory-*.md`. Update the factory with `/install-opencode-factory`; it never overwrites `config.json`, `checks.sh` or `risk.md`.
```

Queue mode:

```markdown
## Software factory

`/factory run` runs the local software factory on issues labelled `factory`: spec (the planner asks all its questions at once, gate 1) → build → checks → review → merged by the factory (low/medium risk) or handed to you (high risk). A stuck job is labelled `factory:needs-human-feedback` and waits (gate 2). `/factory dashboard` serves a live status page. Configuration is in `factory/config.json`, the checks in `factory/checks.sh`, the risk rubric in `factory/risk.md`, runtime state in `factory/jobs/` (gitignored), the agents in `.opencode/agents/factory-*.md`. Update the factory with `/install-opencode-factory`; it never overwrites `config.json`, `checks.sh` or `risk.md`.
```

If Ponytail was added, append to that section that it is pinned in `.opencode/opencode.json` (`plugins`) and OpenCode installs it from npm on its next start; nobody has to run anything.

## 7. Finish

- Show `git status --short` and a one-line summary of what was installed or updated.
- Tell the user the new agents, skills, the `/factory` command and the config load in a **new** OpenCode session.
- **Local** install: run `git status --short` and confirm nothing of the factory shows; don't offer a commit. Otherwise ask whether to commit: `chore: install software factory <short VERSION>` (or `chore: update software factory …`), staging only the paths the install touched, by name. Never push.
- Remove `$src`'s temp directory.
