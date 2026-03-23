# neptune-sdk-harmony

NeptuneKit v2 Harmony SDK，当前阶段已接入 `@cxy/webserver`，可以直接启动本地 HTTP 导出服务。

## 当前能力

- 统一 v2 日志模型定义
- 本地内存队列，支持 overflow 计数
- 基于 `@cxy/webserver` 的 HTTP 导出服务
- 已注册导出路由：
  - `GET /v2/export/health`
  - `GET /v2/export/metrics`
  - `GET /v2/export/logs?cursor&limit&platform&appId&sessionId`
  - `GET /v2/export/sources`

## 队列参数

- 容量：`2000`
- 批量：`50`
- flush 间隔：`1s`
- 重试阶梯：`0.5s / 1s / 2s / 4s / 8s`

## 安装依赖

```bash
ohpm install
```

依赖：

- `@cxy/webserver`

## 启动示例

```ts
import { LogQueue, startExportServer } from 'neptune-sdk-harmony'

const queue = new LogQueue()
const exportServer = await startExportServer(18765, queue, {
  serviceName: 'neptune-harmony-debug',
  version: '0.1.0'
})

exportServer.ingest({
  timestamp: new Date().toISOString(),
  level: 'info',
  message: 'Harmony export server started',
  platform: 'harmony',
  appId: 'demo.app',
  sessionId: 'session-1',
  deviceId: 'device-1',
  category: 'lifecycle',
  source: {
    sdkName: 'neptune-sdk-harmony',
    sdkVersion: '0.1.0'
  }
})
```

`ingest()` 会在入队时自动注册来源快照，来源维度由以下字段共同决定：

- `sdkName`
- `sdkVersion`
- `platform`
- `appId`
- `sessionId`
- `deviceId`

同一维度重复上报时，只会更新对应来源的 `lastSeenAt`。

启动后可访问：

- `http://<device-ip>:18765/v2/export/health`
- `http://<device-ip>:18765/v2/export/metrics`
- `http://<device-ip>:18765/v2/export/logs`
- `http://<device-ip>:18765/v2/export/logs?platform=harmony&appId=demo.app&sessionId=session-1`
- `http://<device-ip>:18765/v2/export/sources`

`/v2/export/logs` 的 `platform`、`appId`、`sessionId` 都是可选参数：

- 不传或传空字符串时，等同于不启用该字段过滤
- 多个过滤条件同时传入时，按 AND 关系匹配
- `cursor/limit` 仍然可用，语义为“在 `id > cursor` 的记录中按过滤条件取最多 `limit` 条”

示例返回：

```json
[
  {
    "deviceId": "device-1",
    "appId": "demo.app",
    "platform": "harmony",
    "sessionId": "session-1",
    "sdkName": "neptune-sdk-harmony",
    "sdkVersion": "0.1.0",
    "lastSeenAt": "2026-03-23T12:34:56.000Z"
  }
]
```

来源去重维度：

- `sdkName`
- `sdkVersion`
- `platform`
- `appId`
- `sessionId`
- `deviceId`

同一来源重复上报时，会更新已有快照的 `lastSeenAt`，不会重复追加。

## 最小验证脚本

仓库内提供：

```bash
./scripts/verify-sources-endpoint.sh http://127.0.0.1:18765 1
node ./scripts/verify-source-dedup.mjs
node ./scripts/verify-log-query-filtering.mjs
```

脚本会检查：

- `/v2/export/health` 可访问
- `/v2/export/sources` 返回 JSON 数组
- 可选校验来源数量是否符合预期
- 来源快照字段完整且非空
- 本地去重逻辑会合并同一来源维度的重复记录
- 日志查询在无过滤、单字段过滤、多字段过滤与 `cursor/limit` 共存时满足预期

## 开发依赖

- `hdc`：连接设备、安装/拉起应用、查看 `hilog`
- `ohpm`：依赖安装与包管理
- `hvigorw`：构建与打包

## 已知限制

- 当前存储仍是内存版，应用重启后日志不会保留。
- 本轮没有在真机或模拟器上跑 Harmony 构建，当前验证以静态自检 + 运行期验证脚本为主。
- `@cxy/webserver` 已接入，但后台常驻承载方式还没有绑定到具体 Ability 生命周期。

## 后续 TODO

- 接入持久化存储，替换纯内存队列
- 绑定 `AppServiceExtensionAbility` 或等效承载层
- 补齐 `hvigorw` 构建配置与最小运行样例
