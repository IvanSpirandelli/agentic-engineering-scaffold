#!/usr/bin/env bash
# Task lifecycle. Deterministic — no LLM involved.
# Usage: task.sh new "<title>" [repos] | start <id> | next | status | done <id> | sync | block <id> "<reason>" | reopen <id>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() { grep '^# Usage' "$0" | cut -c3-; exit 1; }

snapshot_ws() { # commit workspace state (spec/task history for /retro)
  git -C "$WS" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local p
  for p in tasks specs NEEDS_HUMAN.md; do [ -e "$WS/$p" ] && git -C "$WS" add "$p"; done
  git -C "$WS" diff --cached --quiet || git -C "$WS" commit -qm "$1" \
    || echo "WARN: workspace snapshot commit failed" >&2
}

cmd_new() {
  local title="${1:?usage: task.sh new \"<title>\" [repos]}"
  local repos="${2:-$REPOS}"
  local last id slug dir spec
  last=$(ls "$TASKS" 2>/dev/null | grep -E '^[0-9]{4}-' | sort | tail -1 | cut -d- -f1 || true)
  id=$(printf '%04d' $((10#${last:-0} + 1)))
  slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g' | cut -c1-40)
  spec=$(git -C "$WS" log -1 --format=%h -- specs 2>/dev/null) || spec=""
  dir="$TASKS/$id-$slug"
  mkdir -p "$dir"
  cat > "$dir/task.md" <<EOF
# $id · $title

Status: todo
Repos: $repos
Branch: task/$id-$slug
Spec: ${spec:--}
Commits: -
PR: -
Rounds: 0
Cost: -

## Goal

## Acceptance criteria

- [ ]

## Non-goals

## Notes
EOF
  echo "$id"
}

cmd_start() {
  local id="${1:?task id}" dir md branch repo path status
  dir=$(task_dir "$id"); md="$dir/task.md"
  status=$(get_field "$md" Status)
  [ "$status" = "todo" ] || [ "$status" = "in-progress" ] \
    || { echo "ERROR: task $id is $status, not startable" >&2; exit 1; }
  branch=$(get_field "$md" Branch)
  for repo in $(get_field "$md" Repos); do
    path=$(repo_path "$repo")
    if git -C "$path" rev-parse -q --verify "$branch" >/dev/null; then
      git -C "$path" checkout -q "$branch"   # resume an interrupted task
    else
      git -C "$path" diff --quiet && git -C "$path" diff --cached --quiet \
        || { echo "ERROR: $repo has uncommitted changes" >&2; exit 1; }
      git -C "$path" checkout -q "$DEFAULT_BRANCH"
      git -C "$path" checkout -qb "$branch"
    fi
  done
  set_field "$md" Status in-progress
  echo "started $id on $branch"
}

cmd_next() {
  local d
  for d in "$TASKS"/[0-9]*/; do
    [ -f "$d/task.md" ] || continue
    [ "$(get_field "$d/task.md" Status)" = "todo" ] && { basename "$d" | cut -d- -f1; return 0; }
  done
  return 1
}

cmd_status() {
  local d md
  printf '%-6s %-12s %s\n' ID STATUS TITLE
  for d in "$TASKS"/[0-9]*/; do
    md="$d/task.md"; [ -f "$md" ] || continue
    printf '%-6s %-12s %s\n' "$(basename "$d" | cut -d- -f1)" "$(get_field "$md" Status)" "$(task_title "$md")"
  done
}

cmd_done() {
  local id="${1:?task id}" dir md branch title repo path shas sha url urls body
  dir=$(task_dir "$id"); md="$dir/task.md"
  [ "$(get_field "$md" Status)" = "in-progress" ] || { echo "ERROR: task $id is not in-progress" >&2; exit 1; }
  "$(dirname "${BASH_SOURCE[0]}")/verify.sh" || { echo "ERROR: verify failed — not merging" >&2; exit 1; }
  branch=$(get_field "$md" Branch); title=$(task_title "$md"); shas=""
  for repo in $(get_field "$md" Repos); do
    path=$(repo_path "$repo")
    git -C "$path" diff --quiet && git -C "$path" diff --cached --quiet \
      || { echo "ERROR: $repo has uncommitted changes on $branch" >&2; exit 1; }
  done
  if [ "$DONE" = "pr" ]; then
    # Push the branch and open a pre-reviewed PR; the platform merges (its
    # squash policy keeps one commit per feature). task.sh sync completes the
    # task once the PR is merged by a human.
    urls=""; body=$(mktemp)
    { awk '/^## Goal/,0' "$md"
      [ ! -f "$dir/review.md" ] || printf '\n## Agent review\n\n%s\n' "$(cat "$dir/review.md")"
      printf '\nTask-Id: %s\n' "$id"
    } > "$body"
    for repo in $(get_field "$md" Repos); do
      path=$(repo_path "$repo")
      if [ -n "$(git -C "$path" log --oneline "$DEFAULT_BRANCH..$branch" 2>/dev/null)" ]; then
        git -C "$path" push -qu origin "$branch"
        # reuse an existing PR (rerun after an interrupted session), else create
        url=$(cd "$path" && gh pr view "$branch" --json url --jq .url 2>/dev/null) \
          || url=$(cd "$path" && gh pr create --head "$branch" --base "$DEFAULT_BRANCH" --title "$title" --body-file "$body")
        urls="$urls $repo:$url"
        git -C "$path" checkout -q "$DEFAULT_BRANCH"
      else
        git -C "$path" checkout -q "$DEFAULT_BRANCH"
        git -C "$path" branch -qD "$branch"   # no changes in this repo
      fi
    done
    rm -f "$body"
    if [ -z "$urls" ]; then
      set_field "$md" Status done
      echo "- $id · $title · no changes" >> "$TASKS/_log.md"
      snapshot_ws "task $id done: $title"
      echo "done $id → no changes"
    else
      set_field "$md" Status pr
      set_field "$md" PR "${urls# }"
      snapshot_ws "task $id pr: $title"
      echo "pr $id →$urls"
    fi
    return
  fi
  for repo in $(get_field "$md" Repos); do
    path=$(repo_path "$repo")
    git -C "$path" checkout -q "$DEFAULT_BRANCH"
    if ! git -C "$path" merge --squash -q "$branch" >/dev/null; then
      git -C "$path" reset -q --hard "$DEFAULT_BRANCH"
      git -C "$path" checkout -q "$branch"
      echo "ERROR: squash-merge conflict in $repo — resolve on $branch, then rerun done" >&2
      exit 1
    fi
    if git -C "$path" diff --cached --quiet; then
      git -C "$path" reset -q --hard "$DEFAULT_BRANCH"   # no changes in this repo
    else
      git -C "$path" commit -qm "$title" -m "Task-Id: $id"
      sha=$(git -C "$path" rev-parse --short HEAD)
      shas="$shas $repo:$sha"
    fi
    git -C "$path" branch -qD "$branch"
  done
  set_field "$md" Status done
  set_field "$md" Commits "${shas# }"
  echo "- $id · $title ·${shas:- no changes}" >> "$TASKS/_log.md"
  snapshot_ws "task $id done: $title"
  echo "done $id →${shas:- no changes}"
}

cmd_sync() {
  # DONE=pr: reconcile pr-status tasks against GitHub. Merged → done (+digest,
  # local branch cleanup), closed unmerged → blocked, open → leave as-is.
  [ "$DONE" = "pr" ] || { echo "sync: nothing to do (DONE=$DONE)"; return 0; }
  local d md id title branch entry repo url out state sha shas open path
  for d in "$TASKS"/[0-9]*/; do
    md="$d/task.md"; [ -f "$md" ] || continue
    [ "$(get_field "$md" Status)" = "pr" ] || continue
    id=$(basename "$d" | cut -d- -f1); shas=""; open=""
    for entry in $(get_field "$md" PR); do
      repo="${entry%%:*}"; url="${entry#*:}"
      out=$(gh pr view "$url" --json state,mergeCommit --jq '.state + " " + (.mergeCommit.oid // "")') \
        || { echo "WARN: cannot check $url — skipping $id" >&2; open=1; break; }
      state="${out%% *}"; sha="${out#* }"
      case "$state" in
        MERGED) shas="$shas $repo:${sha:0:7}" ;;
        CLOSED) cmd_block "$id" "PR closed without merge: $url" >/dev/null; continue 2 ;;
        *)      open=1 ;;
      esac
    done
    [ -z "$open" ] || continue
    title=$(task_title "$md"); branch=$(get_field "$md" Branch)
    for repo in $(get_field "$md" Repos); do
      path=$(repo_path "$repo")
      git -C "$path" rev-parse -q --verify "$branch" >/dev/null || continue
      [ "$(git -C "$path" rev-parse --abbrev-ref HEAD)" != "$branch" ] || git -C "$path" checkout -q "$DEFAULT_BRANCH"
      git -C "$path" branch -qD "$branch"
    done
    set_field "$md" Status done
    set_field "$md" Commits "${shas# }"
    echo "- $id · $title ·$shas" >> "$TASKS/_log.md"
    snapshot_ws "task $id merged: $title"
    echo "synced $id → done (${shas# })"
  done
}

cmd_block() {
  local id="${1:?task id}" reason="${2:?reason}" dir md
  dir=$(task_dir "$id"); md="$dir/task.md"
  set_field "$md" Status blocked
  { echo "## $(basename "$dir")"; echo "$reason"; echo; } >> "$WS/NEEDS_HUMAN.md"
  "$(dirname "${BASH_SOURCE[0]}")/notify.sh" "Task $id blocked: $reason" || true
  echo "blocked $id"
}

cmd_reopen() {
  local id="${1:?task id}" dir md branch repo path
  dir=$(task_dir "$id"); md="$dir/task.md"
  branch=$(get_field "$md" Branch)
  for repo in $(get_field "$md" Repos); do
    path=$(repo_path "$repo")
    if git -C "$path" rev-parse -q --verify "$branch" >/dev/null; then
      set_field "$md" Status in-progress; echo "reopened $id (branch exists)"; return
    fi
  done
  set_field "$md" Status todo
  echo "reopened $id"
}

case "${1:-}" in
  new|start|next|status|done|sync|block|reopen) c="$1"; shift; "cmd_$c" "$@" ;;
  *) usage ;;
esac
