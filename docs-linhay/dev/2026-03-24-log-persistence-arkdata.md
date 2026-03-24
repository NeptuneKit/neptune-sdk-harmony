# Harmony 持久化实现方案

日期：2026-03-24

## 方案

采用三层结构：

- `LogStoreBase`：保存队列核心语义，负责 `enqueue`、`drain`、游标查询、统计与 flush 状态。
- `MemoryLogStore`：默认实现，仅保留内存行为。
- `RdbLogStore`：基于 Harmony `ArkData` 关系型数据库的持久化后端。

`LogQueue` 作为门面层，对外保留现有 API，并新增持久化工厂 `createPersistentLogQueue(...)`。

## 关键点

- 持久化后端默认只替换数据存储，不改变导出服务的查询语义。
- `ExportServer` 的来源快照在首次查询时可从已持久化日志重建，避免单独造一套来源持久化格式。
- `stop()` 阶段会等待队列 flush，降低后台写入尚未落盘的风险。

## 约束

- 默认仍保留内存后端，避免破坏当前调用方。
- 当前仓库没有完整 Harmony 工程骨架，因此需要通过验证脚本和源代码审查共同确认契约。
- 如果后续补齐 `Ability`/工程骨架，可以直接把 `createPersistentLogQueue` 挂到启动流程里。
