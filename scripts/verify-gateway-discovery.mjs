#!/usr/bin/env node
import assert from 'node:assert/strict'

function normalizeText(value) {
  if (typeof value !== 'string') {
    return null
  }

  const trimmed = value.trim()
  return trimmed.length > 0 ? trimmed : null
}

function parseManualDsnValue(value) {
  const normalized = normalizeText(value)
  if (normalized === null) {
    return null
  }

  let host = ''
  let port = 0

  if (normalized.includes('://')) {
    try {
      const url = new URL(normalized)
      host = url.hostname
      port = Number(url.port)
    } catch {
      return null
    }
  } else if (normalized.startsWith('[')) {
    const end = normalized.indexOf(']')
    const colonIndex = normalized.indexOf(':', end)
    if (end < 0 || colonIndex < 0) {
      return null
    }
    host = normalized.slice(1, end)
    port = Number(normalized.slice(colonIndex + 1))
  } else {
    const lastColonIndex = normalized.lastIndexOf(':')
    if (lastColonIndex <= 0) {
      return null
    }
    host = normalized.slice(0, lastColonIndex)
    port = Number(normalized.slice(lastColonIndex + 1))
  }

  if (!normalizeText(host) || !Number.isInteger(port) || port <= 0 || port > 65535) {
    return null
  }

  return {
    host: normalizeText(host),
    port,
    source: 'manual-dsn',
    label: normalized
  }
}

function collectCandidates({ mdnsCandidates = [], manualDsn } = {}) {
  const manualValues = Array.isArray(manualDsn)
    ? manualDsn
    : typeof manualDsn === 'string'
      ? manualDsn.split(',')
      : []

  const candidates = []
  for (const item of mdnsCandidates) {
    candidates.push(item)
  }
  for (const value of manualValues) {
    const candidate = parseManualDsnValue(value)
    if (candidate !== null) {
      candidates.push(candidate)
    }
  }
  return candidates
}

function isLoopbackOrWildcardHost(host) {
  const normalized = normalizeText(host)?.toLowerCase()
  if (!normalized) {
    return false
  }

  return normalized === 'localhost' ||
    normalized === '127.0.0.1' ||
    normalized === '0.0.0.0' ||
    normalized === '::1' ||
    normalized === '::'
}

function resolveReachableHost(payloadHost, candidateHost) {
  const normalizedPayloadHost = normalizeText(payloadHost)
  const normalizedCandidateHost = normalizeText(candidateHost)

  if (!isLoopbackOrWildcardHost(normalizedPayloadHost)) {
    return normalizedPayloadHost
  }

  if (isWildcardHost(normalizedPayloadHost)) {
    return normalizedCandidateHost ?? normalizedPayloadHost
  }

  if (!isLoopbackOrWildcardHost(normalizedCandidateHost)) {
    return normalizedCandidateHost
  }

  return normalizedPayloadHost
}

function isWildcardHost(host) {
  const normalized = normalizeText(host)?.toLowerCase()
  return normalized === '0.0.0.0' || normalized === '::'
}

async function resolveGateway({ mdnsProvider, httpClient, config = {} }) {
  const attempts = []
  let mdnsCandidates = []
  try {
    mdnsCandidates = await mdnsProvider.discoverCandidates(config)
  } catch {
    mdnsCandidates = []
  }
  const candidates = collectCandidates({
    mdnsCandidates,
    manualDsn: config.manualDsn
  })

  if (candidates.length === 0) {
    throw Object.assign(new Error('No gateway discovery candidates were available.'), {
      code: 'no_candidates',
      attempts
    })
  }

  for (const candidate of candidates) {
    const endpointUrl = `http://${candidate.host}:${candidate.port}/v2/gateway/discovery`
    try {
      const response = await httpClient.request(endpointUrl, config.requestTimeoutMs ?? 2000)
      if (response.statusCode !== 200) {
        attempts.push(endpointUrl)
        continue
      }
      let payload
      try {
        payload = JSON.parse(response.bodyText)
      } catch {
        attempts.push(endpointUrl)
        continue
      }
      if (!normalizeText(payload.host) || !normalizeText(payload.version) || !Number.isInteger(payload.port)) {
        attempts.push(endpointUrl)
        continue
      }
      const host = resolveReachableHost(payload.host.trim(), candidate.host.trim())
      const port = payload.port
      return {
        host,
        port,
        version: payload.version.trim(),
        source: candidate.source,
        endpointUrl: `http://${host}:${port}`,
        candidateLabel: candidate.label
      }
    } catch {
      attempts.push(endpointUrl)
    }
  }

  throw Object.assign(new Error('No discovery endpoint returned a valid payload.'), {
    code: 'no_valid_response',
    attempts
  })
}

function formatDiscoverySummary(result) {
  return `source=${result.source} host=${result.host} port=${result.port} version=${result.version}`
}

function formatDiscoveryFailure(error) {
  return error instanceof Error ? error.message : String(error)
}

function mdnsProviderFromCandidates(candidates, fail = false) {
  return {
    async discoverCandidates() {
      if (fail) {
        throw new Error('mDNS unavailable')
      }
      return candidates
    }
  }
}

function httpClientFromMap(map) {
  return {
    async request(url) {
      const entry = map.get(url)
      if (entry instanceof Error) {
        throw entry
      }
      if (entry === undefined) {
        throw new Error(`missing response for ${url}`)
      }
      return entry
    }
  }
}

const mdnsSuccess = await resolveGateway({
  mdnsProvider: mdnsProviderFromCandidates([
    { host: '127.0.0.1', port: 18001, source: 'mdns', label: 'mdns-1' }
  ]),
  httpClient: httpClientFromMap(new Map([
    [
      'http://127.0.0.1:18001/v2/gateway/discovery',
      { statusCode: 200, bodyText: JSON.stringify({ host: '127.0.0.1', port: 18765, version: '2.0.0-alpha.1' }) }
    ]
  ]))
})
assert.equal(mdnsSuccess.source, 'mdns')
assert.equal(mdnsSuccess.port, 18765)
assert.equal(
  formatDiscoverySummary(mdnsSuccess),
  'source=mdns host=127.0.0.1 port=18765 version=2.0.0-alpha.1'
)

const dsnFallback = await resolveGateway({
  mdnsProvider: mdnsProviderFromCandidates([], true),
  httpClient: httpClientFromMap(new Map([
    [
      'http://127.0.0.1:18765/v2/gateway/discovery',
      { statusCode: 200, bodyText: JSON.stringify({ host: '127.0.0.1', port: 18765, version: '2.0.0-alpha.1' }) }
    ]
  ])),
  config: {
    manualDsn: '127.0.0.1:18765'
  }
})
assert.equal(dsnFallback.source, 'manual-dsn')
assert.equal(
  formatDiscoverySummary(dsnFallback),
  'source=manual-dsn host=127.0.0.1 port=18765 version=2.0.0-alpha.1'
)

const loopbackRewrite = await resolveGateway({
  mdnsProvider: mdnsProviderFromCandidates([]),
  httpClient: httpClientFromMap(new Map([
    [
      'http://10.0.2.2:18765/v2/gateway/discovery',
      { statusCode: 200, bodyText: JSON.stringify({ host: '127.0.0.1', port: 18765, version: '2.0.0-alpha.1' }) }
    ]
  ])),
  config: {
    manualDsn: '10.0.2.2:18765'
  }
})
assert.equal(loopbackRewrite.source, 'manual-dsn')
assert.equal(loopbackRewrite.host, '10.0.2.2')
assert.equal(loopbackRewrite.endpointUrl, 'http://10.0.2.2:18765')

const wildcardRewrite = await resolveGateway({
  mdnsProvider: mdnsProviderFromCandidates([
    { host: '10.0.2.2', port: 18004, source: 'mdns', label: 'wildcard-host' }
  ]),
  httpClient: httpClientFromMap(new Map([
    [
      'http://10.0.2.2:18004/v2/gateway/discovery',
      { statusCode: 200, bodyText: JSON.stringify({ host: '0.0.0.0', port: 18765, version: '2.0.0-alpha.1' }) }
    ]
  ]))
})
assert.equal(wildcardRewrite.source, 'mdns')
assert.equal(wildcardRewrite.host, '10.0.2.2')
assert.equal(wildcardRewrite.endpointUrl, 'http://10.0.2.2:18765')

const invalidSkipped = await resolveGateway({
  mdnsProvider: mdnsProviderFromCandidates([
    { host: '127.0.0.1', port: 18002, source: 'mdns', label: 'bad-first' },
    { host: '127.0.0.1', port: 18003, source: 'mdns', label: 'good-second' }
  ]),
  httpClient: httpClientFromMap(new Map([
    [
      'http://127.0.0.1:18002/v2/gateway/discovery',
      { statusCode: 200, bodyText: '{' }
    ],
    [
      'http://127.0.0.1:18003/v2/gateway/discovery',
      { statusCode: 200, bodyText: JSON.stringify({ host: '127.0.0.1', port: 18765, version: '2.0.0-alpha.1' }) }
    ]
  ]))
})
assert.equal(invalidSkipped.port, 18765)
assert.equal(invalidSkipped.candidateLabel, 'good-second')

let failureError
try {
  await resolveGateway({
    mdnsProvider: mdnsProviderFromCandidates([], true),
    httpClient: httpClientFromMap(new Map()),
    config: {
      manualDsn: 'not-a-valid-dsn'
    }
  })
} catch (error) {
  failureError = error
}

assert.ok(failureError)
assert.ok(
  formatDiscoveryFailure(failureError).includes('No gateway discovery candidates were available.')
)

console.log('verify-gateway-discovery: ok')
