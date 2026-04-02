#!/usr/bin/env node
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

function read(filePath) {
  return fs.readFileSync(filePath, 'utf8')
}

function expectContains(filePath, needle, message) {
  assert.ok(read(filePath).includes(needle), message)
}

function expectNotContains(filePath, needle, message) {
  assert.ok(!read(filePath).includes(needle), message)
}

const libraryPackage = path.join(repoRoot, 'library/oh-package.json5')
expectContains(
  libraryPackage,
  '"harmony-log":',
  'library/oh-package.json5 must declare harmony-log dependency'
)

const sourceIndex = path.join(repoRoot, 'src/main/ets/index.ets')
expectContains(
  sourceIndex,
  "export * from './logging'",
  'src/main/ets/index.ets must export logging helpers'
)

const sourceLoggingIndex = path.join(repoRoot, 'src/main/ets/logging/index.ets')
expectContains(
  sourceLoggingIndex,
  "export * from './NeptuneHarmonyLogger'",
  'logging index must export NeptuneHarmonyLogger module'
)

const sourceLogger = path.join(repoRoot, 'src/main/ets/logging/NeptuneHarmonyLogger.ets')
expectContains(
  sourceLogger,
  'createNeptuneHarmonyLogger',
  'NeptuneHarmonyLogger must expose createNeptuneHarmonyLogger helper'
)

expectNotContains(
  path.join(repoRoot, 'src/main/ets/callback/GatewayClientRegistrationHttpClient.ets'),
  'console.',
  'GatewayClientRegistrationHttpClient should use harmony-log instead of console'
)
expectNotContains(
  path.join(repoRoot, 'src/main/ets/callback/GatewayClientCallbackManager.ets'),
  'console.',
  'GatewayClientCallbackManager should use harmony-log instead of console'
)
expectNotContains(
  path.join(repoRoot, 'entry/src/main/ets/runtime/GatewayIngestHttpClient.ets'),
  'console.',
  'GatewayIngestHttpClient should use harmony-log instead of console'
)

console.log('harmony-log integration check passed.')
