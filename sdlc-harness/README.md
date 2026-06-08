# Spec-Driven Development (SDD)

A lightweight harness for using AI coding agents on major or high-risk software work. It
keeps the work anchored to explicit artifacts — a specification, failing tests, production
code, deterministic verification — and to a small number of human approval gates.

Use it when the cost of ambiguity is high: major features, risky refactors, data
migrations, security-sensitive changes, public API changes, cross-system behavior, or
long-running agent work. For small bug fixes, copy edits, mechanical refactors, or obvious
one-file changes, use the normal loop: research, edit, verify, review.

The goal is not to automate the whole SDLC. The goal is to give the agents enough structure
to work safely while keeping the human in control at a few decisive moments.

---

## Core Ideas

- **Spec first:** write down the intended behavior before tests or code.
- **Tests before implementation:** write tests from the spec and verify the important new
  tests fail for the right reason before production code exists.
- **Cross-model review:** the model that authors an artifact is never the model that
  reviews it. The host orchestrator reviews through local critic agents; GPT authors
  plans, tests, and code through the `codex` CLI.
- **Deterministic checks before critique:** run tests, linters, type checks, or builds
  before asking a model to review.
- **Start once, stop at the gates:** the `sdd` skill drives the whole flow and pauses only
  at the 3 human approval gates.

A spec here is a short feature contract stored as
`<repo-root>/specs/<module>/<task-slug>.md` — goal, non-goals, behavior, interfaces, edge
cases, acceptance criteria, test strategy.

---

## One Entrypoint, Three Gates

The workflow is the shared skill `sdd`, usable from Claude, Codex, or Cursor in this
harness setup. It stores resumable state in `.sdd/TASK` and writes the approved spec to
`specs/<module>/<task-slug>.md`.

The critic is always the non-author model:

| Phase | Author | AI critic | Human gate |
|-------|--------|-----------|------------|
| Spec | host orchestrator | — | **1. Spec approved** |
| Build plans | GPT | host `test-plan-critic` + `code-plan-critic` (1 round each) | **2. Build plans approved** |
| Test code | GPT | host `test-critic` (≤3 rounds) | — |
| Logic code | GPT | host `code-critic` (≤3 rounds) | **3. Build approved** |

- **Host → GPT** handoffs go through `config/lib/sdd-codex.sh` (a thin `codex exec`
  wrapper), so the human no longer relays messages between models.
- The host reviews GPT's plans and code with bootstrapped `test-plan-critic`,
  `code-plan-critic`, `test-critic`, and `code-critic` agents.
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

At the final Build gate, human feedback runs a bounded fix loop: GPT fixes → the relevant
host critic reviews once → back to the human, until approved.

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
│       ├── sdd-codex.sh           # codex exec wrapper (build | fix; plan-review remains available)
│       └── findings.schema.json   # schema for the optional plan-review wrapper mode
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
| Wrapper + schema | `~/.claude/sdd/` and `~/.codex/sdd/` |

`.sdd/TASK-<branch>.md` (or `.sdd/TASK.md` outside a git repo) is the per-task state file.
Add `.sdd/` to `.gitignore` — it is scaffolding, not a committed artifact. The two plan
records `.sdd/PLAN-tests-<branch>.md` and `.sdd/PLAN-code-<branch>.md` are written for
traceability, branch-scoped like the TASK file.

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

## Installation

Requires the [`codex`](https://github.com/openai/codex) CLI on `PATH` and logged in
(`codex login status`). Then, from the repository root:

```bash
chmod +x install.sh && ./install.sh
```

It is acceptable for this personal dev tool to overwrite prior harness files. The installer
does not manage hooks, MCP servers, plugins, backups, cleanup of deprecated files, or
general uninstall.

---

## Usage

Run this in the target workspace from Claude, Codex, or Cursor:

```text
/sdd
```

On first run it scaffolds `.sdd/TASK-<branch>.md` and asks you to fill in Context and
Verification Commands, then proceeds. From there it runs to the next gate and stops for
your approval or feedback; re-running `/sdd` (even in a new session) resumes from where it
left off. You will be asked to approve exactly three times: the spec, the paired build
plans, and the final test + logic code.
