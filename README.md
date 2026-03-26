# neptune-sdk-harmony

NeptuneKit v2 Harmony SDK，当前阶段已接入 `@cxy/webserver`，并提供可切换的本地存储抽象；同时新增了一个可以直接在 Harmony 模拟器运行的 `entry` Demo App。

## 当前能力

- 统一 v2 日志模型定义
- 默认内存队列，支持 overflow 计数
- 可切换到 Harmony 官方 `ArkData` RDB 持久化后端
- 基于 `@cxy/webserver` 的 HTTP 导出服务
- 网关发现支持 `mDNS` 候选优先，失败后回退手动 `DSN`
- 本地主动回调模型支持 `POST /v2/client/command` 与 `POST /v2/clients:register`
- 基于 `@kit.NetworkKit` 的 WebSocket 客户端仍保留为独立能力，但默认不作为 SDK->gateway 主链路
- 已注册导出路由：
  - `GET /v2/export/health`
  - `GET /v2/export/metrics`
  - `GET /v2/logs?cursor&limit&platform&appId&sessionId`
  - `GET /v2/export/sources`
- `entry/` Stage HAP Demo App，按钮触发 Neptune SDK 写入日志并展示 metrics / sources 摘要

## 队列参数

- 容量：`2000`
- 批量：`50`
- flush 间隔：`1s`
- 重试阶梯：`0.5s / 1s / 2s / 4s / 8s`

## 工程结构

当前仓库已经补齐为 Harmony 工程壳 + `HAR` library 模块 + `entry` Demo App：

- 项目根目录：`build-profile.json5`、`hvigorfile.ts`、`hvigor/hvigor-config.json5`、`AppScope/app.json5`
- `entry/`：可运行的 Stage HAP Demo App，通过模块依赖引用 `library/`
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
./hvigorw --mode module -p module=entry assembleHap --no-daemon
./scripts/build-demo-entry.sh
./scripts/start-demo-via-hdc.sh
```

说明：

- `tasks`：验证项目壳和 `library` / `entry` 模块已被 `hvigor` 正确识别。
- `clean`：验证项目级清理任务可执行。
- `assembleHar`：尝试编译 `HAR` 模块，是当前最接近真实 SDK 产物的构建命令。
- `assembleHap`：尝试编译 `entry` Demo App 的 HAP 产物。
- `scripts/build-demo-entry.sh`：`assembleHap` 的便捷包装脚本。
- `scripts/start-demo-via-hdc.sh`：自动检测 target、安装 HAP、尽力唤醒/解锁并拉起 `EntryAbility`。

### 2026-03-25 本机验证结果

已验证通过：

- `ohpm install --all`
- `./hvigorw --mode project tasks --no-daemon`
- `./hvigorw --mode project clean --no-daemon`
- `./hvigorw --mode module -p module=library assembleHar --no-daemon`
- `node ./scripts/verify-demo-entry.mjs`
- `node ./scripts/verify-client-callback-contract.mjs`
- `./hvigorw --mode module -p module=entry assembleHap --no-daemon`
- `./scripts/build-demo-entry.sh`

本次通过点：

1. `ohpm` 源已切到官方 `ohpm.openharmony.cn`，`@cxy/webserver` 可正常解析与下载。
2. `RdbLogStore` 已按 API 12 的 `@kit.ArkData` 命名导出改为 `relationalStore` 类型化调用。
3. `LogModels`、`LogStoreBase`、`LogQueue`、`ExportServer`、`RdbLogStore` 已收敛掉阻塞构建的 ArkTS 严格语法问题。
4. `entry` Demo App 通过本地 `library` HAR 引用 Neptune SDK，不复制核心实现。
5. `AppScope/app.json5` 已补齐 `icon` / `label`，`entry/src/main/module.json5` 已补齐 `startWindowIcon` / `startWindowBackground`。
6. `build-profile.json5` 已开启 `buildOption.strictMode.useNormalizedOHMUrl`，满足 `@cxy/webserver` 的 bytecode HAR 约束。
7. 主动回调模型已接入，且 demo 默认不再把 WS 当作启动主链路。

构建说明：

- `assembleHar` 目前可成功产出 `HAR`。
- `assembleHap` 目前可成功产出 `HAP`，并作为 Demo App 的独立构建命令。
- 构建期间仍会有若干 “Function may throw exceptions” 的 ArkTS 警告，以及 HAR 签名配置缺省警告；它们不会阻塞本地 `HAR` 产物生成。
- `entry` 构建还会提示 local module info 缺省和 SemVer 警告；当前不阻塞本地模拟器构建。

## CI

仓库已配置 `.github/workflows/ci.yml`，分成两条路径：

- `push(main)` / `pull_request`：只跑标准 runner 可执行的校验，不依赖 DevEco 环境
- `workflow_dispatch`：将 `run_harmony_build` 显式设为 `true` 时，才会额外尝试执行 `ohpm install --all`、`./hvigorw --mode module -p module=library assembleHar --no-daemon` 和 `./hvigorw --mode module -p module=entry assembleHap --no-daemon`

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
node ./scripts/demo-smoke.mjs
node ./scripts/verify-demo-entry.mjs
node ./scripts/verify-client-callback-contract.mjs
node ./scripts/verify-gateway-ws-contract.mjs
```

## OHPM Publish

仓库已配置发布 workflow：`.github/workflows/publish-ohpm.yml`

触发方式：
- push tag（例如 `v1.2.3` 或 `2026.3.26`）
- `workflow_dispatch`（支持 `version` 与 `dry_run`）

发布 runner：
- 使用 GitHub 托管 runner（`ubuntu-latest`）
- workflow 会自动下载并安装 Harmony command line tools（`harmonyos-dev/hos-sdk` release 资产）

需要配置 GitHub Secret：
- `OHPM_PRIVATE_KEY_PEM`（私钥文件内容）
- `OHPM_PUBLISH_ID`

## Demo 冒烟

仓库内提供了一个最小 Node demo 冒烟脚本，用于在本地走一遍导出链路并输出摘要：

```bash
node ./scripts/demo-smoke.mjs
```

脚本会：

- 启动一个本地参考导出服务，暴露 `/v2/export/health`、`/v2/export/metrics`、`/v2/logs`、`/v2/export/sources`
- 注入 3 条 demo 日志，其中 2 条会命中同一个 Harmony 来源快照
- 拉取导出结果并断言关键字段
- 输出一个简短摘要，便于快速确认接入链路是否正常

当前脚本是 CLI 可执行的参考 smoke，不依赖 Harmony 运行时，方便在没有真机/模拟器环境时先确认 SDK 导出契约；后续接入实际 Harmony 应用后，可以把同样的导出路径替换成真实服务端点继续复用。

## Demo App

`entry/` 是一个可以直接跑到 Harmony 模拟器上的 Stage HAP，它通过本地 `library` HAR 引用 Neptune SDK，然后在页面上做三件事：

- 点击按钮向 SDK 写入一批示例日志
- 点击“发现网关”按钮，走 `mDNS -> 手动 DSN -> /v2/gateway/discovery` 的发现链路
- 启动时后台建立本地 callback HTTP 服务，并在 discovery 结果变化时向网关执行 `POST /v2/clients:register`
- 刷新 `metrics` 概览
- 刷新 `sources` 和最近日志摘要

### Demo 构建

```bash
./hvigorw --mode module -p module=entry assembleHap --no-daemon
```

或者使用包装脚本：

```bash
./scripts/build-demo-entry.sh
```

### DevEco Studio 跑法

1. 打开 `neptune-sdk-harmony` 工程。
2. 等待 `ohpm install --all` 和项目同步结束。
3. 选择 `entry` 模块和一个 Harmony 模拟器。
4. 点击 Run。
5. 打开页面后点击“写入 Demo 日志批次”按钮。
6. 本地 callback 服务会在后台启动，发现到网关后会自动注册并进入 30 秒续约节奏。

### hdc 跑法

推荐直接执行一键脚本：

```bash
./scripts/start-demo-via-hdc.sh
```

脚本会：

- 自动检测已连接的 hdc target，或使用 `--target` / `HDC_TARGET`
- 自动寻找 `entry/build/default/outputs/default/entry-default-unsigned.hap`
- 如果 HAP 不存在，默认先执行 `./scripts/build-demo-entry.sh`
- 自动配置 `fport tcp:28767 -> tcp:28767`（callback 回调）
- 自动配置 `rport tcp:18765 -> tcp:18765`（设备访问本机 gateway）
- 在启动前尽力执行 `power-shell timeout -o`、`power-shell wakeup` 和 `uinput swipe`
- 安装 HAP 后执行 `aa start -b io.github.neptune.sdk.harmony -a EntryAbility -W`
- 最后用 `aa dump -l EntryAbility` 复核是否已进入前台

如果脚本仍提示 `screen locked during launch`，它会打印最短人工步骤并等待你按回车后重试。

手工 hdc 流程仍然可用：

1. 先在 DevEco Studio 启动一个 Harmony 模拟器。
2. 用下面的命令安装 HAP：

```bash
hdc install <entry-hap-path>
```

3. 查看安装结果：

```bash
hdc shell bm dump -a
```

4. 拉起 Demo Ability：

```bash
hdc shell aa start -b io.github.neptune.sdk.harmony -a EntryAbility
```

5. 如遇 `screen locked during launch`，先在模拟器上解锁再重试。
6. 回到模拟器，点击页面按钮即可看到 metrics / sources 摘要刷新。
7. 点击“发现网关”按钮，确认页面会显示成功结果或失败原因，不影响现有 batch/metrics/sources 面板。

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

## 网关发现

Harmony SDK 侧现在提供一个可注入的网关发现解析器：

- 先尝试 `mDNS` 产生的候选地址
- 如果 `mDNS` 不可用，再回退到手动 `DSN`
- 对每个候选都会请求 `GET /v2/gateway/discovery`
- 只有当返回体包含有效的 `host`、`port`、`version` 时才算发现成功
- `mDNS` 需要在 `GatewayDiscoveryConfig` 中传入 `mdnsContext`（通常是 `UIAbilityContext`）
- 可选配置 `mdnsServiceType`（默认 `_neptune._tcp`）和 `mdnsServiceName`（用于精确匹配实例名）

### 用法

```ts
import { createGatewayDiscoveryResolver } from 'neptune-sdk-harmony'

const resolver = createGatewayDiscoveryResolver()
const gateway = await resolver.discover({
  manualDsn: '127.0.0.1:18765',
  mdnsContext: this.getUIContext().getHostContext(),
  requestTimeoutMs: 2000
})

console.info(gateway.host, gateway.port, gateway.version)
```

### 当前边界

- 默认 `mDNS` 提供器已经接入 `@kit.NetworkKit`；如果未传 `mdnsContext`，会自动返回空候选并回退到手动 DSN。
- 若你有自定义发现策略，仍可自定义实现 `GatewayDiscoveryMdnsProvider` 并注入替换默认实现。
- 手动 `DSN` 仍然是可靠回退路径，适合模拟器和局域网直连调试。

## WebSocket 客户端

Harmony SDK 侧还提供一个后台 WebSocket 客户端，和 discovery / 手动 DSN 共享同一条端点解析链路：

- 启动时先解析网关端点，再连接 `ws://<host>:<port>/v2/ws`
- 建连后立即发送 `{"type":"hello","role":"sdk"}`
- 每 15 秒发送一次 heartbeat
- 如果 45 秒没有收到任何活动，进入重连流程
- 重连退避为 `0.5s / 1s / 2s / 4s / 8s`
- 收到 `command.dispatch` 且 `command === 'ping'` 时，立即回 `command.ack`
- discovery 结果或手动 DSN 变化时，会切换到新的端点并重连

### 用法

```ts
import { GatewayWsManager } from 'neptune-sdk-harmony'

const manager = new GatewayWsManager()
await manager.start({
  manualDsn: '127.0.0.1:18765'
})

await manager.reconnect()
```

### 当前边界

- API 12 没有可直接依赖的应用层 ping/pong 帧，因此这里用应用层 heartbeat 和失联计时实现保活。
- 默认 `GatewayWsManager` 只做连接管理，不把收到的消息再转发给业务层；后续如果要挂入真实命令分发，只需要在 `GatewayWsClient` 的消息分支扩展即可。

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

`ingest()` 会在入队时自动注册来源快照，来源主键由以下字段共同决定：

- `platform`
- `appId`
- `deviceId`

`sessionId` 仅作为展示字段保留，不参与来源主键。

同一主键重复上报时，只会更新对应来源的 `lastSeenAt`。

启动后可访问：

- `http://<device-ip>:18765/v2/export/health`
- `http://<device-ip>:18765/v2/export/metrics`
- `http://<device-ip>:18765/v2/logs`
- `http://<device-ip>:18765/v2/logs?platform=harmony&appId=demo.app&sessionId=session-1`
- `http://<device-ip>:18765/v2/export/sources`

`/v2/logs` 的 `platform`、`appId`、`sessionId` 都是可选参数：

- 不传或传空字符串时，等同于不启用该字段过滤
- 多个过滤条件同时传入时，按 AND 关系匹配
- `cursor/limit` 仍然可用，语义为“在 `id > cursor` 的记录中按过滤条件取最多 `limit` 条”

## 最小验证脚本

仓库内提供：

```bash
./scripts/verify-sources-endpoint.sh http://127.0.0.1:18765 1
node ./scripts/verify-source-dedup.mjs
node ./scripts/verify-log-query-filtering.mjs
node ./scripts/verify-log-persistence.mjs
```
