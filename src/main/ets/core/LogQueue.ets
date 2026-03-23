import { IngestLogRecord, LogRecord, LOG_QUEUE_BATCH_SIZE, LOG_QUEUE_CAPACITY, LOG_QUEUE_FLUSH_INTERVAL_MS, LOG_QUEUE_RETRY_DELAYS_MS } from '../model/LogModels'

export interface QueueSnapshot {
  size: number
  capacity: number
  droppedOverflow: number
  lastEnqueuedAt: string | null
}

export class LogQueue {
  private records: LogRecord[] = []
  private nextId: number = 1
  private droppedOverflow: number = 0
  private lastFlushedAtMs: number = 0
  private totalExported: number = 0
  private totalIngested: number = 0

  readonly capacity: number = LOG_QUEUE_CAPACITY
  readonly batchSize: number = LOG_QUEUE_BATCH_SIZE
  readonly flushIntervalMs: number = LOG_QUEUE_FLUSH_INTERVAL_MS
  readonly retryDelaysMs: number[] = LOG_QUEUE_RETRY_DELAYS_MS

  enqueue(record: IngestLogRecord): LogRecord {
    const stored: LogRecord = {
      id: this.nextId,
      ...record
    }
    this.nextId += 1
    this.totalIngested += 1

    if (this.records.length >= this.capacity) {
      this.records.shift()
      this.droppedOverflow += 1
    }

    this.records.push(stored)
    return stored
  }

  appendAll(records: IngestLogRecord[]): LogRecord[] {
    const appended: LogRecord[] = []
    for (const record of records) {
      appended.push(this.enqueue(record))
    }
    return appended
  }

  drain(limit: number = this.batchSize): LogRecord[] {
    const drainSize = Math.max(0, Math.min(limit, this.records.length))
    const drained = this.records.slice(0, drainSize)
    this.records = this.records.slice(drainSize)
    this.totalExported += drained.length
    this.lastFlushedAtMs = Date.now()
    return drained
  }

  peekAfter(cursor?: string, limit: number = this.batchSize): LogRecord[] {
    const normalizedLimit = Math.max(1, Math.min(limit, this.batchSize))
    if (!cursor || cursor.trim().length === 0) {
      return this.records.slice(0, normalizedLimit)
    }

    const cursorId = Number(cursor)
    if (!Number.isFinite(cursorId)) {
      return this.records.slice(0, normalizedLimit)
    }

    return this.records.filter((item) => item.id > cursorId).slice(0, normalizedLimit)
  }

  hasMoreAfter(cursor?: string, limit: number = this.batchSize): boolean {
    const normalizedLimit = Math.max(1, Math.min(limit, this.batchSize))
    if (!cursor || cursor.trim().length === 0) {
      return this.records.length > normalizedLimit
    }

    const cursorId = Number(cursor)
    if (!Number.isFinite(cursorId)) {
      return this.records.length > normalizedLimit
    }

    let matched = 0
    for (const item of this.records) {
      if (item.id > cursorId) {
        matched += 1
        if (matched > normalizedLimit) {
          return true
        }
      }
    }

    return false
  }

  shouldFlush(nowMs: number = Date.now()): boolean {
    return nowMs - this.lastFlushedAtMs >= this.flushIntervalMs
  }

  markFlushed(nowMs: number = Date.now()): void {
    this.lastFlushedAtMs = nowMs
  }

  snapshot(): QueueSnapshot {
    return {
      size: this.records.length,
      capacity: this.capacity,
      droppedOverflow: this.droppedOverflow,
      lastEnqueuedAt: this.records.length > 0 ? this.records[this.records.length - 1].timestamp : null
    }
  }

  metrics(): { queueSize: number; queueCapacity: number; droppedOverflow: number; totalExported: number } {
    return {
      queueSize: this.records.length,
      queueCapacity: this.capacity,
      droppedOverflow: this.droppedOverflow,
      totalExported: this.totalExported
    }
  }

  totals(): { totalIngested: number; totalExported: number } {
    return {
      totalIngested: this.totalIngested,
      totalExported: this.totalExported
    }
  }
}
