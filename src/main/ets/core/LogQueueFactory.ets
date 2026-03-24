import { LogQueue } from './LogQueue'
import { RdbLogStore, RdbLogStoreOptions } from './RdbLogStore'

export interface PersistentLogQueueOptions extends RdbLogStoreOptions {}

export async function createPersistentLogQueue(context: ESObject, options: PersistentLogQueueOptions = {}): Promise<LogQueue> {
  const store = new RdbLogStore(context, options)
  await store.hydrate()
  return new LogQueue(store)
}
