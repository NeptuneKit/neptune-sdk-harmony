import assert from 'node:assert/strict'

class ReferencePersistentAdapter {
  constructor(snapshot = null) {
    this.snapshot = snapshot ?? {
      records: [],
      meta: {
        nextId: 1,
        droppedOverflow: 0,
        totalIngested: 0,
        totalExported: 0
      }
    }
  }

  load() {
    return structuredClone(this.snapshot)
  }

  save(nextSnapshot) {
    this.snapshot = structuredClone(nextSnapshot)
  }
}

class ReferencePersistentQueue {
  constructor(adapter, capacity = 3) {
    this.adapter = adapter
    this.capacity = capacity
    this.state = adapter.load()
  }

  hydrate() {
    this.state = this.adapter.load()
  }

  ingest(record) {
    const stored = { id: this.state.meta.nextId, ...record }
    this.state.meta.nextId += 1
    this.state.meta.totalIngested += 1
    if (this.state.records.length >= this.capacity) {
      this.state.records.shift()
      this.state.meta.droppedOverflow += 1
    }
    this.state.records.push(stored)
    this.adapter.save(this.state)
    return stored
  }

  peekAfter(cursor, limit = this.capacity, predicate = () => true) {
    const cursorId = cursor === undefined || cursor === null || cursor === '' ? Number.NEGATIVE_INFINITY : Number(cursor)
    return this.state.records
      .filter((item) => item.id > cursorId)
      .filter((item) => predicate(item))
      .slice(0, limit)
  }
}

const source = {
  timestamp: '2026-03-24T01:00:00.000Z',
  level: 'info',
  message: 'persist-me',
  platform: 'harmony',
  appId: 'demo.app',
  sessionId: 'session-1',
  deviceId: 'device-1',
  category: 'lifecycle',
  source: {
    sdkName: 'neptune-sdk-harmony',
    sdkVersion: '0.1.0'
  }
}

const adapter = new ReferencePersistentAdapter()
const queue1 = new ReferencePersistentQueue(adapter)
const first = queue1.ingest(source)
const second = queue1.ingest({ ...source, message: 'persist-me-too', timestamp: '2026-03-24T01:00:01.000Z' })

assert.equal(first.id, 1)
assert.equal(second.id, 2)
assert.equal(queue1.peekAfter('', 10).length, 2)

const restartedQueue = new ReferencePersistentQueue(adapter)
restartedQueue.hydrate()

assert.equal(restartedQueue.peekAfter('', 10).length, 2)
assert.deepEqual(restartedQueue.peekAfter('1', 10).map((item) => item.message), ['persist-me-too'])

const overflowQueue = new ReferencePersistentQueue(new ReferencePersistentAdapter(), 1)
overflowQueue.ingest(source)
overflowQueue.ingest({ ...source, message: 'latest' })
assert.deepEqual(overflowQueue.peekAfter('', 10).map((item) => item.message), ['latest'])

console.log('persistent log contract ok')
