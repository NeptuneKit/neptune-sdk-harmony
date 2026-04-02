#!/usr/bin/env node
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const entryRoot = path.join(repoRoot, 'entry')

function read(filePath) {
  return fs.readFileSync(filePath, 'utf8')
}

function expectContains(filePath, needle, message) {
  assert.ok(read(filePath).includes(needle), message)
}

function expectNotContains(filePath, needle, message) {
  assert.ok(!read(filePath).includes(needle), message)
}

const rootBuildProfile = read(path.join(repoRoot, 'build-profile.json5'))
assert.ok(rootBuildProfile.includes('"name": "entry"'), 'root build-profile must register the entry module')
assert.ok(rootBuildProfile.includes('"name": "library"'), 'root build-profile must keep the library module')

const entryModule = read(path.join(entryRoot, 'src/main/module.json5'))
assert.ok(entryModule.includes('"type": "entry"'), 'entry module must be a HAP entry module')
assert.ok(entryModule.includes('"mainElement": "EntryAbility"'), 'entry module must point at EntryAbility')
assert.ok(entryModule.includes('"pages": "$profile:main_pages"'), 'entry module must reference the page profile')

const pages = read(path.join(entryRoot, 'src/main/resources/base/profile/main_pages.json'))
assert.ok(pages.includes('"pages/Index"'), 'main_pages.json must expose pages/Index')

expectContains(
  path.join(entryRoot, 'src/main/ets/entryability/EntryAbility.ets'),
  "windowStage.loadContent('pages/Index'",
  'EntryAbility must load the demo page'
)
expectContains(
  path.join(entryRoot, 'src/main/ets/pages/Index.ets'),
  '写入日志批次',
  'demo page must expose the write-batch button'
)
expectContains(
  path.join(entryRoot, 'src/main/ets/pages/Index.ets'),
  '发现并上报',
  'demo page must expose the discover-and-ingest button'
)
expectContains(
  path.join(entryRoot, 'src/main/ets/pages/Index.ets'),
  '随机上报日志',
  'demo page must expose the random-ingest button'
)
expectContains(
  path.join(entryRoot, 'src/main/ets/pages/Index.ets'),
  'onRandomIngestTap',
  'demo page must wire random-ingest click handler'
)
expectContains(
  path.join(entryRoot, 'src/main/ets/pages/Index.ets'),
  '刷新快照',
  'demo page must expose the refresh snapshot button'
)
expectContains(
  path.join(entryRoot, 'src/main/ets/pages/Index.ets'),
  'this.snapshot.gatewayDiscovery.detail',
  'demo page must render the discovery result summary'
)
expectContains(
  path.join(entryRoot, 'src/main/ets/pages/Index.ets'),
  'POST /v2/logs:ingest',
  'demo page must explain the automatic ingest flow'
)
expectContains(
  path.join(entryRoot, 'src/main/ets/pages/Index.ets'),
  'aboutToAppear()',
  'demo page must auto-trigger discovery once on appear'
)
expectContains(
  path.join(entryRoot, 'src/main/ets/pages/Index.ets'),
  'Ingest Result',
  'demo page must render the ingest result section'
)
expectContains(
  path.join(entryRoot, 'src/main/ets/pages/Index.ets'),
  'this.snapshot.gatewayDiscovery.ingestDetail',
  'demo page must render the ingest result detail'
)
expectContains(
  path.join(entryRoot, 'src/main/ets/runtime/DemoRuntime.ets'),
  'GatewayIngestHttpClient',
  'demo runtime must create the ingest HTTP client'
)
expectContains(
  path.join(entryRoot, 'src/main/ets/runtime/DemoRuntime.ets'),
  'GatewayClientCallbackManager',
  'demo runtime must create the callback manager'
)
expectContains(
  path.join(entryRoot, 'src/main/ets/runtime/DemoRuntime.ets'),
  'this.callbackManager.start',
  'demo runtime must start the local callback server on boot'
)
expectContains(
  path.join(entryRoot, 'src/main/ets/runtime/DemoRuntime.ets'),
  'this.gatewayIngestClient.ingest',
  'demo runtime must POST the discovery log after gateway discovery succeeds'
)
expectContains(
  path.join(entryRoot, 'src/main/ets/runtime/DemoRuntime.ets'),
  'ingestRandomLogToGateway',
  'demo runtime must expose random single-log ingest action for manual testing'
)
expectContains(
  path.join(entryRoot, 'src/main/ets/runtime/DemoRuntime.ets'),
  "const DEMO_INGEST_SESSION_ID = 'sim-session-alpha'",
  'demo runtime should align ingest session to alpha identity for logs page filtering'
)
expectContains(
  path.join(entryRoot, 'src/main/ets/runtime/DemoRuntime.ets'),
  "const DEMO_INGEST_DEVICE_ID = 'sim-device-alpha'",
  'demo runtime should align ingest device to alpha identity for logs page filtering'
)
expectNotContains(
  path.join(entryRoot, 'src/main/ets/runtime/DemoRuntime.ets'),
  'sim-session-discovery',
  'demo runtime should not use discovery-only session identity for ingest logs'
)
expectNotContains(
  path.join(entryRoot, 'src/main/ets/runtime/DemoRuntime.ets'),
  'sim-device-discovery',
  'demo runtime should not use discovery-only device identity for ingest logs'
)
expectContains(
  path.join(entryRoot, 'src/main/ets/runtime/DemoRuntime.ets'),
  'length: 6',
  'demo runtime must query recent logs with LogQueryOptions.length'
)
expectNotContains(
  path.join(entryRoot, 'src/main/ets/runtime/DemoRuntime.ets'),
  'limit: 6',
  'demo runtime must not use removed LogQueryOptions.limit'
)
expectContains(
  path.join(entryRoot, 'src/main/ets/runtime/DemoRuntime.ets'),
  'this.callbackManager.setGatewayEndpoint',
  'demo runtime must register the callback endpoint when discovery resolves a new gateway'
)
expectNotContains(
  path.join(entryRoot, 'src/main/ets/runtime/DemoRuntime.ets'),
  'GatewayWsManager',
  'demo runtime must not keep the websocket manager as the default main chain'
)
expectNotContains(
  path.join(entryRoot, 'src/main/ets/runtime/DemoRuntime.ets'),
  'this.gatewayWsManager.start',
  'demo runtime must not auto-start the websocket client on boot'
)
expectContains(
  path.join(entryRoot, 'src/main/ets/runtime/GatewayIngestHttpClient.ets'),
  'POST /v2/logs:ingest',
  'ingest client must target the v2 ingest endpoint'
)
expectContains(
  path.join(entryRoot, 'oh-package.json5'),
  '"neptune-sdk-harmony": "file:../library"',
  'entry package must depend on the local HAR module'
)

console.log('Demo entry structure check passed.')
