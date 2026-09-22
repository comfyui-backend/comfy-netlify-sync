// onPostBuild: stores the sync run summary to Netlify Blobs (0 credits,
// unmetered) — durable run telemetry readable from anywhere via the
// Blobs API. The build command phase has no NETLIFY_BLOBS_CONTEXT; only
// this plugin phase does (kit-validated).
import { readFileSync, existsSync } from 'node:fs'

export default {
  onPostBuild: async () => {
    const SUMMARY = '/tmp/sync-run-summary.json'
    console.log('========== STORE_PLUGIN started ==========')
    if (!existsSync(SUMMARY)) {
      console.log('  No sync summary found — nothing to store.')
      return
    }
    const content = readFileSync(SUMMARY, 'utf8')
    const parsed = JSON.parse(content)
    console.log(`  Summary: ${content.slice(0, 200)}`)
    try {
      const { getStore } = await import('@netlify/blobs')
      const store = getStore('sync-runs')
      await store.setJSON(`netlify-${Date.now()}.json`, parsed)
      await store.setJSON('latest', parsed)
      const list = await store.list()
      console.log(`  Store contains ${list.blobs?.length || 0} run summaries — BLOB_WRITE_OK`)
    } catch (e) {
      console.log(`  BLOB_WRITE_ERR: ${e.message} (run summary still in the build log)`)
    }
    console.log('========== STORE_PLUGIN_END ==========')
  },
}
