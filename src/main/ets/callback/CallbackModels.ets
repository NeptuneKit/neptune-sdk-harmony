import { Platform } from '../model/LogModels'

export interface GatewayClientCommandRequest {
  requestId?: string
  command?: string
  version?: number | string
  payload?: ESObject
}

export interface GatewayClientCommandAck {
  requestId: string
  command: string
  status: 'ok' | 'error'
  message?: string
  timestamp: string
}

export interface GatewayClientRegistrationPayload {
  platform: Platform
  appId: string
  deviceId: string
  sessionId?: string
  callbackBaseUrl: string
  callbackPath: string
  registerPath: string
  sdkName: string
  sdkVersion: string
  registeredAt: string
  renewSequence: number
}

export interface GatewayClientRegistrationResult {
  state: 'success' | 'failed'
  title: string
  detail: string
  timestamp: string
}

export interface GatewayClientCallbackOptions {
  listenAddress?: string
  listenPort?: number
  advertisedHost?: string
  renewIntervalMs?: number
  requestTimeoutMs?: number
  platform?: Platform
  appId?: string
  deviceId?: string
  sessionId?: string
  sdkName?: string
  sdkVersion?: string
}

