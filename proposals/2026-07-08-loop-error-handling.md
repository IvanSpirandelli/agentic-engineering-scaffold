# Retro 2026-07-08 · loop.sh error handling & dependency safety

Status: **implemented** (loop.sh, task.sh, skills/build, tests/smoke.sh, 0.6.0). Part 3 deferred.

## Evidence
Headless run of the 0035–0041 batch (`MAX_TASKS=7`):
- **0036** (too heavy for one session) committed nothing across 3 resume attempts → blocked,
  leaving the frontend repo stranded on `task/0036-…`.
- **0037** then failed iterations 2–7 with only `WARN: claude exited nonzero on 0037` and no
  detail. Root: frontend not on `main` → `preflight.sh --quick` fails → `/build 0037` errors
  before any work; because 0036 was `blocked` (not `todo`), `task.sh next` kept returning 0037
  → 6 wasted iterations, nothing captured to explain why.

Three weaknesses: (1) opaque failure output; (2) the loop marches into dependents after a block;
(3) a no-work crash is retried and looks like the task's fault.

## Implemented design (evolved from the original diff in discussion)

1. **Blocked-gate lives in `task.sh next`, not loop.sh.** Deterministic and driver-agnostic —
   it holds for the headless loop *and* interactive `/build`. `next` scans in id order; a blocked
   task returns **exit 3** (stderr note), running only todos *before* it. `CONTINUE_ON_BLOCK=1`
   skips past it for independent task sets. loop.sh reads the exit code to report
   "blocked gates queue" vs "no tasks"; build SKILL step 7 stops when next reports no task.

2. **Env/transient crash → retry, then hard-stop.** A nonzero `claude` exit with the task still
   `todo` (never started — no network, stranded tree, crash) is an environment condition, not the
   task's fault. Retry the *same* task up to `MAX_RETRIES` (10) with `RETRY_BACKOFF` (60s) between
   tries, **without** spending the task budget (`n`). A standing condition (10 straight fails)
   hard-stops with the captured reason and leaves the task `todo` for a clean re-run. Any real
   progress resets the streak. Distinct from `MAX_RESUME` (drives an *in-progress* task to finish).

3. **Capture "why it failed" once, surface both ways.** Full detail → `loop-fail.log` (claude JSON
   envelope + stdout + stderr). A one-line reason (last stderr line — where connection errors land
   — else the parsed envelope) is threaded into (a) the resume prompt, so the retry doesn't repeat
   the mistake, and (b) the `task.sh block` reason → `NEEDS_HUMAN.md` + notify, for the human. Both
   drivers surface it because both call `task.sh block`.

New smoke case: successor-gating (`next` halts exit 3 on a blocked predecessor; `CONTINUE_ON_BLOCK=1`
skips to the later todo). Documented as DESIGN decision #20.

## Deferred — Part 3: blocking should un-strand the repos
`task.sh block` still leaves the affected repos on the task branch. The `next` gate (Part 1) now
prevents the *cascade* into dependents, so this is no longer urgent, but a blocked repo still needs
manual restore before unrelated work. Fix in `task.sh block`: return each repo to `DEFAULT_BRANCH`
**without** deleting the branch (a human must inspect the WIP), parking any uncommitted changes
first. Needs its own smoke case. Not done here.

## Observed, no action (planning, not tooling)
0036 was too big for one implementer session — 0 commits across 3 resumes is a decomposition
signal. Split into: (a) painter core + palette + expressions on one shape; (b) the extra shape
geometries; (c) MoodBead/idle + retire PNGs. Product planning (`/plan`), not a loop.sh change.
