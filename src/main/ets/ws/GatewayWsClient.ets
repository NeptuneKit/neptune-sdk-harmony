import { webSocket } from '@kit.NetworkKit'
import { HarmonyLogLevel } from 'harmony-log'

import {
  DEFAULT_GATEWAY_WS_APP_ID,
  DEFAULT_GATEWAY_WS_HEARTBEAT_INTERVAL_MS,
  DEFAULT_GATEWAY_WS_HEARTBEAT_TIMEOUT_MS,
  DEFAULT_GATEWAY_WS_DEVICE_ID,
  DEFAULT_GATEWAY_WS_PLATFORM,
  DEFAULT_GATEWAY_WS_RECONNECT_DELAYS_MS,
  DEFAULT_GATEWAY_WS_SESSION_ID,
  GatewayWsClientOptions,
  GatewayWsClientSnapshot,
  GatewayWsCommandAckFrame,
  GatewayWsCommandDispatchFrame,
  GatewayWsConnectionState,
  GatewayWsFrame,
  GatewayWsHeartbeatFrame,
  GatewayWsHelloFrame
} from './GatewayWsModels'
import { createNeptuneHarmonyLogger, createNeptuneHarmonyMetadata, setNeptuneHarmonyMetadata } from '../logging'

export class GatewayWsClient {
  private readonly logger = createNeptuneHarmonyLogger(
    'Neptune.WS.Client',
    HarmonyLogLevel.INFO
  )
  private socket: webSocket.WebSocket | null = null
  private endpointUrl: string | null = null
  private state: GatewayWsConnectionState = 'idle'
  private running: boolean = false
  private connectionGeneration: number = 0
  private reconnectAttempt: number = 0
  private lastActivityAtMs: number = 0
  private lastError: string | null = null
  private heartbeatTimerId: number | null = null
  private heartbeatWatchdogTimerId: number | null = null
  private reconnectTimerId: number | null = null
  private readonly heartbeatIntervalMs: number
  private readonly heartbeatTimeoutMs: number
  private readonly reconnectDelaysMs: number[]
  private readonly platform: string
  private readonly appId: string
  private readonly sessionId: string
  private readonly deviceId: string

  constructor(options: GatewayWsClientOptions = {}) {
    this.platform = this.normalizeText(options.platform, DEFAULT_GATEWAY_WS_PLATFORM)
    this.appId = this.normalizeText(options.appId, DEFAULT_GATEWAY_WS_APP_ID)
    this.sessionId = this.normalizeText(options.sessionId, DEFAULT_GATEWAY_WS_SESSION_ID)
    this.deviceId = this.normalizeText(options.deviceId, DEFAULT_GATEWAY_WS_DEVICE_ID)
    this.heartbeatIntervalMs = this.normalizePositiveMs(
      options.heartbeatIntervalMs,
      DEFAULT_GATEWAY_WS_HEARTBEAT_INTERVAL_MS
    )
    this.heartbeatTimeoutMs = this.normalizePositiveMs(
      options.heartbeatTimeoutMs,
      DEFAULT_GATEWAY_WS_HEARTBEAT_TIMEOUT_MS
    )
    this.reconnectDelaysMs = this.normalizeReconnectDelays(options.reconnectDelaysMs)
  }

  async start(endpointUrl: string): Promise<void> {
    this.running = true
    await this.setGatewayEndpoint(endpointUrl)
  }

  async setGatewayEndpoint(endpointUrl: string): Promise<void> {
    const normalizedEndpointUrl = this.normalizeEndpointUrl(endpointUrl)
    if (normalizedEndpointUrl === null) {
      throw new Error('GatewayWsClient requires a non-empty endpointUrl.')
    }

    this.running = true
    if (this.endpointUrl === normalizedEndpointUrl && this.state === 'open' && this.socket !== null) {
      return
    }

    this.endpointUrl = normalizedEndpointUrl
    await this.connectNow('endpoint change', true)
  }

  async reconnect(): Promise<void> {
    if (this.endpointUrl === null) {
      return
    }

    await this.connectNow('manual reconnect', true)
  }

  async stop(): Promise<void> {
    this.running = false
    this.connectionGeneration += 1
    this.clearReconnectTimer()
    this.clearHeartbeatTimer()
    this.clearHeartbeatWatchdogTimer()
    await this.closeSocket()
    this.state = 'closed'
    this.reconnectAttempt = 0
  }

  snapshot(): GatewayWsClientSnapshot {
    return {
      state: this.state,
      endpointUrl: this.endpointUrl,
      lastActivityAt: this.lastActivityAtMs > 0 ? new Date(this.lastActivityAtMs).toISOString() : null,
      reconnectAttempt: this.reconnectAttempt,
      lastError: this.lastError
    }
  }

  private async connectNow(reason: string, resetReconnectAttempt: boolean): Promise<void> {
    const endpointUrl = this.endpointUrl
    if (endpointUrl === null) {
      throw new Error('GatewayWsClient endpointUrl is not configured.')
    }

    if (resetReconnectAttempt) {
      this.reconnectAttempt = 0
    }

    this.connectionGeneration += 1
    const generation = this.connectionGeneration
    this.clearReconnectTimer()
    this.clearHeartbeatTimer()
    this.clearHeartbeatWatchdogTimer()
    await this.closeSocket()
    this.state = this.running ? 'connecting' : 'idle'
    this.lastError = null

    const socket = webSocket.createWebSocket()
    this.socket = socket
    this.bindSocket(socket, generation)

    try {
      const connected = await socket.connect(this.makeWebSocketUrl(endpointUrl))
      if (!connected) {
        this.handleSocketFailure(generation, `${reason}: connect returned false.`)
      }
    } catch (error) {
      this.handleSocketFailure(generation, this.errorMessage(error))
    }
  }

  private bindSocket(socket: webSocket.WebSocket, generation: number): void {
    socket.on('open', (_err: Object, _result: Object) => {
      if (!this.isCurrentGeneration(generation)) {
        return
      }
      this.onSocketOpen(generation)
    })

    socket.on('message', (_err: Object, payload: string | ArrayBuffer) => {
      if (!this.isCurrentGeneration(generation)) {
        return
      }
      this.onSocketMessage(payload)
    })

    socket.on('close', (_err: Object, _result: webSocket.CloseResult) => {
      if (!this.isCurrentGeneration(generation)) {
        return
      }
      this.onSocketClose('socket closed')
    })

    socket.on('error', (_error: Object) => {
      if (!this.isCurrentGeneration(generation)) {
        return
      }
      this.onSocketClose('socket error')
    })
  }

  private onSocketOpen(generation: number): void {
    this.state = 'open'
    this.lastActivityAtMs = Date.now()
    this.lastError = null
    this.reconnectAttempt = 0
    this.startHeartbeatTimers(generation)
    void this.sendFrame({
      type: 'hello',
      role: 'sdk',
      platform: this.platform,
      appId: this.appId,
      sessionId: this.sessionId,
      deviceId: this.deviceId,
      timestamp: new Date().toISOString()
    })
    const metadata = createNeptuneHarmonyMetadata()
    setNeptuneHarmonyMetadata(metadata, 'endpoint', this.endpointUrl ?? '')
    this.logger.info('gateway ws connected', metadata)
  }

  private onSocketMessage(payload: string | ArrayBuffer): void {
    this.lastActivityAtMs = Date.now()
    this.startHeartbeatWatchdogTimer()

    if (typeof payload !== 'string') {
      return
    }

    let frame: GatewayWsFrame | null = null
    try {
      frame = JSON.parse(payload) as GatewayWsFrame
    } catch (_error) {
      return
    }

    if (frame === null || frame === undefined) {
      return
    }

    if (frame.type === 'command.dispatch') {
      const dispatchFrame = frame as GatewayWsCommandDispatchFrame
      if (dispatchFrame.command === 'ping') {
        void this.sendFrame(this.makePingAckFrame(dispatchFrame))
      }
      return
    }
  }

  private onSocketClose(detail: string): void {
    this.clearHeartbeatTimer()
    this.clearHeartbeatWatchdogTimer()
    this.socket = null
    if (!this.running || this.endpointUrl === null) {
      this.state = 'closed'
      return
    }

    this.state = 'reconnecting'
    this.lastError = detail
    this.scheduleReconnect(detail)
  }

  private handleSocketFailure(generation: number, detail: string): void {
    if (!this.isCurrentGeneration(generation)) {
      return
    }

    this.clearHeartbeatTimer()
    this.clearHeartbeatWatchdogTimer()
    this.socket = null
    this.state = this.running ? 'reconnecting' : 'closed'
    this.lastError = detail
    if (this.running && this.endpointUrl !== null) {
      this.scheduleReconnect(detail)
    }
  }

  private startHeartbeatTimers(generation: number): void {
    this.clearHeartbeatTimer()
    this.clearHeartbeatWatchdogTimer()
    this.heartbeatTimerId = setInterval(() => {
      if (!this.isCurrentGeneration(generation) || !this.running) {
        return
      }
      void this.sendHeartbeat()
    }, this.heartbeatIntervalMs)
    this.startHeartbeatWatchdogTimer()
  }

  private startHeartbeatWatchdogTimer(): void {
    this.clearHeartbeatWatchdogTimer()
    this.heartbeatWatchdogTimerId = setTimeout(() => {
      if (!this.running || this.endpointUrl === null) {
        return
      }

      if (Date.now() - this.lastActivityAtMs >= this.heartbeatTimeoutMs) {
        this.lastError = `no websocket activity for ${this.heartbeatTimeoutMs}ms`
        void this.restartAfterTimeout()
      } else {
        this.startHeartbeatWatchdogTimer()
      }
    }, this.heartbeatTimeoutMs)
  }

  private async restartAfterTimeout(): Promise<void> {
    this.state = 'reconnecting'
    await this.closeSocket()
    this.scheduleReconnect(this.lastError ?? 'heartbeat timeout')
  }

  private async sendHeartbeat(): Promise<void> {
    await this.sendFrame({
      type: 'heartbeat',
      timestamp: new Date().toISOString()
    })
  }

  private async sendFrame(frame: GatewayWsFrame): Promise<void> {
    const socket = this.socket
    if (socket === null || !this.running) {
      return
    }

    try {
      await socket.send(JSON.stringify(frame))
    } catch (error) {
      this.handleSocketFailure(this.connectionGeneration, this.errorMessage(error))
    }
  }

  private scheduleReconnect(detail: string): void {
    if (!this.running || this.endpointUrl === null) {
      return
    }

    this.clearReconnectTimer()
    const delayMs = this.nextReconnectDelay()
    this.state = 'reconnecting'
    this.reconnectTimerId = setTimeout(() => {
      this.reconnectTimerId = null
      void this.connectNow(detail, false)
    }, delayMs)
  }

  private nextReconnectDelay(): number {
    const index = this.reconnectAttempt < this.reconnectDelaysMs.length
      ? this.reconnectAttempt
      : this.reconnectDelaysMs.length - 1
    this.reconnectAttempt += 1
    return this.reconnectDelaysMs[index]
  }

  private async closeSocket(): Promise<void> {
    const socket = this.socket
    this.socket = null
    if (socket === null) {
      return
    }

    try {
      await socket.close({ code: 1000, reason: 'gateway websocket stopped' })
    } catch (_error) {
      // Closing a socket can fail during reconnect races; ignore and let the new socket win.
    }
  }

  private clearHeartbeatTimer(): void {
    if (this.heartbeatTimerId === null) {
      return
    }
    clearInterval(this.heartbeatTimerId)
    this.heartbeatTimerId = null
  }

  private clearHeartbeatWatchdogTimer(): void {
    if (this.heartbeatWatchdogTimerId === null) {
      return
    }
    clearTimeout(this.heartbeatWatchdogTimerId)
    this.heartbeatWatchdogTimerId = null
  }

  private clearReconnectTimer(): void {
    if (this.reconnectTimerId === null) {
      return
    }
    clearTimeout(this.reconnectTimerId)
    this.reconnectTimerId = null
  }

  private isCurrentGeneration(generation: number): boolean {
    return generation === this.connectionGeneration
  }

  private makeWebSocketUrl(endpointUrl: string): string {
    const baseUrl = this.normalizeEndpointUrl(endpointUrl)
    if (baseUrl === null) {
      throw new Error('GatewayWsClient cannot build websocket url from an empty endpoint.')
    }

    if (baseUrl.startsWith('ws://') || baseUrl.startsWith('wss://')) {
      return this.appendWsPath(baseUrl)
    }

    if (baseUrl.startsWith('https://')) {
      return this.appendWsPath('wss://' + baseUrl.substring('https://'.length))
    }

    if (baseUrl.startsWith('http://')) {
      return this.appendWsPath('ws://' + baseUrl.substring('http://'.length))
    }

    return this.appendWsPath('ws://' + baseUrl)
  }

  private appendWsPath(baseUrl: string): string {
    return baseUrl.endsWith('/') ? `${baseUrl}v2/ws` : `${baseUrl}/v2/ws`
  }

  private normalizeEndpointUrl(endpointUrl: string): string | null {
    const trimmed = endpointUrl.trim()
    return trimmed.length > 0 ? trimmed : null
  }

  private normalizePositiveMs(value: number | undefined, fallback: number): number {
    if (value === undefined || !Number.isFinite(value) || value <= 0) {
      return fallback
    }
    return Math.floor(value)
  }

  private normalizeText(value: string | undefined, fallback: string): string {
    if (value === undefined) {
      return fallback
    }

    const trimmed = value.trim()
    return trimmed.length > 0 ? trimmed : fallback
  }

  private normalizeReconnectDelays(value: number[] | undefined): number[] {
    if (value === undefined || value.length === 0) {
      return DEFAULT_GATEWAY_WS_RECONNECT_DELAYS_MS.slice()
    }

    const delays: number[] = []
    for (const item of value) {
      if (Number.isFinite(item) && item > 0) {
        delays.push(Math.floor(item))
      }
    }

    return delays.length > 0 ? delays : DEFAULT_GATEWAY_WS_RECONNECT_DELAYS_MS.slice()
  }

  private errorMessage(error: string | Object): string {
    if (error instanceof Error) {
      return error.message
    }

    if (typeof error === 'string') {
      return error
    }

    return String(error)
  }

  private makePingAckFrame(frame: GatewayWsCommandDispatchFrame): GatewayWsCommandAckFrame {
    return {
      type: 'command.ack',
      command: frame.command,
      requestId: frame.requestId,
      status: 'ok',
      message: 'ping acknowledged',
      timestamp: new Date().toISOString()
    }
  }
}
