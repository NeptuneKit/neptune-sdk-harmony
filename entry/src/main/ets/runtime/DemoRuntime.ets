import {
  createExportServer,
  ExportMetrics,
  ExportServer,
  ExportSourceEntry,
  IngestLogRecord,
  LogLevel,
  LogQueue,
  LogRecord,
  Platform
} from 'neptune-sdk-harmony'

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

export interface DemoSnapshot {
  batchIndex: number
  banner: string
  metrics: ExportMetrics
  sources: DemoSourceCard[]
  recentLogs: DemoLogCard[]
}

const DEMO_SERVICE_NAME = 'neptune-sdk-harmony-demo'
const DEMO_VERSION = '0.1.0'
const DEMO_PLATFORM: Platform = 'harmony'
const DEMO_APP_ID = 'io.github.neptune.sdk.harmony.demo'
const DEMO_DEVICE_ALPHA = 'sim-device-alpha'
const DEMO_DEVICE_BETA = 'sim-device-beta'
const DEMO_SESSION_ALPHA = 'sim-session-alpha'
const DEMO_SESSION_BETA = 'sim-session-beta'

class DemoRuntime {
  private readonly exportServer: ExportServer
  private batchIndex: number = 0

  constructor() {
    this.exportServer = createExportServer(new LogQueue(), {
      serviceName: DEMO_SERVICE_NAME,
      version: DEMO_VERSION
    })
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

  private toSourceCard(source: ExportSourceEntry): DemoSourceCard {
    return {
      id: `${source.sessionId}-${source.deviceId}`,
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
}

export const demoRuntime = new DemoRuntime()
