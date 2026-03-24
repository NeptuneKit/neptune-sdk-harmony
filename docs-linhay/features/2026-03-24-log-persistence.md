# Harmony 日志本地持久化

## 背景

当前 Harmony SDK 仅有默认内存队列。应用重启后，已采集日志和来源快照都会丢失，`/v2/export/sources` 也只能依赖当前进程内状态。

## 目标

- 保留现有内存实现作为默认路径。
- 引入 Harmony 官方本地存储后端，优先使用 `ArkData` 的关系型数据库能力。
- 对外保持 `LogQueue` 和 `ExportServer` 的调用方式尽量稳定。
- 在无法直接接入持久化时，至少保留可切换的存储抽象与写读契约验证脚本。

## 验收场景

### 场景 1：默认路径保持兼容

- Given 调用方没有注入持久化后端
- When 使用 `new LogQueue()` 启动导出服务
- Then 行为与现有内存版本一致

### 场景 2：持久化后端可切换

- Given 调用方具备 Harmony `Context`
- When 通过持久化工厂创建队列
- Then 日志写入本地 RDB，重启后仍可读取

### 场景 3：来源快照可恢复

- Given 持久化日志中包含来源字段
- When 服务重启后首次调用 `/v2/export/sources`
- Then 可从已持久化日志重建来源快照

### 场景 4：验证脚本可执行

- Given 仓库拉取完成
- When 运行持久化契约脚本
- Then 脚本输出成功并返回 `0`

## 说明

- 生产实现不应使用自定义文件格式。
- 如果 Harmony RDB API 在当前构建环境中需要微调，优先只改 `RdbLogStore`，不要把持久化逻辑散落到 `ExportServer`。
