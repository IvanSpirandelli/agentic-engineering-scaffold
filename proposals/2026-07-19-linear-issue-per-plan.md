# Linear issue per plan run (opt-in)

**Status:** proposed · 2026-07-19
**Scope:** machines-at-work only (Linear linking is branch/PR-side; the server-orchestrator is not involved).

## Want

For projects that track work in Linear: when a plan is approved, create **one Linear
issue** for that plan run and make every PR the run produces attach to it — so the phone
message "🧠 → read the plan → 🚀" leaves a traceable issue behind, without a human touching
Linear.

Opt-in per project. Projects without a Linear team are unchanged.

## The branch reality this has to fit

`task = commit, feature = PR` (DESIGN #25). Per-task `task/<id>-<slug>` branches are
**local plumbing**, squash-merged away and never pushed. The only branch Linear can ever
see is `feature/<slug>` — pushed when a feature's last task lands, becoming the PR. One plan
run can produce **several** feature branches.

So "use the issue's suggested branch name verbatim" doesn't fit: Linear gives one branch
name per issue, but a plan makes many feature branches — they'd collide. What *does* fit:
Linear auto-links any branch (and thus PR) whose name **contains** the issue key, case-
insensitively. The key rides inside the feature slug, which /plan already chooses.

## Design

1. **One issue per plan run** (user's chosen granularity). After the human approves the
   plan (🚀 in headless, or the terminal prompt), if the project opts in, /plan calls
   `linear.sh create` **once** with the plan's title and the task list as a checklist.
2. **Embed the key in every feature slug.** `linear.sh` returns the issue identifier
   (e.g. `ENG-123`); /plan lowercases it and prefixes every feature slug —
   `feature/eng-123-payment-flow`. Every PR from the run then auto-attaches to the one
   issue. **Zero change to `task.sh` branch mechanics** — the key is just part of the slug
   `cmd_new` already slugifies (`eng-123-…` survives the slugifier unchanged).
3. **Group everything into features** when Linear is on. A featureless one-off pushes its
   `task/<id>-<slug>` branch as its own PR — which would *not* carry the key. So the skill
   wraps even a single task in a feature (a feature of one) so the key reaches every PR.
   This only matters under `DONE=pr`; `DONE=local` never pushes a branch, so Linear linking
   is meaningless there and the skill skips it.

## Where each piece lives (mechanics vs. judgment)

- **`scripts/linear.sh` (mechanics, deterministic).** `linear.sh create "<title>" "<body>"`
  → resolves the team id from `LINEAR_TEAM_KEY`, runs the `issueCreate` GraphQL mutation,
  prints `<IDENTIFIER>\t<url>`. Needs `jq` and `curl`. Errors loudly (never a silent no-op)
  if creds or team are missing/wrong.
- **`skills/plan` (judgment).** Decides the issue title, writes the checklist, chooses the
  key-prefixed feature slugs. Gated on `LINEAR_TEAM_KEY` set **and** `DONE=pr`.

## Config (mirrors the telegram creds pattern)

- **`~/.agent-orchestrator/linear.env`** — `LINEAR_API_KEY=lin_api_…`, shared across
  projects, `chmod 600`, uncommitted (like `telegram.env`).
- **`agents.env`** — `LINEAR_TEAM_KEY=ENG` per project. Unset ⇒ feature off; nothing changes.

## Non-goals

- No status sync back from Linear (issue stays open; humans manage its lifecycle). The link
  is one-directional: plan → issue → PRs, matching the note→intent one-way dependency.
- No sub-issues per task, no comments on merge. One issue, many PRs, done.
- No change to `task.sh`. The whole feature lives in `linear.sh` + the plan skill.

## Verify

- `linear.sh` with `LINEAR_API_KEY`/`LINEAR_TEAM_KEY` unset → clear error, exit non-zero.
- `linear.sh create` with a stubbed `curl` (canned GraphQL responses) prints
  `ENG-123\t<url>`; an unknown team key errors.
- Smoke test covers both, alongside the existing suite.
