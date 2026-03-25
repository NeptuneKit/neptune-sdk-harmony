import http from '@ohos.net.http'

import { IngestLogRecord } from 'neptune-sdk-harmony'

export interface GatewayIngestResult {
  state: 'success' | 'failed'
  title: string
  detail: string
  timestamp: string
}

export class GatewayIngestHttpClient {
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
        console.info(`GatewayIngestHttpClient ingest ok url=${requestUrl} status=${statusCode}`)
        return {
          state: 'success',
          title: '日志上报成功',
          detail: `POST /v2/logs:ingest -> ${statusCode}${bodyText.length > 0 ? ` · ${bodyText}` : ''}`,
          timestamp: new Date().toISOString()
        }
      }

      console.error(`GatewayIngestHttpClient ingest failed url=${requestUrl} status=${statusCode}`)
      return {
        state: 'failed',
        title: '日志上报失败',
        detail: `POST /v2/logs:ingest -> ${statusCode}${bodyText.length > 0 ? ` · ${bodyText}` : ''}`,
        timestamp: new Date().toISOString()
      }
    } catch (error) {
      console.error(
        `GatewayIngestHttpClient ingest error url=${requestUrl} message=${error instanceof Error ? error.message : String(error)}`
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

  private makeIngestUrl(endpointUrl: string): string {
    return this.normalizeBaseUrl(endpointUrl) + '/v2/logs:ingest'
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
