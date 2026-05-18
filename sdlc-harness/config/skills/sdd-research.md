---
name: sdd-research
description: Run the Research step for the active high-risk SDD phase in TASK.md. Use before planning in Spec, Tests, or Code phases. Also scaffolds TASK.md if starting a new task.
disable-model-invocation: true
---

Determine the task file path:
- Run `git rev-parse --show-toplevel 2>/dev/null` to get the repository root
- If the command succeeds, use that absolute path as the task root
- If the command fails (not a git repo), use the current working directory as the task root and state that no git repository root was detected
- Run `git rev-parse --abbrev-ref HEAD 2>/dev/null` to get the current branch name
- If the command fails (not a git repo) or returns "HEAD" (detached), the path is `<task-root>/.sdd/TASK.md`
- Otherwise, sanitize the branch name: strip any prefix up to and including the last `/` (e.g., `feature/my-task` → `my-task`), lowercase all characters, replace any character that is not a letter, digit, or `-` with `-`, collapse consecutive `-` into one, trim leading and trailing `-`; the path is `<task-root>/.sdd/TASK-<sanitized>.md`

Throughout these instructions, "TASK.md" refers to this derived path.

Check whether the task file exists.

If it does not exist:
- Create the `<task-root>/.sdd/` directory if needed
- Draft TASK.md from the template below, filling in as much as possible from the current chat context, branch name, visible repository files, and any linked request the human has provided
- Do not leave a field blank if a reasonable value can be inferred. Mark inferred values plainly, e.g. `Inferred from chat: ...`, when the source may be ambiguous
- For unknown required fields, write a concise placeholder question directly in the relevant field instead of leaving it empty, e.g. `Question: What should be explicitly out of scope?`
- Choose a task title and artifact slug from the most specific available context: the human's request first, then linked issue title, then branch name, then `task`
- Set verification commands to known project commands when they can be discovered quickly from repository metadata such as `package.json`, `pyproject.toml`, `Makefile`, `justfile`, `Cargo.toml`, `go.mod`, or existing CI config. Use `n/a` only when a command is genuinely inapplicable, and use `Question: ...` when the command likely exists but cannot be determined
- Write the drafted TASK.md immediately; then report "TASK.md created at <path>."
- After creating TASK.md, continue with a Q&A bootstrap instead of starting research immediately:
  - Summarize which fields were inferred
  - Ask the human only the missing or ambiguous questions needed to complete the Context section and any essential verification commands
  - Number the questions and keep them specific enough to answer inline
  - Tell the human that after they answer, you will update TASK.md with their answers and then continue the `/sdd-research` flow
- Do not proceed with research until the Context section has no unresolved `Question:` placeholders.

If Tests or Code phase work appears to be in progress (spec, test files, or implementation changes visible) but TASK.md is absent, stop and tell the human to run `/sdd-research` from the beginning or restore TASK.md from git history.

TASK.md content to write when the file is missing:

```
# Task: [Feature or Branch Title]

## Context
<!-- One paragraph: what is being built or changed, and why this qualifies as high-risk work -->
- Goal:
- Why this needs the high-risk SDD flow:
- Linked issue or source request:
- Non-goals:
- Review Focus: <!-- aspects the critic should pay special attention to, e.g. "backwards compatibility and timeout behavior" -->

## Verification Commands
<!-- Fill in before starting the Code phase. Use "n/a" for inapplicable commands. -->
- Test: <!-- e.g. pytest tests/unit/test_feature.py -v -->
- Lint: <!-- e.g. ruff check . -->
- Typecheck: <!-- e.g. mypy src/ -->
- Build: <!-- e.g. make build -->

## Artifacts
- Spec: `docs/specs/<task-slug>.md`
- Test evidence: <!-- filled in during Tests phase Build step -->
- Final verification evidence: <!-- filled in during Code phase Review step -->

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

Once TASK.md exists and the Context section is filled in, read it from top to bottom.

Identify the active phase (Spec, Tests, or Code) and confirm the Research step is unchecked. If Research is already checked, report that and ask the human whether to re-run it anyway.

State what you detected before proceeding: "Active phase: [X]. Running Research."

Perform read-only research appropriate to the active phase:

**Spec phase** — understand the problem space before any contract is written:
- Read the linked issue, user story, or raw request in full
- Identify existing behavior that will change: find relevant source files, APIs, schemas, config, and data models
- Trace downstream dependencies: what calls the thing being changed, what does it call
- Look for prior decisions or constraints in docs, comments, or git history
- List open questions that the spec will need to answer explicitly
- Note security, compatibility, or rollout concerns

**Tests phase** — map what the approved spec promises to what tests must prove:
- Read `docs/specs/<task-slug>.md` in full
- Identify every acceptance criterion and classify it as: covered by existing tests, needs a new test, or untestable (explain why)
- Find existing test files, fixtures, factories, and mocks relevant to the area being changed
- Determine the test command(s) to run and any setup needed
- Note what a meaningful test failure looks like for the most important new behaviors

**Code phase** — understand the implementation target before writing any code:
- Read the test files for the failing tests that need to pass
- Identify the implementation files that need to change
- Study local patterns: naming conventions, error handling, logging, imports, abstractions in use
- Look for existing utilities or helpers that should be reused
- Identify the verification loop: test command, lint command, typecheck/build command, in order

Output a structured research summary with these sections:
- **Detected state**: active phase and step
- **Key findings**: the most important things discovered
- **Constraints**: non-negotiable requirements or existing decisions that bound the solution
- **Open questions**: things the human or spec must resolve before planning can proceed
- **Recommended next step**: confirm Research is complete and suggest running `sdd-plan`

Ask the human to confirm before marking Research complete in TASK.md. Only check `- [x] Research` if the human approves.
