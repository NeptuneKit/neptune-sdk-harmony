import {
  GatewayDiscoveryConfig,
  GatewayDiscoveryError,
  GatewayDiscoveryResult,
  GatewayDiscoveryResolver,
  createGatewayDiscoveryResolver
} from '../discovery'
import { GatewayWsClient } from './GatewayWsClient'
import { GatewayWsClientSnapshot, GatewayWsManagerSnapshot } from './GatewayWsModels'
import { HarmonyLogLevel } from 'harmony-log'
import { createNeptuneHarmonyLogger, createNeptuneHarmonyMetadata, setNeptuneHarmonyMetadata } from '../logging'

export class GatewayWsManager {
  private readonly logger = createNeptuneHarmonyLogger(
    'Neptune.WS.Manager',
    HarmonyLogLevel.INFO
  )
  private readonly discoveryResolver: GatewayDiscoveryResolver
  private readonly wsClient: GatewayWsClient
  private discoveryConfig: GatewayDiscoveryConfig = {}
  private lastResolvedGateway: GatewayDiscoveryResult | null = null

  constructor(
    discoveryResolver: GatewayDiscoveryResolver = createGatewayDiscoveryResolver(),
    wsClient: GatewayWsClient = new GatewayWsClient()
  ) {
    this.discoveryResolver = discoveryResolver
    this.wsClient = wsClient
  }

  async start(config: GatewayDiscoveryConfig = {}): Promise<GatewayDiscoveryResult | null> {
    this.discoveryConfig = this.mergeDiscoveryConfig(config)
    return this.discoverGateway(this.discoveryConfig)
  }

  async discoverGateway(config: GatewayDiscoveryConfig = {}): Promise<GatewayDiscoveryResult | null> {
    this.discoveryConfig = this.mergeDiscoveryConfig(config)
    try {
      const result = await this.discoveryResolver.discover(this.discoveryConfig)
      await this.setGatewayEndpoint(result.endpointUrl)
      this.lastResolvedGateway = result
      return result
    } catch (error) {
      if (error instanceof GatewayDiscoveryError && error.attempts.length > 0) {
        const metadata = createNeptuneHarmonyMetadata()
        setNeptuneHarmonyMetadata(metadata, 'error', error.message)
        setNeptuneHarmonyMetadata(metadata, 'attempts', error.attempts.join(','))
        this.logger.error(
          'gateway ws discovery failed with attempts',
          metadata
        )
      } else {
        const metadata = createNeptuneHarmonyMetadata()
        setNeptuneHarmonyMetadata(metadata, 'error', error instanceof Error ? error.message : String(error))
        this.logger.error(
          'gateway ws discovery failed',
          metadata
        )
      }
      return null
    }
  }

  async setGatewayEndpoint(endpointUrl: string): Promise<void> {
    const nextEndpointUrl = endpointUrl.trim()
    if (nextEndpointUrl.length === 0) {
      return
    }

    const currentEndpointUrl = this.lastResolvedGateway?.endpointUrl ?? null
    if (currentEndpointUrl === nextEndpointUrl) {
      await this.wsClient.setGatewayEndpoint(nextEndpointUrl)
      return
    }

    this.lastResolvedGateway = {
      host: this.extractHost(nextEndpointUrl),
      port: this.extractPort(nextEndpointUrl),
      version: this.lastResolvedGateway?.version ?? 'unknown',
      source: this.lastResolvedGateway?.source ?? 'manual-dsn',
      endpointUrl: nextEndpointUrl,
      candidateLabel: this.lastResolvedGateway?.candidateLabel
    }
    await this.wsClient.setGatewayEndpoint(nextEndpointUrl)
  }

  async reconnect(): Promise<void> {
    if (!this.hasDiscoveryOverrides(this.discoveryConfig)) {
      await this.wsClient.reconnect()
      return
    }

    await this.discoverGateway(this.discoveryConfig)
  }

  async stop(): Promise<void> {
    await this.wsClient.stop()
  }

  snapshot(): GatewayWsManagerSnapshot {
    const clientSnapshot: GatewayWsClientSnapshot = this.wsClient.snapshot()
    return {
      state: clientSnapshot.state,
      endpointUrl: clientSnapshot.endpointUrl,
      lastActivityAt: clientSnapshot.lastActivityAt,
      reconnectAttempt: clientSnapshot.reconnectAttempt,
      lastError: clientSnapshot.lastError,
      manualDsn: this.discoveryConfig.manualDsn
    }
  }

  private mergeDiscoveryConfig(config: GatewayDiscoveryConfig): GatewayDiscoveryConfig {
    return {
      manualDsn: config.manualDsn ?? this.discoveryConfig.manualDsn,
      mdnsTimeoutMs: config.mdnsTimeoutMs ?? this.discoveryConfig.mdnsTimeoutMs,
      mdnsContext: config.mdnsContext ?? this.discoveryConfig.mdnsContext,
      mdnsServiceType: config.mdnsServiceType ?? this.discoveryConfig.mdnsServiceType,
      mdnsServiceName: config.mdnsServiceName ?? this.discoveryConfig.mdnsServiceName,
      requestTimeoutMs: config.requestTimeoutMs ?? this.discoveryConfig.requestTimeoutMs
    }
  }

  private hasDiscoveryOverrides(config: GatewayDiscoveryConfig): boolean {
    return config.manualDsn !== undefined ||
      config.mdnsTimeoutMs !== undefined ||
      config.mdnsContext !== undefined ||
      config.mdnsServiceType !== undefined ||
      config.mdnsServiceName !== undefined ||
      config.requestTimeoutMs !== undefined
  }

  private extractHost(endpointUrl: string): string {
    const normalized = endpointUrl.trim()
    const withoutScheme = normalized.replace(/^https?:\/\//, '')
    const slashIndex = withoutScheme.indexOf('/')
    const hostPort = slashIndex >= 0 ? withoutScheme.substring(0, slashIndex) : withoutScheme
    const colonIndex = hostPort.lastIndexOf(':')
    return colonIndex > 0 ? hostPort.substring(0, colonIndex) : hostPort
  }

  private extractPort(endpointUrl: string): number {
    const normalized = endpointUrl.trim()
    const withoutScheme = normalized.replace(/^https?:\/\//, '')
    const slashIndex = withoutScheme.indexOf('/')
    const hostPort = slashIndex >= 0 ? withoutScheme.substring(0, slashIndex) : withoutScheme
    const colonIndex = hostPort.lastIndexOf(':')
    if (colonIndex < 0) {
      return 0
    }
    const parsed = Number(hostPort.substring(colonIndex + 1))
    return Number.isFinite(parsed) ? parsed : 0
  }
}
