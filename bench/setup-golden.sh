#!/usr/bin/env bash
#
# Boots the image once on an empty volume, creates the first account through the /setup form,
# and keeps that data volume and the session cookie as the starting state of every run.
#
#   bash setup-golden.sh
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

mkdir -p "$STATE_DIR"
docker rm -f "$APP" >/dev/null 2>&1 || true
docker volume rm -f "$GOLDEN_VOLUME" >/dev/null
docker volume create "$GOLDEN_VOLUME" >/dev/null

docker run -d --name "$APP" --platform "$PLATFORM" -p "127.0.0.1:${PORT}:3000" \
  -v "${GOLDEN_VOLUME}:/data/docuseal" "$IMAGE" >/dev/null

wait_up 600

rm -f "$COOKIES"
token="$(curl -s -c "$COOKIES" -b "$COOKIES" "${BASE_URL}/setup" | csrf_token)"
password="bench-$(openssl rand -hex 12)"

status="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -c "$COOKIES" -b "$COOKIES" \
  --data-urlencode "authenticity_token=${token}" \
  --data-urlencode 'account[name]=Bench' \
  --data-urlencode 'account[timezone]=UTC' \
  --data-urlencode 'account[locale]=en-US' \
  --data-urlencode 'user[first_name]=Bench' \
  --data-urlencode 'user[last_name]=User' \
  --data-urlencode 'user[email]=bench@example.com' \
  --data-urlencode "user[password]=${password}" \
  --data-urlencode "encrypted_config[value]=${BASE_URL}" \
  "${BASE_URL}/setup")"

echo "setup: ${status}"

if [[ "$status" != 302* ]]; then
  echo "setup failed" >&2
  exit 1
fi

docker stop "$APP" >/dev/null
docker rm "$APP" >/dev/null
echo "golden volume ${GOLDEN_VOLUME} and ${COOKIES} ready"
