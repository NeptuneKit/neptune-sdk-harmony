import { socket } from '@kit.NetworkKit'

import { ExportServer } from '../server/ExportServer'
import { Platform } from '../model/LogModels'
import {
  GatewayClientCallbackOptions,
  GatewayClientRegistrationPayload,
  GatewayClientRegistrationResult
} from './CallbackModels'
import { GatewayClientRegistrationHttpClient } from './GatewayClientRegistrationHttpClient'

const DEFAULT_CALLBACK_LISTEN_ADDRESS = '0.0.0.0'
const DEFAULT_CALLBACK_ADVERTISED_HOST = '127.0.0.1'
const DEFAULT_CALLBACK_LISTEN_PORT = 0
const DEFAULT_CALLBACK_RENEW_INTERVAL_MS = 30000
const DEFAULT_CALLBACK_REQUEST_TIMEOUT_MS = 2000
const DEFAULT_CALLBACK_COMMAND_PATH = '/v2/client/command'
const DEFAULT_CALLBACK_REGISTER_PATH = '/v2/clients:register'

export class GatewayClientCallbackManager {
  private readonly exportServer: ExportServer
  private readonly registrationClient: GatewayClientRegistrationHttpClient
  private readonly renewIntervalMs: number
  private readonly requestTimeoutMs: number
  private readonly listenAddress: string
  private readonly listenPort: number
  private readonly advertisedHost: string | null
  private readonly platform: Platform
  private readonly appId: string
  private readonly deviceId: string
  private readonly sessionId: string | null
  private readonly sdkName: string
  private readonly sdkVersion: string
  private gatewayEndpointUrl: string | null = null
  private listeningPort: number | null = null
  private renewTimerId: number | null = null
  private renewSequence: number = 0
  private started: boolean = false

  constructor(
    exportServer: ExportServer = new ExportServer(),
    registrationClient: GatewayClientRegistrationHttpClient = new GatewayClientRegistrationHttpClient(),
    options: GatewayClientCallbackOptions = {}
  ) {
    this.exportServer = exportServer
    this.registrationClient = registrationClient
    this.renewIntervalMs = this.normalizePositiveMs(options.renewIntervalMs, DEFAULT_CALLBACK_RENEW_INTERVAL_MS)
    this.requestTimeoutMs = this.normalizePositiveMs(options.requestTimeoutMs, DEFAULT_CALLBACK_REQUEST_TIMEOUT_MS)
    this.listenAddress = this.normalizeText(options.listenAddress, DEFAULT_CALLBACK_LISTEN_ADDRESS)
    this.listenPort = this.normalizePort(options.listenPort, DEFAULT_CALLBACK_LISTEN_PORT)
    this.advertisedHost = this.normalizeOptionalText(options.advertisedHost) ?? null
    this.platform = this.normalizePlatform(options.platform, 'harmony')
    this.appId = this.normalizeText(options.appId, 'neptune-sdk-harmony')
    this.deviceId = this.normalizeText(options.deviceId, 'default-device')
    this.sessionId = this.normalizeOptionalText(options.sessionId) ?? null
    this.sdkName = this.normalizeText(options.sdkName, 'neptune-sdk-harmony')
    this.sdkVersion = this.normalizeText(options.sdkVersion, '0.1.0')
  }

  async start(): Promise<socket.NetAddress | null> {
    if (this.started) {
      return this.currentAddress()
    }

    this.started = true
    try {
      const address = await this.exportServer.start(this.listenPort, this.listenAddress)
      if (address !== null) {
        this.listeningPort = this.normalizePort(address.port, this.listenPort)
      }
      this.refreshRenewTimer()
      void this.registerNow('start')
      return address
    } catch (error) {
      this.started = false
      this.listeningPort = null
      if (error instanceof Error) {
        throw error
      }
      throw new Error(String(error))
    }
  }

  async stop(): Promise<void> {
    this.clearRenewTimer()
    this.gatewayEndpointUrl = null
    this.listeningPort = null
    this.started = false
    await this.exportServer.stop()
  }

  async setGatewayEndpoint(endpointUrl: string): Promise<GatewayClientRegistrationResult | null> {
    const normalizedEndpointUrl = this.normalizeEndpointUrl(endpointUrl)
    if (normalizedEndpointUrl === null) {
      return null
    }

    this.gatewayEndpointUrl = normalizedEndpointUrl
    return await this.registerNow('endpoint change')
  }

  async registerNow(reason: string = 'manual'): Promise<GatewayClientRegistrationResult | null> {
    const endpointUrl = this.gatewayEndpointUrl
    const callbackBaseUrl = this.callbackBaseUrl()
    if (endpointUrl === null || callbackBaseUrl === null) {
      return null
    }

    const payload = this.makeRegistrationPayload(callbackBaseUrl)
    const result = await this.registrationClient.register(endpointUrl, payload, this.requestTimeoutMs)
    if (result.state === 'success') {
      console.info(
        `GatewayClientCallbackManager register ok reason=${reason} endpoint=${endpointUrl} callback=${callbackBaseUrl}`
      )
      this.refreshRenewTimer()
      return result
    }

    console.error(
      `GatewayClientCallbackManager register failed reason=${reason} endpoint=${endpointUrl} callback=${callbackBaseUrl}`
    )
    return result
  }

  snapshot(): ESObject {
    return {
      started: this.started,
      listenAddress: this.listenAddress,
      listeningPort: this.listeningPort,
      callbackBaseUrl: this.callbackBaseUrl(),
      gatewayEndpointUrl: this.gatewayEndpointUrl,
      renewIntervalMs: this.renewIntervalMs,
      renewSequence: this.renewSequence
    }
  }

  private currentAddress(): socket.NetAddress | null {
    if (this.listeningPort === null) {
      return null
    }

    return {
      address: this.listenAddress,
      family: 1,
      port: this.listeningPort
    }
  }

  private refreshRenewTimer(): void {
    this.clearRenewTimer()
    if (this.gatewayEndpointUrl === null || this.listeningPort === null) {
      return
    }

    this.renewTimerId = setInterval(() => {
      void this.registerNow('renewal')
    }, this.renewIntervalMs) as number
  }

  private clearRenewTimer(): void {
    if (this.renewTimerId === null) {
      return
    }

    clearInterval(this.renewTimerId)
    this.renewTimerId = null
  }

  private makeRegistrationPayload(callbackBaseUrl: string): GatewayClientRegistrationPayload {
    this.renewSequence += 1
    return {
      platform: this.platform,
      appId: this.appId,
      deviceId: this.deviceId,
      sessionId: this.sessionId ?? undefined,
      callbackBaseUrl,
      callbackPath: DEFAULT_CALLBACK_COMMAND_PATH,
      registerPath: DEFAULT_CALLBACK_REGISTER_PATH,
      sdkName: this.sdkName,
      sdkVersion: this.sdkVersion,
      registeredAt: new Date().toISOString(),
      renewSequence: this.renewSequence
    }
  }

  private callbackBaseUrl(): string | null {
    const port = this.listeningPort
    if (port === null || port <= 0) {
      return null
    }

    const host = this.resolveCallbackHost()
    return `http://${this.formatHostForUrl(host)}:${String(port)}`
  }

  private resolveCallbackHost(): string {
    const advertisedHost = this.advertisedHost
    if (advertisedHost !== null) {
      return advertisedHost
    }

    if (this.isLoopbackOrWildcardHost(this.listenAddress)) {
      return DEFAULT_CALLBACK_ADVERTISED_HOST
    }

    return this.listenAddress
  }

  private normalizeEndpointUrl(value: string): string | null {
    const normalized = value.trim()
    return normalized.length > 0 ? normalized : null
  }

  private normalizeText(value: string | number | undefined | null, fallback: string): string {
    if (value === undefined || value === null) {
      return fallback
    }

    const normalized = String(value).trim()
    return normalized.length > 0 ? normalized : fallback
  }

  private normalizePlatform(value: Platform | undefined | null, fallback: Platform): Platform {
    if (value === undefined || value === null) {
      return fallback
    }

    const normalized = String(value).trim().toLowerCase()
    switch (normalized) {
      case 'ios':
        return 'ios'
      case 'android':
        return 'android'
      case 'harmony':
        return 'harmony'
      case 'web':
        return 'web'
      default:
        return fallback
    }
  }

  private normalizeOptionalText(value: string | undefined | null): string | undefined {
    if (value === undefined || value === null) {
      return undefined
    }

    const normalized = value.trim()
    return normalized.length > 0 ? normalized : undefined
  }

  private normalizePositiveMs(value: number | undefined, fallback: number): number {
    if (value === undefined || value === null || !Number.isFinite(value)) {
      return fallback
    }

    const normalized = Math.trunc(value)
    return normalized > 0 ? normalized : fallback
  }

  private normalizePort(value: number | undefined, fallback: number): number {
    if (value === undefined || value === null || !Number.isFinite(value)) {
      return fallback
    }

    const normalized = Math.trunc(value)
    return normalized >= 0 && normalized <= 65535 ? normalized : fallback
  }

  private isLoopbackOrWildcardHost(host: string): boolean {
    const normalized = host.trim().toLowerCase()
    return normalized === 'localhost' ||
      normalized === '127.0.0.1' ||
      normalized === '0.0.0.0' ||
      normalized === '::1' ||
      normalized === '::' ||
      normalized === '*'
  }

  private formatHostForUrl(host: string): string {
    if (host.indexOf(':') >= 0 && host.indexOf('[') !== 0) {
      return `[${host}]`
    }

    return host
  }
}
