---
name: sdd
description: Run the full Spec-Driven Development workflow when the human explicitly invokes /sdd in Claude, Codex, or Cursor. It drives Spec through Build, delegates plan and implementation authoring to Codex or Cursor, has 3 human approval gates, and resumes from .sdd/TASK state.
---

You are the host orchestrator for a high-risk Spec-Driven Development task in Claude,
Codex, or Cursor. The human starts this skill once and may resume it in any supported host.
You drive the workflow through Build and pause for approval only at the 3 human gates.
Missing required input, unavailable tooling, and review-cap escalation may also block work.
Resume state lives in the TASK file, so a fresh session re-reads it and continues from the
first incomplete item.

## Roles (the critic is always the non-author model)

| Artifact | Author | AI critic |
|----------|--------|-----------|
| Spec | Host orchestrator | — (human only) |
| Test plan | Delegated author | host `test-plan-critic`, 1 round |
| Code plan | Delegated author | host `code-plan-critic`, 1 round |
| Test code | Delegated author | host `test-critic`, ≤3 rounds |
| Logic code | Delegated author | host `code-critic`, ≤3 rounds |

- The TASK file records `Delegated author: Codex` or `Delegated author: Cursor`. Default to
  Codex when scaffolding a task or reading an older TASK file without this field. If the
  human instructs you to switch, update the field before the next delegated call.
- Reach the delegated author through the installed host-local `sdd-codex.sh` or
  `sdd-cursor.sh` wrapper. If the selected wrapper is unavailable, stop before delegation
  and tell the human which wrapper is missing.
- When a phase says to invoke a critic, use the current host's native sub-agent mechanism
  to dispatch or spawn that named critic, provide the artifact plus required context, wait
  for its result, and use that result as the review output.
- If a named critic is unavailable through that mechanism, stop before Build work and tell
  the human to reinstall the SDD harness.
- You never let an author review its own artifact — that defeats the cross-model check.
- You must not replace these critic agents with inline review. Inline review is only an
  explicit emergency/manual workaround if the human asks for it.

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
- Throughout, "TASK file" means this path.

## If the TASK file is missing — scaffold and continue

Start from either a linked ticket/PRD or detailed instructions in the human's prompt. If
neither provides enough information to state the goal and scope, ask for the missing source
before scaffolding. Create `.sdd/`, suggest adding it to `.gitignore`, and write the TASK file
from the template at the end of this skill, filling in what you can infer from the source,
chat, branch, and repo. Substitute the `<branch>` and `<task-slug>` placeholders with their
resolved values as you write it. Then run a short Context bootstrap:
ask only the questions needed to complete the Context and Verification Commands sections
(numbered, answerable inline). If there are no unresolved `Question:` placeholders, continue
directly into the workflow. Otherwise, wait for the answers, update the TASK file, and then
continue.

## Each invocation — find the resume point

Read the TASK file top to bottom. The checkboxes are the state. Find the **first unchecked
`- [ ]` item** and resume there. Work forward, checking off steps as you finish them, until
you reach an unchecked **GATE** item. At a gate: present the summary below and **STOP** —
do not proceed without explicit human approval in a later message. Announce on entry:
`SDD: resuming at <phase> / <step>.`

A GATE checkbox is checked **only** after the human approves. Step checkboxes you may check
once the step's output exists.

The TASK file is host-owned durable state. Only the host orchestrator may update it.

## Shared loop mechanics

**Findings format.** Every AI review produces `PASS|FAIL` and findings split into
blocking and non-blocking. Critic agents use their prompt-specific text format.

**Blocking gate = "good enough".** Code review ends early on **zero blocking findings**.
Otherwise it continues for up to 3 rounds, then stops and escalates to the human with the
open blockers. Only blocking findings trigger another author edit; carry non-blocking
findings to the human instead of auto-fixing them. Plans receive one review per critic. If
either critic reports blockers, correct the plans once and present the replacements at Gate
2 without another AI verdict; do not claim that the original findings were verified as
resolved.

**Anti-churn.** Code review round 1 reviews the whole artifact. Rounds 2–3 are
**diff-scoped**: tell the reviewer to look only at what changed plus the still-open findings
from the prior round — not to re-derive the whole list. Reuse finding ids across rounds for
persistence.

**Calling the delegated author.** Write the prompt to a branch-scoped scratch file under
`.sdd/` (e.g. `.sdd/_author-prompt<branch>.md`), then call the backend recorded in the TASK:
- Codex: `<sdd-codex-wrapper> .sdd/_author-prompt<branch>.md .sdd/_author-msg<branch>.md`
- Cursor: `<sdd-cursor-wrapper> .sdd/_author-prompt<branch>.md .sdd/_author-msg<branch>.md`

The wrappers open the prompt and response files on the host side. The delegated process has
no access to `.sdd`; do not include the TASK file, its path, critic identities, verdicts,
rounds, or review history in a delegated prompt. When asking for corrections, translate
blocking findings into plain required changes.

Every delegated call starts with fresh context. Include the complete approved spec inline in
every Build-phase prompt. After plans exist, include both complete plans inline in every
plan-correction, test-authoring, implementation, and correction prompt. Include current
failure output and required changes on corrections. Refer to repository source and test files
by path instead of copying them unless an exact excerpt is necessary. Name planned repository
scope and verification commands when known.

Ask the author to report only changed files, verification commands and results, blockers,
and necessary scope deviations. After an implementation call, inspect the changed files
rather than relying on its report.

**Plan response contract.** A plan author cannot write `.sdd`. Require its response to contain
exactly two complete documents delimited by `BEGIN TEST PLAN` / `END TEST PLAN` and
`BEGIN CODE PLAN` / `END CODE PLAN`. Reject a missing, empty, duplicated, or out-of-order
section. The host writes the validated bodies to `PLAN-tests<branch>.md` and
`PLAN-code<branch>.md`. On a plan correction, send the complete spec and both current plans,
require both complete replacement documents, preserve an unaffected plan verbatim, validate
the response again, and let only the host replace the plan files.

## The phases

### Spec phase
1. **Research** (you + human). Read the source request in full. Find affected files, APIs,
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
   choices affect tests or blast radius. Explain non-trivial logic with pseudo-code, not
   actual implementation code. Prefer existing interfaces, design patterns, helpers,
   fixtures, and test conventions.

   The `Test Strategy` is a per-failure-mode rubric covering ownership, test level, rough
   sizing, and the simplest effective seam and fixture. Target enduring owned behavior; do
   not add upstream, migration-only, or config/static-asset loading coverage unless it
   protects an ongoing user-visible contract.

   Before Gate 1, run a scope-control pass. The pass is allowed to delete or narrow spec
   content, acceptance criteria, architecture notes, and test strategy. It should not add new
   scope unless required to resolve a contradiction or make the change testable. Check for
   duplicated coverage of existing tests; acceptance criteria that do not map to the user
   goal or an external contract; contradictions; unnecessary coupling, global state, or
   blast radius; missed reuse; and test strategies that patch internals instead of using an
   ordinary dependency seam.

   Revise the spec before presenting Gate 1. Mention only remaining material risks or
   tradeoffs in the Gate 1 presentation; do not include a QA report when the pass only
   removed or narrowed content. Check `Build`.
3. **GATE 1.** Present the spec and ask the human to approve or give feedback. On approval,
   check the gate. On feedback, revise the spec and re-present (no AI critic in this phase).

### Build phase
1. **Research** (you). Read the approved spec, its Architecture and Testability section, and
   its Test Strategy. For each acceptance criterion, identify its **failure modes**, the
   **unit under test**, collaborators, intended interaction seam, whether behavior is **owned
   here or upstream**, and the intended **level** (unit / integration / acceptance).
   Upstream-owned behavior is covered by its own tests — here you cover only this component's
   interaction with it. Search for existing tests covering the same unit/area and note which
   could be extended versus where a new test is warranted; also find reusable fixtures,
   factories, mocks, dependency-injection points, local mocking conventions, implementation
   targets, import styles, reusable utilities, state boundaries, and the repo-defined
   verification commands and their order. Confirm the test command and what a meaningful
   failure looks like. Check `Research`.
2. **Plan build.** Prompt the delegated author to return a paired, decision-complete test plan
   and code plan using the Plan response contract. The prompt must include the complete spec,
   your research notes, reusable tests/fixtures, implementation targets, local
   patterns, Architecture and Testability decisions, the exact test command, and the expected
   failure shape.

   Require the test plan to cover, for each case: the failure mode it catches, its level, the
   interaction seam it uses, the simplest mechanism that catches it (plain stub/mock through a
   stable seam by default; high-fidelity fixture only when justified by a named failure mode),
   and an assertion that binds to owned behavior and remains valuable after any migration or
   refactor is complete. Require economical case count, reuse-vs-new choices, no upstream
   re-testing, no migration-only assertions unless they protect an ongoing compatibility or
   user-visible contract, no dedicated config/static-asset loading tests, and explicit
   justification for any monkey-patching of internals, globals, or incidental module state.

   Require the code plan to cover: file-change sequence, per-file intent at the function
   level, where functionality belongs (class/module/helper/one-off), stateful vs stateless
   structure, state scope, dependency boundaries, reuse points, coupling tradeoffs, risks,
   commands proving readiness, and applicable Documentation guidance below. The code plan
   must respect the test plan's intended seams and must not require rewriting
   the tests around the implementation. If the spec's architecture is not testable as
   written, either plan must call that out instead of hiding it with brittle tests or
   implementation structure.

   Validate the response and write both plans to their branch-scoped `.sdd` files. Invoke
   `test-plan-critic` on the test plan with the code plan as
   context, then invoke `code-plan-critic` on the code plan with the test plan as context.
   If either critic reports blockers, translate them into required changes and run one plan
   correction, sending the complete spec and both complete plans and persisting only a
   validated response. Do not invoke another critic or infer a new verdict. Check `Plan`.
3. **GATE 2.** Present both plans, the critics' original verdicts and findings, and any
   corrected-plan diff labeled **not re-reviewed**. On feedback, require both complete
   replacement documents through the Plan response contract, preserving an unaffected plan
   verbatim; validate and persist them, then re-present without another AI verdict. On
   approval, check the gate.
4. **Build test code.** Delegate test authoring
   (prompt = complete spec + complete test plan + complete code plan for seam context + planned
   scope/files when known + test command). Instruct the author to implement the test
   plan without production behavior changes, keep changes within the planned scope, and
   report necessary deviations. Run the test command
   (deterministic check — the important new tests must **fail for the behavioral reason**,
   not infra; a premature pass is itself a blocking finding); invoke `test-critic` with the
   spec + approved test plan + test files + failing-test output. If blocking findings remain,
   delegate a correction with the complete spec, both complete plans, current failure
   evidence, and required changes, then repeat the deterministic check and diff-scoped review,
   up to 3 rounds. Stop early on zero blockers; at the cap, escalate. Record the test command
   output as evidence. Check `Build test code`.
5. **Build logic.** Start only after test code has zero blocking `test-critic` findings and
   the important new tests fail for the right reason. Delegate the implementation
   (prompt = complete spec + complete code plan + complete test plan + tests by path + planned scope/files when known +
   verification commands). Instruct the author to implement the code plan, satisfy the tests,
   keep changes within the planned scope, report necessary deviations, avoid weakening or
   rewriting the tests to obtain a pass, and apply the Documentation guidance below. Run
   every applicable command recorded under `Verification Commands` in its
   stated order — the Build-phase tests must pass; any failing command must be resolved before
   invoking `code-critic`. Once green, invoke `code-critic` with spec +
   plans + tests + impl + verification output. If blocking findings remain, delegate a
   correction with the complete spec, both complete plans, current verification evidence,
   and required changes, then repeat verification and diff-scoped review, up to 3 rounds.
   Stop early on zero blockers; at the cap, escalate. Check `Build logic`.
6. **GATE 3.** Present the test code, logic code, failing-test evidence, green verification
   output, and findings; approve or feedback. **Feedback loop:** delegated author fixes →
   rerun the applicable failing-test and full-verification checks → relevant host critic
   reviews once (`test-critic` for test changes, `code-critic` for logic changes, both if
   needed), using the same required context and current evidence → re-present; repeat until
   approved. On approval, check the gate and complete the task.

## Documentation guidance

Use the target repository's documentation style and language. For public and major classes,
functions, and methods, include only the relevant parts of this template:

```text
Summary: responsibility and owned behavior.
Parameters/inputs: important shape, constraints, and meanings.
Returns/outputs: result shape and important semantics.
Raises/errors: expected failures and why.
Side effects: state mutation, IO, network calls, logging, emitted events, or persistence.
Invariants/notes: non-obvious assumptions, lifecycle, dependency, or testing considerations.
```

Omit sections that are obvious or irrelevant. Do not require docstrings for trivial private
helpers, simple accessors, short obvious functions, or documentation that would be longer
than the implementation without adding maintenance value.

## Gate presentation (every gate)

Show the artifact or diff, available critic findings, any cap-hit escalation, and a one-line
readiness assessment. Never describe a correction as reviewed unless a critic actually
reviewed it. Ask the human to **approve** or **give feedback**, and stop.

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
- Delegated author: Codex

## Verification Commands
- Test:
- Additional repo-defined commands:

## Artifacts
- Spec: `specs/<module>/<task-slug>.md`
- Test plan: `.sdd/PLAN-tests<branch>.md`
- Code plan: `.sdd/PLAN-code<branch>.md`

## 1. Spec Phase
- [ ] Research (host orchestrator + human)
- [ ] Build spec (host orchestrator -> specs/<module>/<slug>.md at repo root)
- [ ] GATE 1: human approves spec

## 2. Build Phase
- [ ] Research (host orchestrator, from spec)
- [ ] Plan build (delegated author returns test + code plans; host writes them)
- [ ] GATE 2: human approves build plans
- [ ] Build test code (delegated author; new tests fail for the right reason)
- [ ] Build logic (delegated author; full verification, tests must pass)
- [ ] GATE 3: human approves test + logic code

## Approval Notes
- Spec approved by:
- Build plans approved by:
- Build approved by:
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
