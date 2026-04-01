import {
  GatewayDiscoveryCandidate,
  GatewayDiscoveryConfig,
  GatewayDiscoveryHttpClient,
  GatewayDiscoveryMdnsProvider,
  GatewayDiscoveryHostPort,
  GatewayDiscoveryLooseResponse,
  GatewayDiscoveryResponsePayload,
  GatewayDiscoveryResult
} from './DiscoveryModels'
import { NetworkKitGatewayDiscoveryMdnsProvider } from './GatewayDiscoveryMdnsProvider'
import { FetchGatewayDiscoveryHttpClient } from './GatewayDiscoveryHttpClient'
import { GatewayDiscoveryError } from './GatewayDiscoveryErrors'

export class GatewayDiscoveryResolver {
  private readonly mdnsProvider: GatewayDiscoveryMdnsProvider
  private readonly httpClient: GatewayDiscoveryHttpClient

  constructor(
    mdnsProvider: GatewayDiscoveryMdnsProvider = new NetworkKitGatewayDiscoveryMdnsProvider(),
    httpClient: GatewayDiscoveryHttpClient = new FetchGatewayDiscoveryHttpClient()
  ) {
    this.mdnsProvider = mdnsProvider
    this.httpClient = httpClient
  }

  async discover(config: GatewayDiscoveryConfig = {}): Promise<GatewayDiscoveryResult> {
    const candidates = await this.collectCandidates(config)
    const attempts: string[] = []

    for (const candidate of candidates) {
      const endpointUrl = this.makeDiscoveryUrl(candidate.host, candidate.port)
      try {
        const response = await this.httpClient.request(endpointUrl, this.normalizeTimeout(config.requestTimeoutMs))
        const payload = this.parseResponse(response.bodyText)
        if (response.statusCode !== 200 || payload === null) {
          attempts.push(endpointUrl)
          continue
        }

        const resolvedHost = this.resolveReachableHost(payload.host, candidate.host)
        const resolvedPort = payload.port

        return {
          host: resolvedHost,
          port: resolvedPort,
          version: payload.version,
          source: candidate.source,
          endpointUrl: this.makeBaseUrl(resolvedHost, resolvedPort),
          candidateLabel: candidate.label
        }
      } catch (error) {
        attempts.push(endpointUrl)
      }
    }

    if (candidates.length === 0) {
      throw new GatewayDiscoveryError('no_candidates', 'No gateway discovery candidates were available.')
    }

    throw new GatewayDiscoveryError(
      'no_valid_response',
      'No discovery endpoint returned a valid /v2/gateway/discovery payload.',
      attempts
    )
  }

  private async collectCandidates(config: GatewayDiscoveryConfig): Promise<GatewayDiscoveryCandidate[]> {
    const candidates: GatewayDiscoveryCandidate[] = []

    try {
      const mdnsCandidates = await this.mdnsProvider.discoverCandidates(config)
      this.appendCandidates(candidates, mdnsCandidates)
    } catch (_error) {
      // mDNS is best effort; DSN fallback still runs.
    }

    this.appendCandidates(candidates, this.parseManualDsnCandidates(config.manualDsn))
    return candidates
  }

  private appendCandidates(target: GatewayDiscoveryCandidate[], items: GatewayDiscoveryCandidate[]): void {
    for (const item of items) {
      if (this.isValidCandidate(item)) {
        target.push({
          host: item.host.trim(),
          port: item.port,
          source: item.source,
          label: item.label
        })
      }
    }
  }

  private parseManualDsnCandidates(manualDsn: string | string[] | undefined): GatewayDiscoveryCandidate[] {
    const values = this.normalizeManualDsnValues(manualDsn)
    const candidates: GatewayDiscoveryCandidate[] = []

    for (const value of values) {
      const parsed = this.parseManualDsnValue(value)
      if (parsed !== null) {
        candidates.push(parsed)
      }
    }

    return candidates
  }

  private normalizeManualDsnValues(manualDsn: string | string[] | undefined): string[] {
    if (manualDsn === undefined) {
      return []
    }

    if (typeof manualDsn === 'string') {
      return manualDsn.split(',').map((item) => item.trim()).filter((item) => item.length > 0)
    }

    const values: string[] = []
    for (const item of manualDsn) {
      const normalized = item.trim()
      if (normalized.length > 0) {
        values.push(normalized)
      }
    }
    return values
  }

  private parseManualDsnValue(value: string): GatewayDiscoveryCandidate | null {
    const normalized = value.trim()
    if (normalized.length === 0) {
      return null
    }

    const authority = this.extractAuthority(normalized)
    if (authority === null) {
      return null
    }

    const parsed = this.parseHostPort(authority)
    if (parsed === null) {
      return null
    }

    return this.isValidHost(parsed.host) && this.isValidPort(parsed.port)
      ? {
          host: parsed.host,
          port: parsed.port,
          source: 'manual-dsn',
          label: normalized
        }
      : null
  }

  private extractAuthority(value: string): string | null {
    const separatorIndex = value.indexOf('://')
    if (separatorIndex < 0) {
      return value
    }

    let authority = value.substring(separatorIndex + 3)
    const slashIndex = authority.indexOf('/')
    if (slashIndex >= 0) {
      authority = authority.substring(0, slashIndex)
    }

    return this.normalizeText(authority)
  }

  private parseHostPort(value: string): GatewayDiscoveryHostPort | null {
    if (value.indexOf('[') === 0) {
      const end = value.indexOf(']')
      if (end < 0) {
        return null
      }
      const host = value.substring(1, end)
      const colonIndex = value.indexOf(':', end)
      if (colonIndex < 0) {
        return null
      }
      const port = Number(value.substring(colonIndex + 1))
      return this.isValidHost(host) && this.isValidPort(port)
        ? { host: host, port: port }
        : null
    }

    const lastColonIndex = value.lastIndexOf(':')
    if (lastColonIndex <= 0) {
      return null
    }

    const host = value.substring(0, lastColonIndex)
    const port = Number(value.substring(lastColonIndex + 1))
    return this.isValidHost(host) && this.isValidPort(port)
      ? { host: host, port: port }
      : null
  }

  private parseResponse(bodyText: string): GatewayDiscoveryResponsePayload | null {
    try {
      const payload: GatewayDiscoveryLooseResponse = JSON.parse(bodyText) as GatewayDiscoveryLooseResponse
      if (payload === undefined || payload === null) {
        return null
      }

      const host = this.normalizeText(payload.host)
      const version = this.normalizeText(payload.version)
      const port = this.normalizePort(payload.port)

      if (host === null || version === null || !this.isValidPort(port)) {
        return null
      }

      return {
        host: host,
        port: port,
        version: version
      }
    } catch (_error) {
      return null
    }
  }

  private normalizePort(value: number | string | undefined | null): number {
    if (typeof value === 'number') {
      return value
    }

    if (typeof value === 'string') {
      return Number(value)
    }

    return Number.NaN
  }

  private normalizeTimeout(timeoutMs: number | undefined): number {
    if (timeoutMs === undefined || timeoutMs === null) {
      return 2000
    }
    return timeoutMs > 0 ? timeoutMs : 2000
  }

  private makeDiscoveryUrl(host: string, port: number): string {
    return this.makeBaseUrl(host, port) + '/v2/gateway/discovery'
  }

  private makeBaseUrl(host: string, port: number): string {
    return 'http://' + this.formatHostForUrl(host.trim()) + ':' + String(port)
  }

  private formatHostForUrl(host: string): string {
    if (host.indexOf(':') >= 0 && host.indexOf('[') !== 0) {
      return '[' + host + ']'
    }

    return host
  }

  private isValidCandidate(candidate: GatewayDiscoveryCandidate): boolean {
    return this.isValidHost(candidate.host) && this.isValidPort(candidate.port)
  }

  private isValidHost(host: string): boolean {
    return this.normalizeText(host) !== null
  }

  private isValidPort(port: number): boolean {
    return Number.isInteger(port) && port > 0 && port <= 65535
  }

  private normalizeText(value: string | undefined | null): string | null {
    if (value === undefined || value === null) {
      return null
    }
    const trimmed = value.trim()
    return trimmed.length > 0 ? trimmed : null
  }

  private resolveReachableHost(payloadHost: string, candidateHost: string): string {
    const normalizedPayloadHost = payloadHost.trim()
    const normalizedCandidateHost = candidateHost.trim()

    if (!this.isLoopbackOrWildcardHost(normalizedPayloadHost)) {
      return normalizedPayloadHost
    }

    if (this.isWildcardHost(normalizedPayloadHost)) {
      return normalizedCandidateHost.length > 0 ? normalizedCandidateHost : normalizedPayloadHost
    }

    if (!this.isLoopbackOrWildcardHost(normalizedCandidateHost)) {
      return normalizedCandidateHost
    }

    return normalizedPayloadHost
  }

  private isLoopbackOrWildcardHost(host: string): boolean {
    const normalized = host.trim().toLowerCase()
    return normalized === 'localhost' ||
      normalized === '127.0.0.1' ||
      normalized === '0.0.0.0' ||
      normalized === '::1' ||
      normalized === '::'
  }

  private isWildcardHost(host: string): boolean {
    const normalized = host.trim().toLowerCase()
    return normalized === '0.0.0.0' || normalized === '::'
  }
}

export function createGatewayDiscoveryResolver(
  mdnsProvider: GatewayDiscoveryMdnsProvider = new NetworkKitGatewayDiscoveryMdnsProvider(),
  httpClient: GatewayDiscoveryHttpClient = new FetchGatewayDiscoveryHttpClient()
): GatewayDiscoveryResolver {
  return new GatewayDiscoveryResolver(mdnsProvider, httpClient)
}
