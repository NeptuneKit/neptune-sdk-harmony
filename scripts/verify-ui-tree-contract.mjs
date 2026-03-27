#!/usr/bin/env node
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const exportServerFile = path.join(repoRoot, 'src/main/ets/server/ExportServer.ets')
const logModelsFile = path.join(repoRoot, 'src/main/ets/model/LogModels.ets')
const collectorFile = path.join(repoRoot, 'src/main/ets/ui-tree/ArkUIViewTreeCollector.ets')
const indexFile = path.join(repoRoot, 'src/main/ets/index.ets')

function read(filePath) {
  return fs.readFileSync(filePath, 'utf8')
}

function expectContains(filePath, needle, message) {
  assert.ok(read(filePath).includes(needle), message)
}

assert.ok(fs.existsSync(exportServerFile), 'ExportServer.ets must exist')
assert.ok(fs.existsSync(logModelsFile), 'LogModels.ets must exist')
assert.ok(fs.existsSync(collectorFile), 'ArkUIViewTreeCollector.ets must exist')

expectContains(exportServerFile, "server.get('/v2/ui-tree/inspector'", 'export server must expose ui-tree inspector route')
expectContains(exportServerFile, 'inspectorSnapshot(query', 'export server must provide inspectorSnapshot query entry')
expectContains(exportServerFile, 'snapshotId: `harmony-inspector-', 'inspector snapshot should include deterministic snapshot id prefix')
expectContains(exportServerFile, 'private normalizePlatform', 'export server must normalize ui-tree platform')
expectContains(exportServerFile, "return 'harmony'", 'ui-tree inspector platform should default to harmony')

expectContains(logModelsFile, 'ExportViewTreeNode', 'log models must define view tree node contract')
expectContains(logModelsFile, 'ExportInspectorSnapshot', 'log models must define inspector snapshot contract')
expectContains(logModelsFile, 'ViewTreeQueryOptions', 'log models must define view tree query options')
expectContains(logModelsFile, 'lineHeight?: number', 'log models must expose typography lineHeight')
expectContains(logModelsFile, 'letterSpacing?: number', 'log models must expose typography letterSpacing')
expectContains(logModelsFile, "typographyUnit?: 'dp'", 'log models must expose typography unit')
expectContains(logModelsFile, "sourceTypographyUnit?: 'vp' | 'fp' | 'px'", 'log models must expose source typography unit')
expectContains(logModelsFile, 'platformFontScale?: number', 'log models must expose platform font scale')
expectContains(logModelsFile, 'fontWeightRaw?: string', 'log models must expose raw font weight')
expectContains(indexFile, "export * from './ui-tree/ArkUIViewTreeCollector'", 'sdk index must export arkui ui-tree collector')
expectContains(collectorFile, 'captureInspectorSnapshot', 'collector must provide raw inspector snapshot conversion')
expectContains(collectorFile, 'style.typographyUnit =', 'collector must mark typography output unit')
expectContains(collectorFile, 'style.sourceTypographyUnit =', 'collector must preserve source typography unit')
expectContains(collectorFile, 'style.platformFontScale =', 'collector must expose platform font scale')
expectContains(collectorFile, 'style.fontWeightRaw =', 'collector must preserve raw font weight')
expectContains(collectorFile, 'readTypographyMeasurement', 'collector must normalize typography values with source unit')
expectContains(collectorFile, 'normalizeTypographyMeasurement', 'collector must preserve measurement metadata')
expectContains(collectorFile, 'normalizeTypographyText', 'collector must preserve raw typography text')
expectContains(collectorFile, 'normalizeTypographyInspectorPayload', 'collector must normalize inspector typography payload')

console.log('UI tree contract check passed.')
