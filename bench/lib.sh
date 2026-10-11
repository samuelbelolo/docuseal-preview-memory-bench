# Shared settings and helpers for the DocuSeal preview memory bench (sourced, not run).

IMAGE="${IMAGE:-docuseal/docuseal:3.3.1}"
PLATFORM="${PLATFORM:-linux/amd64}"
PORT="${PORT:-3999}"
BASE_URL="http://127.0.0.1:${PORT}"
APP="ds-bench-app"
SAMPLER="ds-bench-sampler"
GOLDEN_VOLUME="ds-bench-golden"
RUN_VOLUME="ds-bench-run"
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${BENCH_DIR}/.state"
COOKIES="${STATE_DIR}/cookies.txt"

# Prints the current epoch time with milliseconds.
now() {
  perl -MTime::HiRes=time -e 'printf "%.3f\n", time'
}

# Waits until the app answers 200 on /up, or fails after $1 seconds (default 300).
wait_up() {
  local deadline=$(( $(date +%s) + ${1:-300} ))

  until [[ "$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/up")" == "200" ]]; do
    if (( $(date +%s) > deadline )); then
      echo "app did not answer /up in time" >&2
      return 1
    fi

    if [[ "$(docker inspect -f '{{.State.Running}}' "$APP" 2>/dev/null)" != "true" ]]; then
      echo "app container is not running" >&2
      return 1
    fi

    sleep 1
  done
}

# Prints the CSRF token found in the HTML read on stdin.
csrf_token() {
  perl -0ne 'if (/name="csrf-token" content="([^"]+)"/ || /name="authenticity_token" value="([^"]+)"/) { print $1; exit }'
}
