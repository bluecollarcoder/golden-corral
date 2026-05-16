---
name: sdd-plan
description: Create the Plan step for the active high-risk SDD phase in TASK.md. Produces a decision-complete proposal for the human to approve before building.
disable-model-invocation: true
---

Determine the task file path:
- Run `git rev-parse --abbrev-ref HEAD 2>/dev/null` to get the current branch name
- If the command fails (not a git repo) or returns "HEAD" (detached), the path is `.sdd/TASK.md`
- Otherwise, sanitize the branch name: strip any prefix up to and including the last `/` (e.g., `feature/my-task` → `my-task`), lowercase all characters, replace any character that is not a letter, digit, or `-` with `-`, collapse consecutive `-` into one, trim leading and trailing `-`; the path is `.sdd/TASK-<sanitized>.md`

Throughout these instructions, "TASK.md" refers to this derived path.

Read TASK.md. If it does not exist, stop and tell the human to run `/sdd-research` first — that skill creates TASK.md when starting a new task.

Identify the active phase and confirm the Plan step is unchecked. Verify Research for this phase is checked or the human has explicitly said to proceed without it.

State what you detected: "Active phase: [X]. Running Plan."

If any user text was passed after `/sdd-plan`, treat it as focus guidance and prioritize those areas in the plan.

Produce a decision-complete plan for the active phase. The plan must leave no important choices open for the builder — every ambiguity the builder might encounter must be resolved here.

**Spec phase plan** — the feature contract:
- Proposed behavior: precise description of what the system will do after this change
- Non-goals: explicitly what is out of scope
- Interfaces and data shapes: function signatures, API shapes, schema changes, event payloads — with types
- Compatibility: what existing callers, consumers, or data must continue to work unchanged
- Acceptance criteria: a numbered list of testable conditions that define done (each must be verifiable without reading source code)
- Edge cases and failure modes: the specific error conditions and expected system responses
- Test strategy: which behaviors need unit tests, integration tests, or manual verification

**Tests phase plan** — the test layout:
- List of test files to create or modify, with their purpose
- List of test cases per file: name, input, expected output or behavior, and which acceptance criterion it covers
- Fixtures, factories, or mocks required, and how to create or source them
- The exact test command(s) to run
- What "failing for the right reason" looks like for the most important new tests

**Code phase plan** — the implementation sequence:
- Files to create or modify, in the order they should be touched
- For each file: what changes and why, at the function or method level
- Known risks or subtle behaviors to handle
- The verification loop: test command → lint → typecheck/build, in order

Keep the plan as short as possible. Cut anything obvious from the code. Include everything the builder will need to make the right call without asking.

Present the plan to the human and ask for approval. Only check `- [x] Plan` in TASK.md after the human approves.
