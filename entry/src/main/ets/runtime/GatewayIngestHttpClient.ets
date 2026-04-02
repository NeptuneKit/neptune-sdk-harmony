import http from '@ohos.net.http'

import {
  createNeptuneHarmonyLogger,
  createNeptuneHarmonyMetadata,
  IngestLogRecord,
  Platform,
  setNeptuneHarmonyMetadata
} from 'neptune-sdk-harmony'

export interface GatewayIngestResult {
  state: 'success' | 'failed'
  title: string
  detail: string
  timestamp: string
}

export interface GatewayRawViewTreeIngestRecord {
  platform: Platform
  appId: string
  sessionId: string
  deviceId: string
  snapshotId: string
  capturedAt: string
  payload: Object
}

export class GatewayIngestHttpClient {
  private readonly logger = createNeptuneHarmonyLogger('Neptune.Ingest.HttpClient')

  async ingest(
    endpointUrl: string,
    record: IngestLogRecord | IngestLogRecord[],
    timeoutMs: number = 2000
  ): Promise<GatewayIngestResult> {
    const httpRequest: http.HttpRequest = http.createHttp()
    const requestTimeout = timeoutMs > 0 ? timeoutMs : 2000
    const requestUrl = this.makeIngestUrl(endpointUrl)

    try {
      const response: http.HttpResponse = await httpRequest.request(requestUrl, {
        method: http.RequestMethod.POST,
        connectTimeout: requestTimeout,
        readTimeout: requestTimeout,
        expectDataType: http.HttpDataType.STRING,
        header: {
          'content-type': 'application/json; charset=utf-8'
        },
        extraData: JSON.stringify(record)
      })
      const statusCode = Number(response.responseCode)
      const bodyText = this.normalizeBodyText(response.result)
      if (statusCode >= 200 && statusCode < 300) {
        const metadata = createNeptuneHarmonyMetadata()
        setNeptuneHarmonyMetadata(metadata, 'endpoint', requestUrl)
        setNeptuneHarmonyMetadata(metadata, 'statusCode', statusCode)
        this.logger.info(
          'log ingest request succeeded',
          metadata
        )
        return {
          state: 'success',
          title: '日志上报成功',
          detail: `POST /v2/logs:ingest -> ${statusCode}${bodyText.length > 0 ? ` · ${bodyText}` : ''}`,
          timestamp: new Date().toISOString()
        }
      }

      const metadata = createNeptuneHarmonyMetadata()
      setNeptuneHarmonyMetadata(metadata, 'endpoint', requestUrl)
      setNeptuneHarmonyMetadata(metadata, 'statusCode', statusCode)
      setNeptuneHarmonyMetadata(metadata, 'bodyText', bodyText)
      this.logger.error(
        'log ingest request failed',
        metadata
      )
      return {
        state: 'failed',
        title: '日志上报失败',
        detail: `POST /v2/logs:ingest -> ${statusCode}${bodyText.length > 0 ? ` · ${bodyText}` : ''}`,
        timestamp: new Date().toISOString()
      }
    } catch (error) {
      const metadata = createNeptuneHarmonyMetadata()
      setNeptuneHarmonyMetadata(metadata, 'endpoint', requestUrl)
      setNeptuneHarmonyMetadata(metadata, 'error', error instanceof Error ? error.message : String(error))
      this.logger.error(
        'log ingest request exception',
        metadata
      )
      return {
        state: 'failed',
        title: '日志上报失败',
        detail: error instanceof Error ? error.message : String(error),
        timestamp: new Date().toISOString()
      }
    } finally {
      httpRequest.destroy()
    }
  }

  async ingestRawViewTree(
    endpointUrl: string,
    record: GatewayRawViewTreeIngestRecord,
    timeoutMs: number = 2000
  ): Promise<GatewayIngestResult> {
    const httpRequest: http.HttpRequest = http.createHttp()
    const requestTimeout = timeoutMs > 0 ? timeoutMs : 2000
    const requestUrl = this.makeRawViewTreeIngestUrl(endpointUrl)
    const normalizedRecord = this.normalizeRawViewTreeRecord(record)

    try {
      const response: http.HttpResponse = await httpRequest.request(requestUrl, {
        method: http.RequestMethod.POST,
        connectTimeout: requestTimeout,
        readTimeout: requestTimeout,
        expectDataType: http.HttpDataType.STRING,
        header: {
          'content-type': 'application/json; charset=utf-8'
        },
        extraData: JSON.stringify(normalizedRecord)
      })
      const statusCode = Number(response.responseCode)
      const bodyText = this.normalizeBodyText(response.result)
      if (statusCode >= 200 && statusCode < 300) {
        const metadata = createNeptuneHarmonyMetadata()
        setNeptuneHarmonyMetadata(metadata, 'endpoint', requestUrl)
        setNeptuneHarmonyMetadata(metadata, 'statusCode', statusCode)
        this.logger.info(
          'raw ui-tree ingest request succeeded',
          metadata
        )
        return {
          state: 'success',
          title: '视图树上报成功',
          detail: `POST /v2/ui-tree/inspector -> ${statusCode}${bodyText.length > 0 ? ` · ${bodyText}` : ''}`,
          timestamp: new Date().toISOString()
        }
      }

      const metadata = createNeptuneHarmonyMetadata()
      setNeptuneHarmonyMetadata(metadata, 'endpoint', requestUrl)
      setNeptuneHarmonyMetadata(metadata, 'statusCode', statusCode)
      setNeptuneHarmonyMetadata(metadata, 'bodyText', bodyText)
      this.logger.error(
        'raw ui-tree ingest request failed',
        metadata
      )
      return {
        state: 'failed',
        title: '视图树上报失败',
        detail: `POST /v2/ui-tree/inspector -> ${statusCode}${bodyText.length > 0 ? ` · ${bodyText}` : ''}`,
        timestamp: new Date().toISOString()
      }
    } catch (error) {
      const metadata = createNeptuneHarmonyMetadata()
      setNeptuneHarmonyMetadata(metadata, 'endpoint', requestUrl)
      setNeptuneHarmonyMetadata(metadata, 'error', error instanceof Error ? error.message : String(error))
      this.logger.error(
        'raw ui-tree ingest request exception',
        metadata
      )
      return {
        state: 'failed',
        title: '视图树上报失败',
        detail: error instanceof Error ? error.message : String(error),
        timestamp: new Date().toISOString()
      }
    } finally {
      httpRequest.destroy()
    }
  }

  private normalizeRawViewTreeRecord(record: GatewayRawViewTreeIngestRecord): GatewayRawViewTreeIngestRecord {
    return {
      platform: record.platform,
      appId: record.appId,
      sessionId: record.sessionId,
      deviceId: record.deviceId,
      snapshotId: record.snapshotId,
      capturedAt: record.capturedAt,
      payload: record.payload
    }
  }

  private makeIngestUrl(endpointUrl: string): string {
    return this.normalizeBaseUrl(endpointUrl) + '/v2/logs:ingest'
  }

  private makeRawViewTreeIngestUrl(endpointUrl: string): string {
    return this.normalizeBaseUrl(endpointUrl) + '/v2/ui-tree/inspector'
  }

  private normalizeBaseUrl(endpointUrl: string): string {
    const trimmed = endpointUrl.trim()
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed
  }

  private normalizeBodyText(result: string | number | boolean | ArrayBuffer | Object | undefined | null): string {
    if (typeof result === 'string') {
      return result
    }

    if (typeof result === 'number' || typeof result === 'boolean') {
      return String(result)
    }

    if (result instanceof ArrayBuffer) {
      return ''
    }

    if (result === undefined || result === null) {
      return ''
    }

    return JSON.stringify(result)
  }
}
