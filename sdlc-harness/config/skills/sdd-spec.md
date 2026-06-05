---
name: sdd-spec
description: Run only the Spec phase of the SDD workflow in Claude or Codex. It scaffolds/resumes .sdd/TASK state, writes specs/<slug>.md, stops at Gate 1, and hands Tests and Code phases back to Claude's full /sdd workflow.
---

You run only the Spec phase of a high-risk Spec-Driven Development task. This skill may
run in Claude or Codex. It writes the same TASK and spec artifacts used by the full Claude
`sdd` workflow, then stops after Gate 1 so Claude can run Tests and Code.

## Boundary

- You may do Spec Phase work only: scaffold TASK state, research, collaborate on intent,
  write or revise `specs/<slug>.md`, and handle Gate 1 approval.
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
   schemas, configs, and downstream dependencies. Note prior decisions, risks, and open
   questions. Collaborate with the human to resolve intent. Output: Detected state | Key
   findings | Constraints | Open questions. Check `Research`.
2. **Build spec** (you). Derive the slug from the task title. Write `specs/<slug>.md`
   using the Spec structure at the end of this skill, with every section filled and
   acceptance criteria numbered and individually testable. The `Test Strategy` section is a
   real rubric, not a sentence: name failure modes, ownership here vs upstream, test level
   for each (unit / integration / acceptance), rough sizing per level, and any specific
   failure mode that justifies a high-fidelity fixture or mock. Default otherwise to the
   simplest good-enough stub. While writing, keep the acceptance criteria and test strategy
   essential and economical: every criterion maps to user-visible or contract-level behavior
   from the spec; no criterion tests implementation details, incidental sequencing, or
   upstream-owned behavior; criteria are individually testable and non-overlapping; the test
   strategy covers the implied failure modes without duplicate cases; coverage is pushed to
   the cheapest level that catches each failure; high-fidelity fixtures are used only when a
   named failure mode requires them; and nice-to-have, exploratory, or defensive breadth is
   moved to risks/notes or dropped. Read it back for coherence. Check `Build`.
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
- Spec: `specs/<task-slug>.md`
- Test plan: `.sdd/PLAN-tests<branch>.md`
- Code plan: `.sdd/PLAN-code<branch>.md`

## 1. Spec Phase
- [ ] Research (Claude or Codex + human)
- [ ] Build spec (Claude or Codex -> specs/<slug>.md)
- [ ] GATE 1: human approves spec

## 2. Tests Phase
- [ ] Research (Claude only, from spec)
- [ ] Plan test code (Claude draft -> GPT review 1x -> edit)
- [ ] GATE 2: human approves test plan
- [ ] Build test code (GPT author -> Claude review <=3x -> GPT fix; new tests fail for the right reason)
- [ ] GATE 3: human approves test code

## 3. Code Phase
- [ ] Research (Claude only, from spec + test code)
- [ ] Plan logic (Claude draft -> GPT review 1x -> edit)
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

## Spec structure (write this to `specs/<slug>.md`)

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
