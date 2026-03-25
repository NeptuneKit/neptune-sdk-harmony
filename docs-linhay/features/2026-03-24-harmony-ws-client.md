# Harmony WebSocket 客户端

日期：2026-03-24

## 目标

为 `neptune-sdk-harmony` 增加基于 `@kit.NetworkKit` 的 WebSocket 客户端，支持：

- 启动即连 `/v2/ws`
- 建连后发送 `hello(role=sdk)`
- 15 秒 heartbeat
- 45 秒失联判定
- `0.5s / 1s / 2s / 4s / 8s` 阶梯重连
- 收到 `command.dispatch(ping)` 后回 `command.ack`
- 和现有 discovery / 手动 DSN 协同，端点变化时自动重连

## 验收场景

1. 当 SDK 启动并且网关端点可用时，会立即建立 WebSocket 连接。
2. 当连接建立成功时，会先发送 `hello`，并携带 `role=sdk`。
3. 当连接保持打开但长时间没有活动时，会按照 45 秒失联规则触发重连。
4. 当收到 `command.dispatch` 且命令为 `ping` 时，客户端会回复 `command.ack`。
5. 当 discovery 结果或手动 DSN 发生变化时，客户端会切换到新端点并重连。

## 范围

- 只处理客户端链路，不在本轮引入 WebSocket Server。
- API 12 不依赖内建 ping/pong 帧，保活逻辑由应用层 heartbeat 和失联计时实现。
- 默认只做连接管理与协议响应，不把命令再路由给更上层的业务。

## DoD

- `GatewayWsClient`、`GatewayWsManager`、`GatewayWsModels` 可从 `src/main/ets/index.ets` 导出。
- `scripts/verify-gateway-ws-contract.mjs` 可执行并通过。
- `entry` Demo Runtime 启动时会后台建立 WS 连接，并在 discovery 结果变化时重连。
- `README.md` 已补充 WS 客户端用法与约束。
