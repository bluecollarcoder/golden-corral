---
name: sdd-build
description: "Build the artifact for the active high-risk SDD phase in TASK.md: spec document, test files, or production code."
disable-model-invocation: true
---

Determine the task file path:
- Run `git rev-parse --abbrev-ref HEAD 2>/dev/null` to get the current branch name
- If the command fails (not a git repo) or returns "HEAD" (detached), the path is `.sdd/TASK.md`
- Otherwise, sanitize the branch name: strip any prefix up to and including the last `/` (e.g., `feature/my-task` → `my-task`), lowercase all characters, replace any character that is not a letter, digit, or `-` with `-`, collapse consecutive `-` into one, trim leading and trailing `-`; the path is `.sdd/TASK-<sanitized>.md`

Throughout these instructions, "TASK.md" refers to this derived path.

Read TASK.md. If it does not exist, stop and tell the human to run `/sdd-research` first.

Identify the active phase and confirm the Build step is unchecked. Verify Plan for this phase is checked or the human has explicitly said to proceed.

State what you detected: "Active phase: [X]. Running Build."

Build the active phase artifact:

**Spec phase** — write the feature contract:
- Determine the task slug from TASK.md (derive from the task title if not explicit: lowercase, hyphens, no special chars)
- Create or update `docs/specs/<task-slug>.md` using the structure below
- Every section must be filled in — no empty sections
- Acceptance criteria must be numbered and individually testable
- When the file is written, read it back and confirm it is coherent and complete

Spec file structure:

```
# Spec: [Feature Name]

## Goal
[One paragraph: what this change accomplishes and why. Close with a sentence that explicitly bounds the scope.]

## Non-Goals
[Explicit list of what this spec does NOT cover.]
-

## Current Behavior
[Describe what the system does today. Include the failure mode or gap that motivates this work.]

## Proposed Behavior
[Precise description of what the system will do after this change. Who calls what, in what order, what is returned or emitted. Present tense.]

## Interfaces and Data
[Function signatures, API endpoints, event schemas, database columns, config keys, or message formats that are introduced or changed. Include types.]

## Edge Cases and Failure Modes
[Specific conditions outside the happy path and the expected system response for each.]
- When [condition]: [expected behavior]

## Acceptance Criteria
[Numbered list. Each criterion must be independently testable without reading source code.]
1.
2.

## Test Strategy
[Which criteria need unit tests? Integration tests? Manual verification? Note behaviors that cannot be tested automatically and why.]

## Compatibility, Rollout, and Risks
[Schema migrations, API versioning, feature flags, deployment ordering, downstream impact, rollback plan, known unknowns.]
```

**Tests phase** — write failing tests:
- Create or modify the test files identified in the Plan
- Write tests that target the acceptance criteria from the spec
- After writing tests, run the test command from TASK.md scoped to the new test files
- Confirm that the important new tests fail, and that they fail for the expected behavioral reason — not syntax errors, import failures, or missing setup
- If a new test passes unexpectedly, stop and investigate before proceeding
- If a test fails for the wrong reason (infrastructure, setup), fix the setup and re-run

**Code phase** — write production code:
- Follow the implementation sequence from the Plan
- After each meaningful change, run the test command to see progress
- Do not move to the next file until the current change is verified or a clear dependency exists
- When all new tests pass, run the full verification loop from TASK.md: test → lint → typecheck/build
- If any step fails, fix it before reporting complete — do not skip or defer failures

Report:
- Files created or modified (full paths)
- Verification output: what was run and what it showed
- Any deviations from the Plan, with reasons

Mark Build complete (`- [x] Build`) only after the artifact exists and the required local verification has been run. If verification could not be run, document why and ask the human whether to proceed.
