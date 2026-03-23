import { ExportCursorPage, ExportHealth, ExportMetrics, ExportServerResponse, ExportServerRoute, ExportSourceEntry, IngestLogRecord, LogQueryOptions, LogRecord, LOG_QUEUE_BATCH_SIZE, LOG_QUEUE_CAPACITY } from '../model/LogModels'
import { LogQueue } from '../core/LogQueue'

export interface ExportServerOptions {
  serviceName?: string
  version?: string
  startedAt?: string
}

export interface ExportRequest {
  method: 'GET' | 'POST'
  path: string
  query?: LogQueryOptions
  body?: unknown
}

export class ExportServer {
  private readonly queue: LogQueue
  private readonly serviceName: string
  private readonly version: string
  private readonly startedAt: string
  private readonly sources: ExportSourceEntry[] = []
  private running: boolean = false

  constructor(queue: LogQueue = new LogQueue(), options: ExportServerOptions = {}) {
    this.queue = queue
    this.serviceName = options.serviceName ?? 'neptune-sdk-harmony-export'
    this.version = options.version ?? '0.1.0'
    this.startedAt = options.startedAt ?? new Date().toISOString()
  }

  start(): ExportServerResponse<ExportHealth> {
    this.running = true
    return {
      statusCode: 200,
      body: this.health()
    }
  }

  stop(): void {
    this.running = false
  }

  isRunning(): boolean {
    return this.running
  }

  routes(): ExportServerRoute[] {
    return [
      { method: 'GET', path: '/v2/export/health', description: 'Export service health snapshot' },
      { method: 'GET', path: '/v2/export/metrics', description: 'Export service metrics snapshot' },
      { method: 'GET', path: '/v2/export/logs', description: 'Incremental export logs by cursor and limit' }
    ]
  }

  registerSource(source: ExportSourceEntry): void {
    const index = this.sources.findIndex((item) => item.deviceId === source.deviceId && item.appId === source.appId && item.sessionId === source.sessionId)
    if (index >= 0) {
      this.sources[index] = source
      return
    }
    this.sources.push(source)
  }

  ingest(record: IngestLogRecord | IngestLogRecord[]): LogRecord[] {
    const records = Array.isArray(record) ? record : [record]
    const appended = this.queue.appendAll(records)
    return appended
  }

  health(): ExportHealth {
    return {
      status: this.running ? 'ok' : 'degraded',
      service: this.serviceName,
      version: this.version,
      startedAt: this.startedAt
    }
  }

  metrics(): ExportMetrics {
    const queueMetrics = this.queue.metrics()
    const queueTotals = this.queue.totals()
    return {
      queueSize: queueMetrics.queueSize,
      queueCapacity: queueMetrics.queueCapacity,
      droppedOverflow: queueMetrics.droppedOverflow,
      totalIngested: queueTotals.totalIngested,
      totalExported: queueMetrics.totalExported
    }
  }

  sourcesSnapshot(): ExportSourceEntry[] {
    return this.sources.slice()
  }

  queryLogs(query: LogQueryOptions = {}): ExportCursorPage<LogRecord> {
    const limit = this.normalizeLimit(query.limit)
    const records = this.queue.peekAfter(query.cursor, limit)
    const nextCursor = records.length > 0 ? String(records[records.length - 1].id) : (query.cursor ?? '')
    return {
      records,
      nextCursor,
      hasMore: this.queue.hasMoreAfter(query.cursor, limit)
    }
  }

  handleRequest(request: ExportRequest): ExportServerResponse<unknown> {
    if (request.method !== 'GET') {
      return { statusCode: 405, body: { message: 'method not allowed' } }
    }

    if (request.path === '/v2/export/health') {
      return { statusCode: 200, body: this.health() }
    }

    if (request.path === '/v2/export/metrics') {
      return { statusCode: 200, body: this.metrics() }
    }

    if (request.path === '/v2/export/logs') {
      return { statusCode: 200, body: this.queryLogs(request.query) }
    }

    return { statusCode: 404, body: { message: 'not found' } }
  }

  private normalizeLimit(limit?: number): number {
    if (limit === undefined || limit === null) {
      return LOG_QUEUE_BATCH_SIZE
    }
    if (limit <= 0) {
      return 1
    }
    return Math.min(limit, LOG_QUEUE_CAPACITY)
  }
}
