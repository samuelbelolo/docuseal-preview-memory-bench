#!/usr/bin/env bash
#
# One bench run: mounts a variant of lib/templates/process_document.rb into a memory-limited container
# started from the golden state, uploads the PDF 5 times one after another, then 2 times at once,
# through the web upload form (POST /templates_upload), while a sidecar samples the container cgroup.
#
#   bash run.sh <variant.rb> <label> [cpuset] [pdf]
#
# Env: MEMORY (default 740m), SETTLE (seconds of rest before the first upload, default 20).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [[ ! -f "${1:-}" || -z "${2:-}" ]]; then
  echo "usage: bash run.sh <variant.rb> <label> [cpuset] [pdf]" >&2
  exit 2
fi

variant="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
label="$2"
cpuset="${3:-0}"
pdf="${4:-${BENCH_DIR}/test-22-pages.pdf}"
memory="${MEMORY:-740m}"
settle="${SETTLE:-20}"
out="${BENCH_DIR}/results/${label}"

rm -rf "$out"
mkdir -p "$out"
docker rm -f "$APP" "$SAMPLER" >/dev/null 2>&1 || true
docker volume rm -f "$RUN_VOLUME" >/dev/null
docker volume create "$RUN_VOLUME" >/dev/null
docker run --rm --platform "$PLATFORM" -v "${GOLDEN_VOLUME}:/from:ro" -v "${RUN_VOLUME}:/to" --entrypoint sh "$IMAGE" -c 'cp -a /from/. /to/'
cp "$COOKIES" "${STATE_DIR}/run-cookies.txt"
jar="${STATE_DIR}/run-cookies.txt"

docker run -d --name "$APP" --platform "$PLATFORM" --restart=no \
  --memory="$memory" --memory-swap="$memory" --cpuset-cpus="$cpuset" \
  -p "127.0.0.1:${PORT}:3000" -v "${RUN_VOLUME}:/data/docuseal" \
  -v "${variant}:/app/lib/templates/process_document.rb:ro" "$IMAGE" >/dev/null

app_id="$(docker inspect -f '{{.Id}}' "$APP")"
docker run -d --name "$SAMPLER" --platform "$PLATFORM" --privileged --cgroupns=host --cpuset-cpus="${SAMPLER_CPUSET:-$(( $(docker info --format "{{.NCPU}}") - 1 ))}" \
  -v /sys/fs/cgroup:/cg:ro -v "${BENCH_DIR}/sampler.rb:/sampler.rb:ro" --entrypoint ruby "$IMAGE" \
  /sampler.rb "$app_id" 0.25 >/dev/null

wait_up 300
token="$(curl -s -c "$jar" -b "$jar" "${BASE_URL}/" | csrf_token)"

if [[ -z "$token" ]]; then
  echo "no CSRF token: session not valid" >&2
  exit 1
fi

sleep "$settle"
printf 'doc\tphase\tstart\tend\thttp\tredirect\n' > "${out}/uploads.tsv"

# Uploads the PDF once and appends one line to uploads.tsv.
upload() {
  local doc="$1" phase="$2" start end result

  start="$(now)"
  result="$(curl -s -o /dev/null -w '%{http_code}\t%{redirect_url}' --max-time 600 -c "$jar" -b "$jar" \
    -F "authenticity_token=${token}" -F "files[]=@${pdf};type=application/pdf" \
    "${BASE_URL}/templates_upload" || true)"
  end="$(now)"
  printf '%s\t%s\t%s\t%s\t%s\n' "$doc" "$phase" "$start" "$end" "$result" >> "${out}/uploads.tsv"
}

# Returns success while the app container is running.
alive() {
  [[ "$(docker inspect -f '{{.State.Running}}' "$APP")" == "true" ]]
}

for doc in 1 2 3 4 5; do
  alive || break
  upload "$doc" sequential
  sleep 5
done

if alive; then
  sleep 5
  upload 6 parallel &
  upload 7 parallel &
  wait
  sleep 10
fi

docker inspect -f '{"oom_killed":{{.State.OOMKilled}},"exit_code":{{.State.ExitCode}},"running":{{.State.Running}},"restarts":{{.RestartCount}}}' "$APP" > "${out}/container.json"
docker stop -t 30 "$APP" >/dev/null 2>&1 || true
sleep 1
docker logs "$SAMPLER" > "${out}/samples.jsonl" 2>/dev/null
docker rm -f "$SAMPLER" >/dev/null
docker logs "$APP" > "${out}/app.log" 2>&1
docker cp "${APP}:/data/docuseal/." "${out}/data" >/dev/null
docker rm "$APP" >/dev/null
docker volume rm "$RUN_VOLUME" >/dev/null

sqlite3 -separator $'\t' "${out}/data/db.sqlite3" \
  "SELECT a.record_id, b.filename, b.checksum, b.key FROM active_storage_attachments a
   JOIN active_storage_blobs b ON b.id = a.blob_id
   WHERE a.name = 'preview_images' ORDER BY a.record_id, a.id" > "${out}/previews.tsv"

cp "$variant" "${out}/variant.rb"
printf 'cpuset=%s memory=%s image=%s platform=%s pdf=%s\n' "$cpuset" "$memory" "$IMAGE" "$PLATFORM" \
  "$(basename "$pdf")" > "${out}/settings.txt"
ruby "${BENCH_DIR}/summarize.rb" "$out"

# The copied data holds the generated SECRET_KEY_BASE and signing key of the throwaway account.
rm -rf "${out}/data"
