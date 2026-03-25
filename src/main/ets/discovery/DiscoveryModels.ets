export type GatewayDiscoverySource = 'mdns' | 'manual-dsn'

export interface GatewayDiscoveryCandidate {
  host: string
  port: number
  source: GatewayDiscoverySource
  label?: string
}

export interface GatewayDiscoveryConfig {
  manualDsn?: string | string[]
  mdnsTimeoutMs?: number
  mdnsContext?: Object
  mdnsServiceType?: string
  mdnsServiceName?: string
  requestTimeoutMs?: number
}

export interface GatewayDiscoveryResponsePayload {
  host: string
  port: number
  version: string
}

export interface GatewayDiscoveryLooseResponse {
  host?: string
  port?: number | string
  version?: string
}

export interface GatewayDiscoveryHostPort {
  host: string
  port: number
}

export interface GatewayDiscoveryResult extends GatewayDiscoveryResponsePayload {
  source: GatewayDiscoverySource
  endpointUrl: string
  candidateLabel?: string
}

export interface GatewayDiscoveryHttpResponse {
  statusCode: number
  bodyText: string
}

export interface GatewayDiscoveryMdnsProvider {
  discoverCandidates(config: GatewayDiscoveryConfig): Promise<GatewayDiscoveryCandidate[]>
}

export interface GatewayDiscoveryHttpClient {
  request(url: string, timeoutMs: number): Promise<GatewayDiscoveryHttpResponse>
}

export type GatewayDiscoveryErrorCode = 'no_candidates' | 'no_valid_response' | 'invalid_manual_dsn'
