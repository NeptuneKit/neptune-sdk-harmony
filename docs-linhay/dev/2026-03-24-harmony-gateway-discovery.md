# Harmony 网关发现实现说明

日期：2026-03-24

## 设计

Harmony SDK 的网关发现拆成三层：

1. `GatewayDiscoveryMdnsProvider`：只负责产出 mDNS 候选，不强制绑定具体系统能力。
2. `GatewayDiscoveryResolver`：统一做候选排序、请求发送、响应校验和错误收敛。
3. `GatewayDiscoveryHttpClient`：负责发起 `GET /v2/gateway/discovery` 请求，便于测试时注入 mock。

## 关键约束

- mDNS 只是优先候选，不是硬依赖。
- 手动 `DSN` 作为 fallback，保证模拟器和局域网直连场景可用。
- discovery 响应只有在 `host`、`port`、`version` 三个字段都合法时才接受。

## 验证

- `node ./scripts/verify-gateway-discovery.mjs`
- `./hvigorw --mode project tasks --no-daemon`
- `entry` Demo App 页面包含独立“发现网关”按钮，并在成功/失败时更新状态卡片
