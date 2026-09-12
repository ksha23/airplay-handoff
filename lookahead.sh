#!/bin/zsh
# lookahead.sh - send the frontmost browser tab to Safari, where the native
# player exposes an AirPlay button and therefore the BUFFERED AirPlay engine
# (~120 ms) instead of the realtime system-audio engine.
#
# Chrome and Edge expose the URL over AppleScript properly.
# Firefox's AppleScript support does not include reading the active tab URL,
# so we fall back to focusing it and copying the address bar.

set -e

front_app() {
  osascript -e 'tell application "System Events" to name of first process whose frontmost is true'
}

url_from_chromium() {  # $1 = app name
  osascript -e "tell application \"$1\" to get URL of active tab of front window" 2>/dev/null
}

url_from_safari() {
  osascript -e 'tell application "Safari" to get URL of front document' 2>/dev/null
}

url_from_firefox() {
  # No AppleScript dictionary entry for the active tab. Use the address bar.
  local old new
  old=$(pbpaste 2>/dev/null || true)
  osascript <<'OSA' >/dev/null 2>&1
tell application "Firefox" to activate
delay 0.25
tell application "System Events"
  keystroke "l" using command down
  delay 0.2
  keystroke "c" using command down
  delay 0.25
  key code 53
end tell
OSA
  new=$(pbpaste 2>/dev/null || true)
  # restore whatever the user had
  if [ -n "$old" ]; then printf '%s' "$old" | pbcopy 2>/dev/null || true; fi
  printf '%s' "$new"
}

APP="${1:-$(front_app)}"
case "$APP" in
  "Google Chrome"|"Chromium"|"Brave Browser"|"Microsoft Edge") URL=$(url_from_chromium "$APP") ;;
  firefox|Firefox)                                             URL=$(url_from_firefox) ;;
  Safari)  echo "Already in Safari. Use the player's AirPlay button." >&2; exit 0 ;;
  *)       URL=$(url_from_firefox) ;;   # best effort
esac

case "$URL" in
  http://*|https://*) ;;
  *) echo "Could not read a URL from \"$APP\" (got: ${URL:-<empty>})" >&2; exit 1 ;;
esac

echo "handing off: $URL"
open -a Safari "$URL"
