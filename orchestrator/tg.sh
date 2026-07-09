#!/usr/bin/env bash
# Telegram orchestrator helpers — the cross-project control plane (NOT plugin code).
# Reads TELEGRAM_BOT_TOKEN from the env or ~/.agent-orchestrator/telegram.env.
#   tg.sh chat-id                     # discover the id of the group the bot can see
#   tg.sh new-topic <name> [chat_id]  # create a forum topic, print its thread id
set -euo pipefail
env_file="${TELEGRAM_ENV:-$HOME/.agent-orchestrator/telegram.env}"
# shellcheck disable=SC1090
[ -f "$env_file" ] && . "$env_file"
: "${TELEGRAM_BOT_TOKEN:?set TELEGRAM_BOT_TOKEN (in the env or $env_file)}"
api="https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN"

case "${1:-}" in
  chat-id)
    # Add the bot to your group as admin, send one message in the group, run this.
    curl -fsS "$api/getUpdates" | python3 -c 'import json,sys
seen={}
for u in json.load(sys.stdin).get("result",[]):
    for k in ("message","channel_post","my_chat_member"):
        c=u.get(k,{}).get("chat")
        if c: seen[c["id"]]=c.get("title") or c.get("username") or c.get("type")
for i,t in seen.items(): print(f"{i}\t{t}")
if not seen: sys.exit("no chats seen — add the bot to the group as admin, send a message there, and retry")'
    ;;
  new-topic)
    name="${2:?usage: tg.sh new-topic <name> [chat_id]}"
    chat="${3:-${TELEGRAM_CHAT_ID:?set TELEGRAM_CHAT_ID (env/file) or pass chat_id}}"
    curl -fsS "$api/createForumTopic" \
      --data-urlencode "chat_id=$chat" \
      --data-urlencode "name=$name" | python3 -c 'import json,sys
r=json.load(sys.stdin)
if not r.get("ok"): sys.exit("createForumTopic failed: "+json.dumps(r))
print(r["result"]["message_thread_id"])'
    ;;
  *)
    echo "usage: tg.sh {chat-id | new-topic <name> [chat_id]}" >&2; exit 2 ;;
esac
