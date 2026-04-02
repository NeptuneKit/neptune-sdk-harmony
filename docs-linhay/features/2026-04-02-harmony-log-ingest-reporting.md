# neptune-sdk-harmony 接入 harmony-log 并改造日志上报

## 背景

当前 `neptune-sdk-harmony` 在回调注册、WS 连接和 Demo 上报链路中仍使用 `console.info/error`，存在三个问题：

- 日志字段不统一，难以按 endpoint/status 聚合排障。
- SDK 内部日志能力无法复用 `harmony-log` 的 metadata 与分级能力。
- 上报失败时缺少结构化上下文，不利于定位网络与网关问题。

## 目标

- `library` 模块增加 `harmony-log` 依赖并提供统一 logger helper。
- 改造日志上报关键路径（注册上报、日志 ingest、raw ui-tree ingest）到 `harmony-log`。
- 保持现有 HTTP 上报协议与返回结构不变，避免行为回归。

## 非目标

- 不修改 `/v2/logs:ingest` 与 `/v2/ui-tree/inspector` 的网关契约。
- 不在本轮引入新的重试策略或批量压缩协议。

## 验收场景

### 场景 1：SDK 依赖声明

- Given 我查看 `library/oh-package.json5`
- When 检查 dependencies
- Then 能看到 `harmony-log` 依赖声明

### 场景 2：统一日志入口

- Given SDK 代码需要打印内部运行日志
- When 调用日志 helper
- Then 应通过统一导出的 logging 模块创建 logger，并附带 `sdk=neptune-sdk-harmony` metadata

### 场景 3：日志上报链路结构化日志

- Given 触发 `POST /v2/logs:ingest` 或 `POST /v2/ui-tree/inspector`
- When 请求成功/失败/异常
- Then 日志应记录结构化 metadata（endpoint、statusCode、error/bodyText）
- And 不再直接使用 `console.info/error`

### 场景 4：回调注册链路结构化日志

- Given 回调管理器向网关发起 `POST /v2/clients:register`
- When 成功或失败
- Then 记录 reason、endpoint、callback 等关键信息到 `harmony-log`
