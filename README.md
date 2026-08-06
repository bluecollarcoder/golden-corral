# Spec-Driven Development (SDD)

A harness for long-running coding-agent sessions. It encodes spec-driven and test-driven
development in durable process artifacts, strictly separates orchestration, authoring, and
review responsibilities, and keeps humans in control through three approval gates.

SDD runs from Claude Code, the Codex CLI, or the Cursor CLI and can coordinate different
models. This brings independent perspectives, matches model and thinking effort to the task,
limits delegated file access and context to reduce hallucinations, and makes better use of
multiple coding-agent subscriptions.

Use it when the cost of ambiguity is high: major features, risky refactors, data
migrations, security-sensitive changes, public API changes, cross-system behavior, or
long-running agent work. For small bug fixes, copy edits, mechanical refactors, or obvious
one-file changes, use the normal loop: research, edit, verify, review.

---

## Core Ideas

- **Requirements become a technical specification:** the SDD orchestrator uses AI-assisted
  repository research to translate a ticket, PRD, or detailed human instructions into a
  concrete technical specification before planning begins.
- **Plan before coding:** the delegated author produces decision-complete plans from the
  approved specification, and the human approves those plans before any tests or production
  code are written.
- **Separate test and code plans:** the test plan defines the cases, expected failure reasons,
  seams, fixtures, and test commands; the code plan separately defines production changes,
  affected files, sequencing, and verification. Keeping both explicit makes their alignment
  reviewable without collapsing testing into implementation.
- **Tests before implementation:** write tests from the spec and verify the important new
  tests fail for the right reason before production code exists.
- **Agents check each other's work:** critic agents automatically review delegated plans,
  tests, and code, returning blockers to the author for bounded fix rounds. Human gates focus
  on output that has already gone through automated critique and correction.
- **Cross-model delegation and review are recommended:** match the model and thinking effort
  to the task, constrain each delegate's files and context, and use a different perspective
  to catch assumptions and blind spots while making productive use of multiple subscriptions.
- **Start once, stop at the gates:** the `sdd` skill drives the whole flow and pauses only
  at three human approval gates:

  1. Approve the specification.
  2. Approve the paired test and code plans.
  3. Approve the final tests and implementation.

---

## Workflow Summary

The workflow is the shared skill `sdd`, usable from Claude, Codex, or Cursor in this
harness setup. A new task starts from a Linear issue, PRD document, or sufficiently
detailed human instructions supplied with the skill invocation.

### Files created by the workflow

SDD creates two different kinds of files:

- **Repository technical asset — `specs/<module>/<task-slug>.md`:** the version-controlled
  feature contract containing the goal, non-goals, behavior, interfaces, edge cases,
  acceptance criteria, and test strategy. It belongs to the repository alongside its code
  and tests; it is not SDD workflow state.
- **Local workflow records — `.sdd/`:** resumable, uncommitted scaffolding maintained by
  the SDD orchestrator:

  - `TASK-<branch>.md` records the source, gathered context, verification commands,
    delegated-author choice, and phase checklist. Outside a git repository, its fallback
    name is `TASK.md`.
  - `PLAN-tests-<branch>.md` records the current complete delegated plan for test cases,
    failure reasons, fixtures, and verification.
  - `PLAN-code-<branch>.md` records the current complete delegated plan for production
    changes, affected files, sequencing, and verification.

Tests and production code are also repository technical assets changed during Build, not
SDD workflow records.

1. **Establish the source:** for a new task, read the supplied Linear issue or PRD document
   or detailed human instructions as the originating problem statement; on resume, use the
   source already recorded in TASK.
2. **Scaffold or resume:** resolve the repository and branch, create or read the branch-scoped
   TASK file, and continue from its first incomplete checkbox.
3. **Research the specification:** inspect the source document, affected code, contracts,
   dependencies, risks, existing patterns, and test seams; resolve material questions with
   the human.
4. **Write the specification:** the orchestrator writes the behavioral contract, acceptance
   criteria, architecture and testability decisions, and test strategy, then narrows
   unnecessary scope.
5. **Gate 1 — approve the spec:** the human approves the specification or gives feedback for
   another orchestrator revision.
6. **Research the build:** map acceptance criteria to failure modes, implementation targets,
   existing tests and fixtures, dependency seams, and repository verification commands.
7. **Create and review plans:** the delegated author returns paired test and code plans. The
   orchestrator persists them, runs the plan critics, and requests one correction when
   blocking findings remain.
8. **Gate 2 — approve the plans:** the human approves both plans or requests another planning
   pass.
9. **Build the tests:** the delegated author writes the planned tests without production
   changes. The orchestrator proves the important tests fail for the intended behavioral
   reason and runs `test-critic`; blocking findings enter a correction loop of at most three
   rounds.
10. **Build the logic:** after the tests have no blocking findings and fail correctly, the
   delegated author implements the code plan. The orchestrator runs the complete verification
   suite and `code-critic`, with another correction loop of at most three rounds.
11. **Gate 3 — approve the build:** the human reviews the tests, implementation, deterministic
   evidence, and remaining non-blocking findings. Feedback repeats the relevant correction and
   critic loop until approval completes the task.

The workflow assigns authors and critics as follows:

| Phase | Author | AI critic | Human gate |
|-------|--------|-----------|------------|
| Spec | SDD orchestrator | — | **1. Spec approved** |
| Build plans | delegated author | `test-plan-critic` + `code-plan-critic` (1 round each) | **2. Build plans approved** |
| Test code | delegated author | `test-critic` (≤3 rounds) | — |
| Logic code | delegated author | `code-critic` (≤3 rounds) | **3. Build approved** |

- Delegated author calls go through `config/lib/sdd-codex.sh` or
  `config/lib/sdd-cursor.sh`. Codex is the default; a human instruction switches the TASK
  to Cursor until changed again.
- The orchestrator reviews the delegated author's plans and code with installed
  `test-plan-critic`, `code-plan-critic`, `test-critic`, and `code-critic` agents.

### Termination and cost control

- Reviews return **blocking** vs **non-blocking** findings. A review loop ends the moment a
  round returns **zero blocking findings**; otherwise it stops at its cap (1 round for
  plans, 3 for code) and escalates to the human. Only blocking findings trigger another
  author edit; non-blocking findings go to the human at the gate.
- Round 1 reviews the whole artifact; **rounds 2–3 are diff-scoped** (only the changes plus
  still-open findings). This stops the "different issues every round" churn and bounds cost.
- Logic code does not start until the test code has zero blocking `test-critic` findings
  and the important new tests fail for the right reason.
- The final Build gate will not pass while the Build-phase tests or verification commands
  fail.

At the final Build gate, human feedback runs a bounded fix loop: delegated author fixes →
the relevant critic agent reviews once → back to the human, until approved.

---

## Installation

The default Codex delegated author requires version 0.138 or newer of the
[`codex`](https://github.com/openai/codex) CLI on `PATH` and logged in
(`codex login status`). Then, from the repository root:

```bash
chmod +x install.sh && ./install.sh
```

It is acceptable for this personal dev tool to overwrite prior harness files. The installer
does not manage hooks, MCP servers, plugins, backups, cleanup of deprecated files, or
general uninstall.

Selecting Cursor instead requires Linux, Bubblewrap (`bwrap`), and the Cursor CLI executable
`agent` on `PATH` and authenticated (`agent status`). Cursor delegation fails closed when
the process-scoped filesystem boundary cannot be established.

---

## Usage

Run this in the target workspace from Claude, Codex, or Cursor:

```text
/sdd <Linear issue or PRD doc>	# Claude Code and Cursor

$sdd <Linear issue or PRD doc>	# Codex
```

On first run it scaffolds `.sdd/TASK-<branch>.md`, asks only for missing Context or
Verification Commands, and continues immediately when those sections are complete. From
there it runs to the next gate and stops for your approval or feedback; re-running `/sdd`
(even in a new session) resumes from where it left off. You will be asked to approve exactly
three times: the spec, the paired build plans, and the final test + logic code.

Each TASK records its delegated author. New and older tasks default to Codex; instruct the
orchestrator to use Cursor to switch the current task, or to use Codex to switch it back.

---

## Repository Architecture

Source files stay flat and provider-neutral; the installer expands them into the locations
Claude Code and Codex expect.

```text
├── config/
│   ├── skills/
│   │   └── sdd.md                 # shared orchestrator skill
│   ├── agents/
│   │   ├── test-plan-critic.md    # test plan critic prompt body
│   │   ├── code-plan-critic.md    # code plan critic prompt body
│   │   ├── test-critic.md         # shared critic prompt bodies
│   │   └── code-critic.md
│   └── lib/
│       ├── sdd-codex.sh           # Codex wrapper for delegated authoring
│       └── sdd-cursor.sh          # Cursor wrapper for delegated authoring
├── templates/
│   └── PULL_REQUEST_TEMPLATE.md
└── install.sh
```

The TASK state template and the spec structure live inside `config/skills/sdd.md`; the
skill writes them when scaffolding a task.

Install targets:

| Component | Destination |
| --- | --- |
| Orchestrator skill | `~/.claude/skills/sdd/SKILL.md` and `~/.codex/skills/sdd/SKILL.md` |
| Claude critic agents | `~/.claude/agents/<name>.md` |
| Codex critic agents | `~/.codex/agents/<name>.toml` |
| Wrappers | `~/.claude/sdd/` and `~/.codex/sdd/` |

`.sdd/TASK-<branch>.md` (or `.sdd/TASK.md` outside a git repo) is the per-task state file.
Add `.sdd/` to `.gitignore` — it contains local workflow state, not repository technical
assets. The orchestrator writes the two plan records `.sdd/PLAN-tests-<branch>.md` and
`.sdd/PLAN-code-<branch>.md` from validated delegated responses for traceability.

Do not add hooks, MCP servers, plugins, or extra automation until repeated manual use
proves they are needed.

---

## Critic Prompts (`config/agents/`)

Shared prompt bodies; `install.sh` adapts them into Claude subagent Markdown and Codex
custom agent TOML.

- **`test-plan-critic.md`** — coverage, failure quality, seams, fixture/mock economy, and
  alignment with the paired code plan.
- **`code-plan-critic.md`** — implementation architecture, blast radius, verification, and
  alignment with the paired test plan.
- **`test-critic.md`** — criterion coverage, failure quality (tests must fail for the right
  reason before code exists), boundary coverage, mock fidelity.
- **`code-critic.md`** — correctness, security, reliability, maintainability, and whether
  the verification output supports the claimed readiness.

---

## Delegation

The Codex and Cursor wrappers share one interface for plan creation, implementation, and
corrections: `<prompt-file> [out-msg]`. Omit the output path to stream the delegated author's
final message. The orchestrator launches each wrapper through the current CLI's native
background or asynchronous mechanism and waits for it to complete before continuing.

### Shared context boundary

Every delegated call starts fresh. The orchestrator includes the complete approved spec and,
after planning, both complete plans inline in every implementation or correction prompt.
Repository source and test files remain available by path. PLAN and TASK files are never
loaded from `.sdd` by a delegate.

For plan creation or correction, the delegated author returns complete test and code plans in
two delimited response sections. The orchestrator validates those sections and writes the
branch-scoped PLAN files. For implementation, the delegate edits repository tests or
production code directly; only the orchestrator updates `.sdd` state.

### Codex

Invoke the installed Codex wrapper with:

```bash
~/.codex/sdd/sdd-codex.sh .sdd/_author-prompt.md .sdd/_author-msg.md
```

Set `SDD_CODEX_MODEL` to request a specific model; when unset, Codex chooses its configured
default. Each call is ephemeral and uses a permission profile that denies delegated reads and
writes to the complete `.sdd` subtree. The wrapper opens the prompt and response files before
launching the delegated process. It intentionally does not pass `--sandbox`, because legacy
sandbox settings take precedence over permission profiles. A loaded Codex configuration that
sets `sandbox_mode` or `[sandbox_workspace_write]` is therefore incompatible with this
boundary and should be migrated to permission profiles.

### Cursor

The orchestrator calls Cursor's default Agent mode through the installed wrapper. The
prompt file may be absolute or relative to the caller; Cursor always uses the current Git
repository root as its workspace:

```bash
~/.codex/sdd/sdd-cursor.sh .sdd/_author-prompt.md .sdd/_author-msg.md
```

Set `SDD_CURSOR_MODEL` to request a specific model; when unset, Cursor chooses its default.
The wrapper uses Bubblewrap to give only the delegated process an empty, read-only `.sdd`, while
interactive Cursor and other agents retain normal access to the real directory. Cursor's
own sandbox and unattended approval remain enabled inside that boundary. The wrapper refuses
tracked or symlinked TASK state and supports only Cursor's default editing Agent mode, not
`plan` or `ask` modes.
