#!/bin/zsh
# Register the native messaging host with Firefox.
set -e
cd "$(dirname "$0")"
DIR="$HOME/Library/Application Support/Mozilla/NativeMessagingHosts"
HOST="$PWD/lookahead_host.py"
mkdir -p "$DIR"
cat > "$DIR/com.ksha23.lookahead.json" <<JSON
{
  "name": "com.ksha23.lookahead",
  "description": "AirPlay Handoff native host",
  "path": "$HOST",
  "type": "stdio",
  "allowed_extensions": ["lookahead@ksha23"]
}
JSON
echo "registered: $DIR/com.ksha23.lookahead.json -> $HOST"
echo "Now load extension/ in Firefox via about:debugging > This Firefox > Load Temporary Add-on"
