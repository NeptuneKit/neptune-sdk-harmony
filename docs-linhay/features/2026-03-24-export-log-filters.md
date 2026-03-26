# 导出日志过滤

## 背景

`GET /v2/logs` 目前只支持 `cursor` 和 `limit`，调用方无法按 `platform`、`appId`、`sessionId` 缩小结果集。

## 验收场景

### 场景 1：不传过滤参数时保持兼容

- Given 队列中已经有多条不同来源的日志
- When 调用 `GET /v2/logs` 且只传 `cursor/limit` 或完全不传过滤参数
- Then 返回结果与当前增量导出行为一致

### 场景 2：按单个来源字段过滤

- Given 队列中存在多个 `platform`、`appId` 或 `sessionId` 不同的日志
- When 调用 `GET /v2/logs?platform=harmony`
- Then 仅返回 `platform=harmony` 的日志

### 场景 3：过滤条件与 cursor/limit 共存

- Given 队列中存在满足与不满足条件的混合日志
- When 调用 `GET /v2/logs?cursor=<id>&limit=<n>&appId=<value>&sessionId=<value>`
- Then 仅在 `id > cursor` 的记录中按过滤条件筛选并返回最多 `limit` 条
- And `nextCursor` 与 `hasMore` 基于过滤后的结果集计算
