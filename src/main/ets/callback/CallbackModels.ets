import { Platform } from '../model/LogModels'

export type BusDirection = 'cli_to_client' | 'client_to_cli'
export type BusKind = 'command' | 'event' | 'log'
export type BusAckStatus = 'ok' | 'error'

export interface GatewayBusEvent {
  name: string
  attributes?: ESObject
}

export interface GatewayClientBusEnvelope {
  requestId?: string
  direction: BusDirection
  kind: BusKind
  command?: string
  event?: GatewayBusEvent
  logRecord?: ESObject
  timestamp?: string
}

export interface GatewayClientCommandAck {
  requestId?: string
  command?: string
  status: BusAckStatus
  message?: string
  timestamp: string
}

export interface GatewayClientUSBMuxdHint {
  deviceID: number
  socketPath?: string
}

export interface GatewayClientRegistrationPayload {
  platform: Platform
  appId: string
  deviceId: string
  sessionId?: string
  callbackEndpoint: string
  preferredTransports: string[]
  usbmuxdHint?: GatewayClientUSBMuxdHint
  sdkName: string
  sdkVersion: string
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
