---
description: Guided creation or modification of a GitHub Actions workflow (design → verify → run)
argument-hint: "[what the workflow should do]"
allowed-tools: Bash, Read, Glob, Grep, WebSearch, WebFetch, Task, AskUserQuestion
---

Use the gha-brainstorming skill to guide workflow creation or
modification, starting from $ARGUMENTS if the user provided a
description.

Follow the skill's flow exactly, including both GATE steps: explicit
user confirmation before anything is pushed/PR'd/triggered, and again
before any merge. The gha-creator agent does the writing and
verification; this conversation owns the questions, approvals, and
gates.
