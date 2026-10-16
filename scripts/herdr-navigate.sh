#!/usr/bin/env bash
#
# smart-splits-backend-herdr: the herdr half.
#
# herdr runs this for a key binding as: herdr-navigate.sh <left|down|up|right>
#
# For each keypress:
#   1. If the focused pane's foreground process is Vim or Neovim (or matches
#      SMART_SPLITS_HERDR_PASSTHROUGH_RE), send the key into the pane. Neovim
#      moves between its own splits and, at an edge, asks herdr to cross over.
#   2. Otherwise move herdr focus in that direction.
#   3. If there is no pane that way, or herdr could not be asked, send the key
#      back to the pane, so shell bindings such as C-l (clear) and C-h
#      (backspace) keep working.
#
# Needs `jq` to tell a Vim pane from any other. Without it, step 1 is skipped.

set -euo pipefail

dir="${1:-}"
herdr="${HERDR_BIN_PATH:-herdr}"
pane="${HERDR_PANE_ID:-}"

case "$dir" in
  left) key="ctrl+h" ;;
  down) key="ctrl+j" ;;
  up) key="ctrl+k" ;;
  right) key="ctrl+l" ;;
  *)
    echo "herdr-navigate.sh: usage: herdr-navigate.sh <left|down|up|right>" >&2
    exit 2
    ;;
esac

if [ -z "$pane" ]; then
  # no pane to forward to or move from
  exit 0
fi

# Foreground process names that mean Vim is in charge of the pane: vi, vim,
# nvim, view, gvim, vimdiff, nvimdiff and so on. Same matcher as
# vim-tmux-navigator.
vim_re='^g?(view|l?n?vim?x?)(diff)?$'

# Opt-in for other programs that handle C-hjkl themselves, e.g.
# SMART_SPLITS_HERDR_PASSTHROUGH_RE='^(lazygit|k9s)$'
passthrough_re="${SMART_SPLITS_HERDR_PASSTHROUGH_RE:-}"

have_jq=0
if command -v jq >/dev/null 2>&1; then
  have_jq=1
fi

send_key() {
  exec "$herdr" pane send-keys "$pane" "$key"
}

if [ "$have_jq" -eq 1 ]; then
  if "$herdr" pane process-info --pane "$pane" 2>/dev/null |
    jq -e --arg vim "$vim_re" --arg pass "$passthrough_re" '
      [.result.process_info.foreground_processes[]?
        | (.name // "") | ascii_downcase
        | select(test($vim) or ($pass != "" and (try test($pass) catch false)))]
      | length > 0' >/dev/null 2>&1; then
    send_key
  fi
fi

focus_output="$("$herdr" pane focus --direction "$dir" --pane "$pane" 2>/dev/null)" || send_key

if [ "$have_jq" -eq 1 ]; then
  changed="$(printf '%s' "$focus_output" | jq -r '.result.focus.changed // false' 2>/dev/null || echo false)"
  if [ "$changed" = "true" ]; then
    exit 0
  fi
  send_key
fi

# Without jq the answer cannot be read. A JSON body that says the focus moved
# is the only thing worth trusting; anything else goes back to the pane.
case "$focus_output" in
  *'"changed":true'*) exit 0 ;;
  *) send_key ;;
esac
