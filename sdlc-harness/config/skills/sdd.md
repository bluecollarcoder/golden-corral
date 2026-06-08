---
name: sdd
description: Run the full Spec-Driven Development workflow for high-risk work end to end in Claude, Codex, or Cursor after or including the Spec phase. It drives Spec -> Tests -> Code, pausing only at the 5 human approval gates, and resumes from .sdd/TASK state on re-invocation. GPT is reached through the codex CLI, and each host bootstraps its own critic agents.
disable-model-invocation: true
---

You are the host orchestrator for a high-risk Spec-Driven Development task in Claude,
Codex, or Cursor. The human starts this skill once and may resume it in any supported host.
You drive the workflow through Tests and Code and **stop only at the 5 human gates**. You
are resumable: all progress lives in the TASK file, so a fresh session re-reads it and
continues from the first incomplete item.

## Roles (the critic is always the non-author model)

| Artifact | Author | AI critic |
|----------|--------|-----------|
| Spec | Host orchestrator | — (human only) |
| Test plan | GPT | host `plan-critic`, 1 round |
| Test code | GPT | host `test-critic`, ≤3 rounds |
| Code plan | GPT | host `plan-critic`, 1 round |
| Logic code | GPT | host `code-critic`, ≤3 rounds |

- You reach **GPT** through the host-local installed `sdd-codex.sh` wrapper (it calls
  `codex exec`): `~/.claude/sdd/sdd-codex.sh` in Claude, `~/.codex/sdd/sdd-codex.sh` in
  Codex, or the active underlying host path in Cursor. If no wrapper is available, stop
  before calling GPT and tell the human which wrapper path is missing.
- You review **GPT's plans** with the host-local `plan-critic` agent, **GPT's tests** with
  the host-local `test-critic` agent, and **GPT's implementation** with the host-local
  `code-critic` agent.
- When a phase says to invoke a critic, dispatch or spawn that named host-local critic
  agent, provide the artifact plus required context, wait for its result, and use that
  result as the review output.
- You never let an author review its own artifact — that defeats the cross-model check.
- You must not replace these critic agents with inline review. Inline review is only an
  explicit emergency/manual workaround if the human asks for it.

## Critic bootstrap

Before any Tests Phase or Code Phase step that invokes `plan-critic`, `test-critic`, or
`code-critic`, ensure the current host has those three critic agents available:

- Claude: `~/.claude/agents/plan-critic.md`, `~/.claude/agents/test-critic.md`, and
  `~/.claude/agents/code-critic.md`.
- Codex: `~/.codex/agents/plan-critic.toml`, `~/.codex/agents/test-critic.toml`, and
  `~/.codex/agents/code-critic.toml`.
- Cursor: use the active underlying Claude or Codex host path available in the current
  environment; do not require a separate Cursor-specific command or rules install.

The installed critic agents are generated from the shared prompt bodies in
`config/agents/*.md`. If the required critic agents are missing and the source prompt bodies
are available, create the missing host-local agent files before continuing. If the source
prompt bodies are not available or the host cannot create agent files, stop before Tests or
Code work and tell the human exactly which critic setup is missing.

## Resolve the TASK file

- `git rev-parse --show-toplevel` → repo root (else the working directory; say so).
- `git rev-parse --abbrev-ref HEAD` → branch. Sanitize: strip up to the last `/`,
  lowercase, replace non `[a-z0-9-]` with `-`, collapse repeats, trim `-`. Define the
  suffix `<branch>` as `-<sanitized>`; on failure or detached HEAD, `<branch>` is empty.
- The TASK file is `<root>/.sdd/TASK<branch>.md`. Every other per-task `.sdd/` artifact
  uses the same `<branch>` suffix so parallel branches never collide: `PLAN-tests<branch>.md`,
  `PLAN-code<branch>.md`, and the scratch files below.
- The spec file is always `<root>/specs/<module>/<task-slug>.md`; pick the existing
  `specs/` subfolder that matches the affected area, or create the obvious domain folder.
  Never write the spec relative to the current working directory.
- Throughout, "TASK file" means this path. Suggest the human add `.sdd/` to `.gitignore`.

## If the TASK file is missing — scaffold, then stop

Create `.sdd/`, write the TASK file from the template at the end of this skill, filling in
what you can infer from the chat, branch, and repo. Substitute the `<branch>` and
`<task-slug>` placeholders with their resolved values as you write it. Then run a short Context bootstrap:
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

**Findings format.** Every AI review produces `PASS|FAIL` and findings split into
blocking and non-blocking. Critic agents use their prompt-specific text format.

**Blocking gate = "good enough".** A review round ends the loop early the moment it returns
**zero blocking findings**. Otherwise the loop continues up to its cap (1 round for plans,
3 for code), then you **stop and escalate to the human** with the open blockers listed.
Only **blocking** findings trigger another author edit. Non-blocking findings are carried
to the human at the gate, not auto-fixed.

**Anti-churn.** Round 1 reviews the whole artifact. Rounds 2–3 are **diff-scoped**: tell
the reviewer to look only at what changed plus the still-open findings from the prior
round — not to re-derive the whole list. Reuse finding ids across rounds for persistence.

**Calling GPT.** Write the prompt to a branch-scoped scratch file under `.sdd/` (e.g.
`.sdd/_codex-prompt<branch>.md`), then:
- Plan, test, or code authoring: `<sdd-codex-wrapper> build .sdd/_codex-prompt<branch>.md .sdd/_codex-msg<branch>.md`
- Applying blocking fixes: `<sdd-codex-wrapper> fix .sdd/_codex-prompt<branch>.md .sdd/_codex-msg<branch>.md`
Each GPT prompt must include the relevant context inline or by file path (spec path, plan,
the open findings, and exactly which files to write). For plans, tell GPT to write the
exact `.sdd/PLAN-*<branch>.md` file. After a build/fix, read the changed files from disk
to see what GPT actually did.

## The phases

### Spec phase
1. **Research** (you + human). Read the linked request in full. Find affected files, APIs,
   schemas, configs, downstream dependencies, existing design patterns, and test seams. Note
   prior decisions, risks, and open questions. Collaborate with the human to resolve intent.
   Output: Detected state | Key findings | Architecture/testability constraints | Open
   questions. Check `Research`.
2. **Build spec** (you). Choose the `specs/<module>/` folder from the affected area and
   derive the slug from the task title. Create `<root>/specs/<module>/` if needed and
   write `<root>/specs/<module>/<slug>.md` using the Spec structure at the end of this
   skill — every section filled, acceptance criteria numbered, individually testable, and
   limited to behavior that must change or remain guaranteed for the user goal to be
   satisfied. Use `Architecture and Testability` to choose the smallest code structure that
   preserves dependency injection, reuse, loose coupling, testability, and mockability.
   Address where functionality belongs (class/module/helper/one-off), interaction seams,
   stateful vs stateless behavior, and state scope (global/module/class/closure) when those
   choices affect tests or blast radius. Prefer existing interfaces, design patterns,
   helpers, fixtures, and test conventions.

   The `Test Strategy` section is a real rubric, not a sentence. It names only the new or
   changed behavior that needs additional coverage, notes existing tests that already cover
   unchanged behavior when relevant, and uses the cheapest effective test level. For each
   failure mode, name ownership here vs upstream, test level (unit / integration /
   acceptance), rough sizing per level, and any specific failure mode that justifies a
   high-fidelity fixture or mock. Default otherwise to the simplest good-enough stub. When a
   class interface or expected output shape changes, aim tests at the new enduring contract
   and owned failure modes. Avoid migration-only assertions that only prove the old shape,
   adapter, class name, or transitional mapping changed, unless compatibility or
   user-visible regression risk makes that behavior an ongoing contract.

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
   check the gate. On feedback, revise the spec and re-present (no AI critic in this phase).

### Tests phase
1. **Research** (you). Read the approved spec, its Architecture and Testability section, and
   its Test Strategy. For each acceptance criterion, identify its **failure modes**, the
   **unit under test**, collaborators, intended interaction seam, whether behavior is **owned
   here or upstream**, and the intended **level** (unit / integration / acceptance).
   Upstream-owned behavior is covered by its own tests — here you cover only this component's
   interaction with it. Classify each criterion: covered / needs-new-test / untestable (say
   why). Search for **existing tests covering the same unit/area** and note which could be
   extended (an added assertion or a parametrized case) versus where a new test is warranted;
   also find reusable fixtures, factories, mocks, dependency-injection points, and local
   mocking conventions. Confirm the test command and what a meaningful failure looks like.
   Check `Research`.
2. **Plan test code** (GPT → you 1 round). Prompt GPT via `build` to author a
   decision-complete **test-code-only** plan and write it to `.sdd/PLAN-tests<branch>.md`.
   The prompt must include the approved spec, your research notes, reusable tests/fixtures,
   the exact test command, and the expected failure shape. Require the plan to cover, for
   each case: the failure mode it catches, its level, the interaction seam it uses, the
   simplest mechanism that catches it (plain stub/mock through a stable seam by default;
   high-fidelity fixture only when justified by a named failure mode), and an assertion that
   binds to owned behavior and remains valuable after any migration or refactor is complete.
   Require economical case count, reuse-vs-new choices, no upstream re-testing, no
   migration-only assertions unless they protect an ongoing compatibility or user-visible
   contract, and explicit justification for any monkey-patching of internals, globals, or
   incidental module state. If the spec's architecture is not testable as written, the plan
   must call that out instead of hiding it with brittle tests. Read the plan from disk, invoke
   `plan-critic` in test-plan mode, then have GPT fix blocking findings once if needed.
   Carry non-blocking findings to the gate. Check `Plan`.
3. **GATE 2.** Present the plan + `plan-critic` non-blocking findings; approve or feedback.
4. **Build test code** (GPT → you ≤3 rounds). Have GPT author the tests via `build`
   (prompt = spec + approved plan + exact files to write). Instruct GPT to follow the plan's
   level, seam, and mechanism per case: favor simple, maintainable, economical tests; reuse
   existing tests/fixtures/helpers as the plan specifies; stub/mock collaborators through
   stable dependency seams to create the condition (or load a high-fidelity fixture only
   where the plan justified one); do not patch internals/globals/incidental module state when
   the approved architecture provides a normal seam; keep each test at its chosen level and
   within the task's ownership boundary. Then loop:
   run the test command
   (deterministic check — the important new tests must **fail for the behavioral reason**,
   not infra; a premature pass is itself a blocking finding); invoke `test-critic` with the
   spec + test files as a review round; if blocking findings remain, have GPT `fix` them
   (diff-scoped after round 1) and repeat, up to 3 rounds. Stop early on zero blockers; at
   the cap, escalate. Record the test command output as evidence. Check `Build`.
5. **GATE 3.** Present the tests, the failing-for-the-right-reason evidence, and findings;
   approve or feedback. **Feedback loop:** GPT applies the human's fixes (`fix`) → you
   review once (`test-critic`) → re-present to the human; repeat until approved.

### Code phase
1. **Research** (you). From the spec + the test code: identify implementation targets, the
   approved Architecture and Testability decisions, local patterns, import styles, reusable
   utilities, dependency-injection points, state boundaries, and the verification loop order
   (test → lint → typecheck → build). Check `Research`.
2. **Plan logic** (GPT → you 1 round). Prompt GPT via `build` to author a
   decision-complete implementation plan from **spec + test code** and write it to
   `.sdd/PLAN-code<branch>.md`. The prompt must include the approved spec, the approved
   test code, your research notes, implementation targets, local patterns, architecture and
   testability decisions, and the verification loop. Require file-change sequence, per-file
   intent at the function level, where functionality belongs (class/module/helper/one-off),
   stateful vs stateless structure, state scope, dependency boundaries, reuse points,
   coupling tradeoffs, risks, and commands proving readiness. Read the plan from disk, invoke
   `plan-critic` in code-plan mode, then have GPT fix blocking findings once if needed.
   Carry non-blocking findings to the gate. Check `Plan`.
3. **GATE 4.** Present the plan + `plan-critic` non-blocking findings; approve or feedback.
4. **Build logic** (GPT → you ≤3 rounds). GPT authors the implementation via `build`.
   Instruct GPT to follow the approved architecture and code plan, preserve the smallest
   practical blast radius, reuse existing patterns/utilities, avoid opportunistic
   abstractions or refactors, and keep dependency injection, state scope, and interaction
   seams testable. Then loop: run the full verification (test → lint → typecheck → build) —
   **the test-phase tests must pass**; any failing command is a blocking finding GPT must fix before review.
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
- Spec: `specs/<module>/<task-slug>.md`
- Test plan: `.sdd/PLAN-tests<branch>.md`
- Code plan: `.sdd/PLAN-code<branch>.md`

## 1. Spec Phase
- [ ] Research (host orchestrator + human)
- [ ] Build spec (host orchestrator -> specs/<module>/<slug>.md at repo root)
- [ ] GATE 1: human approves spec

## 2. Tests Phase
- [ ] Research (host orchestrator, from spec)
- [ ] Plan test code (GPT author -> host plan-critic 1x -> GPT fix)
- [ ] GATE 2: human approves test plan
- [ ] Build test code (GPT author -> host test-critic <=3x -> GPT fix; new tests fail for the right reason)
- [ ] GATE 3: human approves test code

## 3. Code Phase
- [ ] Research (host orchestrator, from spec + test code)
- [ ] Plan logic (GPT author -> host plan-critic 1x -> GPT fix)
- [ ] GATE 4: human approves code plan
- [ ] Build logic (GPT author -> host code-critic <=3x -> GPT fix; full verification, tests must pass)
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
[Signatures, endpoints, schemas, columns, config keys, message formats — with types.]

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
