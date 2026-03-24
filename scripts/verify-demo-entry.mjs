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
  '写入 Demo 日志批次',
  'demo page must expose the write-log button'
)
expectContains(
  path.join(entryRoot, 'oh-package.json5'),
  '"neptune-sdk-harmony": "file:../library"',
  'entry package must depend on the local HAR module'
)

console.log('Demo entry structure check passed.')
