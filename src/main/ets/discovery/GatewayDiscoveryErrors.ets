import { GatewayDiscoveryErrorCode } from './DiscoveryModels'

export class GatewayDiscoveryError extends Error {
  readonly code: GatewayDiscoveryErrorCode
  readonly attempts: string[]

  constructor(code: GatewayDiscoveryErrorCode, message: string, attempts: string[] = []) {
    super(message)
    this.name = 'GatewayDiscoveryError'
    this.code = code
    this.attempts = attempts.slice()
  }
}

