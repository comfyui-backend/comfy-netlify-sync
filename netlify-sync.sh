#!/usr/bin/env bash
# Netlify build-time pricing sync (venue port, wave-27)
#
# Runs as the Netlify build command on a DRAFT (preview) deploy —
# 0 credits per run (validated: netlify-free-tier-agent-kit). The
# build container gives 15 min / 2 vCPU / 4 GB; the sync takes ~6-9 min
# end-to-end (clone + npm ci + prisma + sync).
#
# What this does (mirrors comfyui-backend/comfy-sync-runner sync.yml):
#   1. Clone the PRIVATE backend repo (GH_PAT from site env).
#   2. npm ci + prisma db push (ephemeral SQLite — git is the disk).
#   3. npx tsx scripts/run-scheduled-sync.ts (seed → history replay →
#      web3 listings → channels + persist; provider keys from env).
#   4. Race-safe data commit + push ([skip ci], rebase ×3).
#   5. Write a run-summary marker file for the store plugin (Blobs).
#
# Env (site-scoped, set via netlify env:set):
#   GH_PAT, RUNPOD_API_KEY, REPLICATE_API_TOKEN, DATABASE_URL,
#   NODE_VERSION=20.

set -euo pipefail

RUN_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RUN_START=$(date +%s)
echo "========== NETLIFY SYNC RUN ${RUN_TS} =========="

WORK=/opt/build/repo/backend
mkdir -p "$(dirname "$WORK")"

# ── 1. Clone the private backend repo (full history for the rebase) ──
T0=$(date +%s)
echo "[1/5] cloning beulahkemp/comfyui_backend (full history)…"
git clone -q "https://x-access-token:${GH_PAT}@github.com/beulahkemp/comfyui_backend.git" "$WORK"
echo "    clone done in $(( $(date +%s) - T0 ))s"

cd "$WORK/mvp-app"

# ── 2. deps + ephemeral DB ──
T0=$(date +%s)
echo "[2/5] npm ci…"
npm ci --no-audit --no-fund
echo "    npm ci done in $(( $(date +%s) - T0 ))s"

T0=$(date +%s)
echo "[3/5] prisma db push…"
npx prisma db push
echo "    prisma done in $(( $(date +%s) - T0 ))s"

# ── 3. The sync itself ──
T0=$(date +%s)
echo "[4/5] run-scheduled-sync…"
# Provider keys come from SITE ENV (not the tracked .env, which carries
# placeholders — run-scheduled-sync loads .env WITHOUT overriding existing
# env; explicit env wins: the wave-17 E-01 pattern).
npx tsx scripts/run-scheduled-sync.ts
echo "    sync done in $(( $(date +%s) - T0 ))s"

# ── 4. Race-safe data commit + push ──
T0=$(date +%s)
echo "[5/5] committing data refresh…"
cd "$WORK"
git config user.name "beulahkemp"
git config user.email "223220792+beulahkemp@users.noreply.github.com"
git add mvp-app/src/data/model-catalog.json
if [ -e mvp-app/src/data/price-history.jsonl ] || git ls-files --error-unmatch mvp-app/src/data/price-history.jsonl >/dev/null 2>&1; then
  git add mvp-app/src/data/price-history.jsonl
fi
[ -d mvp-app/src/data/price-history ] && git add mvp-app/src/data/price-history/

if git diff --cached --quiet; then
  echo "    no data changes this run — nothing to commit."
  PUSHED="no-change"
else
  git commit -m "data(pricing): netlify scheduled sync ${RUN_TS} [skip ci]"
  PUSHED="no"
  for attempt in 1 2 3; do
    if git push origin HEAD:main; then
      echo "    data commit pushed (attempt ${attempt})."
      PUSHED="yes"
      break
    fi
    echo "    push rejected (attempt ${attempt}) — rebasing on origin/main and retrying."
    git fetch origin main
    git rebase origin/main
    sleep $((attempt * 5))
  done
  if [ "$PUSHED" != "yes" ]; then
    echo "::error::netlify data push failed after 3 attempts — next hourly run re-syncs."
    # Do not fail the whole build for a lost push race; the run itself
    # succeeded and the data is in the clone + the next run re-syncs.
  fi
fi
COMMIT_SHA="$(git rev-parse --short HEAD)"
echo "    git phase done in $(( $(date +%s) - T0 ))s"

# ── 5. Run summary for the store plugin (Blobs) ──
ELAPSED=$(( $(date +%s) - RUN_START ))
cat > /tmp/sync-run-summary.json <<EOF
{
  "run_ts": "${RUN_TS}",
  "venue": "netlify",
  "elapsed_seconds": ${ELAPSED},
  "pushed": "${PUSHED}",
  "commit": "${COMMIT_SHA}",
  "node": "$(node -v)"
}
EOF
echo "========== NETLIFY SYNC RUN ${RUN_TS} COMPLETED in ${ELAPSED}s (pushed: ${PUSHED}) =========="
