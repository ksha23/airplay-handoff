#!/bin/zsh
set -e
cd "$(dirname "$0")"
swiftc -O src/lookahead-play.swift -o lookahead-play
echo "built ./lookahead-play"
