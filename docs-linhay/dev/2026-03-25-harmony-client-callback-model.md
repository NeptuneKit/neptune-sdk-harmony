# Harmony 主动回调模型实现说明

日期：2026-03-25

## 设计

本次实现把 SDK 侧能力拆成两段：

1. `ExportServer`
   - 继续承担本地 HTTP 服务与日志/来源数据导出。
   - 新增 `POST /v2/client/command`，用于接收网关回调。
   - 默认绑定地址改为 `0.0.0.0`，并允许调用方显式传入回环地址。
2. `GatewayClientCallbackManager`
   - 负责启动本地 HTTP 服务。
   - 负责向网关调用 `POST /v2/clients:register`。
   - 在运行态按 30 秒续约。
   - 通过 `callbackBaseUrl`、`callbackPath`、`registerPath` 把本地命令入口与注册信息绑定起来。

## 协议字段

### 本地命令 ACK

`POST /v2/client/command` 仅对 `ping` 返回成功 ACK：

- `requestId`
- `command`
- `status`
- `message`
- `timestamp`

### 注册载荷

`POST /v2/clients:register` 使用以下身份与回调信息：

- `platform`
- `appId`
- `deviceId`
- `sessionId` 仅用于展示
- `callbackBaseUrl`
- `callbackPath`
- `registerPath`
- `sdkName`
- `sdkVersion`
- `registeredAt`
- `renewSequence`

## 关键约束

- 依旧复用 `@cxy/webserver` 和 `@ohos.net.http`，没有手写底层 socket 协议。
- `sessionId` 不再参与来源主键，主键收敛为 `platform + appId + deviceId`。
- demo 仍保留 discovery 能力，但默认不再把 WS 当作启动主链路。

## 验证

- `node ./scripts/verify-client-callback-contract.mjs`
- `node ./scripts/verify-demo-entry.mjs`
- `./hvigorw --mode module -p module=library assembleHar --no-daemon`
- `./hvigorw --mode module -p module=entry assembleHap --no-daemon`
