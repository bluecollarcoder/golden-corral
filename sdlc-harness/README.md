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
  reviews it. Claude drives Tests and Code; GPT is reached through the `codex` CLI.
- **Deterministic checks before critique:** run tests, linters, type checks, or builds
  before asking a model to review.
- **Start once, stop at the gates:** the full Claude skill drives the whole flow and pauses
  only at the 5 human approval gates. The shared spec skill stops after Gate 1.

A spec here is a short feature contract stored as `specs/<task-slug>.md` — goal,
non-goals, behavior, interfaces, edge cases, acceptance criteria, test strategy.

---

## Two Entrypoints, Five Gates

The full workflow is the Claude-only skill `sdd`. The spec-only workflow is the shared
skill `sdd-spec`, installed in both Claude and Codex. Both use the same `.sdd/TASK` state
and `specs/<task-slug>.md` artifact, so a spec started in Codex can hand off cleanly to
Claude for Tests and Code.

The critic is always the non-author model:

| Phase | Author | AI critic | Human gate |
|-------|--------|-----------|------------|
| Spec | Claude or Codex | — | **1. Spec approved** |
| Test plan | Claude | GPT (1 round) | **2. Test plan approved** |
| Test code | GPT | Claude (≤3 rounds) | **3. Test code approved** |
| Code plan | Claude | GPT (1 round) | **4. Code plan approved** |
| Logic code | GPT | Claude (≤3 rounds) | **5. Logic code approved** |

- **Claude → GPT** handoffs go through `config/lib/sdd-codex.sh` (a thin `codex exec`
  wrapper), so the human no longer relays messages between models.
- **Claude reviews GPT's code** with the `test-critic` and `code-critic` subagents.
- **GPT reviews Claude's plans** read-only, returning structured findings.
- **Codex spec mode** never plans or writes tests/code. After Gate 1 approval, resume in
  Claude Code with `/sdd`.

### Termination and cost control

- Reviews return **blocking** vs **non-blocking** findings. A review loop ends the moment a
  round returns **zero blocking findings**; otherwise it stops at its cap (1 round for
  plans, 3 for code) and escalates to the human. Only blocking findings trigger another
  author edit; non-blocking findings go to the human at the gate.
- Round 1 reviews the whole artifact; **rounds 2–3 are diff-scoped** (only the changes plus
  still-open findings). This stops the "different issues every round" churn and bounds cost.
- The Code phase will not pass its gate while the Tests-phase tests fail.

At gates 3 and 5, human feedback runs a bounded fix loop: GPT fixes → Claude reviews once →
back to the human, until approved.

---

## Repository Architecture

Source files stay flat and provider-neutral; the installer expands them into the locations
Claude Code and Codex expect.

```text
├── config/
│   ├── skills/
│   │   ├── sdd.md                 # Claude-only full orchestrator skill
│   │   └── sdd-spec.md            # shared Claude/Codex spec-only skill
│   ├── agents/
│   │   ├── test-critic.md         # shared critic prompt bodies
│   │   └── code-critic.md
│   └── lib/
│       ├── sdd-codex.sh           # codex exec wrapper (plan-review | build | fix)
│       └── findings.schema.json   # structured-findings schema for GPT reviews
├── templates/
│   └── PULL_REQUEST_TEMPLATE.md
└── install.sh
```

The TASK state template and the spec structure live inside `config/skills/sdd.md` and
`config/skills/sdd-spec.md` (the skills write them when scaffolding a task).

Install targets:

| Component | Destination |
| --- | --- |
| Full orchestrator skill | `~/.claude/skills/sdd/SKILL.md` |
| Spec-only skill | `~/.claude/skills/sdd-spec/SKILL.md` and `~/.codex/skills/sdd-spec/SKILL.md` |
| Critic subagents | `~/.claude/agents/<name>.md` |
| Wrapper + schema | `~/.claude/sdd/` |

`.sdd/TASK-<branch>.md` (or `.sdd/TASK.md` outside a git repo) is the per-task state file.
Add `.sdd/` to `.gitignore` — it is scaffolding, not a committed artifact. The two plan
records `.sdd/PLAN-tests-<branch>.md` and `.sdd/PLAN-code-<branch>.md` are written for
traceability, branch-scoped like the TASK file.

Do not add hooks, MCP servers, plugins, or extra automation until repeated manual use
proves they are needed.

---

## Critic Prompts (`config/agents/`)

Shared prompt bodies; `install.sh` adds the Claude subagent frontmatter.

- **`test-critic.md`** — criterion coverage, failure quality (tests must fail for the right
  reason before code exists), boundary coverage, mock fidelity.
- **`code-critic.md`** — correctness, security, reliability, maintainability, and whether
  the verification output supports the claimed readiness.

GPT's plan reviews use a plan-specific rubric supplied by the orchestrator (does the plan
cover every acceptance criterion, are cases concrete, is anything left ambiguous for the
builder) and return JSON matching `config/lib/findings.schema.json`.

---

## Installation

Requires the [`codex`](https://github.com/openai/codex) CLI on `PATH` and logged in
(`codex login status`). Then, from the repository root:

```bash
chmod +x install.sh && ./install.sh
```

It is acceptable for this personal dev tool to overwrite prior harness files. The installer
does not manage hooks, MCP servers, plugins, backups, or uninstall.

---

## Usage

For the full Claude workflow, run this in the target workspace:

```text
/sdd
```

On first run it scaffolds `.sdd/TASK-<branch>.md` and asks you to fill in Context and
Verification Commands, then proceeds. From there it runs to the next gate and stops for
your approval or feedback; re-running `/sdd` (even in a new session) resumes from where it
left off. You will be asked to approve exactly five times: the spec, the test plan, the
test code, the code plan, and the logic code.

For spec-only work in Claude or Codex, invoke the `sdd-spec` skill. It scaffolds or resumes
the same `.sdd/TASK-<branch>.md`, writes `specs/<task-slug>.md`, stops at Gate 1, and does
not start Tests or Code. After approving Gate 1, switch to Claude Code and run `/sdd` to
resume at the Tests phase.
