#!/bin/bash

set -euo pipefail

DAEMON_LOG="$HOME/.cicada/daemon.log"
DAEMON_STDERR="$HOME/.cicada/daemon.stderr.log"
DAEMON_STDOUT="$HOME/.cicada/daemon.stdout.log"
SENTINEL_STDERR="$HOME/.cicada/sentinel.stderr.log"
SENTINEL_STDOUT="$HOME/.cicada/sentinel.stdout.log"

echo "Cicada 实时日志（Swift Runtime）"
echo "================================"
echo "daemon:   $DAEMON_LOG"
echo "daemon-err: $DAEMON_STDERR"
echo "daemon-out: $DAEMON_STDOUT"
echo "sentinel-err: $SENTINEL_STDERR"
echo "sentinel-out: $SENTINEL_STDOUT"
echo "================================"

mkdir -p "$HOME/.cicada"
touch "$DAEMON_LOG" "$DAEMON_STDERR" "$DAEMON_STDOUT" "$SENTINEL_STDERR" "$SENTINEL_STDOUT"

tail -f "$DAEMON_LOG" "$DAEMON_STDERR" "$DAEMON_STDOUT" "$SENTINEL_STDERR" "$SENTINEL_STDOUT"
