# Harmony WebSocket 客户端实现说明

日期：2026-03-24

## 设计

WS 链路拆成两层：

1. `GatewayWsClient`
   - 负责 `createWebSocket()`
   - 负责连接 `/v2/ws`
   - 负责发送 `hello` / heartbeat
   - 负责失联判定与重连退避
   - 负责 `command.dispatch(ping)` -> `command.ack`
2. `GatewayWsManager`
   - 负责复用现有 `GatewayDiscoveryResolver`
   - 负责把 discovery/manual DSN 的变化同步到 WS 客户端
   - 负责在端点变化时触发重连

## 关键约束

- API 12 的 `webSocket` 接口没有可直接依赖的应用层 ping/pong，保活用 heartbeat frame 自己做。
- 事件回调必须按 `AsyncCallback` 的双参数形态写，不能用单参数简写。
- ArkTS 严格模式下，避免 `unknown`、类型守卫返回类型和过度花式的运行时推断。
- 连接切换时先关闭旧 socket，再切到新 endpoint，避免重复重连和悬挂回调。

## 验证

- `node ./scripts/verify-gateway-ws-contract.mjs`
- `./hvigorw --mode project tasks --no-daemon`
- `./hvigorw --mode module -p module=library assembleHar --no-daemon`
- `./hvigorw --mode module -p module=entry assembleHap --no-daemon`

## 备注

- 目前 WS 客户端只负责协议层，不向外暴露业务事件总线。
- 如果后续要接真实命令分发，可以在 `GatewayWsClient.onSocketMessage()` 里增加更高层的 frame routing。
