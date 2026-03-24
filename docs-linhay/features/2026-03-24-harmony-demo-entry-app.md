# neptune-sdk-harmony 可运行 Demo App

## 背景

当前 `neptune-sdk-harmony` 已经具备可构建的 HAR SDK 能力，但缺少一个真正可以在 Harmony 模拟器上直接运行的 `entry` HAP。这样会导致：

- 只能验证 library 构建，无法验证真实 UI 启动链路。
- SDK 对外使用者没有一个官方 demo 入口去观察日志写入、metrics 和 sources 摘要。
- 核心 HAR 虽然可用，但 demo 层需要额外的工程模板才能接起来。

## 目标

在当前工程中新增一个可运行的 Harmony Demo App，满足以下条件：

- 新增 `entry` 模块，能够被 DevEco / hvigor 识别并打包为 HAP。
- Demo 页面通过模块依赖引用现有 `library` HAR，不复制核心 SDK 代码。
- 页面提供一个按钮，点击后向 Neptune SDK 写入示例日志，并在页面内刷新 `metrics` 与 `sources` 摘要。
- 保持现有 `library` 构建链路不退化。
- 提供独立的 demo 构建命令和脚本。
- README、文档和记忆同步更新，说明模拟器运行步骤。

## 非目标

- 不在本轮引入网络服务端口监听。
- 不在本轮做真机/上架签名流程。
- 不改动现有 HAR 核心日志模型和导出契约。

## 验收场景

### 场景 1：Demo 工程可识别

- 假如仓库根目录已安装 Harmony Command Line Tools
- 当我执行 `./hvigorw --mode project tasks --no-daemon`
- 那么输出中应能识别 `entry` 与 `library` 两个模块

### 场景 2：Demo HAP 可构建

- 假如 `entry` 模块已配置完成
- 当我执行 `./hvigorw --mode module -p module=entry assembleHap --no-daemon`
- 那么应成功产出可安装到模拟器的 HAP

### 场景 3：按钮能写入 SDK 日志

- 假如 demo 页面已在模拟器中打开
- 当我点击“写入 Demo 日志批次”按钮
- 那么页面应调用 Neptune SDK 写入一批日志，并刷新 `queueSize`、`totalIngested`、`sources`、`recent logs` 的展示

### 场景 4：核心代码不重复

- 假如 demo 需要 Neptune SDK 的日志能力
- 当我查看 `entry` 的依赖配置
- 那么应只看到对 `library` HAR 的模块依赖，而不是复制一份 SDK 核心实现

## 交付物

- `entry/` Harmony Stage 应用模块
- `scripts/build-demo-entry.sh`
- `scripts/verify-demo-entry.mjs`
- `README.md` 中的模拟器运行步骤
