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
import {
  GatewayClientBusEnvelope,
  GatewayClientCommandAck,
} from '../callback/CallbackModels'
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
  private commandSequence: number = 0

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
    server.json()
    this.registerRoutes(server)
    this.httpServer = server
    return server
  }

  async start(port: number, address: string = '0.0.0.0'): Promise<socket.NetAddress | null> {
    const server = this.createHttpServer()
    const info = await server.startServer(port, address)
    this.running = info !== null && info !== undefined
    this.listeningPort = this.running && info !== null && info !== undefined && info.port !== undefined
      ? info.port
      : null
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
      this.sources[index] = this.copySourceEntry(source)
      return
    }
    this.sources.push(this.copySourceEntry(source))
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
    const snapshot: ExportSourceEntry[] = []
    for (const source of this.sources) {
      snapshot.push(this.copySourceEntry(source))
    }
    return snapshot
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

    server.post('/v2/client/command', (req: HttpRequest, res: HttpResponse) => {
      res.status(200).json(this.handleClientCommand(req) as ESObject)
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
    if (!this.hasSourceIdentity(sdkName, sdkVersion, record.platform, record.appId, record.deviceId)) {
      return
    }

    const sourceEntry: ExportSourceEntry = {
      deviceId: record.deviceId,
      appId: record.appId,
      platform: record.platform,
      sessionId: record.sessionId,
      sdkName: record.source.sdkName,
      sdkVersion: record.source.sdkVersion,
      lastSeenAt: record.timestamp
    }
    this.registerSource(sourceEntry)
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
    deviceId: string | undefined
  ): boolean {
    return this.normalizeSourceField(sdkName) !== null &&
      this.normalizeSourceField(sdkVersion) !== null &&
      this.normalizeSourceField(platform) !== null &&
      this.normalizeSourceField(appId) !== null &&
      this.normalizeSourceField(deviceId) !== null
  }

  private makeSourceKey(source: ExportSourceEntry): string | null {
    const sdkName = this.normalizeSourceField(source.sdkName)
    const sdkVersion = this.normalizeSourceField(source.sdkVersion)
    const platform = this.normalizeSourceField(source.platform)
    const appId = this.normalizeSourceField(source.appId)
    const deviceId = this.normalizeSourceField(source.deviceId)
    if (
      sdkName === null ||
      sdkVersion === null ||
      platform === null ||
      appId === null ||
      deviceId === null
    ) {
      return null
    }

    return [platform, appId, deviceId].join('::')
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

  private copySourceEntry(source: ExportSourceEntry): ExportSourceEntry {
    return {
      deviceId: source.deviceId,
      appId: source.appId,
      platform: source.platform,
      sessionId: source.sessionId,
      sdkName: source.sdkName,
      sdkVersion: source.sdkVersion,
      lastSeenAt: source.lastSeenAt
    }
  }

  private handleClientCommand(req: HttpRequest): GatewayClientCommandAck {
    const commandRequest = this.parseClientCommandRequest(req)
    const timestamp = new Date().toISOString()
    if (commandRequest === null) {
      return {
        requestId: this.makeRequestId('invalid'),
        direction: 'client_to_cli',
        command: 'unknown',
        status: 'error',
        message: 'invalid command request',
        timestamp
      }
    }

    if (commandRequest.direction !== 'cli_to_client') {
      return {
        requestId: this.makeRequestId(commandRequest.requestId),
        direction: 'client_to_cli',
        command: 'unknown',
        status: 'error',
        message: 'unsupported direction',
        timestamp
      }
    }
    if (commandRequest.kind !== 'command') {
      return {
        requestId: this.makeRequestId(commandRequest.requestId),
        direction: 'client_to_cli',
        command: 'unknown',
        status: 'error',
        message: 'unsupported message kind',
        timestamp
      }
    }

    const command = this.normalizeCommand(commandRequest.command)
    const requestId = this.makeRequestId(commandRequest.requestId)
    if (command !== 'ping') {
      return {
        requestId,
        direction: 'client_to_cli',
        command,
        status: 'error',
        message: `unsupported command ${command}`,
        timestamp
      }
    }

    return {
      requestId,
      direction: 'client_to_cli',
      command,
      status: 'ok',
      message: 'ping acknowledged',
      timestamp
    }
  }

  private parseClientCommandRequest(req: HttpRequest): GatewayClientBusEnvelope | null {
    try {
      const rawText = typeof req.body === 'string' ? req.body : JSON.stringify(req.body)
      if (rawText === undefined || rawText === null) {
        return null
      }
      const parsed = JSON.parse(rawText) as Record<string, string | number | boolean | null | undefined>
      if (parsed === undefined || parsed === null || typeof parsed !== 'object') {
        return null
      }
      const payload = parsed as Record<string, string | number | boolean | null | undefined>
      return {
        requestId: this.normalizeTextValue(payload.requestId),
        direction: this.normalizeDirectionValue(payload.direction),
        kind: this.normalizeKindValue(payload.kind),
        command: this.normalizeTextValue(payload.command),
        event: undefined,
        logRecord: undefined,
        timestamp: this.normalizeTextValue(payload.timestamp)
      }
    } catch (_error) {
      return null
    }
  }

  private normalizeCommand(command: string | undefined | null): string {
    const normalized = this.normalizeTextValue(command)
    return normalized === undefined ? 'unknown' : normalized
  }

  private normalizeDirectionValue(value: string | number | boolean | undefined | null): 'cli_to_client' | 'client_to_cli' {
    return this.normalizeTextValue(value) === 'cli_to_client' ? 'cli_to_client' : 'client_to_cli'
  }

  private normalizeKindValue(value: string | number | boolean | undefined | null): 'command' | 'event' | 'log' {
    const normalized = this.normalizeTextValue(value)
    if (normalized === 'command' || normalized === 'event' || normalized === 'log') {
      return normalized
    }
    return 'event'
  }

  private makeRequestId(value: string | undefined | null): string {
    const normalized = this.normalizeTextValue(value)
    if (normalized !== undefined) {
      return normalized
    }

    this.commandSequence += 1
    return `local-command-${String(this.commandSequence)}-${Date.now()}`
  }

  private normalizeTextValue(value: string | number | boolean | undefined | null): string | undefined {
    if (value === undefined || value === null) {
      return undefined
    }

    const normalized = String(value).trim()
    return normalized.length > 0 ? normalized : undefined
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
