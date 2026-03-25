# Harmony 网关发现能力

日期：2026-03-24

## 目标

为 `neptune-sdk-harmony` 增加网关发现能力，支持：

- `mDNS` 候选优先
- 手动 `DSN` 回退
- 对 `GET /v2/gateway/discovery` 的响应进行结构化校验

## 验收场景

1. 当 `mDNS` 返回可用候选时，优先命中 `mDNS`。
2. 当 `mDNS` 不可用时，回退到手动 `DSN`。
3. 当某个候选返回非法响应时，继续尝试下一个候选。
4. 当所有候选都失败时，返回明确错误。

## 范围

- 只定义 Harmony SDK 的发现流程，不引入系统级 mDNS 具体实现。
- 默认 `mDNS` 提供器允许为空实现，便于后续按平台能力渐进接入。
- 手动 `DSN` 必须始终可用。

## DoD

- discovery 模块可从 `src/main/ets/index.ets` 导出。
- node 校验脚本可在仓内运行。
- README 已补充使用说明与限制边界。
- `entry` Demo App 已接入发现入口，页面可直接展示成功结果或失败原因。
