# Software factory

A local software factory: it turns GitHub issues into merged pull requests, with you involved at exactly two gates (the planner's questions up front, and a job that gets stuck). Two copies of the same factory, one per coding agent:

| Folder | For | Install |
| --- | --- | --- |
| [`claude-code/`](claude-code/README.md) | Claude Code | the `install-factory` skill in `~/.claude/skills/`, then `/install-factory` |
| [`opencode/`](opencode/README.md) | OpenCode 2 | the `install-opencode-factory` skill and the `install-factory` command in `~/.config/opencode/`, then `/install-factory` |

The two folders are independent: each has its own installer, scripts, agents, skills and tests. A fix in `factory/bin/` or in a skill that both need goes into both.

How it works, step by step: [How it works](claude-code/docs/how-it-works.md) · po polsku: [Jak działa fabryka](claude-code/docs/jak-dziala.md).
