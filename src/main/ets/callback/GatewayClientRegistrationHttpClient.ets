import http from '@ohos.net.http'
import { HarmonyLogLevel } from 'harmony-log'

import {
  GatewayClientRegistrationPayload,
  GatewayClientRegistrationResult
} from './CallbackModels'
import { createNeptuneHarmonyLogger, createNeptuneHarmonyMetadata, setNeptuneHarmonyMetadata } from '../logging'

export class GatewayClientRegistrationHttpClient {
  private readonly logger = createNeptuneHarmonyLogger(
    'Neptune.Callback.Register',
    HarmonyLogLevel.INFO
  )

  async register(
    endpointUrl: string,
    payload: GatewayClientRegistrationPayload,
    timeoutMs: number = 2000
  ): Promise<GatewayClientRegistrationResult> {
    const httpRequest: http.HttpRequest = http.createHttp()
    const requestTimeout = timeoutMs > 0 ? timeoutMs : 2000
    const requestUrl = this.makeRegisterUrl(endpointUrl)

    try {
      const response: http.HttpResponse = await httpRequest.request(requestUrl, {
        method: http.RequestMethod.POST,
        connectTimeout: requestTimeout,
        readTimeout: requestTimeout,
        expectDataType: http.HttpDataType.STRING,
        header: {
          'content-type': 'application/json; charset=utf-8'
        },
        extraData: JSON.stringify(payload)
      })
      const statusCode = Number(response.responseCode)
      const bodyText = this.normalizeBodyText(response.result)
      if (statusCode >= 200 && statusCode < 300) {
        const metadata = createNeptuneHarmonyMetadata()
        setNeptuneHarmonyMetadata(metadata, 'endpoint', requestUrl)
        setNeptuneHarmonyMetadata(metadata, 'statusCode', statusCode)
        this.logger.info(
          'gateway callback registration succeeded',
          metadata
        )
        return {
          state: 'success',
          title: '注册成功',
          detail: `POST /v2/clients:register -> ${statusCode}${bodyText.length > 0 ? ` · ${bodyText}` : ''}`,
          timestamp: new Date().toISOString()
        }
      }

      const metadata = createNeptuneHarmonyMetadata()
      setNeptuneHarmonyMetadata(metadata, 'endpoint', requestUrl)
      setNeptuneHarmonyMetadata(metadata, 'statusCode', statusCode)
      setNeptuneHarmonyMetadata(metadata, 'bodyText', bodyText)
      this.logger.error(
        'gateway callback registration failed',
        metadata
      )
      return {
        state: 'failed',
        title: '注册失败',
        detail: `POST /v2/clients:register -> ${statusCode}${bodyText.length > 0 ? ` · ${bodyText}` : ''}`,
        timestamp: new Date().toISOString()
      }
    } catch (error) {
      const metadata = createNeptuneHarmonyMetadata()
      setNeptuneHarmonyMetadata(metadata, 'endpoint', requestUrl)
      setNeptuneHarmonyMetadata(metadata, 'error', error instanceof Error ? error.message : String(error))
      this.logger.error(
        'gateway callback registration exception',
        metadata
      )
      return {
        state: 'failed',
        title: '注册失败',
        detail: error instanceof Error ? error.message : String(error),
        timestamp: new Date().toISOString()
      }
    } finally {
      httpRequest.destroy()
    }
  }

  private makeRegisterUrl(endpointUrl: string): string {
    return this.normalizeBaseUrl(endpointUrl) + '/v2/clients:register'
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
