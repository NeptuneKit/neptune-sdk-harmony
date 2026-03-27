export type Platform = 'ios' | 'android' | 'harmony' | 'web'
export type LogLevel = 'trace' | 'debug' | 'info' | 'notice' | 'warning' | 'error' | 'critical'

export type StringMap = Record<string, string>

export interface LogSourceInfo {
  sdkName: string
  sdkVersion: string
  file?: string
  function?: string
  line?: number
}

export interface IngestLogRecord {
  timestamp: string
  level: LogLevel
  message: string
  platform: Platform
  appId: string
  sessionId: string
  deviceId: string
  category: string
  attributes?: StringMap
  source?: LogSourceInfo
}

export interface LogRecord extends IngestLogRecord {
  id: number
}

export interface ExportCursorPage<T> {
  records: T[]
  hasMore: boolean
}

export interface ExportHealth {
  status: 'ok' | 'degraded'
  service: string
  version: string
  startedAt: string
}

export interface ExportMetrics {
  queueSize: number
  queueCapacity: number
  droppedOverflow: number
  totalIngested: number
  totalExported: number
}

export interface ExportSourceEntry {
  deviceId: string
  appId: string
  platform: Platform
  sessionId: string
  sdkName: string
  sdkVersion: string
  lastSeenAt: string
}

export interface ExportViewTreeNode {
  id: string
  parentId: string | null
  name: string
  frame?: ExportViewTreeFrame
  style?: ExportViewTreeStyle
  text?: string
  visible?: boolean
  children: ExportViewTreeNode[]
}

export interface ExportViewTreeFrame {
  x: number
  y: number
  width: number
  height: number
}

export interface ExportViewTreeStyle {
  opacity?: number
  backgroundColor?: string
  textColor?: string
  fontSize?: number
  lineHeight?: number
  letterSpacing?: number
  typographyUnit?: 'dp'
  sourceTypographyUnit?: 'vp' | 'fp' | 'px'
  platformFontScale?: number
  fontWeight?: string
  fontWeightRaw?: string
  borderRadius?: number
  borderWidth?: number
  borderColor?: string
  zIndex?: number
  textAlign?: string
}

export interface ExportViewTreeSnapshot {
  snapshotId: string
  capturedAt: string
  platform: Platform
  roots: ExportViewTreeNode[]
}

export interface ExportInspectorSnapshot {
  snapshotId: string
  capturedAt: string
  platform: Platform
  available: boolean
  payload: Object | null
  reason?: string
}

export interface LogQueryOptions {
  cursor?: string
  length?: number
  platform?: string
  appId?: string
  sessionId?: string
}

export interface ViewTreeQueryOptions {
  platform?: string
  appId?: string
  sessionId?: string
  deviceId?: string
}

export interface ExportServerRoute {
  method: 'GET' | 'POST'
  path: string
  description: string
}

export interface ExportServerResponse<T> {
  statusCode: number
  body: T
}

export const LOG_QUEUE_CAPACITY: number = 2000
export const LOG_QUEUE_BATCH_SIZE: number = 50
export const LOG_QUEUE_FLUSH_INTERVAL_MS: number = 1000
export const LOG_QUEUE_RETRY_DELAYS_MS: number[] = [500, 1000, 2000, 4000, 8000]
