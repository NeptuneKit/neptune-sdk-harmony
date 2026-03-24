import relationalStore from '@kit.ArkData'
import { IngestLogRecord, LogRecord } from '../model/LogModels'
import { LogStoreBase } from './LogStoreBase'

export interface RdbLogStoreOptions {
  databaseName?: string
  tableName?: string
  metaTableName?: string
}

interface MetaSnapshot {
  nextId: number
  droppedOverflow: number
  lastFlushedAtMs: number
  totalExported: number
  totalIngested: number
}

export class RdbLogStore extends LogStoreBase {
  private readonly context: ESObject
  private readonly databaseName: string
  private readonly tableName: string
  private readonly metaTableName: string
  private store: ESObject | null = null
  private pendingPersist: Promise<void> = Promise.resolve()

  constructor(context: ESObject, options: RdbLogStoreOptions = {}) {
    super()
    this.context = context
    this.databaseName = options.databaseName ?? 'neptune_sdk_harmony_logs.db'
    this.tableName = options.tableName ?? 'logs'
    this.metaTableName = options.metaTableName ?? 'queue_meta'
  }

  async hydrate(): Promise<void> {
    const store = await this.openStore()
    await this.ensureSchema()
    const records = await this.readRecords()
    const meta = await this.readMeta()
    const nextId = meta.nextId > 0 ? meta.nextId : this.calculateNextId(records)
    this.restore({
      records,
      nextId,
      droppedOverflow: meta.droppedOverflow,
      lastFlushedAtMs: meta.lastFlushedAtMs,
      totalExported: meta.totalExported,
      totalIngested: meta.totalIngested
    })
    this.store = store
  }

  flush(): Promise<void> {
    return this.pendingPersist.then(() => {
      this.markFlushed()
    })
  }

  protected afterEnqueue(stored: LogRecord, dropped?: LogRecord): void {
    void this.queuePersistOperation(async () => {
      await this.upsertRecord(stored)
      if (dropped !== undefined) {
        await this.deleteRecord(dropped.id)
      }
      await this.upsertMeta({
        nextId: this.nextId,
        droppedOverflow: this.droppedOverflow,
        lastFlushedAtMs: this.lastFlushedAtMs,
        totalExported: this.totalExported,
        totalIngested: this.totalIngested
      })
    })
  }

  protected afterDrain(drained: LogRecord[]): void {
    void this.queuePersistOperation(async () => {
      for (const item of drained) {
        await this.deleteRecord(item.id)
      }
      await this.upsertMeta({
        nextId: this.nextId,
        droppedOverflow: this.droppedOverflow,
        lastFlushedAtMs: this.lastFlushedAtMs,
        totalExported: this.totalExported,
        totalIngested: this.totalIngested
      })
    })
  }

  private async openStore(): Promise<ESObject> {
    if (this.store !== null) {
      return this.store
    }

    const storeConfig = {
      name: this.databaseName,
      securityLevel: relationalStore.SecurityLevel.S1
    }

    const store = await this.invokeMaybeAsync((relationalStore as ESObject).getRdbStore, [
      this.context,
      storeConfig,
      1
    ])
    this.store = store as ESObject
    return this.store
  }

  private async ensureSchema(): Promise<void> {
    await this.runSql(`CREATE TABLE IF NOT EXISTS ${this.tableName} (
      id INTEGER PRIMARY KEY,
      timestamp TEXT NOT NULL,
      level TEXT NOT NULL,
      message TEXT NOT NULL,
      platform TEXT NOT NULL,
      appId TEXT NOT NULL,
      sessionId TEXT NOT NULL,
      deviceId TEXT NOT NULL,
      category TEXT NOT NULL,
      attributes TEXT,
      sourceSdkName TEXT,
      sourceSdkVersion TEXT,
      sourceFile TEXT,
      sourceFunction TEXT,
      sourceLine INTEGER
    )`)
    await this.runSql(`CREATE TABLE IF NOT EXISTS ${this.metaTableName} (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )`)
  }

  private async readRecords(): Promise<LogRecord[]> {
    const resultSet = await this.querySql(`SELECT id, timestamp, level, message, platform, appId, sessionId, deviceId, category, attributes, sourceSdkName, sourceSdkVersion, sourceFile, sourceFunction, sourceLine FROM ${this.tableName} ORDER BY id ASC`)
    const records: LogRecord[] = []
    if (resultSet === null || resultSet === undefined) {
      return records
    }

    try {
      const hasRow = typeof resultSet.goToFirstRow === 'function' ? resultSet.goToFirstRow() : false
      if (!hasRow) {
        return records
      }

      do {
        records.push(this.readRecord(resultSet))
      } while (typeof resultSet.goToNextRow === 'function' ? resultSet.goToNextRow() : false)
    } finally {
      if (typeof resultSet.close === 'function') {
        resultSet.close()
      }
    }

    return records
  }

  private readRecord(resultSet: ESObject): LogRecord {
    const attributesJson = this.readString(resultSet, 'attributes')
    const sourceSdkName = this.readNullableString(resultSet, 'sourceSdkName')
    const sourceSdkVersion = this.readNullableString(resultSet, 'sourceSdkVersion')
    const sourceFile = this.readNullableString(resultSet, 'sourceFile')
    const sourceFunction = this.readNullableString(resultSet, 'sourceFunction')
    const sourceLine = this.readNullableNumber(resultSet, 'sourceLine')

    return {
      id: this.readNumber(resultSet, 'id'),
      timestamp: this.readString(resultSet, 'timestamp'),
      level: this.readString(resultSet, 'level') as LogRecord['level'],
      message: this.readString(resultSet, 'message'),
      platform: this.readString(resultSet, 'platform') as LogRecord['platform'],
      appId: this.readString(resultSet, 'appId'),
      sessionId: this.readString(resultSet, 'sessionId'),
      deviceId: this.readString(resultSet, 'deviceId'),
      category: this.readString(resultSet, 'category'),
      attributes: this.parseAttributes(attributesJson),
      source: this.makeSource(sourceSdkName, sourceSdkVersion, sourceFile, sourceFunction, sourceLine)
    }
  }

  private makeSource(
    sdkName: string | null,
    sdkVersion: string | null,
    file: string | null,
    functionName: string | null,
    line: number | null
  ): IngestLogRecord['source'] {
    if (sdkName === null || sdkVersion === null) {
      return undefined
    }

    const source: NonNullable<IngestLogRecord['source']> = {
      sdkName: sdkName,
      sdkVersion: sdkVersion
    }

    if (file !== null) {
      source.file = file
    }
    if (functionName !== null) {
      source.function = functionName
    }
    if (line !== null) {
      source.line = line
    }

    return source
  }

  private parseAttributes(value: string | null): { [key: string]: string } | undefined {
    if (value === null || value.length === 0) {
      return undefined
    }

    try {
      return JSON.parse(value) as { [key: string]: string }
    } catch (_error) {
      return undefined
    }
  }

  private async readMeta(): Promise<MetaSnapshot> {
    const rows = await this.queryMetaRows()
    const meta: MetaSnapshot = {
      nextId: 1,
      droppedOverflow: 0,
      lastFlushedAtMs: 0,
      totalExported: 0,
      totalIngested: 0
    }

    for (const row of rows) {
      if (row.key === 'nextId') {
        meta.nextId = Number(row.value)
        continue
      }
      if (row.key === 'droppedOverflow') {
        meta.droppedOverflow = Number(row.value)
        continue
      }
      if (row.key === 'lastFlushedAtMs') {
        meta.lastFlushedAtMs = Number(row.value)
        continue
      }
      if (row.key === 'totalExported') {
        meta.totalExported = Number(row.value)
        continue
      }
      if (row.key === 'totalIngested') {
        meta.totalIngested = Number(row.value)
      }
    }

    return meta
  }

  private async queryMetaRows(): Promise<Array<{ key: string; value: string }>> {
    const resultSet = await this.querySql(`SELECT key, value FROM ${this.metaTableName}`)
    const rows: Array<{ key: string; value: string }> = []
    if (resultSet === null || resultSet === undefined) {
      return rows
    }

    try {
      const hasRow = typeof resultSet.goToFirstRow === 'function' ? resultSet.goToFirstRow() : false
      if (!hasRow) {
        return rows
      }

      do {
        rows.push({
          key: this.readString(resultSet, 'key'),
          value: this.readString(resultSet, 'value')
        })
      } while (typeof resultSet.goToNextRow === 'function' ? resultSet.goToNextRow() : false)
    } finally {
      if (typeof resultSet.close === 'function') {
        resultSet.close()
      }
    }

    return rows
  }

  private async upsertRecord(record: LogRecord): Promise<void> {
    const attributes = record.attributes === undefined ? null : JSON.stringify(record.attributes)
    const source = record.source
    await this.runSql(
      `INSERT OR REPLACE INTO ${this.tableName} (
        id, timestamp, level, message, platform, appId, sessionId, deviceId, category, attributes, sourceSdkName, sourceSdkVersion, sourceFile, sourceFunction, sourceLine
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        record.id,
        record.timestamp,
        record.level,
        record.message,
        record.platform,
        record.appId,
        record.sessionId,
        record.deviceId,
        record.category,
        attributes,
        source?.sdkName ?? null,
        source?.sdkVersion ?? null,
        source?.file ?? null,
        source?.function ?? null,
        source?.line ?? null
      ]
    )
  }

  private async deleteRecord(id: number): Promise<void> {
    await this.runSql(`DELETE FROM ${this.tableName} WHERE id = ?`, [id])
  }

  private async upsertMeta(meta: MetaSnapshot): Promise<void> {
    await this.writeMeta('nextId', String(meta.nextId))
    await this.writeMeta('droppedOverflow', String(meta.droppedOverflow))
    await this.writeMeta('lastFlushedAtMs', String(meta.lastFlushedAtMs))
    await this.writeMeta('totalExported', String(meta.totalExported))
    await this.writeMeta('totalIngested', String(meta.totalIngested))
  }

  private async writeMeta(key: string, value: string): Promise<void> {
    await this.runSql(`INSERT OR REPLACE INTO ${this.metaTableName} (key, value) VALUES (?, ?)`, [key, value])
  }

  private async runSql(sql: string, args?: Array<string | number | null>): Promise<void> {
    const store = await this.openStore()
    await this.invokeMaybeAsync((store as ESObject).executeSql, [sql, args ?? []], store)
  }

  private async querySql(sql: string, args?: Array<string | number | null>): Promise<ESObject | null> {
    const store = await this.openStore()
    return await this.invokeMaybeAsync((store as ESObject).querySql, [sql, args ?? []], store) as ESObject | null
  }

  private readString(resultSet: ESObject, columnName: string): string {
    const value = this.readNullableString(resultSet, columnName)
    return value === null ? '' : value
  }

  private readNullableString(resultSet: ESObject, columnName: string): string | null {
    if (typeof resultSet.getString === 'function') {
      const value = resultSet.getString(columnName)
      return value === null || value === undefined ? null : String(value)
    }

    const value = resultSet[columnName]
    return value === null || value === undefined ? null : String(value)
  }

  private readNullableNumber(resultSet: ESObject, columnName: string): number | null {
    if (typeof resultSet.getLong === 'function') {
      const value = resultSet.getLong(columnName)
      return value === null || value === undefined ? null : Number(value)
    }

    const value = resultSet[columnName]
    if (value === null || value === undefined) {
      return null
    }

    return Number(value)
  }

  private readNumber(resultSet: ESObject, columnName: string): number {
    const value = this.readNullableNumber(resultSet, columnName)
    return value === null ? 0 : value
  }

  private queuePersistOperation(task: () => Promise<void>): Promise<void> {
    this.pendingPersist = this.pendingPersist
      .then(async () => {
        await task()
      })
      .catch(() => undefined)

    return this.pendingPersist
  }

  private async invokeMaybeAsync(callable: any, args: any[], receiver?: any): Promise<any> {
    return await new Promise((resolve, reject) => {
      const callback = (error: any, value?: any): void => {
        if (error !== undefined && error !== null) {
          reject(error)
          return
        }

        resolve(value ?? undefined)
      }

      try {
        const callArgs = args.slice()
        callArgs.push(callback)
        const result = receiver === undefined ? callable(...callArgs) : callable.call(receiver, ...callArgs)

        if (result !== undefined && result !== null && typeof result.then === 'function') {
          result.then((value: any) => {
            resolve(value)
          }).catch((error: any) => {
            reject(error)
          })
          return
        }

        if (result !== undefined && result !== null) {
          resolve(result)
        }
      } catch (error) {
        reject(error)
      }
    })
  }
}
