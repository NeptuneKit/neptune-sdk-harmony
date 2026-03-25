import { mdns } from '@kit.NetworkKit'

import { GatewayDiscoveryCandidate, GatewayDiscoveryConfig, GatewayDiscoveryMdnsProvider } from './DiscoveryModels'

export class EmptyGatewayDiscoveryMdnsProvider implements GatewayDiscoveryMdnsProvider {
  async discoverCandidates(_config: GatewayDiscoveryConfig): Promise<GatewayDiscoveryCandidate[]> {
    return []
  }
}

const DEFAULT_MDNS_SERVICE_TYPE = '_neptune._tcp'
const DEFAULT_MDNS_TIMEOUT_MS = 2000
const MIN_MDNS_TIMEOUT_MS = 200
const MAX_MDNS_TIMEOUT_MS = 10000

export class NetworkKitGatewayDiscoveryMdnsProvider implements GatewayDiscoveryMdnsProvider {
  async discoverCandidates(config: GatewayDiscoveryConfig): Promise<GatewayDiscoveryCandidate[]> {
    const context = config.mdnsContext
    if (context === undefined || context === null) {
      return []
    }

    const serviceType = this.normalizeServiceType(config.mdnsServiceType)
    const serviceNameFilter = this.normalizeText(config.mdnsServiceName)
    const timeoutMs = this.normalizeTimeout(config.mdnsTimeoutMs)
    const candidates: GatewayDiscoveryCandidate[] = []
    const dedup = new Set<string>()

    return await new Promise((resolve) => {
      let discoveryService: mdns.DiscoveryService | null = null
      let settled = false
      let stopRequested = false
      let pendingResolves = 0
      let forceSettleTimer: number | null = null

      const safeResolve = (): void => {
        if (settled) {
          return
        }
        settled = true
        this.cleanupDiscovery(discoveryService, onServiceFound, onDiscoveryStop)
        if (forceSettleTimer !== null) {
          clearTimeout(forceSettleTimer)
          forceSettleTimer = null
        }
        resolve(candidates)
      }

      const maybeResolve = (): void => {
        if (!stopRequested || pendingResolves > 0) {
          return
        }
        safeResolve()
      }

      const onDiscoveryStop = (_event: mdns.DiscoveryEventInfo): void => {
        stopRequested = true
        maybeResolve()
      }

      const onServiceFound = (serviceInfo: mdns.LocalServiceInfo): void => {
        pendingResolves += 1
        void this.resolveService(context, serviceInfo)
          .then((candidate) => {
            if (candidate === null) {
              return
            }

            if (serviceNameFilter !== null && candidate.label !== serviceNameFilter) {
              return
            }

            const dedupKey = this.makeDedupKey(candidate.host, candidate.port)
            if (dedup.has(dedupKey)) {
              return
            }

            dedup.add(dedupKey)
            candidates.push(candidate)
          })
          .catch(() => {
            // mDNS resolve is best effort.
          })
          .finally(() => {
            pendingResolves = Math.max(0, pendingResolves - 1)
            maybeResolve()
          })
      }

      try {
        discoveryService = mdns.createDiscoveryService(context as never, serviceType)
        discoveryService.on('serviceFound', onServiceFound)
        discoveryService.on('discoveryStop', onDiscoveryStop)
        discoveryService.startSearchingMDNS()
      } catch (_error) {
        safeResolve()
        return
      }

      setTimeout(() => {
        stopRequested = true
        try {
          discoveryService?.stopSearchingMDNS()
        } catch (_error) {
          // Ignore stop failures and settle below.
        }

        forceSettleTimer = setTimeout(() => {
          safeResolve()
        }, 180)

        maybeResolve()
      }, timeoutMs)
    })
  }

  private async resolveService(context: Object, serviceInfo: mdns.LocalServiceInfo): Promise<GatewayDiscoveryCandidate | null> {
    try {
      const resolved = await mdns.resolveLocalService(context as never, serviceInfo)
      const host = this.normalizeHost(resolved.host?.address)
      const port = this.normalizePort(resolved.port)
      const label = this.normalizeText(resolved.serviceName) ?? this.normalizeText(serviceInfo.serviceName) ?? undefined

      if (host === null || port === null) {
        return null
      }

      return {
        host,
        port,
        source: 'mdns',
        label
      }
    } catch (_error) {
      return null
    }
  }

  private cleanupDiscovery(
    discoveryService: mdns.DiscoveryService | null,
    onServiceFound: (serviceInfo: mdns.LocalServiceInfo) => void,
    onDiscoveryStop: (event: mdns.DiscoveryEventInfo) => void
  ): void {
    if (discoveryService === null) {
      return
    }

    try {
      discoveryService.off('serviceFound', onServiceFound)
    } catch (_error) {
      // Ignore cleanup failures.
    }

    try {
      discoveryService.off('discoveryStop', onDiscoveryStop)
    } catch (_error) {
      // Ignore cleanup failures.
    }

    try {
      discoveryService.stopSearchingMDNS()
    } catch (_error) {
      // Ignore cleanup failures.
    }
  }

  private normalizeServiceType(value: string | undefined): string {
    const normalized = this.normalizeText(value)
    if (normalized === null) {
      return DEFAULT_MDNS_SERVICE_TYPE
    }

    let serviceType = normalized
    serviceType = serviceType.replace(/\.local\.?$/i, '')
    serviceType = serviceType.replace(/\.+$/g, '')

    if (serviceType.length === 0) {
      return DEFAULT_MDNS_SERVICE_TYPE
    }

    return serviceType
  }

  private normalizeTimeout(timeoutMs: number | undefined): number {
    if (timeoutMs === undefined || timeoutMs === null || !Number.isFinite(timeoutMs)) {
      return DEFAULT_MDNS_TIMEOUT_MS
    }

    const bounded = Math.trunc(timeoutMs)
    if (bounded < MIN_MDNS_TIMEOUT_MS) {
      return MIN_MDNS_TIMEOUT_MS
    }

    if (bounded > MAX_MDNS_TIMEOUT_MS) {
      return MAX_MDNS_TIMEOUT_MS
    }

    return bounded
  }

  private normalizeHost(value: string | undefined): string | null {
    const normalized = this.normalizeText(value)
    if (normalized === null) {
      return null
    }

    const withoutBracket = normalized.startsWith('[') && normalized.endsWith(']')
      ? normalized.substring(1, normalized.length - 1)
      : normalized
    const zoneIndex = withoutBracket.indexOf('%')
    const host = zoneIndex >= 0 ? withoutBracket.substring(0, zoneIndex) : withoutBracket
    return this.normalizeText(host)
  }

  private normalizePort(value: number | undefined): number | null {
    if (value === undefined || value === null || !Number.isFinite(value)) {
      return null
    }

    const port = Math.trunc(value)
    if (port <= 0 || port > 65535) {
      return null
    }
    return port
  }

  private makeDedupKey(host: string, port: number): string {
    return `${host.toLowerCase()}:${String(port)}`
  }

  private normalizeText(value: string | undefined | null): string | null {
    if (value === undefined || value === null) {
      return null
    }
    const trimmed = value.trim()
    return trimmed.length > 0 ? trimmed : null
  }
}
