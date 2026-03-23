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
    const index = this.sources.findIndex((item) => item.deviceId === source.deviceId && item.appId === source.appId && item.sessionId === source.sessionId)
    if (index >= 0) {
      this.sources[index] = source
      return
    }
    this.sources.push(source)
  }

  ingest(record: IngestLogRecord | IngestLogRecord[]): LogRecord[] {
    const records = Array.isArray(record) ? record : [record]
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
  }

  private parseQuery(req: HttpRequest): LogQueryOptions {
    const cursor = req.query.get('cursor') ?? undefined
    const limitValue = req.query.get('limit')
    const parsedLimit = limitValue !== undefined ? Number.parseInt(limitValue, 10) : undefined

    return {
      cursor,
      limit: Number.isFinite(parsedLimit) ? parsedLimit : undefined
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
}

export function createExportServer(queue?: LogQueue, options?: ExportServerOptions): ExportServer {
  return new ExportServer(queue ?? new LogQueue(), options ?? {})
}

export async function startExportServer(port: number, queue?: LogQueue, options?: ExportServerOptions): Promise<ExportServer> {
  const server = createExportServer(queue, options)
  await server.start(port)
  return server
}
