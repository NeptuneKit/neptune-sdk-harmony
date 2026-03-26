import {
  createExportServer,
  createGatewayDiscoveryResolver,
  ExportMetrics,
  ExportServer,
  ExportSourceEntry,
  GatewayDiscoveryResult,
  IngestLogRecord,
  LogLevel,
  LogQueue,
  LogRecord,
  Platform,
  LogSourceInfo,
  GatewayClientCallbackManager
} from 'neptune-sdk-harmony'
import { GatewayIngestHttpClient, GatewayIngestResult } from './GatewayIngestHttpClient'

export interface DemoLogCard {
  id: string
  title: string
  detail: string
  timestamp: string
}

export interface DemoSourceCard {
  id: string
  title: string
  detail: string
  timestamp: string
}

export interface DemoGatewayDiscoveryCard {
  state: 'idle' | 'loading' | 'success' | 'failed'
  title: string
  detail: string
  timestamp: string
  ingestState: 'idle' | 'loading' | 'success' | 'failed'
  ingestTitle: string
  ingestDetail: string
  ingestTimestamp: string
}

export interface DemoSnapshot {
  batchIndex: number
  banner: string
  gatewayDiscovery: DemoGatewayDiscoveryCard
  metrics: ExportMetrics
  sources: DemoSourceCard[]
  recentLogs: DemoLogCard[]
}

const DEMO_SERVICE_NAME = 'neptune-sdk-harmony-demo'
const DEMO_VERSION = '0.1.0'
const DEMO_MANUAL_DSN = '127.0.0.1:18765'
const DEMO_MANUAL_ENDPOINT_URL = 'http://127.0.0.1:18765'
const DEMO_CALLBACK_LISTEN_PORT = 28767
const DEMO_PLATFORM: Platform = 'harmony'
const DEMO_APP_ID = 'io.github.neptune.sdk.harmony.demo'
const DEMO_DEVICE_ALPHA = 'sim-device-alpha'
const DEMO_DEVICE_BETA = 'sim-device-beta'
const DEMO_SESSION_ALPHA = 'sim-session-alpha'
const DEMO_SESSION_BETA = 'sim-session-beta'
const DEMO_INGEST_DEVICE_ID = 'sim-device-discovery'
const DEMO_INGEST_SESSION_ID = 'sim-session-discovery'

class DemoRuntime {
  private readonly exportServer: ExportServer
  private readonly callbackManager: GatewayClientCallbackManager
  private readonly gatewayDiscoveryResolver = createGatewayDiscoveryResolver()
  private readonly gatewayIngestClient = new GatewayIngestHttpClient()
  private gatewayDiscoveryContext: Object | undefined = undefined
  private batchIndex: number = 0
  private gatewayDiscovery: DemoGatewayDiscoveryCard = {
    state: 'idle',
    title: '等待发现网关',
    detail: `点击“发现网关”后，将优先尝试 mDNS，并回退到手动 DSN ${DEMO_MANUAL_DSN}`,
    timestamp: new Date().toISOString(),
    ingestState: 'idle',
    ingestTitle: '等待自动上报',
    ingestDetail: '发现成功后会自动 POST /v2/logs:ingest 一条日志',
    ingestTimestamp: new Date().toISOString()
  }

  constructor() {
    this.exportServer = createExportServer(new LogQueue(), {
      serviceName: DEMO_SERVICE_NAME,
      version: DEMO_VERSION
    })
    this.callbackManager = new GatewayClientCallbackManager(this.exportServer, undefined, {
      listenAddress: '0.0.0.0',
      listenPort: DEMO_CALLBACK_LISTEN_PORT,
      platform: DEMO_PLATFORM,
      appId: DEMO_APP_ID,
      deviceId: DEMO_DEVICE_ALPHA,
      sessionId: DEMO_SESSION_ALPHA,
      sdkName: DEMO_SERVICE_NAME,
      sdkVersion: DEMO_VERSION,
      renewIntervalMs: 30000
    })
    void this.callbackManager.start()
      .then(() => this.callbackManager.setGatewayEndpoint(DEMO_MANUAL_ENDPOINT_URL))
      .then((result) => {
        if (result !== null) {
          console.info(`Callback manager auto register state=${result.state} detail=${result.detail}`)
        }
      })
      .catch((error: Error) => {
        console.error(`Callback manager start failed: ${error instanceof Error ? error.message : String(error)}`)
      })
    // Seed one initial batch so gateway /v2/logs can immediately pull Harmony records after registration.
    this.seedBatch()
  }

  setGatewayDiscoveryContext(context: Object | undefined | null): void {
    if (context === undefined || context === null) {
      return
    }

    this.gatewayDiscoveryContext = context
  }

  seedBatch(): DemoSnapshot {
    this.batchIndex += 1
    const now = new Date().toISOString()
    const batchLabel = `Batch ${String(this.batchIndex).padStart(2, '0')}`
    const batchRecords: IngestLogRecord[] = [
      this.makeRecord(batchLabel, 0, now, 'info', 'entry 页面按钮触发了 Neptune SDK 写入', DEMO_SESSION_ALPHA, DEMO_DEVICE_ALPHA),
      this.makeRecord(batchLabel, 1, now, 'notice', 'metrics 摘要已刷新并保持在页面内', DEMO_SESSION_BETA, DEMO_DEVICE_BETA),
      this.makeRecord(batchLabel, 2, now, 'debug', 'sources 摘要从同一 HAR 实例重建', DEMO_SESSION_ALPHA, DEMO_DEVICE_ALPHA)
    ]
    this.exportServer.ingest(batchRecords)
    return this.snapshot(`已写入 ${batchRecords.length} 条日志`)
  }

  beginGatewayDiscovery(): DemoSnapshot {
    this.gatewayDiscovery = {
      state: 'loading',
      title: '正在发现网关',
      detail: `优先 mDNS，回退到手动 DSN ${DEMO_MANUAL_DSN}`,
      timestamp: new Date().toISOString(),
      ingestState: 'idle',
      ingestTitle: '等待自动上报',
      ingestDetail: '发现成功后会自动 POST /v2/logs:ingest 一条日志',
      ingestTimestamp: new Date().toISOString()
    }
    return this.snapshot('正在发现网关')
  }

  async discoverGateway(): Promise<DemoSnapshot> {
    try {
      const result = await this.gatewayDiscoveryResolver.discover({
        manualDsn: DEMO_MANUAL_DSN,
        mdnsContext: this.gatewayDiscoveryContext
      })
      console.info(
        `discoverGateway success source=${result.source} host=${result.host} port=${result.port} version=${result.version}`
      )
      this.gatewayDiscovery = this.toGatewayDiscoverySuccessCard(result)
      this.gatewayDiscovery = this.toGatewayDiscoveryIngestLoadingCard(this.gatewayDiscovery)
      void this.callbackManager.setGatewayEndpoint(result.endpointUrl).catch((error: Error) => {
        console.error(
          `Callback manager register failed: ${error instanceof Error ? error.message : String(error)}`
        )
      })

      const ingestResult = await this.ingestDiscoveryLog(result)
      console.info(
        `discoverGateway ingest ${ingestResult.state} title=${ingestResult.title} detail=${ingestResult.detail}`
      )
      this.gatewayDiscovery = this.applyIngestResult(this.gatewayDiscovery, ingestResult)
      return this.snapshot(
        ingestResult.state === 'success'
          ? '网关发现成功并已自动上报日志'
          : '网关发现成功，但自动上报日志失败'
      )
    } catch (error) {
      this.gatewayDiscovery = this.toGatewayDiscoveryFailureCard(error)
      return this.snapshot('网关发现失败')
    }
  }

  snapshot(message: string = '等待首个按钮事件'): DemoSnapshot {
    const metrics = this.exportServer.metrics()
    const cursor = metrics.queueSize > 6 ? String(metrics.queueSize - 6) : undefined
    const records = this.exportServer.queryLogs({
      cursor,
      limit: 6
    }).records

    return {
      batchIndex: this.batchIndex,
      banner: message,
      gatewayDiscovery: this.gatewayDiscovery,
      metrics,
      sources: this.exportServer.sourcesSnapshot().map((source) => this.toSourceCard(source)),
      recentLogs: records.map((record) => this.toLogCard(record))
    }
  }

  private makeRecord(
    batchLabel: string,
    sequence: number,
    timestamp: string,
    level: LogLevel,
    message: string,
    sessionId: string,
    deviceId: string
  ): IngestLogRecord {
    return {
      timestamp,
      level,
      message: `${batchLabel} #${sequence + 1} · ${message}`,
      platform: DEMO_PLATFORM,
      appId: DEMO_APP_ID,
      sessionId,
      deviceId,
      category: sequence === 0 ? 'ui' : sequence === 1 ? 'metrics' : 'sources',
      source: {
        sdkName: DEMO_SERVICE_NAME,
        sdkVersion: DEMO_VERSION,
        file: 'entry/src/main/ets/pages/Index.ets',
        function: 'seedBatch',
        line: 0
      }
    }
  }

  private async ingestDiscoveryLog(result: GatewayDiscoveryResult): Promise<GatewayIngestResult> {
    const ingestSource: LogSourceInfo = {
      sdkName: DEMO_SERVICE_NAME,
      sdkVersion: DEMO_VERSION,
      file: 'entry/src/main/ets/runtime/DemoRuntime.ets',
      function: 'discoverGateway',
      line: 0
    }
    const ingestRecord: IngestLogRecord = {
      timestamp: new Date().toISOString(),
      level: 'info',
      message: `Discovery demo auto-ingest after ${result.source} gateway discovery`,
      platform: DEMO_PLATFORM,
      appId: DEMO_APP_ID,
      sessionId: DEMO_INGEST_SESSION_ID,
      deviceId: DEMO_INGEST_DEVICE_ID,
      category: 'discovery',
      source: ingestSource
    }
    const ingestEndpoint = result.source === 'manual-dsn'
      ? DEMO_MANUAL_ENDPOINT_URL
      : result.endpointUrl
    return this.gatewayIngestClient.ingest(ingestEndpoint, ingestRecord)
  }

  private toSourceCard(source: ExportSourceEntry): DemoSourceCard {
    return {
      id: `${source.platform}-${source.appId}-${source.deviceId}`,
      title: `${source.sdkName}@${source.sdkVersion}`,
      detail: `${source.platform} · ${source.appId} · ${source.sessionId}`,
      timestamp: `device ${source.deviceId} · last seen ${source.lastSeenAt}`
    }
  }

  private toLogCard(record: LogRecord): DemoLogCard {
    return {
      id: String(record.id),
      title: `${record.level.toUpperCase()} · ${record.message}`,
      detail: `${record.platform} · ${record.appId} · ${record.sessionId} · ${record.category}`,
      timestamp: record.timestamp
    }
  }

  private toGatewayDiscoverySuccessCard(result: GatewayDiscoveryResult): DemoGatewayDiscoveryCard {
    return {
      state: 'success',
      title: `发现成功 · ${this.prettyDiscoverySource(result.source)}`,
      detail: `source=${result.source} host=${result.host} port=${result.port} version=${result.version} endpoint=${result.endpointUrl}`,
      timestamp: new Date().toISOString(),
      ingestState: 'idle',
      ingestTitle: '等待自动上报',
      ingestDetail: '发现成功后会自动 POST /v2/logs:ingest 一条日志',
      ingestTimestamp: new Date().toISOString()
    }
  }

  private toGatewayDiscoveryIngestLoadingCard(card: DemoGatewayDiscoveryCard): DemoGatewayDiscoveryCard {
    return {
      state: card.state,
      title: card.title,
      detail: card.detail,
      timestamp: card.timestamp,
      ingestState: 'loading',
      ingestTitle: '正在自动上报日志',
      ingestDetail: 'POST /v2/logs:ingest 正在请求 CLI 网关',
      ingestTimestamp: new Date().toISOString()
    }
  }

  private applyIngestResult(
    card: DemoGatewayDiscoveryCard,
    result: GatewayIngestResult
  ): DemoGatewayDiscoveryCard {
    return {
      state: card.state,
      title: card.title,
      detail: card.detail,
      timestamp: card.timestamp,
      ingestState: result.state,
      ingestTitle: result.title,
      ingestDetail: result.detail,
      ingestTimestamp: result.timestamp
    }
  }

  private toGatewayDiscoveryFailureCard(error: Error | string): DemoGatewayDiscoveryCard {
    return {
      state: 'failed',
      title: '网关发现失败',
      detail: error instanceof Error ? error.message : String(error),
      timestamp: new Date().toISOString(),
      ingestState: 'idle',
      ingestTitle: '等待自动上报',
      ingestDetail: '发现成功后会自动 POST /v2/logs:ingest 一条日志',
      ingestTimestamp: new Date().toISOString()
    }
  }

  private prettyDiscoverySource(source: string): string {
    switch (source) {
      case 'mdns':
        return 'mDNS'
      case 'manual-dsn':
        return '手动 DSN'
      default:
        return source
    }
  }
}

export const demoRuntime = new DemoRuntime()
