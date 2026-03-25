import http from '@ohos.net.http'

import { GatewayDiscoveryHttpClient, GatewayDiscoveryHttpResponse } from './DiscoveryModels'
import { GatewayDiscoveryError } from './GatewayDiscoveryErrors'

export class FetchGatewayDiscoveryHttpClient implements GatewayDiscoveryHttpClient {
  async request(url: string, timeoutMs: number): Promise<GatewayDiscoveryHttpResponse> {
    const httpRequest: http.HttpRequest = http.createHttp()
    const requestTimeout = timeoutMs > 0 ? timeoutMs : 2000

    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: requestTimeout,
        readTimeout: requestTimeout,
        expectDataType: http.HttpDataType.STRING
      }

      const response: http.HttpResponse = await httpRequest.request(url, options)
      return {
        statusCode: Number(response.responseCode),
        bodyText: this.normalizeBodyText(response.result)
      }
    } catch (_error) {
      throw new GatewayDiscoveryError('no_valid_response', 'Discovery request failed.', [url])
    } finally {
      httpRequest.destroy()
    }
  }

  private normalizeBodyText(result: string | number | boolean | ArrayBuffer | Object | undefined | null): string {
    if (typeof result === 'string') {
      return result
    }

    if (typeof result === 'number' || typeof result === 'boolean') {
      return String(result)
    }

    return ''
  }
}
