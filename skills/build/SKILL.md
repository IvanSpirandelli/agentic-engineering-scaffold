---
name: build
description: Run the pipeline for one task (or the next todo one) — implement, verify, review, then squash-merge (DONE=local) or open a PR (DONE=pr).
disable-model-invocation: true
argument-hint: "[task-id | all]"
---

Target: $ARGUMENTS (empty or `all` → use `task.sh next`).
Scripts: `${CLAUDE_PLUGIN_ROOT}/scripts/`. You orchestrate; you do not write code yourself.

1. `preflight.sh --quick`; then `task.sh start <id>`.
2. Spawn the `implementer` agent: "Implement task <id>. Folder: scaffold/tasks/<id>-<slug>/". If UI-heavy and no design.md exists, run /scaffold:design first.
3. `RESULT: blocked` → `task.sh block <id> "<question>"`, report to user, stop this task.
4. Spawn the `reviewer` agent on the task — **always**, and always let it write a verdict to `review.md`, even on a resume where the branch is already complete and step 2 was a no-op. A branch that already looks finished still flows review → done; never stop at Status `in-progress`. Then:
   - `VERDICT: approve` → step 5.
   - `VERDICT: blocking` and Rounds < 2 → increment Rounds in task.md, send ONLY the blocking findings back to the implementer to fix, then review again.
   - still blocking at Rounds = 2 → `task.sh block <id> "review did not converge: <summary>"`, stop this task.
5. `task.sh done <id>` — verifies green, then per `DONE` in agents.env: `local` squash-merges one commit per repo; `pr` pushes the branch and opens a pre-reviewed PR (the task completes via `task.sh sync` once a human merges it). If it fails, treat the failure output as a blocking finding: one repair round, then block.
6. Report ≤5 lines to the user: task, verdict, commits or PR URL, cost if known, anything odd.
7. If the argument was `all`, repeat from step 1 until `task.sh next` reports no task — it halts (and says so) on a blocked task, which gates its successors, so stop and report when it does. `DONE=pr`: if the next task builds on work sitting in an unmerged PR, stop and say so — it would branch from a base without that work.

Never edit code yourself, never merge manually, never bypass a red verify.
