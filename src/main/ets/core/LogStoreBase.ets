import { IngestLogRecord, LogRecord, LOG_QUEUE_BATCH_SIZE, LOG_QUEUE_CAPACITY, LOG_QUEUE_FLUSH_INTERVAL_MS, LOG_QUEUE_RETRY_DELAYS_MS } from '../model/LogModels'

export interface QueueSnapshot {
  size: number
  capacity: number
  droppedOverflow: number
  lastEnqueuedAt: string | null
}

export interface LogStoreSnapshot {
  records: LogRecord[]
  nextId: number
  droppedOverflow: number
  lastFlushedAtMs: number
  totalExported: number
  totalIngested: number
}

export interface LogStoreMetrics {
  queueSize: number
  queueCapacity: number
  droppedOverflow: number
  totalExported: number
}

export interface LogStoreTotals {
  totalIngested: number
  totalExported: number
}

export abstract class LogStoreBase {
  protected records: LogRecord[] = []
  protected nextId: number = 1
  protected droppedOverflow: number = 0
  protected lastFlushedAtMs: number = 0
  protected totalExported: number = 0
  protected totalIngested: number = 0

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

    let dropped: LogRecord | undefined = undefined
    if (this.records.length >= this.capacity) {
      dropped = this.records.shift()
      this.droppedOverflow += 1
    }

    this.records.push(stored)
    this.afterEnqueue(stored, dropped)
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
    this.afterDrain(drained)
    return drained
  }

  peekAfter(cursor?: string, limit: number = this.batchSize, predicate?: (record: LogRecord) => boolean): LogRecord[] {
    const normalizedLimit = Math.max(1, Math.min(limit, this.batchSize))
    const records = this.recordsAfter(cursor)
    return records.filter((item) => this.matchesPredicate(item, predicate)).slice(0, normalizedLimit)
  }

  hasMoreAfter(cursor?: string, limit: number = this.batchSize, predicate?: (record: LogRecord) => boolean): boolean {
    const normalizedLimit = Math.max(1, Math.min(limit, this.batchSize))
    let matched = 0
    for (const item of this.recordsAfter(cursor)) {
      if (!this.matchesPredicate(item, predicate)) {
        continue
      }
      matched += 1
      if (matched > normalizedLimit) {
        return true
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

  metrics(): LogStoreMetrics {
    return {
      queueSize: this.records.length,
      queueCapacity: this.capacity,
      droppedOverflow: this.droppedOverflow,
      totalExported: this.totalExported
    }
  }

  totals(): LogStoreTotals {
    return {
      totalIngested: this.totalIngested,
      totalExported: this.totalExported
    }
  }

  flush(): Promise<void> {
    this.markFlushed()
    return Promise.resolve()
  }

  protected restore(snapshot: LogStoreSnapshot): void {
    this.records = snapshot.records.slice()
    this.nextId = snapshot.nextId > 0 ? snapshot.nextId : this.calculateNextId(this.records)
    this.droppedOverflow = Math.max(0, snapshot.droppedOverflow)
    this.lastFlushedAtMs = Math.max(0, snapshot.lastFlushedAtMs)
    this.totalExported = Math.max(0, snapshot.totalExported)
    this.totalIngested = Math.max(0, snapshot.totalIngested)
  }

  protected afterEnqueue(_stored: LogRecord, _dropped?: LogRecord): void {}

  protected afterDrain(_drained: LogRecord[]): void {}

  protected recordsAfter(cursor?: string): LogRecord[] {
    if (!cursor || cursor.trim().length === 0) {
      return this.records
    }

    const cursorId = Number(cursor)
    if (!Number.isFinite(cursorId)) {
      return this.records
    }

    return this.records.filter((item) => item.id > cursorId)
  }

  protected calculateNextId(records: LogRecord[]): number {
    if (records.length === 0) {
      return 1
    }

    return records[records.length - 1].id + 1
  }

  private matchesPredicate(record: LogRecord, predicate?: (record: LogRecord) => boolean): boolean {
    return predicate === undefined ? true : predicate(record)
  }
}
