# neptune-sdk-harmony

NeptuneKit v2 Harmony SDK，当前阶段已接入 `@cxy/webserver`，可以直接启动本地 HTTP 导出服务。

## 当前能力

- 统一 v2 日志模型定义
- 本地内存队列，支持 overflow 计数
- 基于 `@cxy/webserver` 的 HTTP 导出服务
- 已注册导出路由：
  - `GET /v2/export/health`
  - `GET /v2/export/metrics`
  - `GET /v2/export/logs?cursor&limit`

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

queue.enqueue({
  timestamp: new Date().toISOString(),
  level: 'info',
  message: 'Harmony export server started',
  platform: 'harmony',
  appId: 'demo.app',
  sessionId: 'session-1',
  deviceId: 'device-1',
  category: 'lifecycle'
})
```

启动后可访问：

- `http://<device-ip>:18765/v2/export/health`
- `http://<device-ip>:18765/v2/export/metrics`
- `http://<device-ip>:18765/v2/export/logs`

## 开发依赖

- `hdc`：连接设备、安装/拉起应用、查看 `hilog`
- `ohpm`：依赖安装与包管理
- `hvigorw`：构建与打包

## 已知限制

- 当前存储仍是内存版，应用重启后日志不会保留。
- 目前只实现 `cursor/limit` 增量导出，尚未加入 `platform/appId/sessionId` 过滤。
- 本轮没有在真机或模拟器上跑 Harmony 构建，当前验证以静态自检为主。
- `@cxy/webserver` 已接入，但后台常驻承载方式还没有绑定到具体 Ability 生命周期。

## 后续 TODO

- 接入持久化存储，替换纯内存队列
- 增加 `platform/appId/sessionId` 过滤
- 绑定 `AppServiceExtensionAbility` 或等效承载层
- 补齐 `hvigorw` 构建配置与最小运行样例
