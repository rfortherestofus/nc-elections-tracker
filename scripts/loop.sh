#!/usr/bin/env bash
# The publish loop. Runs inside the "Live results" GitHub Action.
#
# Every 5 minutes:
#   1. Download the latest results (R/fetch.R). Unchanged files cost a 304.
#   2. If anything changed (or this is the first pass), render the site.
#   3. Check the rendered site is 2026 data, then force-push it to the
#      cloudflare branch. Cloudflare deploys that branch.
#
# Stops when every precinct has reported and nothing has changed for 60
# minutes, or at noon ET on November 4. Before GitHub's 6-hour job limit it
# starts a fresh run of the workflow and exits.
#
# Local dry run (renders, never pushes):
#   DRY_RUN=1 INTERVAL=20 bash scripts/loop.sh

set -uo pipefail

PUBLISH_DATE="20261103"       # the only election this loop will ever publish
DEADLINE="2026-11-04T17:00:00Z" # noon ET on November 4
INTERVAL="${INTERVAL:-300}"   # seconds between checks
QUIET_LIMIT=3600              # stop after 60 quiet minutes at full reporting
MAX_RUNTIME=$((345 * 60))     # hand off to a fresh run at 5 hours 45 minutes
DRY_RUN="${DRY_RUN:-0}"

export ELECTION_DATE="${ELECTION_DATE:-$PUBLISH_DATE}"
STATUS_FILE="data/raw/${ELECTION_DATE}/status.json"

log() { echo "[$(TZ=America/New_York date '+%H:%M:%S ET')] $*"; }

to_epoch() {
  date -u -d "$1" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s
}

start=$(date +%s)
deadline=$(to_epoch "$DEADLINE")
last_change=$start
published_once=0

# Refuse to publish anything but 2026 data
verify_site() {
  if [[ "$ELECTION_DATE" != "$PUBLISH_DATE" ]]; then
    log "REFUSING to publish: ELECTION_DATE is $ELECTION_DATE, not $PUBLISH_DATE"
    return 1
  fi
  local expected data_date
  expected="${PUBLISH_DATE:4:2}/${PUBLISH_DATE:6:2}/${PUBLISH_DATE:0:4}"
  data_date=$(jq -r '.data_date' "$STATUS_FILE")
  if [[ "$data_date" != "$expected" ]]; then
    log "REFUSING to publish: data is for $data_date, not $expected"
    return 1
  fi
  if grep -q 'test-data-banner' _site/*.html; then
    log "REFUSING to publish: rendered pages carry the test data banner"
    return 1
  fi
  return 0
}

# Force-push _site plus wrangler.jsonc to the cloudflare branch as one commit
deploy() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log "Dry run: would push to the cloudflare branch"
    return 0
  fi

  local tmp
  tmp=$(mktemp -d)
  cp -R _site "$tmp/_site"
  cp wrangler.jsonc "$tmp/"

  (
    cd "$tmp" &&
      git init -q -b cloudflare &&
      git add -A &&
      git -c user.name="github-actions[bot]" \
        -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
        commit -qm "Results as of $(TZ=America/New_York date '+%-I:%M %p ET, %B %-d')" &&
      git push -q -f "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" cloudflare
  )
  local result=$?
  rm -rf "$tmp"
  return $result
}

while true; do
  now=$(date +%s)

  if ((now >= deadline)); then
    log "Reached the noon ET deadline. Stopping."
    exit 0
  fi

  if ((now - start >= MAX_RUNTIME)); then
    if [[ "$DRY_RUN" == "1" ]]; then
      log "Dry run: would start a fresh workflow run"
    else
      log "Near GitHub's 6-hour limit. Starting a fresh run and exiting."
      gh workflow run live.yml --ref "${GITHUB_REF_NAME:-main}"
    fi
    exit 0
  fi

  if Rscript R/fetch.R; then
    changed=$(jq -r '.changed' "$STATUS_FILE")
    all_reporting=$(jq -r '.all_reporting' "$STATUS_FILE")

    if [[ "$changed" == "true" || "$published_once" == "0" ]]; then
      [[ "$changed" == "true" ]] && last_change=$now
      log "Rendering"
      if quarto render --quiet && verify_site && deploy; then
        published_once=1
        log "Published"
      else
        log "Render or publish failed. Keeping the last good site."
      fi
    else
      log "No change"
    fi

    if [[ "$all_reporting" == "true" ]] && ((now - last_change >= QUIET_LIMIT)); then
      log "Every precinct reported and no change for 60 minutes. Stopping."
      exit 0
    fi
  else
    log "Download failed. Keeping the last good site."
  fi

  sleep "$INTERVAL"
done
