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

const exportServerFile = path.join(repoRoot, 'src/main/ets/server/ExportServer.ets')
const callbackModelsFile = path.join(repoRoot, 'src/main/ets/callback/CallbackModels.ets')
const callbackHttpClientFile = path.join(repoRoot, 'src/main/ets/callback/GatewayClientRegistrationHttpClient.ets')
const callbackManagerFile = path.join(repoRoot, 'src/main/ets/callback/GatewayClientCallbackManager.ets')

assert.ok(fs.existsSync(exportServerFile), 'ExportServer.ets must exist')
assert.ok(fs.existsSync(callbackModelsFile), 'CallbackModels.ets must exist')
assert.ok(fs.existsSync(callbackHttpClientFile), 'GatewayClientRegistrationHttpClient.ets must exist')
assert.ok(fs.existsSync(callbackManagerFile), 'GatewayClientCallbackManager.ets must exist')

expectContains(exportServerFile, 'server.startServer(port, address)', 'local HTTP server must accept an explicit listen address')
expectContains(exportServerFile, '0.0.0.0', 'local HTTP server should default to a reachable bind address')
expectContains(exportServerFile, '/v2/client/command', 'local HTTP server must expose the command callback route')
expectContains(exportServerFile, 'ping acknowledged', 'local command route must ack ping')
expectContains(exportServerFile, 'status: \'ok\'', 'local command route must return ok status for ping')
expectContains(exportServerFile, 'status: \'error\'', 'local command route must return error status for unsupported commands')
expectContains(exportServerFile, 'return [platform, appId, deviceId].join', 'source identity must key on platform + appId + deviceId')

expectContains(callbackModelsFile, 'callbackEndpoint', 'callback payload must include callbackEndpoint')
expectContains(callbackModelsFile, 'preferredTransports', 'callback payload must include preferredTransports')
expectContains(callbackModelsFile, 'GatewayClientBusEnvelope', 'callback model file must define the v2 bus envelope')
expectContains(callbackModelsFile, 'GatewayClientCommandAck', 'callback model file must define command ACK payloads')
expectContains(callbackModelsFile, 'requestId', 'callback model file must keep requestId in the command payload')

expectContains(callbackHttpClientFile, '/v2/clients:register', 'registration client must target the register endpoint')
expectContains(callbackHttpClientFile, 'POST', 'registration client must use POST')
expectContains(callbackHttpClientFile, 'application/json; charset=utf-8', 'registration client must send JSON')

expectContains(callbackManagerFile, '0.0.0.0', 'callback manager must default to a bindable listen address')
expectContains(callbackManagerFile, '30000', 'callback manager must renew every 30 seconds')
expectContains(callbackManagerFile, 'callbackBaseUrl', 'callback manager must compute a callback base URL')
expectContains(callbackManagerFile, 'setGatewayEndpoint', 'callback manager must react to gateway endpoint changes')
expectContains(callbackManagerFile, '/v2/client/command', 'callback manager must advertise the command callback path')
expectContains(callbackManagerFile, 'preferredTransports', 'callback manager must send preferredTransports')

console.log('Client callback contract check passed.')
