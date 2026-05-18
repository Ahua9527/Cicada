#!/bin/bash

set -euo pipefail

DAEMON_LOG="$HOME/.cicada/daemon.log"
DAEMON_STDERR="$HOME/.cicada/daemon.stderr.log"
DAEMON_STDOUT="$HOME/.cicada/daemon.stdout.log"
NOTIFIER_STDERR="$HOME/.cicada/notifier.stderr.log"
NOTIFIER_STDOUT="$HOME/.cicada/notifier.stdout.log"

echo "Cicada 实时日志（Swift Runtime）"
echo "================================"
echo "daemon:   $DAEMON_LOG"
echo "daemon-err: $DAEMON_STDERR"
echo "daemon-out: $DAEMON_STDOUT"
echo "notifier-err: $NOTIFIER_STDERR"
echo "notifier-out: $NOTIFIER_STDOUT"
echo "================================"

mkdir -p "$HOME/.cicada"
touch "$DAEMON_LOG" "$DAEMON_STDERR" "$DAEMON_STDOUT" "$NOTIFIER_STDERR" "$NOTIFIER_STDOUT"

tail -f "$DAEMON_LOG" "$DAEMON_STDERR" "$DAEMON_STDOUT" "$NOTIFIER_STDERR" "$NOTIFIER_STDOUT"
