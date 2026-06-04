---
name: sdd
description: Run the full Spec-Driven Development workflow for high-risk work end to end. Start it once; it drives Spec -> Tests -> Code, pausing only at the 5 human approval gates, and resumes from .sdd/TASK state on re-invocation. Claude authors and orchestrates; GPT (via the codex CLI) is the cross-model author/critic.
disable-model-invocation: true
---

You are the orchestrator for a high-risk Spec-Driven Development task. The human starts
this skill once. You drive the whole workflow and **stop only at the 5 human gates**. You
are resumable: all progress lives in the TASK file, so a fresh session re-reads it and
continues from the first incomplete item.

## Roles (the critic is always the non-author model)

| Artifact | Author | AI critic |
|----------|--------|-----------|
| Spec | you (Claude) | — (human only) |
| Test plan | you (Claude) | GPT, 1 round |
| Test code | GPT | you (Claude), ≤3 rounds |
| Code plan | you (Claude) | GPT, 1 round |
| Logic code | GPT | you (Claude), ≤3 rounds |

- You reach **GPT** through the wrapper `~/.claude/sdd/sdd-codex.sh` (it calls `codex exec`).
- You review **GPT's code** with the `test-critic` (Tests phase) and `code-critic` (Code
  phase) subagents.
- You never let GPT review its own code and never review your own plan — that defeats the
  cross-model check.

## Resolve the TASK file

- `git rev-parse --show-toplevel` → repo root (else the working directory; say so).
- `git rev-parse --abbrev-ref HEAD` → branch. Sanitize: strip up to the last `/`,
  lowercase, replace non `[a-z0-9-]` with `-`, collapse repeats, trim `-`. Path is
  `<root>/.sdd/TASK-<branch>.md`. On failure or detached HEAD, use `<root>/.sdd/TASK.md`.
- Throughout, "TASK file" means this path. Suggest the human add `.sdd/` to `.gitignore`.

## If the TASK file is missing — scaffold, then stop

Create `.sdd/`, write the TASK file from the template at the end of this skill, filling in
what you can infer from the chat, branch, and repo. Then run a short Context bootstrap:
ask only the questions needed to complete the Context and Verification Commands sections
(numbered, answerable inline). **Do not start the workflow until Context has no unresolved
`Question:` placeholders.** Once the human answers, update the TASK file and continue.

## Each invocation — find the resume point

Read the TASK file top to bottom. The checkboxes are the state. Find the **first unchecked
`- [ ]` item** and resume there. Work forward, checking off steps as you finish them, until
you reach an unchecked **GATE** item. At a gate: present the summary below and **STOP** —
do not proceed without explicit human approval in a later message. Announce on entry:
`SDD: resuming at <phase> / <step>.`

A GATE checkbox is checked **only** after the human approves. Step checkboxes you may check
once the step's output exists.

## Shared loop mechanics

**Findings format.** Every AI review (GPT plan review and your code review) produces:
`verdict: PASS|FAIL` and a list of findings, each `{id, blocking, location, description,
suggested_fix}`. GPT emits this as JSON (the wrapper enforces the schema). You emit the
same shape from the critic subagent output.

**Blocking gate = "good enough".** A review round ends the loop early the moment it returns
**zero blocking findings**. Otherwise the loop continues up to its cap (1 round for plans,
3 for code), then you **stop and escalate to the human** with the open blockers listed.
Only **blocking** findings trigger another author edit. Non-blocking findings are carried
to the human at the gate, not auto-fixed.

**Anti-churn.** Round 1 reviews the whole artifact. Rounds 2–3 are **diff-scoped**: tell
the reviewer to look only at what changed plus the still-open findings from the prior
round — not to re-derive the whole list. Reuse finding ids across rounds for persistence.

**Calling GPT.** Write the prompt to a temp file under `.sdd/` (e.g.
`.sdd/_codex-prompt.md`), then:
- Plan review: `~/.claude/sdd/sdd-codex.sh plan-review .sdd/_codex-prompt.md .sdd/_codex-out.json`
  then read `.sdd/_codex-out.json`.
- Code authoring: `~/.claude/sdd/sdd-codex.sh build .sdd/_codex-prompt.md .sdd/_codex-msg.md`
- Applying blocking fixes: `~/.claude/sdd/sdd-codex.sh fix .sdd/_codex-prompt.md .sdd/_codex-msg.md`
Each GPT prompt must include the relevant context inline or by file path (spec path, plan,
the open findings, and exactly which files to write). After a build/fix, read the changed
files from disk to see what GPT actually did.

## The phases

### Spec phase
1. **Research** (you + human). Read the linked request in full. Find affected files, APIs,
   schemas, configs, and downstream dependencies. Note prior decisions, risks, and open
   questions. Collaborate with the human to resolve intent. Output: Detected state | Key
   findings | Constraints | Open questions. Check `Research`.
2. **Build spec** (you). Derive the slug from the task title. Write `specs/<slug>.md`
   using the Spec structure at the end of this skill — every section filled, acceptance
   criteria numbered and individually testable. Read it back for coherence. Check `Build`.
3. **GATE 1.** Present the spec and ask the human to approve or give feedback. On approval,
   check the gate. On feedback, revise the spec and re-present (no AI critic in this phase).

### Tests phase
1. **Research** (you). Read the approved spec. Classify each acceptance criterion:
   covered / needs-new-test / untestable (say why). Find fixtures, factories, mocks.
   Confirm the test command and what a meaningful failure looks like. Check `Research`.
2. **Plan test code** (you → GPT 1 round). Draft a decision-complete plan covering **test
   code only**: files to create, cases per criterion (name/input/expected/criterion),
   fixtures and mocks, the exact test command, and the expected failure shape. Send the
   plan + spec to GPT via `plan-review` (rubric: does the plan cover every acceptance
   criterion, are cases concrete, will the named tests actually fail for the right reason,
   any missing edge/failure cases, any ambiguity left for the builder). Apply blocking
   findings; carry non-blocking to the gate. Persist the plan to `.sdd/PLAN-tests.md`.
   Check `Plan`.
3. **GATE 2.** Present the plan + GPT's non-blocking findings; approve or feedback.
4. **Build test code** (GPT → you ≤3 rounds). Have GPT author the tests via `build`
   (prompt = spec + approved plan + exact files to write). Then loop: run the test command
   (deterministic check — the important new tests must **fail for the behavioral reason**,
   not infra; a premature pass is itself a blocking finding); invoke `test-critic` with the
   spec + test files as a review round; if blocking findings remain, have GPT `fix` them
   (diff-scoped after round 1) and repeat, up to 3 rounds. Stop early on zero blockers; at
   the cap, escalate. Record the test command output as evidence. Check `Build`.
5. **GATE 3.** Present the tests, the failing-for-the-right-reason evidence, and findings;
   approve or feedback. **Feedback loop:** GPT applies the human's fixes (`fix`) → you
   review once (`test-critic`) → re-present to the human; repeat until approved.

### Code phase
1. **Research** (you). From the spec + the test code: identify implementation targets,
   local patterns, import styles, reusable utilities, and the verification loop order
   (test → lint → typecheck → build). Check `Research`.
2. **Plan logic** (you → GPT 1 round). Draft a decision-complete implementation plan from
   **spec + test code**: file-change sequence, per-file intent at the function level,
   risks, and the verification loop. GPT `plan-review` (rubric: will this make the failing
   tests pass, correctness of approach, missing cases, interface consistency with the
   tests, decision-completeness). Apply blocking findings; persist to `.sdd/PLAN-code.md`.
   Check `Plan`.
3. **GATE 4.** Present the plan + non-blocking findings; approve or feedback.
4. **Build logic** (GPT → you ≤3 rounds). GPT authors the implementation via `build`. Then
   loop: run the full verification (test → lint → typecheck → build) — **the test-phase
   tests must pass**; any failing command is a blocking finding GPT must fix before review.
   Once green, invoke `code-critic` with spec + tests + impl + verification output as a
   review round; have GPT `fix` blocking findings (diff-scoped after round 1), up to 3
   rounds. Stop early on zero blockers; at the cap, escalate. Check `Build`.
5. **GATE 5.** Present the implementation, the green verification output, and findings;
   approve or feedback. **Feedback loop:** GPT fixes → you review once (`code-critic`) →
   re-present; repeat until approved. On approval, the task is complete.

## Gate presentation (every gate)

Show: the artifact (or its diff), the cross-model findings split into **blocking (resolved
this round)** and **non-blocking (for your call)**, any cap-hit escalations, and a one-line
readiness assessment. Then ask the human to **approve** or **give feedback**, and stop.

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
- Test plan: `.sdd/PLAN-tests.md`
- Code plan: `.sdd/PLAN-code.md`

## 1. Spec Phase
- [ ] Research (Claude + human)
- [ ] Build spec (Claude -> specs/<slug>.md)
- [ ] GATE 1: human approves spec

## 2. Tests Phase
- [ ] Research (Claude, from spec)
- [ ] Plan test code (Claude draft -> GPT review 1x -> edit)
- [ ] GATE 2: human approves test plan
- [ ] Build test code (GPT author -> Claude review <=3x -> GPT fix; new tests fail for the right reason)
- [ ] GATE 3: human approves test code

## 3. Code Phase
- [ ] Research (Claude, from spec + test code)
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
[Signatures, endpoints, schemas, columns, config keys, message formats — with types.]

## Edge Cases and Failure Modes
- When [condition]: [expected behavior]

## Acceptance Criteria
[Numbered; each independently testable without reading source.]
1.

## Test Strategy
[Which criteria need unit/integration tests; what can't be tested automatically and why.]

## Compatibility, Rollout, and Risks
[Migrations, versioning, flags, ordering, downstream impact, rollback, known unknowns.]
```
