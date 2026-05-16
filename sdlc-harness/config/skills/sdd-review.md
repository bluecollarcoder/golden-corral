---
name: sdd-review
description: Run deterministic verification and phase-specific critic review for the active high-risk SDD phase in TASK.md. Human approval required to mark complete.
disable-model-invocation: true
---

Determine the task file path:
- Run `git rev-parse --abbrev-ref HEAD 2>/dev/null` to get the current branch name
- If the command fails (not a git repo) or returns "HEAD" (detached), the path is `.sdd/TASK.md`
- Otherwise, sanitize the branch name: strip any prefix up to and including the last `/` (e.g., `feature/my-task` → `my-task`), lowercase all characters, replace any character that is not a letter, digit, or `-` with `-`, collapse consecutive `-` into one, trim leading and trailing `-`; the path is `.sdd/TASK-<sanitized>.md`

Throughout these instructions, "TASK.md" refers to this derived path.

Read TASK.md. If it does not exist, stop and tell the human to run `/sdd-research` first — that skill creates TASK.md when starting a new task.

Identify the active phase and confirm the Review step is unchecked. Verify Build for this phase is checked.

Treat any text passed after `/sdd-review` as the Review Focus. If no Review Focus was given, note that and proceed with the standard review.

State what you detected: "Active phase: [X]. Running Review. Review Focus: [Y or 'none provided']."

**Step 1: Deterministic checks (run before invoking any critic)**

Spec phase:
- Verify `docs/specs/<task-slug>.md` exists and is non-empty
- Confirm it contains all required sections: Goal, Non-Goals, Current Behavior, Proposed Behavior, Interfaces and Data, Edge Cases and Failure Modes, Acceptance Criteria, Test Strategy, Compatibility/Rollout/Risks
- Confirm Acceptance Criteria is a numbered list with at least one item
- If any check fails, stop and report — do not invoke the critic

Tests phase:
- Run the test command from TASK.md scoped to the new or changed test files
- Confirm that important new tests fail, and that they fail for the expected behavioral reason
- If tests pass when they should fail, stop and report — this is a blocking problem
- If tests fail for setup or infrastructure reasons rather than the expected behavioral reason, stop and report
- Do not invoke the critic until the failure behavior is confirmed correct

Code phase:
- Run each command in the Verification Commands section of TASK.md in order: Test, Lint, Typecheck, Build
- If any command fails, stop and report the exact command and its output — do not invoke the critic
- Only proceed to critic invocation after all commands pass

**Step 2: Critic invocation (only after deterministic checks pass)**

Invoke the appropriate critic agent with the inputs below. Provide them in full — do not summarize or filter.

Spec: invoke `spec-critic` with the original task context from TASK.md, the Review Focus, and the full contents of `docs/specs/<task-slug>.md`.

Tests: invoke `test-critic` with the full spec file, the Review Focus, and the full contents of all new or changed test files.

Code: invoke `code-critic` with the full spec file, the full test files, the Review Focus, all modified implementation files, and the full verification command output.

**Step 3: Present results**

Report:
- Deterministic check results (pass or fail, with evidence)
- Critic report verbatim: PASS/FAIL, blocking findings, non-blocking findings, open questions
- Your own assessment of whether the phase is ready for human approval

Mark Review complete (`- [x] Review`) only after the human explicitly approves the phase. If the human asks to fix something and re-review, uncheck Build and Review in TASK.md before the next build cycle.
