import { HarmonyLogLevel, HarmonyLogMetadata, Logger } from 'harmony-log'

export type NeptuneHarmonyLogValue = string | number | boolean | null | undefined

export function createNeptuneHarmonyLogger(
  label: string,
  level: HarmonyLogLevel = HarmonyLogLevel.INFO
): Logger {
  const logger = Logger.logger(label)
  logger.level = level
  logger.setMetadata('sdk', 'neptune-sdk-harmony')
  return logger
}

export function createNeptuneHarmonyMetadata(): HarmonyLogMetadata {
  return new HarmonyLogMetadata()
}

export function setNeptuneHarmonyMetadata(
  metadata: HarmonyLogMetadata,
  key: string,
  value: NeptuneHarmonyLogValue
): void {
  if (value !== undefined) {
    metadata.set(key, value)
  }
}
