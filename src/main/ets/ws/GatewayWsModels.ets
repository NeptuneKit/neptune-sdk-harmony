import { GatewayDiscoveryConfig } from '../discovery'

export type GatewayWsConnectionState = 'idle' | 'connecting' | 'open' | 'reconnecting' | 'closed' | 'failed'

export interface GatewayWsHelloFrame {
  type: 'hello'
  role: 'sdk'
  platform: string
  appId: string
  sessionId: string
  deviceId: string
  timestamp: string
}

export interface GatewayWsHeartbeatFrame {
  type: 'heartbeat'
  timestamp: string
}

export interface GatewayWsCommandDispatchFrame {
  type: 'command.dispatch'
  command: string
  requestId?: string
  payload?: ESObject
}

export interface GatewayWsCommandAckFrame {
  type: 'command.ack'
  command: string
  requestId?: string
  status: 'ok' | 'error'
  message?: string
  timestamp: string
}

export interface GatewayWsStatusFrame {
  type: 'status'
  state: GatewayWsConnectionState
  endpointUrl?: string
  detail?: string
}

export interface GatewayWsFrameBase {
  type: string
}

export type GatewayWsFrame =
  | GatewayWsHelloFrame
  | GatewayWsHeartbeatFrame
  | GatewayWsCommandDispatchFrame
  | GatewayWsCommandAckFrame
  | GatewayWsStatusFrame
  | GatewayWsFrameBase

export interface GatewayWsClientOptions {
  platform?: string
  appId?: string
  sessionId?: string
  deviceId?: string
  heartbeatIntervalMs?: number
  heartbeatTimeoutMs?: number
  reconnectDelaysMs?: number[]
}

export interface GatewayWsClientSnapshot {
  state: GatewayWsConnectionState
  endpointUrl: string | null
  lastActivityAt: string | null
  reconnectAttempt: number
  lastError: string | null
}

export interface GatewayWsManagerSnapshot extends GatewayWsClientSnapshot {
  manualDsn: string | string[] | undefined
}

export interface GatewayWsDiscoveryConfig extends GatewayDiscoveryConfig {}

export const DEFAULT_GATEWAY_WS_PLATFORM = 'harmony'
export const DEFAULT_GATEWAY_WS_APP_ID = 'neptune-sdk-harmony'
export const DEFAULT_GATEWAY_WS_SESSION_ID = 'default-session'
export const DEFAULT_GATEWAY_WS_DEVICE_ID = 'default-device'
export const DEFAULT_GATEWAY_WS_HEARTBEAT_INTERVAL_MS = 15000
export const DEFAULT_GATEWAY_WS_HEARTBEAT_TIMEOUT_MS = 45000
export const DEFAULT_GATEWAY_WS_RECONNECT_DELAYS_MS = [500, 1000, 2000, 4000, 8000]
