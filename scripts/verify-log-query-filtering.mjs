#!/usr/bin/env node
import assert from 'node:assert/strict'

function normalizeQueryField(value) {
  if (typeof value !== 'string') {
    return undefined
  }

  const trimmed = value.trim()
  return trimmed.length > 0 ? trimmed : undefined
}

function normalizeLength(length, maxSize = 2000) {
  if (length === undefined || length === null) {
    return maxSize
  }
  if (length <= 0) {
    return maxSize
  }
  return Math.min(length, maxSize)
}

function matchesField(actual, expected) {
  if (expected === undefined) {
    return true
  }
  return actual === expected
}

function queryLogs(records, query = {}, batchSize = 50) {
  const cursor = typeof query.cursor === 'string' ? query.cursor : undefined
  const cursorId = cursor && cursor.trim().length > 0 ? Number(cursor) : Number.NaN
  const length = normalizeLength(query.length, batchSize)
  const platform = normalizeQueryField(query.platform)
  const appId = normalizeQueryField(query.appId)
  const sessionId = normalizeQueryField(query.sessionId)

  const filtered = records.filter((record) => {
    if (Number.isFinite(cursorId) && record.id <= cursorId) {
      return false
    }
    return matchesField(record.platform, platform) &&
      matchesField(record.appId, appId) &&
      matchesField(record.sessionId, sessionId)
  })

  const page = filtered.slice(0, length)
  return {
    records: page,
    hasMore: filtered.length > length
  }
}

const records = [
  { id: 1, platform: 'ios', appId: 'demo.app', sessionId: 'session-a' },
  { id: 2, platform: 'harmony', appId: 'demo.app', sessionId: 'session-a' },
  { id: 3, platform: 'harmony', appId: 'demo.app', sessionId: 'session-b' },
  { id: 4, platform: 'harmony', appId: 'demo.admin', sessionId: 'session-b' },
  { id: 5, platform: 'android', appId: 'demo.app', sessionId: 'session-b' }
]

assert.deepEqual(
  queryLogs(records, { length: 2 }),
  {
    records: records.slice(0, 2),
    hasMore: true
  }
)

assert.deepEqual(
  queryLogs(records, { platform: 'harmony', length: 2 }),
  {
    records: [records[1], records[2]],
    hasMore: true
  }
)

assert.deepEqual(
  queryLogs(records, { cursor: '2', appId: 'demo.app', sessionId: 'session-b', length: 2 }),
  {
    records: [records[2], records[4]],
    hasMore: false
  }
)

assert.deepEqual(
  queryLogs(records, { platform: '   ', appId: '', sessionId: undefined, length: 3 }),
  {
    records: records.slice(0, 3),
    hasMore: true
  }
)

console.log('verify-log-query-filtering: ok')
