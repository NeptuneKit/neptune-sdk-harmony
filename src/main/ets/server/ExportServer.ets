import { HttpRequest, HttpResponse, HttpServer } from '@cxy/webserver'
import { socket } from '@kit.NetworkKit'
import {
  ExportCursorPage,
  ExportHealth,
  ExportMetrics,
  ExportSourceEntry,
  IngestLogRecord,
  LogQueryOptions,
  LogRecord,
  LOG_QUEUE_BATCH_SIZE,
  LOG_QUEUE_CAPACITY
} from '../model/LogModels'
import { LogQueue } from '../core/LogQueue'

export interface ExportServerOptions {
  serviceName?: string
  version?: string
  startedAt?: string
}

export class ExportServer {
  private readonly queue: LogQueue
  private readonly serviceName: string
  private readonly version: string
  private readonly startedAt: string
  private readonly sources: ExportSourceEntry[] = []
  private httpServer: HttpServer | null = null
  private running: boolean = false
  private listeningPort: number | null = null

  constructor(queue: LogQueue = new LogQueue(), options: ExportServerOptions = {}) {
    this.queue = queue
    this.serviceName = options.serviceName ?? 'neptune-sdk-harmony-export'
    this.version = options.version ?? '0.1.0'
    this.startedAt = options.startedAt ?? new Date().toISOString()
  }

  createHttpServer(): HttpServer {
    if (this.httpServer !== null) {
      return this.httpServer
    }

    const server = new HttpServer()
    this.registerRoutes(server)
    this.httpServer = server
    return server
  }

  async start(port: number): Promise<socket.NetAddress | null> {
    const server = this.createHttpServer()
    const info = await server.startServer(port)
    this.running = info !== null && info !== undefined
    this.listeningPort = this.running ? port : null
    return info ?? null
  }

  async stop(): Promise<void> {
    await this.queue.flush()
    if (this.httpServer !== null) {
      await this.httpServer.stopServer()
    }
    this.running = false
    this.listeningPort = null
  }

  isRunning(): boolean {
    return this.running
  }

  port(): number | null {
    return this.listeningPort
  }

  registerSource(source: ExportSourceEntry): void {
    const sourceKey = this.makeSourceKey(source)
    if (sourceKey === null) {
      return
    }
    const index = this.sources.findIndex((item) => this.makeSourceKey(item) === sourceKey)
    if (index >= 0) {
      this.sources[index] = {
        ...this.sources[index],
        ...source
      }
      return
    }
    this.sources.push(source)
  }

  ingest(record: IngestLogRecord | IngestLogRecord[]): LogRecord[] {
    const records = Array.isArray(record) ? record : [record]
    for (const item of records) {
      this.registerSourceFromRecord(item)
    }
    return this.queue.appendAll(records)
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
    this.ensureSourcesLoaded()
    return this.sources.map((source) => ({
      ...source
    }))
  }

  queryLogs(query: LogQueryOptions = {}): ExportCursorPage<LogRecord> {
    const limit = this.normalizeLimit(query.limit)
    const predicate = this.makeLogFilter(query)
    const records = this.queue.peekAfter(query.cursor, limit, predicate)
    const nextCursor = records.length > 0 ? String(records[records.length - 1].id) : (query.cursor ?? '')
    return {
      records,
      nextCursor,
      hasMore: this.queue.hasMoreAfter(query.cursor, limit, predicate)
    }
  }

  private registerRoutes(server: HttpServer): void {
    server.get('/v2/export/health', (_req: HttpRequest, res: HttpResponse) => {
      res.status(200).json(this.health() as ESObject)
    })

    server.get('/v2/export/metrics', (_req: HttpRequest, res: HttpResponse) => {
      res.status(200).json(this.metrics() as ESObject)
    })

    server.get('/v2/export/logs', (req: HttpRequest, res: HttpResponse) => {
      const query = this.parseQuery(req)
      res.status(200).json(this.queryLogs(query) as ESObject)
    })

    server.get('/v2/export/sources', (_req: HttpRequest, res: HttpResponse) => {
      res.status(200).json(this.sourcesSnapshot() as ESObject)
    })
  }

  private parseQuery(req: HttpRequest): LogQueryOptions {
    const cursor = req.query.get('cursor') ?? undefined
    const limitValue = req.query.get('limit')
    const parsedLimit = limitValue !== undefined ? Number.parseInt(limitValue, 10) : undefined

    return {
      cursor,
      limit: Number.isFinite(parsedLimit) ? parsedLimit : undefined,
      platform: this.normalizeQueryField(req.query.get('platform')),
      appId: this.normalizeQueryField(req.query.get('appId')),
      sessionId: this.normalizeQueryField(req.query.get('sessionId'))
    }
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

  private makeLogFilter(query: LogQueryOptions): ((record: LogRecord) => boolean) | undefined {
    const platform = this.normalizeQueryField(query.platform)
    const appId = this.normalizeQueryField(query.appId)
    const sessionId = this.normalizeQueryField(query.sessionId)

    if (platform === undefined && appId === undefined && sessionId === undefined) {
      return undefined
    }

    return (record: LogRecord): boolean => {
      return this.matchesQueryField(record.platform, platform) &&
        this.matchesQueryField(record.appId, appId) &&
        this.matchesQueryField(record.sessionId, sessionId)
    }
  }

  private registerSourceFromRecord(record: IngestLogRecord): void {
    if (record.source === undefined || record.source === null) {
      return
    }

    const sdkName = record.source.sdkName
    const sdkVersion = record.source.sdkVersion
    if (!this.hasSourceIdentity(sdkName, sdkVersion, record.platform, record.appId, record.sessionId, record.deviceId)) {
      return
    }

    this.registerSource({
      deviceId: record.deviceId,
      appId: record.appId,
      platform: record.platform,
      sessionId: record.sessionId,
      sdkName: record.source.sdkName,
      sdkVersion: record.source.sdkVersion,
      lastSeenAt: record.timestamp
    })
  }

  private ensureSourcesLoaded(): void {
    if (this.sources.length > 0) {
      return
    }

    const records = this.queue.peekAfter(undefined, LOG_QUEUE_CAPACITY)
    for (const record of records) {
      this.registerSourceFromRecord(record)
    }
  }

  private hasSourceIdentity(
    sdkName: string | undefined,
    sdkVersion: string | undefined,
    platform: string | undefined,
    appId: string | undefined,
    sessionId: string | undefined,
    deviceId: string | undefined
  ): boolean {
    return this.normalizeSourceField(sdkName) !== null &&
      this.normalizeSourceField(sdkVersion) !== null &&
      this.normalizeSourceField(platform) !== null &&
      this.normalizeSourceField(appId) !== null &&
      this.normalizeSourceField(sessionId) !== null &&
      this.normalizeSourceField(deviceId) !== null
  }

  private makeSourceKey(source: ExportSourceEntry): string | null {
    const sdkName = this.normalizeSourceField(source.sdkName)
    const sdkVersion = this.normalizeSourceField(source.sdkVersion)
    const platform = this.normalizeSourceField(source.platform)
    const appId = this.normalizeSourceField(source.appId)
    const sessionId = this.normalizeSourceField(source.sessionId)
    const deviceId = this.normalizeSourceField(source.deviceId)
    if (
      sdkName === null ||
      sdkVersion === null ||
      platform === null ||
      appId === null ||
      sessionId === null ||
      deviceId === null
    ) {
      return null
    }

    return [sdkName, sdkVersion, platform, appId, sessionId, deviceId].join('::')
  }

  private normalizeSourceField(value: string | undefined | null): string | null {
    if (value === undefined || value === null) {
      return null
    }

    const trimmed = value.trim()
    return trimmed.length > 0 ? trimmed : null
  }

  private normalizeQueryField(value: string | undefined | null): string | undefined {
    const normalized = this.normalizeSourceField(value)
    return normalized === null ? undefined : normalized
  }

  private matchesQueryField(actual: string | undefined, expected: string | undefined): boolean {
    if (expected === undefined) {
      return true
    }

    return this.normalizeQueryField(actual) === expected
  }
}

export function createExportServer(queue?: LogQueue, options?: ExportServerOptions): ExportServer {
  return new ExportServer(queue ?? new LogQueue(), options ?? {})
}

export async function startExportServer(port: number, queue?: LogQueue, options?: ExportServerOptions): Promise<ExportServer> {
  const server = createExportServer(queue, options)
  await server.start(port)
  return server
}
