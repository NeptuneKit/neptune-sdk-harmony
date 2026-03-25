#!/usr/bin/env node
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

function read(filePath) {
  return fs.readFileSync(filePath, 'utf8')
}

function expectContains(filePath, needle, message) {
  assert.ok(read(filePath).includes(needle), message)
}

const wsClientFile = path.join(repoRoot, 'src/main/ets/ws/GatewayWsClient.ets')
const wsManagerFile = path.join(repoRoot, 'src/main/ets/ws/GatewayWsManager.ets')
const wsTypesFile = path.join(repoRoot, 'src/main/ets/ws/GatewayWsModels.ets')

assert.ok(fs.existsSync(wsClientFile), 'GatewayWsClient.ets must exist')
assert.ok(fs.existsSync(wsManagerFile), 'GatewayWsManager.ets must exist')
assert.ok(fs.existsSync(wsTypesFile), 'GatewayWsModels.ets must exist')

expectContains(wsClientFile, "createWebSocket()", 'WS client must create the socket through NetworkKit')
expectContains(wsClientFile, '/v2/ws', 'WS client must connect to /v2/ws')
expectContains(wsClientFile, 'hello', 'WS client must send a hello message after connect')
expectContains(wsClientFile, 'role: \'sdk\'', 'WS client hello must identify the sdk role')
expectContains(wsClientFile, 'platform: this.platform', 'WS client hello must carry platform')
expectContains(wsClientFile, 'appId: this.appId', 'WS client hello must carry appId')
expectContains(wsClientFile, 'sessionId: this.sessionId', 'WS client hello must carry sessionId')
expectContains(wsClientFile, 'deviceId: this.deviceId', 'WS client hello must carry deviceId')
expectContains(wsClientFile, 'normalizeText(options.platform', 'WS client must accept a platform option')
expectContains(wsClientFile, 'normalizeText(options.appId', 'WS client must accept an appId option')
expectContains(wsClientFile, 'normalizeText(options.sessionId', 'WS client must accept a sessionId option')
expectContains(wsClientFile, 'normalizeText(options.deviceId', 'WS client must accept a deviceId option')
expectContains(wsClientFile, 'DEFAULT_GATEWAY_WS_HEARTBEAT_INTERVAL_MS', 'WS client must use the shared heartbeat interval constant')
expectContains(wsClientFile, 'DEFAULT_GATEWAY_WS_HEARTBEAT_TIMEOUT_MS', 'WS client must use the shared heartbeat timeout constant')
expectContains(wsClientFile, 'DEFAULT_GATEWAY_WS_RECONNECT_DELAYS_MS', 'WS client must use the shared reconnect backoff table')
expectContains(wsClientFile, 'command.dispatch', 'WS client must handle command.dispatch frames')
expectContains(wsClientFile, 'command.ack', 'WS client must answer dispatch ping with command.ack')

expectContains(wsManagerFile, 'manualDsn', 'WS manager must accept manual DSN input')
expectContains(wsManagerFile, 'discoverGateway', 'WS manager must be able to resolve gateway endpoints')
expectContains(wsManagerFile, 'setGatewayEndpoint', 'WS manager must react to endpoint updates')
expectContains(wsManagerFile, 'reconnect', 'WS manager must reconnect after endpoint changes')

expectContains(wsTypesFile, 'GatewayWsFrame', 'WS model file must define the wire frame types')
expectContains(wsTypesFile, 'DEFAULT_GATEWAY_WS_PLATFORM', 'WS model file must define a default platform')
expectContains(wsTypesFile, 'DEFAULT_GATEWAY_WS_APP_ID', 'WS model file must define a default appId')
expectContains(wsTypesFile, 'DEFAULT_GATEWAY_WS_SESSION_ID', 'WS model file must define a default sessionId')
expectContains(wsTypesFile, 'DEFAULT_GATEWAY_WS_DEVICE_ID', 'WS model file must define a default deviceId')
expectContains(wsTypesFile, '15000', 'WS model file must define the 15s heartbeat interval')
expectContains(wsTypesFile, '45000', 'WS model file must define the 45s lost-connection timeout')
expectContains(wsTypesFile, '500, 1000, 2000, 4000, 8000', 'WS model file must define the requested reconnect backoff table')
expectContains(wsTypesFile, 'command.dispatch', 'WS model file must define command.dispatch handling')
expectContains(wsTypesFile, 'command.ack', 'WS model file must define command.ack payloads')

console.log('Gateway WS contract check passed.')
