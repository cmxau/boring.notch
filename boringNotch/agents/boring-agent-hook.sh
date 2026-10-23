#!/bin/bash
#
# Boring Notch agent hook bridge.
#
# AI coding agents (Claude Code, Codex, Gemini CLI, Cursor, ...) run this from their hook settings. It forwards
# the hook event to Boring Notch over localhost and prints Boring Notch's reply, which is how approvals and
# answers made in the notch get back to the agent.
#
# Usage: boring-agent-hook <agent> <event> [payload]
#   The hook payload is read from stdin, or taken from the third argument for agents that pass it that way
#   (Codex's notify).
#
# When Boring Notch isn't running or doesn't answer, this prints nothing and exits 0, so the agent carries on
# exactly as if the hook weren't installed.
#
# Installed and kept up to date by Boring Notch. Edits will be overwritten.

agent="${1:-unknown}"
event="${2:-unknown}"
bridge="$HOME/.boring-notch/bridge"

[ -r "$bridge" ] || exit 0
port="$(sed -n 's/^port=//p' "$bridge" | head -n 1)"
token="$(sed -n 's/^token=//p' "$bridge" | head -n 1)"
# Set on remote servers, where the notch is reached through an SSH tunnel
host="$(sed -n 's/^host=//p' "$bridge" | head -n 1)"
case "$port" in
    '' | *[!0-9]*) exit 0 ;;
esac

if [ -n "${3:-}" ]; then
    payload="$3"
elif [ -t 0 ]; then
    payload='{}'
else
    payload="$(cat)"
fi

# Hooks that wait for a decision in the notch are installed with BORING_NOTCH_WAIT set: "always", or
# "tools:A,B" to wait only for those tools. Everything else is fire-and-forget, so a stuck notch can never
# hold an agent up for more than a few seconds.
wait=3
case "${BORING_NOTCH_WAIT:-}" in
    always) wait=86400 ;;
    tools:*)
        tools="${BORING_NOTCH_WAIT#tools:}"
        old_ifs="$IFS"
        IFS=','
        for tool in $tools; do
            if printf '%s' "$payload" | grep -Eq "\"tool_name\"[[:space:]]*:[[:space:]]*\"$tool\""; then
                wait=86400
            fi
        done
        IFS="$old_ifs"
        ;;
esac

# Where the agent is running, so the notch can jump back to the right terminal, tab or pane.
tty="$(ps -o tty= -p $$ 2>/dev/null | tr -d ' ')"

response="$(
    printf '%s' "$payload" | curl --silent --fail --max-time "$wait" \
        --connect-timeout 1 \
        -X POST "http://127.0.0.1:$port/v1/hooks/$agent" \
        -H "Content-Type: application/json" \
        -H "X-Boring-Notch-Token: $token" \
        -H "X-Agent-Event: $event" \
        -H "X-Agent-Pid: $PPID" \
        -H "X-Terminal-Tty: $tty" \
        -H "X-Terminal-Program: ${TERM_PROGRAM:-}" \
        -H "X-Terminal-App: ${__CFBundleIdentifier:-}" \
        -H "X-Terminal-Session: ${ITERM_SESSION_ID:-${TERM_SESSION_ID:-}}" \
        -H "X-Agent-Host: $host" \
        -H "X-Tmux: ${TMUX:-}" \
        -H "X-Tmux-Pane: ${TMUX_PANE:-}" \
        -H "X-Kitty-Window: ${KITTY_WINDOW_ID:-}" \
        -H "X-Kitty-Listen-On: ${KITTY_LISTEN_ON:-}" \
        -H "X-Wezterm-Pane: ${WEZTERM_PANE:-}" \
        --data-binary @- 2>/dev/null
)" || exit 0

printf '%s' "$response"
exit 0
