# neptune-sdk-harmony

NeptuneKit v2 Harmony SDK，当前阶段已接入 `@cxy/webserver`，并提供可切换的本地存储抽象。

## 当前能力

- 统一 v2 日志模型定义
- 默认内存队列，支持 overflow 计数
- 可切换到 Harmony 官方 `ArkData` RDB 持久化后端
- 基于 `@cxy/webserver` 的 HTTP 导出服务
- 已注册导出路由：
  - `GET /v2/export/health`
  - `GET /v2/export/metrics`
  - `GET /v2/export/logs?cursor&limit&platform&appId&sessionId`
  - `GET /v2/export/sources`

## 队列参数

- 容量：`2000`
- 批量：`50`
- flush 间隔：`1s`
- 重试阶梯：`0.5s / 1s / 2s / 4s / 8s`

## 工程结构

当前仓库已经补齐为 Harmony 工程壳 + `HAR` library 模块：

- 项目根目录：`build-profile.json5`、`hvigorfile.ts`、`hvigor/hvigor-config.json5`、`AppScope/app.json5`
- `library/`：最小可构建 `HAR` 模块配置
- `src/main/ets/`：SDK 源码主目录，仍然是唯一源码来源
- `scripts/sync-harmony-module.sh`：构建前把顶层源码同步到 `library/src/main/ets`
- `./hvigorw`：本地包装脚本，会自动做源码同步并尝试补齐常见 SDK 环境变量

## 安装依赖

仓库根目录已提交项目级 `.ohpmrc`，会优先固定到 Harmony 官方源：

- `https://ohpm.openharmony.cn/ohpm/`

直接执行：

```bash
ohpm install --all
```

当前模块依赖：

- `@cxy/webserver`
- `@kit.ArkData`（持久化后端）

## 构建步骤

### 前置工具

需要本机已安装 Harmony Command Line Tools，至少包含：

- `ohpm`
- `hvigorw`
- OpenHarmony SDK API 12（与 `library/oh-package.json5` 的 `compatibleSdkVersion: 12` 对齐）

本仓库在以下工具版本上已验证：

- `ohpm 6.0.1`
- `hvigor 6.22.3`

如果本机使用 DevEco Studio 默认安装路径，仓库内的 `./hvigorw` 会自动尝试设置：

- `DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk`
- `OHOS_BASE_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony`

如果你的 Harmony SDK 不在默认目录，需要自行导出：

- `DEVECO_SDK_HOME`
- `OHOS_BASE_SDK_HOME`
- 可选：`HVIGORW_BIN`

### 可执行命令

```bash
ohpm install --all
./hvigorw --mode project tasks --no-daemon
./hvigorw --mode project clean --no-daemon
./hvigorw --mode module -p module=library assembleHar --no-daemon
```

说明：

- `tasks`：验证项目壳和 `library` 模块已被 `hvigor` 正确识别。
- `clean`：验证项目级清理任务可执行。
- `assembleHar`：尝试编译 `HAR` 模块，是当前最接近真实 SDK 产物的构建命令。

### 2026-03-24 本机验证结果

已验证通过：

- `ohpm install --all`
- `./hvigorw --mode project tasks --no-daemon`
- `./hvigorw --mode project clean --no-daemon`
- `./hvigorw --mode module -p module=library assembleHar --no-daemon`

本次通过点：

1. `ohpm` 源已切到官方 `ohpm.openharmony.cn`，`@cxy/webserver` 可正常解析与下载。
2. `RdbLogStore` 已按 API 12 的 `@kit.ArkData` 命名导出改为 `relationalStore` 类型化调用。
3. `LogModels`、`LogStoreBase`、`LogQueue`、`ExportServer`、`RdbLogStore` 已收敛掉阻塞构建的 ArkTS 严格语法问题。

构建说明：

- `assembleHar` 目前可成功产出 `HAR`。
- 构建期间仍会有若干 “Function may throw exceptions” 的 ArkTS 警告，以及 HAR 签名配置缺省警告；它们不会阻塞本地 `HAR` 产物生成。

## CI

仓库已配置 `.github/workflows/ci.yml`，分成两条路径：

- `push(main)` / `pull_request`：只跑标准 runner 可执行的校验，不依赖 DevEco 环境
- `workflow_dispatch`：将 `run_harmony_build` 显式设为 `true` 时，才会额外尝试执行 `ohpm install --all` 和 `./hvigorw --mode module -p module=library assembleHar --no-daemon`

说明：

- 默认 CI 不会因为缺少 `ohpm` / DevEco / Harmony SDK 而失败
- 手动构建只适合已经具备 Harmony 工具链的 runner
- 本地对齐默认 CI 的命令：

```bash
bash -n hvigorw
bash -n scripts/verify-sources-endpoint.sh
sh -n scripts/sync-harmony-module.sh
node ./scripts/verify-source-dedup.mjs
node ./scripts/verify-log-query-filtering.mjs
node ./scripts/verify-log-persistence.mjs
```

## 启动示例

```ts
import { LogQueue, startExportServer } from 'neptune-sdk-harmony'

const queue = new LogQueue()
const exportServer = await startExportServer(18765, queue, {
  serviceName: 'neptune-harmony-debug',
  version: '0.1.0'
})

exportServer.ingest({
  timestamp: new Date().toISOString(),
  level: 'info',
  message: 'Harmony export server started',
  platform: 'harmony',
  appId: 'demo.app',
  sessionId: 'session-1',
  deviceId: 'device-1',
  category: 'lifecycle',
  source: {
    sdkName: 'neptune-sdk-harmony',
    sdkVersion: '0.1.0'
  }
})
```

## 持久化示例

在具备 Harmony `Context` 的应用内，可以先创建持久化队列，再传入导出服务：

```ts
import { createPersistentLogQueue, startExportServer } from 'neptune-sdk-harmony'

const queue = await createPersistentLogQueue(getContext(), {
  databaseName: 'neptune_sdk_harmony_logs.db'
})

const exportServer = await startExportServer(18765, queue, {
  serviceName: 'neptune-harmony-debug',
  version: '0.1.0'
})
```

持久化队列会把日志写入本地 RDB，并在进程重启后恢复当前记录。`/v2/export/sources` 会在首次查询时从已持久化日志重建来源快照。

`ingest()` 会在入队时自动注册来源快照，来源维度由以下字段共同决定：

- `sdkName`
- `sdkVersion`
- `platform`
- `appId`
- `sessionId`
- `deviceId`

同一维度重复上报时，只会更新对应来源的 `lastSeenAt`。

启动后可访问：

- `http://<device-ip>:18765/v2/export/health`
- `http://<device-ip>:18765/v2/export/metrics`
- `http://<device-ip>:18765/v2/export/logs`
- `http://<device-ip>:18765/v2/export/logs?platform=harmony&appId=demo.app&sessionId=session-1`
- `http://<device-ip>:18765/v2/export/sources`

`/v2/export/logs` 的 `platform`、`appId`、`sessionId` 都是可选参数：

- 不传或传空字符串时，等同于不启用该字段过滤
- 多个过滤条件同时传入时，按 AND 关系匹配
- `cursor/limit` 仍然可用，语义为“在 `id > cursor` 的记录中按过滤条件取最多 `limit` 条”

示例返回：

```json
[
  {
    "deviceId": "device-1",
    "appId": "demo.app",
    "platform": "harmony",
    "sessionId": "session-1",
    "sdkName": "neptune-sdk-harmony",
    "sdkVersion": "0.1.0",
    "lastSeenAt": "2026-03-23T12:34:56.000Z"
  }
]
```

来源去重维度：

- `sdkName`
- `sdkVersion`
- `platform`
- `appId`
- `sessionId`
- `deviceId`

同一来源重复上报时，会更新已有快照的 `lastSeenAt`，不会重复追加。

## 最小验证脚本

仓库内提供：

```bash
./scripts/verify-sources-endpoint.sh http://127.0.0.1:18765 1
node ./scripts/verify-source-dedup.mjs
node ./scripts/verify-log-query-filtering.mjs
node ./scripts/verify-log-persistence.mjs
```

脚本会检查：

- `/v2/export/health` 可访问
- `/v2/export/sources` 返回 JSON 数组
- 可选校验来源数量是否符合预期
- 来源快照字段完整且非空
- 本地去重逻辑会合并同一来源维度的重复记录
- 日志查询在无过滤、单字段过滤、多字段过滤与 `cursor/limit` 共存时满足预期
- 持久化契约脚本会验证“写入后重启再读取”的链路

## 开发依赖

- `hdc`：连接设备、安装/拉起应用、查看 `hilog`
- `ohpm`：依赖安装与包管理
- `hvigorw`：构建与打包

## 已知限制

- 默认仍是内存版，若调用方不注入持久化队列，应用重启后日志不会保留。
- `@cxy/webserver` 已接入，但后台常驻承载方式还没有绑定到具体 Ability 生命周期。
- `RdbLogStore` 当前已经能通过 API 12 编译，但仍保留少量 ArkTS “可能抛异常” 警告，后续可以按显式错误处理继续收敛。

## 后续 TODO

- 将持久化队列接入具体 `Ability` 初始化流程
- 绑定 `AppServiceExtensionAbility` 或等效承载层
- 视需要继续清理 `RdbLogStore` 的 ArkTS 警告级异常处理提示
