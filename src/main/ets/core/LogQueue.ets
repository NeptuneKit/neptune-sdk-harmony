import { IngestLogRecord, LogRecord, LOG_QUEUE_BATCH_SIZE, LOG_QUEUE_CAPACITY, LOG_QUEUE_FLUSH_INTERVAL_MS, LOG_QUEUE_RETRY_DELAYS_MS } from '../model/LogModels'
import { LogStoreBase, LogStoreMetrics, LogStoreTotals, QueueSnapshot } from './LogStoreBase'
import { MemoryLogStore } from './MemoryLogStore'

export { QueueSnapshot }

export class LogQueue {
  private readonly store: LogStoreBase

  constructor(store: LogStoreBase = new MemoryLogStore()) {
    this.store = store
  }

  readonly capacity: number = LOG_QUEUE_CAPACITY
  readonly batchSize: number = LOG_QUEUE_BATCH_SIZE
  readonly flushIntervalMs: number = LOG_QUEUE_FLUSH_INTERVAL_MS
  readonly retryDelaysMs: number[] = LOG_QUEUE_RETRY_DELAYS_MS

  enqueue(record: IngestLogRecord): LogRecord {
    return this.store.enqueue(record)
  }

  appendAll(records: IngestLogRecord[]): LogRecord[] {
    return this.store.appendAll(records)
  }

  drain(limit: number = this.batchSize): LogRecord[] {
    return this.store.drain(limit)
  }

  peekAfter(cursor?: string, limit: number = this.batchSize, predicate?: (record: LogRecord) => boolean): LogRecord[] {
    return this.store.peekAfter(cursor, limit, predicate)
  }

  hasMoreAfter(cursor?: string, limit: number = this.batchSize, predicate?: (record: LogRecord) => boolean): boolean {
    return this.store.hasMoreAfter(cursor, limit, predicate)
  }

  shouldFlush(nowMs: number = Date.now()): boolean {
    return this.store.shouldFlush(nowMs)
  }

  markFlushed(nowMs: number = Date.now()): void {
    this.store.markFlushed(nowMs)
  }

  snapshot(): QueueSnapshot {
    return this.store.snapshot()
  }

  metrics(): LogStoreMetrics {
    return this.store.metrics()
  }

  totals(): LogStoreTotals {
    return this.store.totals()
  }

  flush(): Promise<void> {
    return this.store.flush()
  }
}
