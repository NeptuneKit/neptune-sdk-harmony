#!/usr/bin/env node
import assert from 'node:assert/strict'
import http from 'node:http'

const DEFAULT_SERVICE_NAME = 'neptune-sdk-harmony-demo'
const DEFAULT_VERSION = '0.1.0'
const DEFAULT_PORT = 0

function normalizeText(value) {
  if (typeof value !== 'string') {
    return null
  }

  const trimmed = value.trim()
  return trimmed.length > 0 ? trimmed : null
}

function makeSourceKey(source) {
  const sdkName = normalizeText(source.sdkName)
  const sdkVersion = normalizeText(source.sdkVersion)
  const platform = normalizeText(source.platform)
  const appId = normalizeText(source.appId)
  const sessionId = normalizeText(source.sessionId)
  const deviceId = normalizeText(source.deviceId)

  if (
    sdkName === null ||
    sdkVersion === null ||
    platform === null ||
    appId === null ||
    sessionId === null ||
    deviceId === null
  ) {
    return null
  }

  return [sdkName, sdkVersion, platform, appId, sessionId, deviceId].join('::')
}

function createReferenceExportServer(options = {}) {
  const serviceName = options.serviceName ?? DEFAULT_SERVICE_NAME
  const version = options.version ?? DEFAULT_VERSION
  const startedAt = options.startedAt ?? new Date().toISOString()

  const state = {
    running: false,
    nextId: 1,
    records: [],
    sources: [],
    totalIngested: 0,
    totalExported: 0,
    droppedOverflow: 0
  }

  function registerSource(source) {
    const key = makeSourceKey(source)
    if (key === null) {
      return
    }

    const index = state.sources.findIndex((item) => makeSourceKey(item) === key)
    if (index >= 0) {
      state.sources[index] = {
        ...state.sources[index],
        ...source
      }
      return
    }

    state.sources.push({ ...source })
  }

  function registerSourceFromRecord(record) {
    if (record.source === undefined || record.source === null) {
      return
    }

    const source = {
      deviceId: record.deviceId,
      appId: record.appId,
      platform: record.platform,
      sessionId: record.sessionId,
      sdkName: record.source.sdkName,
      sdkVersion: record.source.sdkVersion,
      lastSeenAt: record.timestamp
    }
    registerSource(source)
  }

  function ingest(recordOrRecords) {
    const records = Array.isArray(recordOrRecords) ? recordOrRecords : [recordOrRecords]
    const stored = []

    for (const record of records) {
      registerSourceFromRecord(record)
      const nextRecord = {
        id: state.nextId,
        timestamp: record.timestamp,
        level: record.level,
        message: record.message,
        platform: record.platform,
        appId: record.appId,
        sessionId: record.sessionId,
        deviceId: record.deviceId,
        category: record.category,
        attributes: record.attributes,
        source: record.source
      }
      state.nextId += 1
      state.totalIngested += 1
      state.records.push(nextRecord)
      stored.push(nextRecord)
    }

    return stored
  }

  function normalizeLimit(limit) {
    if (limit === undefined || limit === null) {
      return 50
    }

    if (limit <= 0) {
      return 1
    }

    return Math.min(limit, 2000)
  }

  function normalizeQueryField(value) {
    const normalized = normalizeText(value)
    return normalized === null ? undefined : normalized
  }

  function matchesQueryField(actual, expected) {
    if (expected === undefined) {
      return true
    }
    return normalizeQueryField(actual) === expected
  }

  function queryLogs(query = {}) {
    const cursor = typeof query.cursor === 'string' ? query.cursor : undefined
    const cursorId = cursor && cursor.trim().length > 0 ? Number(cursor) : Number.NaN
    const limit = normalizeLimit(query.limit)
    const platform = normalizeQueryField(query.platform)
    const appId = normalizeQueryField(query.appId)
    const sessionId = normalizeQueryField(query.sessionId)

    const filtered = state.records.filter((record) => {
      if (Number.isFinite(cursorId) && record.id <= cursorId) {
        return false
      }

      return matchesQueryField(record.platform, platform) &&
        matchesQueryField(record.appId, appId) &&
        matchesQueryField(record.sessionId, sessionId)
    })

    const page = filtered.slice(0, limit)
    return {
      records: page,
      nextCursor: page.length > 0 ? String(page[page.length - 1].id) : (cursor ?? ''),
      hasMore: filtered.length > limit
    }
  }

  function metrics() {
    return {
      queueSize: state.records.length,
      queueCapacity: 2000,
      droppedOverflow: state.droppedOverflow,
      totalIngested: state.totalIngested,
      totalExported: state.totalExported
    }
  }

  function health() {
    return {
      status: state.running ? 'ok' : 'degraded',
      service: serviceName,
      version,
      startedAt
    }
  }

  function sourcesSnapshot() {
    return state.sources.map((source) => ({ ...source }))
  }

  function createHttpServer() {
    return http.createServer((req, res) => {
      const requestUrl = new URL(req.url ?? '/', 'http://127.0.0.1')
      res.setHeader('Content-Type', 'application/json; charset=utf-8')

      if (req.method === 'GET' && requestUrl.pathname === '/v2/export/health') {
        res.statusCode = 200
        res.end(JSON.stringify(health()))
        return
      }

      if (req.method === 'GET' && requestUrl.pathname === '/v2/export/metrics') {
        res.statusCode = 200
        res.end(JSON.stringify(metrics()))
        return
      }

      if (req.method === 'GET' && requestUrl.pathname === '/v2/logs') {
        const limitValue = requestUrl.searchParams.get('limit')
        const parsedLimit = limitValue !== null ? Number.parseInt(limitValue, 10) : undefined
        res.statusCode = 200
        res.end(JSON.stringify(queryLogs({
          cursor: requestUrl.searchParams.get('cursor') ?? undefined,
          limit: Number.isFinite(parsedLimit) ? parsedLimit : undefined,
          platform: requestUrl.searchParams.get('platform') ?? undefined,
          appId: requestUrl.searchParams.get('appId') ?? undefined,
          sessionId: requestUrl.searchParams.get('sessionId') ?? undefined
        })))
        return
      }

      if (req.method === 'GET' && requestUrl.pathname === '/v2/export/sources') {
        res.statusCode = 200
        res.end(JSON.stringify(sourcesSnapshot()))
        return
      }

      res.statusCode = 404
      res.end(JSON.stringify({ error: 'not_found' }))
    })
  }

  async function start(port = DEFAULT_PORT) {
    const server = createHttpServer()
    await new Promise((resolve) => {
      server.listen(port, resolve)
    })

    state.running = true
    const address = server.address()
    const resolvedPort = typeof address === 'object' && address !== null ? address.port : port

    return {
      port: resolvedPort,
      stop: async () => {
        state.running = false
        await new Promise((resolve) => {
          server.close(() => resolve(undefined))
        })
      }
    }
  }

  return {
    ingest,
    queryLogs,
    metrics,
    health,
    sourcesSnapshot,
    start
  }
}

async function requestJson(baseUrl, path) {
  const response = await fetch(`${baseUrl}${path}`)
  assert.equal(response.ok, true, `request failed: ${path} -> ${response.status}`)
  return response.json()
}

function makeDemoRecords() {
  return [
    {
      timestamp: '2026-03-24T03:00:00.000Z',
      level: 'info',
      message: 'demo export started',
      platform: 'harmony',
      appId: 'com.neptune.demo.harmony',
      sessionId: 'smoke-session',
      deviceId: 'device-alpha',
      category: 'lifecycle',
      source: {
        sdkName: 'neptune-sdk-harmony',
        sdkVersion: '0.1.0'
      }
    },
    {
      timestamp: '2026-03-24T03:00:01.000Z',
      level: 'warning',
      message: 'demo export filtered',
      platform: 'harmony',
      appId: 'com.neptune.demo.harmony',
      sessionId: 'smoke-session',
      deviceId: 'device-alpha',
      category: 'export',
      source: {
        sdkName: 'neptune-sdk-harmony',
        sdkVersion: '0.1.0'
      }
    },
    {
      timestamp: '2026-03-24T03:00:02.000Z',
      level: 'info',
      message: 'demo export ios sibling',
      platform: 'ios',
      appId: 'com.neptune.demo.ios',
      sessionId: 'smoke-session-ios',
      deviceId: 'device-beta',
      category: 'lifecycle',
      source: {
        sdkName: 'neptune-sdk-ios',
        sdkVersion: '0.1.0'
      }
    }
  ]
}

async function main() {
  const server = createReferenceExportServer({
    serviceName: DEFAULT_SERVICE_NAME,
    version: DEFAULT_VERSION,
    startedAt: '2026-03-24T03:00:00.000Z'
  })

  const listener = await server.start()
  const baseUrl = `http://127.0.0.1:${listener.port}`

  try {
    const inserted = server.ingest(makeDemoRecords())
    assert.equal(inserted.length, 3)

    const health = await requestJson(baseUrl, '/v2/export/health')
    const metrics = await requestJson(baseUrl, '/v2/export/metrics')
    const logs = await requestJson(baseUrl, '/v2/logs?platform=harmony&appId=com.neptune.demo.harmony&sessionId=smoke-session&limit=2')
    const sources = await requestJson(baseUrl, '/v2/export/sources')

    assert.equal(health.status, 'ok')
    assert.equal(health.service, DEFAULT_SERVICE_NAME)
    assert.equal(metrics.queueSize, 3)
    assert.equal(metrics.totalIngested, 3)
    assert.equal(metrics.totalExported, 0)
    assert.equal(logs.records.length, 2)
    assert.equal(logs.nextCursor, '2')
    assert.equal(logs.hasMore, false)
    assert.equal(sources.length, 2)
    assert.equal(sources[0].sdkName, 'neptune-sdk-harmony')
    assert.equal(sources[0].lastSeenAt, '2026-03-24T03:00:01.000Z')

    const summary = {
      service: health.service,
      version: health.version,
      status: health.status,
      queueSize: metrics.queueSize,
      totalIngested: metrics.totalIngested,
      totalExported: metrics.totalExported,
      filteredLogCount: logs.records.length,
      nextCursor: logs.nextCursor,
      sourceCount: sources.length,
      primarySource: sources[0].sdkName,
      siblingSource: sources[1].sdkName
    }

    console.log('demo-smoke: ok')
    console.log(JSON.stringify(summary, null, 2))
  } finally {
    await listener.stop()
  }
}

main().catch((error) => {
  console.error('demo-smoke: failed')
  console.error(error instanceof Error ? error.stack ?? error.message : String(error))
  process.exitCode = 1
})
