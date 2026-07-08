# Workspace: {{PROJECT_NAME}}

Scaffold workspace. Product spec: `scaffold/specs/` (living documents; versions live in this repo's git history). To change it: drop notes in `scaffold/specs/updates/` and run `/scaffold:plan` — it merges them in and plans the delta. Task state (single source of truth): `scaffold/tasks/` — status lives in each `task.md`; digest in `tasks/_log.md`. Config: `scaffold/agents.env`. Escalations: `scaffold/NEEDS_HUMAN.md`.

Pipeline: `/scaffold:plan` → `/scaffold:build` (or `scripts/loop.sh` headless). Mechanics (branching, merging, verification) are scripts under the scaffold plugin — never do them by hand.

Rules:
- Never commit to the default branch directly; `task.sh done` merges (or opens a PR when `DONE=pr`).
- Never mark work done with a red `verify.sh`.
- Repos: see `scaffold/agents.env`. Scaffold state is versioned by this root repo; code lives in the top-level repo directories (each its own git repo, ignored here).
