#!/usr/bin/env node
import assert from 'node:assert/strict'

function normalizeQueryField(value) {
  if (typeof value !== 'string') {
    return undefined
  }

  const trimmed = value.trim()
  return trimmed.length > 0 ? trimmed : undefined
}

function normalizeLimit(limit, batchSize = 50) {
  if (limit === undefined || limit === null) {
    return batchSize
  }
  if (limit <= 0) {
    return 1
  }
  return Math.min(limit, batchSize)
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
  const limit = normalizeLimit(query.limit, batchSize)
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

  const page = filtered.slice(0, limit)
  return {
    records: page,
    nextCursor: page.length > 0 ? String(page[page.length - 1].id) : (cursor ?? ''),
    hasMore: filtered.length > limit
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
  queryLogs(records, { limit: 2 }),
  {
    records: records.slice(0, 2),
    nextCursor: '2',
    hasMore: true
  }
)

assert.deepEqual(
  queryLogs(records, { platform: 'harmony', limit: 2 }),
  {
    records: [records[1], records[2]],
    nextCursor: '3',
    hasMore: true
  }
)

assert.deepEqual(
  queryLogs(records, { cursor: '2', appId: 'demo.app', sessionId: 'session-b', limit: 2 }),
  {
    records: [records[2], records[4]],
    nextCursor: '5',
    hasMore: false
  }
)

assert.deepEqual(
  queryLogs(records, { platform: '   ', appId: '', sessionId: undefined, limit: 3 }),
  {
    records: records.slice(0, 3),
    nextCursor: '3',
    hasMore: true
  }
)

console.log('verify-log-query-filtering: ok')
