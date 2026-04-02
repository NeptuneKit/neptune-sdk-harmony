import {
  ArkUIViewTreeCollector,
  createExportServer,
  createGatewayDiscoveryResolver,
  ExportInspectorSnapshot,
  ExportMetrics,
  ExportServer,
  ExportSourceEntry,
  ExportViewTreeFrame,
  ExportViewTreeNode,
  ExportViewTreeSnapshot,
  ExportViewTreeStyle,
  GatewayDiscoveryResult,
  IngestLogRecord,
  LogQueryOptions,
  LogLevel,
  LogQueue,
  LogRecord,
  Platform,
  LogSourceInfo,
  GatewayClientCallbackManager,
  ViewTreeQueryOptions
} from 'neptune-sdk-harmony'
import { ExpandMode, FrameNode, UIContext } from '@kit.ArkUI'
import { AbilityConstant, Configuration, EnvironmentCallback } from '@kit.AbilityKit'
import { GatewayIngestHttpClient, GatewayIngestResult, GatewayRawViewTreeIngestRecord } from './GatewayIngestHttpClient'

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

interface InspectorNode {
  $type?: string
  $ID?: number
  $rect?: string
  $attrs?: InspectorAttrs
  $children?: InspectorNode[]
}

interface InspectorAttrs {
  id?: string
  opacity?: string | number
  alpha?: string | number
  backgroundColor?: string
  background?: string
  bgColor?: string
  fill?: string
  fontColor?: string
  textColor?: string
  color?: string
  fontSize?: string | number
  lineHeight?: string | number
  letterSpacing?: string | number
  fontWeight?: string
  borderRadius?: string | number
  radius?: string | number
  borderWidth?: string | number
  borderColor?: string
  stroke?: string
  strokeWidth?: string | number
  zIndex?: string | number
  textAlign?: string
  textAlignHorizontal?: string
  align?: string
  content?: string
  text?: string
  value?: string
  label?: string
  visible?: boolean | string
  visibility?: string
}

interface InspectorEnvelope extends InspectorNode {
  type?: string
  content?: InspectorNode
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
const DEMO_INGEST_DEVICE_ID = 'sim-device-alpha'
const DEMO_INGEST_SESSION_ID = 'sim-session-alpha'
class DemoRuntime {
  private readonly exportServer: ExportServer
  private readonly callbackManager: GatewayClientCallbackManager
  private readonly gatewayDiscoveryResolver = createGatewayDiscoveryResolver()
  private readonly gatewayIngestClient = new GatewayIngestHttpClient()
  private readonly uiTreeCollector = new ArkUIViewTreeCollector()
  private uiContext: UIContext | null = null
  private viewTreeAnchorUniqueId: number | null = null
  private typographyFontScale: number = 1
  private typographyEnvironmentCallbackId: number | null = null
  private manualUiTreeBackfillScheduled: boolean = false
  private manualUiTreeBackfillInFlight: boolean = false
  private gatewayDiscoveryContext: Object | undefined = undefined
  private activeGatewayIngestEndpoint: string = DEMO_MANUAL_ENDPOINT_URL
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
    this.exportServer.setViewTreeSnapshotProvider((query) => this.captureViewTreeSnapshot(query))
    this.exportServer.setInspectorSnapshotProvider((query) => this.captureInspectorSnapshot(query))
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

  setUIContext(context: UIContext | undefined | null): void {
    if (context === undefined || context === null) {
      return
    }
    this.uiContext = context
    this.uiTreeCollector.setUIContext(context)
    this.updateTypographyScaleListener(context)
    this.scheduleManualUiTreeBackfill()
  }

  setViewTreeAnchorUniqueId(uniqueId: number | undefined | null): void {
    if (uniqueId === undefined || uniqueId === null || uniqueId <= 0) {
      return
    }
    this.viewTreeAnchorUniqueId = uniqueId
    this.uiTreeCollector.setViewTreeAnchorUniqueId(uniqueId)
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
      this.activeGatewayIngestEndpoint = result.source === 'manual-dsn'
        ? DEMO_MANUAL_ENDPOINT_URL
        : result.endpointUrl
      void this.callbackManager.setGatewayEndpoint(result.endpointUrl).catch((error: Error) => {
        console.error(
          `Callback manager register failed: ${error instanceof Error ? error.message : String(error)}`
        )
      })

      const ingestResult = await this.ingestDiscoveryLog(result)
      console.info(
        `discoverGateway ingest ${ingestResult.state} title=${ingestResult.title} detail=${ingestResult.detail}`
      )
      void this.ingestDiscoveryRawViewTree(result).then((uiTreeIngestResult) => {
        console.info(
          `discoverGateway ui-tree ingest ${uiTreeIngestResult.state} title=${uiTreeIngestResult.title} detail=${uiTreeIngestResult.detail}`
        )
      }).catch((error: Error) => {
        console.error(`discoverGateway ui-tree ingest failed: ${error instanceof Error ? error.message : String(error)}`)
      })
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

  async ingestRandomLogToGateway(): Promise<DemoSnapshot> {
    const now = new Date().toISOString()
    const levels: LogLevel[] = ['info', 'notice', 'warning', 'error', 'debug']
    const categories = ['ui', 'network', 'metrics', 'sources', 'runtime']
    const actions = ['用户点击随机上报按钮', '模拟联调上报链路', '验证网关日志过滤', '刷新客户端日志页', '打点多端链路状态']
    const randomLevel = levels[Math.floor(Math.random() * levels.length)]
    const randomCategory = categories[Math.floor(Math.random() * categories.length)]
    const randomAction = actions[Math.floor(Math.random() * actions.length)]
    const randomCode = Math.random().toString(36).slice(2, 8)
    const ingestRecord: IngestLogRecord = {
      timestamp: now,
      level: randomLevel,
      message: `Manual random ingest · ${randomAction} · #${randomCode}`,
      platform: DEMO_PLATFORM,
      appId: DEMO_APP_ID,
      sessionId: DEMO_INGEST_SESSION_ID,
      deviceId: DEMO_INGEST_DEVICE_ID,
      category: randomCategory,
      source: {
        sdkName: DEMO_SERVICE_NAME,
        sdkVersion: DEMO_VERSION,
        file: 'entry/src/main/ets/runtime/DemoRuntime.ets',
        function: 'ingestRandomLogToGateway',
        line: 0
      }
    }
    this.exportServer.ingest(ingestRecord)
    this.gatewayDiscovery = this.toGatewayDiscoveryIngestLoadingCard(this.gatewayDiscovery)
    const ingestResult = await this.gatewayIngestClient.ingest(this.activeGatewayIngestEndpoint, ingestRecord)
    this.gatewayDiscovery = this.applyIngestResult(this.gatewayDiscovery, ingestResult)
    return this.snapshot(
      ingestResult.state === 'success'
        ? `已随机上报 1 条日志 #${randomCode}`
        : `随机上报失败 #${randomCode}`
    )
  }

  snapshot(message: string = '等待首个按钮事件'): DemoSnapshot {
    const metrics = this.exportServer.metrics()
    const cursor = metrics.queueSize > 6 ? String(metrics.queueSize - 6) : undefined
    const recentLogsQuery: LogQueryOptions = {
      cursor,
      length: 6
    }
    const records = this.exportServer.queryLogs(recentLogsQuery).records

    return {
      batchIndex: this.batchIndex,
      banner: message,
      gatewayDiscovery: this.gatewayDiscovery,
      metrics,
      sources: this.exportServer.sourcesSnapshot().map((source) => this.toSourceCard(source)),
      recentLogs: records.map((record) => this.toLogCard(record))
    }
  }

  async ingestCurrentViewTreeToManualGateway(): Promise<void> {
    try {
      const result = await this.ingestRawViewTreeToEndpoint(DEMO_MANUAL_ENDPOINT_URL)
      console.info(
        `manual ui-tree ingest-now ${result.state} title=${result.title} detail=${result.detail}`
      )
    } catch (error) {
      console.error(`manual ui-tree ingest-now failed: ${error instanceof Error ? error.message : String(error)}`)
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

  private async ingestDiscoveryRawViewTree(result: GatewayDiscoveryResult): Promise<GatewayIngestResult> {
    const ingestEndpoint = result.source === 'manual-dsn'
      ? DEMO_MANUAL_ENDPOINT_URL
      : result.endpointUrl
    return this.ingestRawViewTreeToEndpoint(ingestEndpoint)
  }

  private async ingestRawViewTreeToEndpoint(ingestEndpoint: string): Promise<GatewayIngestResult> {
    const inspectorSnapshot = this.captureInspectorSnapshot({})
    if (!inspectorSnapshot.available || inspectorSnapshot.payload === null) {
      return {
        state: 'failed',
        title: '视图树上报失败',
        detail: 'Inspector payload unavailable.',
        timestamp: new Date().toISOString()
      }
    }

    const rawRecord: GatewayRawViewTreeIngestRecord = {
      platform: DEMO_PLATFORM,
      appId: DEMO_APP_ID,
      sessionId: DEMO_SESSION_ALPHA,
      deviceId: DEMO_DEVICE_ALPHA,
      snapshotId: inspectorSnapshot.snapshotId,
      capturedAt: inspectorSnapshot.capturedAt,
      payload: inspectorSnapshot.payload
    }
    return this.gatewayIngestClient.ingestRawViewTree(ingestEndpoint, rawRecord)
  }

  private scheduleManualUiTreeBackfill(): void {
    if (this.manualUiTreeBackfillScheduled) {
      return
    }
    this.manualUiTreeBackfillScheduled = true
    setTimeout(() => {
      void this.runManualUiTreeBackfill()
    }, 1200)
  }

  private async runManualUiTreeBackfill(): Promise<void> {
    if (this.manualUiTreeBackfillInFlight) {
      return
    }
    this.manualUiTreeBackfillInFlight = true
    try {
      const result = await this.ingestRawViewTreeToEndpoint(DEMO_MANUAL_ENDPOINT_URL)
      console.info(
        `manual ui-tree backfill ${result.state} title=${result.title} detail=${result.detail}`
      )
    } catch (error) {
      console.error(`manual ui-tree backfill failed: ${error instanceof Error ? error.message : String(error)}`)
    } finally {
      this.manualUiTreeBackfillInFlight = false
    }
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

  private captureViewTreeSnapshot(query: ViewTreeQueryOptions): ExportViewTreeSnapshot {
    return this.uiTreeCollector.captureViewTreeSnapshot(query)
  }

  private captureInspectorSnapshot(query: ViewTreeQueryOptions): ExportInspectorSnapshot {
    return this.uiTreeCollector.captureInspectorSnapshot(query)
  }

  private resolveInspectorRootNode(): InspectorNode | null {
    if (this.uiContext === null) {
      return null
    }

    try {
      const payload = this.getInspectorTreePayload()
      const parsed = this.normalizeInspectorPayload(JSON.parse(payload)) as InspectorEnvelope
      if (parsed.content !== undefined && parsed.content !== null) {
        return parsed.content
      }
      return parsed
    } catch (_error) {
      return null
    }
  }

  private toInspectorViewTreeNode(
    node: InspectorNode,
    parentId: string | null,
    fallbackId: string
  ): ExportViewTreeNode {
    const nodeId = this.normalizeInspectorNodeId(node, fallbackId)
    const name = this.normalizeInspectorNodeType(node.$type)
    const frame = this.parseInspectorFrame(node.$rect) ?? this.readFrameFromInspectorId(node.$ID)
    const style = this.parseInspectorStyle(node.$attrs)
    const text = this.parseInspectorText(node.$attrs)
    const visible = this.parseInspectorVisible(node.$attrs)
    const rawChildren = node.$children ?? []
    const children: ExportViewTreeNode[] = []
    for (let index = 0; index < rawChildren.length; index += 1) {
      const child = rawChildren[index]
      children.push(this.toInspectorViewTreeNode(child, nodeId, `${nodeId}-${String(index)}`))
    }
    return {
      id: nodeId,
      parentId,
      name,
      frame,
      style,
      text,
      visible,
      children
    }
  }

  private parseInspectorFrame(rawRect: string | undefined): ExportViewTreeFrame | undefined {
    if (rawRect === undefined) {
      return undefined
    }

    const values = rawRect.match(/-?\d+(?:\.\d+)?/g)
    if (values === null || values.length < 4) {
      return undefined
    }
    const left = Number.parseFloat(values[0])
    const top = Number.parseFloat(values[1])
    const right = Number.parseFloat(values[2])
    const bottom = Number.parseFloat(values[3])
    if (!Number.isFinite(left) || !Number.isFinite(top) || !Number.isFinite(right) || !Number.isFinite(bottom)) {
      return undefined
    }
    return {
      x: left,
      y: top,
      width: Math.max(0, right - left),
      height: Math.max(0, bottom - top)
    }
  }

  private readFrameFromInspectorId(uniqueId: number | undefined): ExportViewTreeFrame | undefined {
    if (this.uiContext === null || uniqueId === undefined || !Number.isFinite(uniqueId)) {
      return undefined
    }

    const node = this.uiContext.getFrameNodeByUniqueId(uniqueId)
    if (node === null) {
      return undefined
    }

    try {
      const position = node.getPositionToWindow()
      const size = node.getMeasuredSize()
      if (
        !Number.isFinite(position.x) ||
        !Number.isFinite(position.y) ||
        !Number.isFinite(size.width) ||
        !Number.isFinite(size.height)
      ) {
        return undefined
      }
      return {
        x: position.x,
        y: position.y,
        width: Math.max(0, size.width),
        height: Math.max(0, size.height)
      }
    } catch (_error) {
      return undefined
    }
  }

  private parseInspectorStyle(attrs: InspectorAttrs | undefined): ExportViewTreeStyle | undefined {
    if (attrs === undefined) {
      return undefined
    }

    const style: ExportViewTreeStyle = {}
    style.opacity = this.readAttrNumber(attrs, ['opacity', 'alpha'])
    style.backgroundColor = this.readAttrString(attrs, ['backgroundColor', 'background', 'bgColor', 'fill'])
    style.textColor = this.readAttrString(attrs, ['fontColor', 'textColor', 'color'])
    style.fontSize = this.readTypographyNumber(attrs, ['fontSize'], 'vp')
    style.lineHeight = this.readTypographyNumber(attrs, ['lineHeight'], 'fp')
    style.letterSpacing = this.readTypographyNumber(attrs, ['letterSpacing'], 'fp')
    style.fontWeight = this.readAttrString(attrs, ['fontWeight'])
    style.borderRadius = this.readAttrNumber(attrs, ['borderRadius', 'radius'])
    style.borderWidth = this.readAttrNumber(attrs, ['borderWidth', 'strokeWidth'])
    style.borderColor = this.readAttrString(attrs, ['borderColor', 'stroke'])
    style.zIndex = this.readAttrNumber(attrs, ['zIndex'])
    style.textAlign = this.readAttrString(attrs, ['textAlign', 'textAlignHorizontal', 'align'])
    if (
      style.fontSize !== undefined ||
      style.lineHeight !== undefined ||
      style.letterSpacing !== undefined
    ) {
      style.typographyUnit = 'dp'
    }

    if (
      style.opacity === undefined &&
      style.backgroundColor === undefined &&
      style.textColor === undefined &&
      style.fontSize === undefined &&
      style.lineHeight === undefined &&
      style.letterSpacing === undefined &&
      style.typographyUnit === undefined &&
      style.fontWeight === undefined &&
      style.borderRadius === undefined &&
      style.borderWidth === undefined &&
      style.borderColor === undefined &&
      style.zIndex === undefined &&
      style.textAlign === undefined
    ) {
      return undefined
    }
    return style
  }

  private parseInspectorText(attrs: InspectorAttrs | undefined): string | undefined {
    if (attrs === undefined) {
      return undefined
    }
    return this.readAttrString(attrs, ['content', 'text', 'value', 'label'])
  }

  private parseInspectorVisible(attrs: InspectorAttrs | undefined): boolean | undefined {
    if (attrs === undefined) {
      return undefined
    }

    const visible = this.readAttrBoolean(attrs, ['visible'])
    if (visible !== undefined) {
      return visible
    }
    const visibility = this.readAttrString(attrs, ['visibility'])
    if (visibility === undefined) {
      return undefined
    }
    const normalized = visibility.toLowerCase()
    return normalized !== 'hidden' && normalized !== 'gone' && normalized !== 'none'
  }

  private readAttrString(attrs: InspectorAttrs, keys: string[]): string | undefined {
    for (const key of keys) {
      const raw = this.readInspectorAttrValue(attrs, key)
      if (typeof raw === 'string') {
        const normalized = raw.trim()
        if (normalized.length > 0) {
          return normalized
        }
      }
    }
    return undefined
  }

  private readAttrNumber(attrs: InspectorAttrs, keys: string[]): number | undefined {
    for (const key of keys) {
      const raw = this.readInspectorAttrValue(attrs, key)
      if (typeof raw === 'number' && Number.isFinite(raw)) {
        return raw
      }
      if (typeof raw === 'string') {
        const parsed = Number.parseFloat(raw)
        if (Number.isFinite(parsed)) {
          return parsed
        }
      }
    }
    return undefined
  }

  private readTypographyNumber(
    attrs: InspectorAttrs,
    keys: string[],
    defaultUnit: 'vp' | 'fp'
  ): number | undefined {
    for (const key of keys) {
      const raw = this.readInspectorAttrValue(attrs, key)
      const value = this.normalizeTypographyNumber(raw, defaultUnit)
      if (value !== undefined) {
        return value
      }
    }
    return undefined
  }

  private normalizeTypographyNumber(
    raw: string | number | boolean | null | undefined,
    defaultUnit: 'vp' | 'fp'
  ): number | undefined {
    if (typeof raw === 'number' && Number.isFinite(raw)) {
      return this.convertTypographyNumber(raw, defaultUnit)
    }

    if (typeof raw !== 'string') {
      return undefined
    }

    const trimmed = raw.trim()
    if (trimmed.length === 0) {
      return undefined
    }

    const match = trimmed.match(/^(-?\d+(?:\.\d+)?)([a-zA-Z%]+)?$/)
    if (match === null) {
      const parsed = Number.parseFloat(trimmed)
      if (Number.isFinite(parsed)) {
        return this.convertTypographyNumber(parsed, defaultUnit)
      }
      return undefined
    }

    const value = Number.parseFloat(match[1])
    if (!Number.isFinite(value)) {
      return undefined
    }

    const unit = this.normalizeTypographySourceUnit(match[2], defaultUnit)
    if (unit === null) {
      return undefined
    }
    return this.convertTypographyNumber(value, unit)
  }

  private normalizeTypographySourceUnit(
    rawUnit: string | undefined,
    defaultUnit: 'vp' | 'fp'
  ): 'vp' | 'fp' | 'px' | null {
    const normalized = rawUnit?.trim().toLowerCase() ?? ''
    if (normalized.length === 0) {
      return defaultUnit
    }
    if (normalized === 'dp' || normalized === 'vp') {
      return 'vp'
    }
    if (normalized === 'fp') {
      return 'fp'
    }
    if (normalized === 'px') {
      return 'px'
    }
    return null
  }

  private convertTypographyNumber(value: number, unit: 'vp' | 'fp' | 'px'): number {
    switch (unit) {
      case 'vp':
        return value
      case 'fp':
        return value * this.resolveTypographyFontScale()
      case 'px':
        return this.convertPxToDp(value)
      default:
        return value
    }
  }

  private convertPxToDp(value: number): number {
    if (this.uiContext === null) {
      return value
    }

    try {
      return this.uiContext.px2vp(value)
    } catch (_error) {
      return value
    }
  }

  private resolveTypographyFontScale(): number {
    if (Number.isFinite(this.typographyFontScale) && this.typographyFontScale > 0) {
      return this.typographyFontScale
    }
    return 1
  }

  private updateTypographyScaleListener(context: UIContext): void {
    if (this.typographyEnvironmentCallbackId !== null) {
      return
    }

    const hostContext = context.getHostContext()
    const applicationContext = hostContext?.getApplicationContext()
    if (applicationContext === undefined) {
      return
    }

    const environmentCallback: EnvironmentCallback = {
      onConfigurationUpdated: (config: Configuration): void => {
        this.updateTypographyFontScale(config)
      },
      onMemoryLevel: (_level: AbilityConstant.MemoryLevel): void => {
      }
    }

    try {
      this.typographyEnvironmentCallbackId = applicationContext.on('environment', environmentCallback)
    } catch (_error) {
      this.typographyEnvironmentCallbackId = null
    }
  }

  private updateTypographyFontScale(config: Configuration): void {
    const fontSizeScale = config.fontSizeScale
    if (typeof fontSizeScale === 'number' && Number.isFinite(fontSizeScale) && fontSizeScale > 0) {
      this.typographyFontScale = fontSizeScale
    }
  }

  private readAttrBoolean(attrs: InspectorAttrs, keys: string[]): boolean | undefined {
    for (const key of keys) {
      const raw = this.readInspectorAttrValue(attrs, key)
      if (typeof raw === 'boolean') {
        return raw
      }
      if (typeof raw === 'string') {
        if (raw === 'true') {
          return true
        }
        if (raw === 'false') {
          return false
        }
      }
    }
    return undefined
  }

  private readInspectorAttrValue(
    attrs: InspectorAttrs,
    key: string
  ): string | number | boolean | null | undefined {
    switch (key) {
      case 'id':
        return attrs.id
      case 'opacity':
        return attrs.opacity
      case 'alpha':
        return attrs.alpha
      case 'backgroundColor':
        return attrs.backgroundColor
      case 'background':
        return attrs.background
      case 'bgColor':
        return attrs.bgColor
      case 'fill':
        return attrs.fill
      case 'fontColor':
        return attrs.fontColor
      case 'textColor':
        return attrs.textColor
      case 'color':
        return attrs.color
      case 'fontSize':
        return attrs.fontSize
      case 'fontWeight':
        return attrs.fontWeight
      case 'borderRadius':
        return attrs.borderRadius
      case 'radius':
        return attrs.radius
      case 'borderWidth':
        return attrs.borderWidth
      case 'borderColor':
        return attrs.borderColor
      case 'stroke':
        return attrs.stroke
      case 'strokeWidth':
        return attrs.strokeWidth
      case 'zIndex':
        return attrs.zIndex
      case 'textAlign':
        return attrs.textAlign
      case 'textAlignHorizontal':
        return attrs.textAlignHorizontal
      case 'align':
        return attrs.align
      case 'content':
        return attrs.content
      case 'text':
        return attrs.text
      case 'value':
        return attrs.value
      case 'label':
        return attrs.label
      case 'visible':
        return attrs.visible
      case 'visibility':
        return attrs.visibility
      default:
        return undefined
    }
  }

  private normalizeInspectorNodeId(node: InspectorNode, fallbackId: string): string {
    const attrId = node.$attrs?.id?.trim() ?? ''
    if (attrId.length > 0) {
      return attrId
    }

    if (node.$ID !== undefined && Number.isFinite(node.$ID)) {
      return `inspector-${String(node.$ID)}`
    }
    return fallbackId
  }

  private normalizeInspectorNodeType(rawType: string | undefined): string {
    if (rawType === undefined) {
      return 'UnknownNode'
    }
    const normalized = rawType.trim()
    return normalized.length > 0 ? normalized : 'UnknownNode'
  }

  private getInspectorTreePayload(): string {
    if (this.uiContext === null) {
      return '{}'
    }

    try {
      // Keep full attrs while including custom component nodes.
      return this.uiContext.getFilteredInspectorTree(['isLayoutInspector'])
    } catch (_error) {
      try {
        return this.uiContext.getFilteredInspectorTree()
      } catch (_fallbackError) {
        try {
          return this.uiContext.getFilteredInspectorTree(['content'])
        } catch (_finalError) {
          return '{}'
        }
      }
    }
  }

  private normalizeInspectorPayload(value: Object | string | number | boolean | null): Object | string | number | boolean | null {
    if (value === null) {
      return null
    }

    if (typeof value === 'string') {
      return this.parseEmbeddedJsonString(value)
    }

    if (Array.isArray(value)) {
      const normalizedArray: (Object | string | number | boolean | null)[] = []
      const items = value as (Object | string | number | boolean | null)[]
      for (let index = 0; index < items.length; index += 1) {
        normalizedArray.push(this.normalizeInspectorPayload(items[index]))
      }
      return normalizedArray as Object
    }

    if (typeof value !== 'object') {
      return value
    }

    const normalizedObject: Record<string, Object | string | number | boolean | null> = {}
    for (const key of Object.keys(value)) {
      const raw = (value as Record<string, Object | string | number | boolean | null>)[key]
      normalizedObject[key] = this.normalizeInspectorPayload(raw)
    }
    return normalizedObject
  }

  private parseEmbeddedJsonString(value: string): Object | string | number | boolean | null {
    const trimmed = value.trim()
    const maybeJson =
      (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
      (trimmed.startsWith('[') && trimmed.endsWith(']'))
    if (!maybeJson) {
      return value
    }

    try {
      const parsed = JSON.parse(trimmed) as Object | string | number | boolean | null
      return this.normalizeInspectorPayload(parsed)
    } catch (_error) {
      return value
    }
  }

  private captureFrameNodeRoots(): ExportViewTreeNode[] {
    const anchorNode = this.resolveAnchorNode()
    const rootNode = this.resolveTopRootNode(anchorNode)
    if (rootNode === null) {
      return []
    }
    return [this.toViewTreeNode(rootNode, null)]
  }

  private resolveAnchorNode(): FrameNode | null {
    if (this.uiContext === null || this.viewTreeAnchorUniqueId === null) {
      return null
    }
    return this.uiContext.getFrameNodeByUniqueId(this.viewTreeAnchorUniqueId)
  }

  private resolveTopRootNode(node: FrameNode | null): FrameNode | null {
    if (node === null) {
      return null
    }

    let current: FrameNode = node
    while (true) {
      const parent = current.getParent()
      if (parent === null || parent.getUniqueId() <= 0) {
        break
      }
      current = parent
    }
    return current
  }

  private toViewTreeNode(node: FrameNode, parentId: string | null): ExportViewTreeNode {
    const uniqueId = node.getUniqueId()
    const rawId = node.getId()
    const nodeId = this.normalizeNodeId(rawId, uniqueId)
    const nodeType = this.normalizeNodeType(node.getNodeType())
    const children: ExportViewTreeNode[] = []
    const count = node.getChildrenCount()
    for (let index = 0; index < count; index += 1) {
      const child = this.readChildNode(node, index)
      if (child !== null) {
        children.push(this.toViewTreeNode(child, nodeId))
      }
    }
    return {
      id: nodeId,
      parentId,
      name: nodeType,
      children
    }
  }

  private readChildNode(node: FrameNode, index: number): FrameNode | null {
    try {
      return node.getChild(index, ExpandMode.EXPAND)
    } catch (_error) {
      return node.getChild(index)
    }
  }

  private normalizeNodeId(rawId: string, uniqueId: number): string {
    const normalized = rawId.trim()
    if (normalized.length > 0) {
      return normalized
    }
    return `node-${String(uniqueId)}`
  }

  private normalizeNodeType(rawType: string): string {
    const normalized = rawType.trim()
    return normalized.length > 0 ? normalized : 'UnknownNode'
  }

  private normalizeViewTreePlatform(platform: string | undefined): Platform {
    if (platform === 'ios' || platform === 'android' || platform === 'web') {
      return platform
    }
    return 'harmony'
  }
}

export const demoRuntime = new DemoRuntime()
