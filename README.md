# comfy-netlify-sync

The Netlify venue for the pricing sync (wave-27 port of
comfyui-backend/comfy-sync-runner's sync.yml). The build command
(`netlify-sync.sh`) clones the PRIVATE backend repo (GH_PAT site env),
runs the scheduled sync, and pushes the data commit back to main.

- Site: comfy-pricing-sync-runner (https://comfy-pricing-sync-runner.netlify.app)
- Trigger: draft deploy via API (0 credits) — POST
  /api/v1/sites/{site_id}/deploys {"draft":true,"files":{}}
- Site env (set via netlify env:set, site-scoped): GH_PAT,
  RUNPOD_API_KEY, REPLICATE_API_TOKEN, DATABASE_URL, NODE_VERSION.
- Runs are ALSO observed via Netlify Blobs (sync-runs store, latest key)
  by the store-data plugin.
