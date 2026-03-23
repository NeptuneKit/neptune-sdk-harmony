#!/usr/bin/env node
import assert from 'node:assert/strict'

const keyFields = ['sdkName', 'sdkVersion', 'platform', 'appId', 'sessionId', 'deviceId']

function normalizeField(value) {
  if (typeof value !== 'string') {
    return null
  }

  const trimmed = value.trim()
  return trimmed.length > 0 ? trimmed : null
}

function makeSourceKey(source) {
  const values = keyFields.map((field) => normalizeField(source[field]))
  if (values.some((value) => value === null)) {
    return null
  }
  return values.join('::')
}

function registerSource(sources, source) {
  const key = makeSourceKey(source)
  if (key === null) {
    return
  }

  const index = sources.findIndex((item) => makeSourceKey(item) === key)
  if (index >= 0) {
    sources[index] = {
      ...sources[index],
      ...source
    }
    return
  }

  sources.push(source)
}

const sources = []
registerSource(sources, {
  deviceId: 'device-1',
  appId: 'demo.app',
  platform: 'harmony',
  sessionId: 'session-1',
  sdkName: 'neptune-sdk-harmony',
  sdkVersion: '0.1.0',
  lastSeenAt: '2026-03-23T12:00:00.000Z'
})
registerSource(sources, {
  deviceId: 'device-1',
  appId: 'demo.app',
  platform: 'harmony',
  sessionId: 'session-1',
  sdkName: 'neptune-sdk-harmony',
  sdkVersion: '0.1.0',
  lastSeenAt: '2026-03-23T12:34:56.000Z'
})
registerSource(sources, {
  deviceId: 'device-2',
  appId: 'demo.app',
  platform: 'harmony',
  sessionId: 'session-1',
  sdkName: 'neptune-sdk-harmony',
  sdkVersion: '0.1.0',
  lastSeenAt: '2026-03-23T12:40:00.000Z'
})
registerSource(sources, {
  deviceId: 'device-3',
  appId: 'demo.app',
  platform: 'harmony',
  sessionId: 'session-1',
  sdkName: '',
  sdkVersion: '0.1.0',
  lastSeenAt: '2026-03-23T12:45:00.000Z'
})

assert.equal(sources.length, 2)
assert.equal(sources[0].lastSeenAt, '2026-03-23T12:34:56.000Z')
assert.deepEqual(
  Object.keys(sources[0]).sort(),
  ['appId', 'deviceId', 'lastSeenAt', 'platform', 'sdkName', 'sdkVersion', 'sessionId'].sort()
)

console.log('verify-source-dedup: ok')
console.log(`sources.length=${sources.length}`)
console.log(`sources[0].lastSeenAt=${sources[0].lastSeenAt}`)
