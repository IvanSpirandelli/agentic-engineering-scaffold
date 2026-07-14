---
name: plan
description: Decompose the spec (scaffold/specs/*.md) into small, verifiable tasks. Run after writing or changing the spec.
disable-model-invocation: true
argument-hint: "[section of spec to plan, default: all unplanned]"
---

Turn `scaffold/specs/` into tasks. Focus: $ARGUMENTS

1. Absorb updates: if `scaffold/specs/updates/` contains files, commit them as-written (the user's words stay in history), then integrate each into the living spec — add what's new, rewrite what it contradicts, delete what it retires; the spec must read as one current description, not a changelog. Delete the absorbed files, show the user the spec diff, commit on their approval.
2. If `scaffold/specs/` still has uncommitted changes, commit them — each new task records the spec commit it was planned from (`Spec:` in task.md).
3. Read all `scaffold/specs/*.md`, `scaffold/tasks/_log.md`, and `${CLAUDE_PLUGIN_ROOT}/scripts/task.sh status` output. Only plan what is specced and not yet covered by a task — nor already present in the code: in a pre-existing codebase, check the repos before tasking specced behavior.
4. Draft the task list. Each task MUST have:
   - a goal one implementer can finish and verify in a single green run,
   - testable acceptance criteria ("WHEN <condition> THE SYSTEM SHALL <behavior>"),
   - explicit non-goals ("don't touch X"),
   - the repos it spans (cross-repo only when the feature genuinely spans them).
   Too big to verify in one run → split it. Vague spec → ask the user now, not the implementer later.
   If `DONE=pr` in agents.env, also group the tasks into **features** — one feature = one coherent, reviewable PR. Tasks in a feature land as single commits on a shared `feature/<slug>` branch and the PR opens when its last task finishes, so dependencies *within* a feature are fine; avoid depending on a task in a different, still-unmerged feature. A one-off task may stay featureless (it gets its own PR).
5. Order by dependency, then present the list (with its feature grouping) to the user for approval. Decomposition quality is the leading indicator of pipeline success — spend your effort here.
6. On approval, for each task run `${CLAUDE_PLUGIN_ROOT}/scripts/task.sh new "<title>" ["<repos>"] ["<feature-slug>"]` and fill Goal / Acceptance criteria / Non-goals in the created task.md. Do not implement anything.
