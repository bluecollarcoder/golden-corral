---
name: sdd-spec
description: Run only the Spec phase of the SDD workflow in Claude or Codex. It scaffolds/resumes .sdd/TASK state, writes specs/<module>/<slug>.md at the repo root, stops at Gate 1, and hands Tests and Code phases back to Claude's full /sdd workflow.
---

You run only the Spec phase of a high-risk Spec-Driven Development task. This skill may
run in Claude or Codex. It writes the same TASK and spec artifacts used by the full Claude
`sdd` workflow, then stops after Gate 1 so Claude can run Tests and Code.

## Boundary

- You may do Spec Phase work only: scaffold TASK state, research, collaborate on intent,
  write or revise `<root>/specs/<module>/<slug>.md`, and handle Gate 1 approval.
- You must not start Tests Phase or Code Phase work.
- If the TASK file's first unchecked item is after `GATE 1: human approves spec`, stop and
  tell the human to resume in Claude Code with `/sdd`.
- If the first unchecked item is `GATE 1: human approves spec` and the human explicitly
  approves the spec, check that gate, then stop and tell the human to resume in Claude Code
  with `/sdd`.

## Resolve the TASK file

- `git rev-parse --show-toplevel` -> repo root (else the working directory; say so).
- `git rev-parse --abbrev-ref HEAD` -> branch. Sanitize: strip up to the last `/`,
  lowercase, replace non `[a-z0-9-]` with `-`, collapse repeats, trim `-`. Define the
  suffix `<branch>` as `-<sanitized>`; on failure or detached HEAD, `<branch>` is empty.
- The TASK file is `<root>/.sdd/TASK<branch>.md`. Every per-task `.sdd/` artifact uses the
  same `<branch>` suffix so parallel branches never collide.
- The spec file is always `<root>/specs/<module>/<task-slug>.md`; pick the existing
  `specs/` subfolder that matches the affected area, or create the obvious domain folder.
  Never write the spec relative to the current working directory.
- Throughout, "TASK file" means this path. Suggest the human add `.sdd/` to `.gitignore`.

## If the TASK file is missing - scaffold, then stop

Create `.sdd/`, write the TASK file from the template at the end of this skill, filling in
what you can infer from the chat, branch, and repo. Substitute the `<branch>` and
`<task-slug>` placeholders with their resolved values as you write it. Then run a short
Context bootstrap: ask only the questions needed to complete the Context and Verification
Commands sections (numbered, answerable inline). Do not start the workflow until Context
has no unresolved `Question:` placeholders. Once the human answers, update the TASK file
and continue.

## Each invocation - find the resume point

Read the TASK file top to bottom. The checkboxes are the state. Find the first unchecked
`- [ ]` item and resume there. Work forward only through the Spec Phase until you reach
Gate 1. Announce on entry: `SDD spec: resuming at <phase> / <step>.`

A GATE checkbox is checked only after the human approves. Step checkboxes may be checked
once the step's output exists.

## Spec phase

1. **Research** (you + human). Read the linked request in full. Find affected files, APIs,
   schemas, configs, downstream dependencies, existing design patterns, and test seams. Note
   prior decisions, risks, and open questions. Collaborate with the human to resolve intent.
   Output: Detected state | Key findings | Architecture/testability constraints | Open
   questions. Check `Research`.
2. **Build spec** (you). Choose the `specs/<module>/` folder from the affected area and
   derive the slug from the task title. Create `<root>/specs/<module>/` if needed and
   write `<root>/specs/<module>/<slug>.md` using the Spec structure at the end of this
   skill, with every section filled and
   acceptance criteria numbered, individually testable, and limited to behavior that must
   change or remain guaranteed for the user goal to be satisfied. Use `Architecture and
   Testability` to choose the smallest code structure that preserves dependency injection,
   reuse, loose coupling, testability, and mockability. Address where functionality belongs
   (class/module/helper/one-off), interaction seams, stateful vs stateless behavior, and
   state scope (global/module/class/closure) when those choices affect tests or blast
   radius. Prefer existing interfaces, design patterns, helpers, fixtures, and test
   conventions.

   The `Test Strategy` section is a real rubric, not a sentence. It names only the new or
   changed behavior that needs additional coverage, notes existing tests that already cover
   unchanged behavior when relevant, and uses the cheapest effective test level. For each
   failure mode, name ownership here vs upstream, test level (unit / integration /
   acceptance), rough sizing per level, and any specific failure mode that justifies a
   high-fidelity fixture or mock. Default otherwise to the simplest good-enough stub.

   Before Gate 1, run a scope-control pass. The pass is allowed to delete or narrow spec
   content, acceptance criteria, architecture notes, and test strategy. It should not add new
   scope unless required to resolve a contradiction or make the change testable. Check for
   duplicated coverage of existing tests; acceptance criteria that do not map to the user
   goal or an external contract; contradictory requirements; architectural choices that
   increase coupling, global state, or blast radius without need; missed reuse of existing
   patterns, helpers, fixtures, or seams; and test strategies that rely on monkey-patching
   where ordinary dependency structure would make the code easy to test.

   Revise the spec before presenting Gate 1. Mention only remaining material risks or
   tradeoffs in the Gate 1 presentation; do not include a QA report when the pass only
   removed or narrowed content. Check `Build`.
3. **GATE 1.** Present the spec and ask the human to approve or give feedback. On approval,
   check the gate, then stop and tell the human to resume Tests and Code in Claude Code
   with `/sdd`. On feedback, revise the spec and re-present. There is no AI critic in this
   phase.

## Gate presentation

Show the spec path, a concise summary of decisions, open risks or questions, and a one-line
readiness assessment. Ask the human to approve or give feedback, and stop.

---

## TASK file template (write this when scaffolding)

```markdown
# Task: [Feature or Branch Title]

## Context
- Goal:
- Why this needs the high-risk SDD flow:
- Linked issue or source request:
- Non-goals:
- Review Focus:

## Verification Commands
- Test:
- Lint:
- Typecheck:
- Build:

## Artifacts
- Spec: `specs/<module>/<task-slug>.md`
- Test plan: `.sdd/PLAN-tests<branch>.md`
- Code plan: `.sdd/PLAN-code<branch>.md`

## 1. Spec Phase
- [ ] Research (Claude or Codex + human)
- [ ] Build spec (Claude or Codex -> specs/<module>/<slug>.md at repo root)
- [ ] GATE 1: human approves spec

## 2. Tests Phase
- [ ] Research (Claude only, from spec)
- [ ] Plan test code (GPT author -> Claude plan-critic 1x -> GPT fix)
- [ ] GATE 2: human approves test plan
- [ ] Build test code (GPT author -> Claude review <=3x -> GPT fix; new tests fail for the right reason)
- [ ] GATE 3: human approves test code

## 3. Code Phase
- [ ] Research (Claude only, from spec + test code)
- [ ] Plan logic (GPT author -> Claude plan-critic 1x -> GPT fix)
- [ ] GATE 4: human approves code plan
- [ ] Build logic (GPT author -> Claude review <=3x -> GPT fix; full verification, tests must pass)
- [ ] GATE 5: human approves logic code

## Approval Notes
- Spec approved by:
- Test plan approved by:
- Test code approved by:
- Code plan approved by:
- Logic code approved by:
```

## Spec structure (write this to `<root>/specs/<module>/<slug>.md`)

```markdown
# Spec: [Feature Name]

## Goal
[One paragraph: what this accomplishes and why. Close with a sentence bounding scope.]

## Non-Goals
[High-level boundaries a reader might assume are included but aren't. Omit trivial ones.]

## Current Behavior
[What the system does today, including the gap that motivates this work.]

## Proposed Behavior
[Precise post-change behavior: who calls what, in what order, what is returned. Present tense.]

## Interfaces and Data
[Signatures, endpoints, schemas, columns, config keys, message formats - with types.]

## Architecture and Testability
[Chosen code structure and why: where functionality belongs, dependency injection path,
reuse points, coupling boundaries, interaction seams, stateful vs stateless behavior, state
scope, and how tests should exercise the seam without patching internals.]

## Edge Cases and Failure Modes
- When [condition]: [expected behavior]

## Acceptance Criteria
[Numbered; each independently testable without reading source.]
1.

## Test Strategy
[Per failure mode: what failure are we catching, and is the behavior owned here or upstream
(re-test only what we own). Level: unit / integration / acceptance, pushing volume to the
cheapest level that catches it. Sizing: rough case count per level. Fidelity: default to the
simplest good-enough stub/mock; name any specific failure mode that justifies a high-fidelity
recorded fixture. Note anything that can't be tested automatically and why.]

## Compatibility, Rollout, and Risks
[Migrations, versioning, flags, ordering, downstream impact, rollback, known unknowns.]
```
