# Spec-Driven Development (SDD)

This is a lightweight harness for using AI coding agents on major or high-risk software work. It keeps the work anchored to explicit artifacts: a specification, failing tests, production code, deterministic verification, and human approval gates.

Use this when the cost of ambiguity is high: major features, risky refactors, data migrations, security-sensitive changes, public API changes, cross-system behavior, or long-running agent work. For small bug fixes, copy edits, mechanical refactors, or obvious one-file changes, use the normal loop: research, edit, verify, review.

The goal is not to automate the whole SDLC. The goal is to give Claude Code, Codex, or another agent enough structure to work safely while keeping the human in control.

---

## Core Ideas

- **Spec first:** write down the intended behavior before tests or code.
- **Tests before implementation:** write tests from the spec and verify the important new tests fail before production code is added.
- **Deterministic checks before critique:** run the relevant tests, linters, type checks, or build commands before asking an agent to review.
- **Separate critic context:** use a focused reviewer agent for spec, test, and code review so the builder and reviewer do not share all the same assumptions.
- **Human gates:** the human decides whether a phase is accepted and whether to continue.

The spec is not a giant requirements document. For this harness, a spec is a short feature contract stored as `docs/specs/<task-slug>.md`. It defines the goal, non-goals, behavior, interfaces, edge cases, acceptance criteria, and test strategy for one task.

---

## Skills, Not Commands

The workflow is implemented as explicit skills instead of custom slash commands:

- `sdd-research`
- `sdd-plan`
- `sdd-build`
- `sdd-review`

Call the skills directly. Do not create custom `/plan` or `/review` commands, because both Claude Code and Codex already have host-level planning and review features. The SDD skills are the workflow-specific layer: they read `TASK.md`, identify the active phase and step, enforce the Spec-Tests-Code gates, and use the right critic.

Claude Code invocation:

```text
/sdd-research
/sdd-plan focus on API compatibility
/sdd-build
/sdd-review focus on backwards compatibility and timeout behavior
```

Codex invocation:

```text
$sdd-research
$sdd-plan focus on API compatibility
$sdd-build
$sdd-review focus on backwards compatibility and timeout behavior
```

---

## High-Risk RPBR Matrix

Each phase follows Research, Plan, Build, and Review. For high-risk work, use the full matrix. For medium-sized work, collapse steps where it is obvious and keep only the artifacts that reduce risk.

| Phase | `sdd-research` | `sdd-plan` | `sdd-build` | `sdd-review` |
| --- | --- | --- | --- | --- |
| **1. Spec** | Agent scans requirements, codebase, schemas, issues, and dependencies. | Agent proposes the feature contract and key design choices. | Agent writes `docs/specs/<task-slug>.md`. | `spec-critic` checks ambiguity, hidden dependencies, scope, and acceptance criteria. |
| **2. Tests** | Agent maps the approved spec to testable behavior. | Agent proposes test files, cases, fixtures, mocks, and commands. | Agent writes tests and verifies the important new tests fail for the right reason. | `test-critic` checks coverage, mock fidelity, boundaries, and missing assertions. |
| **3. Code** | Agent inspects implementation targets, style, imports, and local patterns. | Agent proposes the file-change sequence needed to satisfy the tests. | Agent writes production code until verification is green. | `code-critic` checks correctness, security, performance, maintainability, and final verification. |

---

## Repository Architecture

Keep the source tree flat. The installer expands these shared source files into the directory shape each harness expects.

```text
├── config/
│   ├── skills/
│   │   ├── sdd-research.md
│   │   ├── sdd-plan.md
│   │   ├── sdd-build.md
│   │   └── sdd-review.md
│   └── agents/
│       ├── spec-critic.md
│       ├── test-critic.md
│       └── code-critic.md
├── templates/
│   ├── TASK.md
│   ├── SPEC.md
│   └── PULL_REQUEST_TEMPLATE.md
└── install.sh
```

Source files stay provider-neutral:

- `config/skills/*.md` are complete `SKILL.md` files stored flat for easier editing.
- `config/agents/*.md` are shared critic prompt bodies.
- `install.sh` copies each skill to the required `SKILL.md` path for Claude and Codex.
- `install.sh` wraps each shared critic prompt as a Claude Markdown subagent and as a Codex TOML custom agent.

Install targets:

| Harness | Skills | Agents |
| --- | --- | --- |
| Claude Code | `~/.claude/skills/<skill-name>/SKILL.md` | `~/.claude/agents/<agent-name>.md` |
| Codex | `$HOME/.agents/skills/<skill-name>/SKILL.md` | `~/.codex/agents/<agent-name>.toml` |

Codex also supports repo-scoped skills under `.agents/skills/` and project-scoped agents under `.codex/agents/`. This harness installs user-scoped files by default because it is a personal development tool.

Do not add hooks, MCP servers, plugins, or extra automation until repeated manual use proves they are needed.

---

## 1. Workflow Skills (`config/skills/`)

`.sdd/TASK-<branch>.md` is the workflow state file for the current branch or task (falls back to `.sdd/TASK.md` when not in a git repo). Add `.sdd/` to `.gitignore` — it is scaffolding, not a committed artifact. Each skill determines the path from the current git branch, then reads the file from top to bottom and identifies:

1. The **active phase**: Spec, Tests, or Code.
2. The **active step** inside that phase: Research, Plan, Build, or Review.

The human owns phase progression. The agent may mark a step complete after it produces the requested output, but review gates should only be marked complete after human approval. If the human rejects a result, rerun the step or uncheck it in `TASK.md`.

### `sdd-research.md`

```text
task_file = resolve_task_path()
  // git rev-parse --abbrev-ref HEAD → sanitize → ".sdd/TASK-<branch>.md"
  // not a git repo or detached HEAD  → ".sdd/TASK.md"

if task_file missing:
    create .sdd/, write task_file from built-in template
    tell human: "fill in Context section, then re-run /sdd-research"
    stop

read task_file
phase = first phase with unchecked Research step
assert Research[phase] is unchecked (or human re-runs explicitly)
announce "Active phase: {phase}. Running Research."

research:
    Spec  → read linked issue; find affected files/APIs/schemas/deps; note risks and open questions
    Tests → read approved spec; classify each criterion (existing/new/untestable);
            find fixtures/mocks; confirm test command and what failure looks like
    Code  → read failing tests; identify impl targets; study local patterns and reusable utils;
            map verification loop (test → lint → typecheck → build)

output: Detected state | Key findings | Constraints | Open questions | Next step

ask human to confirm → if yes, check [x] Research in task_file
```

### `sdd-plan.md`

```text
task_file = resolve_task_path()
if task_file missing → "run /sdd-research first"; stop

phase = active phase from task_file
assert Research[phase] is checked (or human explicitly waives)
focus = any text passed after /sdd-plan
announce "Active phase: {phase}. Running Plan."

plan:
    Spec  → behavior, non-goals, interfaces+types, compatibility,
            acceptance criteria (numbered, testable), edge cases, test strategy
    Tests → test files and purpose, cases per criterion (name/input/expected/criterion),
            fixtures and mocks, exact test command, expected failure shape
    Code  → file-change sequence, per-file intent at function level,
            risks, verification loop order

present plan to human
if approved → check [x] Plan in task_file
```

### `sdd-build.md`

```text
task_file = resolve_task_path()
if task_file missing → "run /sdd-research first"; stop

phase = active phase from task_file
assert Plan[phase] is checked
announce "Active phase: {phase}. Running Build."

build:
    Spec  → derive slug from task title; write docs/specs/<slug>.md (embedded structure);
            all sections required; read back to confirm coherence
    Tests → write test files; run test command scoped to new files;
            new tests MUST FAIL for behavioral reason (not infra);
            premature pass → investigate; wrong failure → fix setup, re-run
    Code  → follow impl sequence; run tests after each meaningful change;
            when all new tests pass → run full loop: test → lint → typecheck → build;
            fix every failure before declaring done

report: files created/modified | verification output | plan deviations
check [x] Build only after artifact exists and verification has run
```

### `sdd-review.md`

```text
task_file = resolve_task_path()
if task_file missing → "run /sdd-research first"; stop

phase = active phase from task_file
assert Build[phase] is checked
focus = text after /sdd-review (may be empty)
announce "Active phase: {phase}. Running Review. Focus: {focus | 'none'}."

step 1 — deterministic checks (run first; do not invoke critic if these fail):
    Spec  → spec file exists, non-empty, all required sections present,
            Acceptance Criteria is a numbered list with ≥1 item
    Tests → run test command on new files; new tests must FAIL for behavioral reason;
            premature pass or wrong-failure-reason → stop and report
    Code  → run Test, Lint, Typecheck, Build in order;
            any failure → stop and report command + output

step 2 — critic invocation (only if step 1 passes):
    Spec  → spec-critic(task context + focus + spec file)
    Tests → test-critic(spec + focus + new/changed test files)
    Code  → code-critic(spec + tests + focus + impl files + verification output)

step 3 — present:
    deterministic check results | critic report verbatim | readiness assessment

check [x] Review only after human explicitly approves
if human requests fixes → uncheck Build and Review before next cycle
```

---

## 2. Shared Critic Prompts (`config/agents/`)

The critic prompts are shared source files. The installer adds the provider-specific wrapper metadata needed by Claude Code and Codex.

### `spec-critic.md`

```text
inputs: original request, Review Focus, spec file

review:
    ambiguity    → inputs/outputs/states/errors/permissions underspecified?
                   two valid implementations possible from the same spec?
    acceptance   → each criterion testable without reading source?
                   bounded, observable, numbered?
    scope        → behavior outside stated goal? implied behaviors absent from non-goals?
    dependencies → hidden schema/API/migration/rollout/env assumptions?
    Review Focus → targeted attention on stated areas

output:
    [PASS] or [FAIL]
    blocking findings    → [finding]: [evidence] → [why this breaks tests or impl]
    non-blocking findings
    open questions

FAIL if any blocking finding; PASS only if builder can start tests with no ambiguity
```

### `test-critic.md`

```text
inputs: approved spec, Review Focus, test files

review:
    criterion coverage → each acceptance criterion has a covering test?
                         trivial cases that don't actually validate the criterion flagged?
    failure quality    → important new tests currently FAIL for behavioral reason?
                         premature pass or wrong-reason failure → blocking
    boundary coverage  → edge cases and failure modes from spec have tests?
    mock fidelity      → mocks match real behavior? not overfit? not too loose?
    Review Focus       → targeted attention on stated areas

output:
    [PASS] or [FAIL]
    blocking findings    → [criterion]: [coverage gap] → [risk if unaddressed]
    non-blocking findings
    missing tests (beyond blocking)
    open questions

FAIL if a defective implementation could pass these tests
```

### `code-critic.md`

```text
inputs: approved spec, test files, Review Focus, impl files, verification output

review:
    correctness     → impl matches spec? conditions ordered right? return shapes correct?
                      silent truncation/coercion? edge cases tests didn't exercise?
    security        → unsanitized input in queries/commands/paths/HTML?
                      missing authz? secrets in logs? injection vectors? race conditions?
    reliability     → queries in loops? unbounded growth? missing timeouts?
                      resource leaks? retry without backoff or caps?
    maintainability → names match spec vocabulary? blast radius bounded?
                      duplicated logic? over/under abstraction?
    verification    → test command covered expected scope?
                      lint/typecheck suppressed rather than fixed?

output:
    [PASS] or [FAIL]
    blocking findings    → [finding]: [file:line or command] → [risk]
    non-blocking findings
    verification summary: Tests | Lint | Typecheck/Build
    open questions

FAIL if correctness, security, or reliability risk present; PASS only if ready to merge
```

---

## 3. Workflow State Templates (`templates/`)

### `TASK.md`

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
- Spec: `docs/specs/<task-slug>.md`
- Test evidence:
- Final verification evidence:

## 1. Spec Phase
- [ ] Research: Analyze requirements, codebase constraints, dependencies, and risks
- [ ] Plan: Define behavior, boundaries, interfaces, and acceptance criteria
- [ ] Build: Create or update the spec in `docs/specs/`
- [ ] Review: Critic review plus human sign-off

## 2. Tests Phase
- [ ] Research: Map spec acceptance criteria to testable behavior
- [ ] Plan: Determine test layout, cases, fixtures, mocks, and commands
- [ ] Build: Write tests and verify important new tests fail for the expected reason
- [ ] Review: Critic review plus human sign-off

## 3. Code Phase
- [ ] Research: Inspect active system patterns, import styles, utilities, and risks
- [ ] Plan: Sequence the code edits needed to satisfy the failing tests
- [ ] Build: Write production code until agreed verification is green
- [ ] Review: Critic review plus final human approval

## Approval Notes
- Spec approved by:
- Tests approved by:
- Code approved by:
```

### `SPEC.md`

Store each completed spec as `docs/specs/<task-slug>.md`.

```markdown
# Spec: [Feature Name]

## Goal

## Non-Goals

## Current Behavior

## Proposed Behavior

## Interfaces and Data

## Edge Cases and Failure Modes

## Acceptance Criteria

## Test Strategy

## Compatibility, Rollout, and Risks
```

### `PULL_REQUEST_TEMPLATE.md`

```markdown
## Summary

## Spec
- Spec: `docs/specs/<task-slug>.md`
- Task checklist: `TASK.md`

## Verification
- [ ] New tests were verified failing before implementation.
- [ ] Final tests pass.
- [ ] Lint passes or exceptions are documented.
- [ ] Typecheck/build passes or exceptions are documented.

## Commands Run

## Review Focus

## Critic Feedback Summary

## Known Risks or Follow-Ups
```

---

## 4. Simple Installation Script (`install.sh`)

The installer should remain simple: expand flat source files into the user-scoped configuration directories required by each harness. It is acceptable for this dev tool to overwrite prior harness files. It should not manage hooks, MCP servers, plugins, backups, uninstall, or project-specific settings.

```bash
#!/bin/sh
set -e

CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
CLAUDE_AGENTS_DIR="$HOME/.claude/agents"
CODEX_SKILLS_DIR="$HOME/.agents/skills"
CODEX_AGENTS_DIR="$HOME/.codex/agents"

echo "=========================================="
echo "Installing Agent SDD Harness"
echo "=========================================="

mkdir -p "$CLAUDE_SKILLS_DIR" "$CLAUDE_AGENTS_DIR"
mkdir -p "$CODEX_SKILLS_DIR" "$CODEX_AGENTS_DIR"

for skill_file in config/skills/*.md; do
    [ -f "$skill_file" ] || continue
    skill_name=$(basename "$skill_file" .md)

    mkdir -p "$CLAUDE_SKILLS_DIR/$skill_name"
    mkdir -p "$CODEX_SKILLS_DIR/$skill_name"

    cp "$skill_file" "$CLAUDE_SKILLS_DIR/$skill_name/SKILL.md"
    cp "$skill_file" "$CODEX_SKILLS_DIR/$skill_name/SKILL.md"

    echo "Installed skill: $skill_name"
done

agent_description() {
    case "$1" in
        spec-critic)
            printf '%s\n' "Reviews specs for ambiguity, hidden dependencies, scope control, and acceptance criteria."
            ;;
        test-critic)
            printf '%s\n' "Reviews tests for coverage, failure quality, mock fidelity, and missing assertions."
            ;;
        code-critic)
            printf '%s\n' "Reviews implementation for correctness, security, performance, maintainability, and verification gaps."
            ;;
        *)
            printf '%s\n' "Evidence-based SDD critic."
            ;;
    esac
}

for agent_file in config/agents/*.md; do
    [ -f "$agent_file" ] || continue
    agent_name=$(basename "$agent_file" .md)
    description=$(agent_description "$agent_name")

    {
        printf '%s\n' "---"
        printf 'name: %s\n' "$agent_name"
        printf 'description: %s\n' "$description"
        printf '%s\n' "tools: Read, Grep, Glob, Bash"
        printf '%s\n\n' "---"
        cat "$agent_file"
    } > "$CLAUDE_AGENTS_DIR/$agent_name.md"

    {
        printf 'name = "%s"\n' "$agent_name"
        printf 'description = "%s"\n' "$description"
        printf '%s\n' 'sandbox_mode = "read-only"'
        printf "%s\n" "developer_instructions = '''"
        cat "$agent_file"
        printf "\n%s\n" "'''"
    } > "$CODEX_AGENTS_DIR/$agent_name.toml"

    echo "Installed critic agent: $agent_name"
done

echo "Installed Claude skills to: $CLAUDE_SKILLS_DIR"
echo "Installed Claude agents to: $CLAUDE_AGENTS_DIR"
echo "Installed Codex skills to: $CODEX_SKILLS_DIR"
echo "Installed Codex agents to: $CODEX_AGENTS_DIR"
echo "Copy templates/TASK.md into a workspace when starting a high-risk branch."
echo "Copy templates/SPEC.md to docs/specs/<task-slug>.md during the Spec phase."
echo "=========================================="
```

Run it from the repository root:

```bash
chmod +x install.sh && ./install.sh
```

---

## 5. Manual Usage

Start a high-risk task by running `/sdd-research` in the target workspace. It will create `.sdd/TASK-<branch>.md` from the built-in template and prompt you to fill in the Context and Verification Commands sections before proceeding. Add `.sdd/` to `.gitignore` so the workflow state file is not committed.

Claude Code:

```text
/sdd-research
/sdd-plan focus on API compatibility
/sdd-build
/sdd-review focus on backwards compatibility and timeout behavior
```

Codex:

```text
$sdd-research
$sdd-plan focus on API compatibility
$sdd-build
$sdd-review focus on backwards compatibility and timeout behavior
```

The workflow is intentionally manual at the gates. The agent can produce research, plans, specs, tests, code, and critic reports, but the human decides whether each phase is accepted.
