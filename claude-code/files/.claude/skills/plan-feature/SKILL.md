---
name: plan-feature
description: Turn a feature request into a phased implementation plan saved at context/<feature-name>/plan.md, with per-phase files and true/false acceptance criteria, resolving open questions with the user first. Use whenever the user asks to plan, scope, break down or design a feature, change or refactor before building it ("zaplanuj", "rozpisz na etapy", "how should we implement X", "make a plan for X") — even if they don't say "plan.md". Planning only; implementation happens in a later session.
disable-model-invocation: true
---

# Plan a feature

Produce a **phased plan**: the work split into ordered phases, each with the files it modifies or creates and a definition of done made of acceptance criteria. Write it to `context/<feature-name>/plan.md` (relative to the project root) and stop. Do not write or change any other file — implementation belongs to a later session, and that session will start with nothing but this plan, so everything it needs to know must be in the file.

## Ask rule

Gaps (missing pieces, ambiguities, open decisions) come up throughout. Handle each one the moment it appears:

- **A fact about the code** (which library, where X lives, how Y is done today) — look it up yourself. Asking the user something the codebase can answer wastes their time.
- **A choice only the user can make** (behaviour, scope, UX, trade-offs) — ask with the AskUserQuestion tool. Put your recommended answer first, labelled "(Recommended)", with a one-line reason, so the user can accept it in one click.
- Questions that don't depend on each other can go in one AskUserQuestion call (up to 4). A question whose options depend on another answer waits for that answer. Never continue past a gap while its answer is pending.
- Ask in the language the user writes in.
- Record every resolved gap for the Decisions table — user answers and facts you settled from the code — with its source, so the implementing session knows what was confirmed by the user and what was inferred.

Setup questions from step 1 (the slug, overwrite vs. revise) are not decisions; leave them out of the table.

## Steps

1. **Name the feature.** Derive `<feature-name>` from the request as a kebab-case slug; if the request gives nothing to name it by, ask. If `context/<feature-name>/plan.md` already exists, read it and ask whether to overwrite it or revise it (revise = keep its decisions and still-valid phases, change only what the new request affects).
   *Done when:* the slug is fixed and the target path is cleared.

2. **Map the terrain.** Read the project's `CLAUDE.md` / `AGENTS.md` files — root and every area the feature touches — then explore until you can name each file the feature modifies or creates. Note the existing patterns, helpers and conventions the implementation should reuse; they go into the phase notes. In a large codebase, send independent areas to parallel Explore subagents and keep only their conclusions, so your context stays free for planning.
   *Done when:* every file path headed for the plan is one you have opened, or, for a new file, one whose parent directory you have confirmed exists. Unverified paths are the most common way a plan misleads the next session.

3. **Close every gap.** Sweep the request and your findings for any gap not yet resolved and handle each by the ask rule. Gaps raised by an answer join the sweep.
   *Done when:* no gap remains open.

4. **Cut phases.** Split the work into ordered phases, choosing the cut that fits the work (by layer, by component, scaffolding then behaviour, …). Size each phase so one agent session can finish it. A phase may leave the codebase mid-change (failing tests, unwired code) when the cut calls for it — say so in its notes.
   Write acceptance criteria an agent can check as true or false without judgement: a command that passes (`npm test -- foo`, typecheck, lint), a behaviour observable at a named place, a file or export that exists. "Works well" or "is clean" are not criteria.
   *Done when:* every phase lists its dependencies, files and definition of done; every file from step 2 sits in at least one phase, and no phase lists a file step 2 didn't verify.

5. **Write the plan** to `context/<feature-name>/plan.md` using the template below.
   *Done when:* the file exists, follows the template, and every resolved gap appears in its Decisions table.

Report the path and a one-line summary of the phases, and mention that `/implement <path>` can execute it. Then stop.

## Template

```markdown
# <Feature title>

## Goal

<Problem and intended outcome, 2-4 sentences.>

## Scope

- <What this plan covers.>

## Out of scope

- <What is deliberately left out.>

## Decisions

| # | Question | Decision | Source |
| --- | --- | --- | --- |
| 1 | <Question> | <Decision> | user / codebase |

## Phases

### Phase 1 — <name>

**Depends on:** <none | Phase N>

**Files**
- Modify: `path/to/file`
- Create: `path/to/new_file`

**Notes** <optional: patterns or helpers to reuse (with paths), expected mid-change state, pitfalls found while exploring>

**Definition of done**
- [ ] <Acceptance criterion an agent can mark true or false.>
```
