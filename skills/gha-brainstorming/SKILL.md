---
name: gha-brainstorming
description: This skill should be used when the user asks to "create a workflow", "add CI to this repo", "set up a deploy pipeline", "add a GitHub Action for X", or wants to significantly modify an existing workflow's behavior. Guides workflow creation/modification through clarifying questions, best-practice research, a short approved design, then dispatches gha-creator to build and verify it. Self-contained — requires no other plugins.
---

# gha Brainstorming

Guide the user from "I want a workflow that does X" to a verified,
running workflow. Follow the steps in order; the two **GATE** steps are
hard stops that require the user's explicit go-ahead.

Small tweaks (bump a version, fix one step) don't need this ceremony —
edit directly and run the `gha-lint`/`gha-security-audit` skills. This
flow is for new workflows or behavior-changing modifications.

## The flow

1. **Explore context.** Existing workflows (Glob `.github/workflows/*`),
   project language/tooling (manifests, lockfiles), CI conventions
   already in use. Don't ask the user things the repo already answers.
2. **Clarify, one question at a time:** trigger events; what makes the
   workflow pass vs fail; secrets/environments needed; runner choice
   (default `ubuntu-latest` unless there's a reason). Prefer multiple
   choice (AskUserQuestion). Stop when you could write the workflow
   without guessing.
3. **Research current best practice** for the specific actions involved
   (WebSearch/web fetch): current major versions, known deprecations.
   Don't trust memorized versions — they rot.
4. **Propose 2-3 approaches** with trade-offs and a recommendation
   (e.g. matrix vs single job; marketplace action vs plain `run:` steps).
5. **Present a short inline design summary** — trigger, jobs, key
   decisions — in chat (not a committed spec file). Get approval.
6. **Write the inline plan** (this flow's own format, in chat):

   ```
   Workflow: .github/workflows/<name>.yml (create | modify)
   Trigger:  <events + filters>
   Jobs:
     - <job>: <runner> — <key steps, one line each>
   Secrets/permissions: <what and why, or "none">
   Verification: lint → security-audit → local run → first real run
   ```

   Get approval on the plan. (Self-contained on purpose: this flow never
   invokes another plugin's planning skills.)
7. **Dispatch the `gha-creator` agent** with the approved plan. It
   applies the `gha-dangerous-patterns` catalog while writing the YAML,
   then loops `gha-lint` → `gha-security-audit` → `gha-local-run` until
   clean, and reports back. Relay its report, including caveats.
8. **GATE: nothing leaves the machine without explicit confirmation.**
   Present the finished workflow and ask the user explicitly before ANY
   of: committing+pushing, opening a PR, or triggering a run. "The local
   loop is clean" is not consent to push.
9. **On confirmation:** push / open the PR as agreed, then trigger the
   first real run via the `gha-trigger` skill and watch it via
   `gha-monitor`. Report pass/fail; on failure, diagnose (gha-monitor's
   view mode) and loop back to gha-creator with the fix.
10. **GATE: never merge without being told.** When the run is green, stop
    and ask. Merging is always the user's explicit call — even if they
    said "handle everything" earlier.
