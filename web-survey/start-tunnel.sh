#!/usr/bin/env bash
set -euo pipefail

PORT="${SURVEY_DEV_PORT:-5199}"
LOG="/tmp/dops-cloudflared-survey.log"
PID_FILE="/tmp/dops-cloudflared-survey.pid"

if ! lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Survey dev server is not listening on port $PORT."
  echo "Start it first: cd functions && npm run serve:survey"
  exit 1
fi

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "Stopping existing cloudflared (pid $(cat "$PID_FILE"))..."
  kill "$(cat "$PID_FILE")" || true
  sleep 1
fi

rm -f "$LOG"
TUNNEL_URL_FILE="$(dirname "$0")/.tunnel-url"
nohup cloudflared tunnel --url "http://localhost:${PORT}" >>"$LOG" 2>&1 &
echo $! >"$PID_FILE"
disown

for _ in $(seq 1 30); do
  URL=$(rg -o 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG" | head -1 || true)
  if [ -n "$URL" ]; then
    echo "$URL" >"$TUNNEL_URL_FILE"
    echo "Tunnel URL: $URL"
    echo "Saved to: $TUNNEL_URL_FILE"
    echo "Update DEBUG baseURL in CustomerSatisfactionSurveyToken.swift if needed."
    echo "Log: $LOG"
    exit 0
  fi
  sleep 1
done

echo "cloudflared started but tunnel URL not found yet. Check $LOG"
exit 1
