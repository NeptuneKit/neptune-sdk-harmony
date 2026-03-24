# neptune-sdk-harmony 最小 Harmony 构建骨架

## 背景

`neptune-sdk-harmony` 当前已经具备 ArkTS SDK 源码，但缺少可被 `hvigor` 识别的最小 Harmony 工程壳与模块配置，导致无法执行基础构建命令，也无法作为 HAR 静态共享包进入后续集成链路。

## 目标

为仓库补齐最小可审查、可执行的 Harmony HAR 模块骨架，满足以下条件：

- 保留现有 `src/main/ets` SDK 源码结构，不做回滚。
- 补齐项目级 `build-profile.json5`、`hvigorfile.ts`、`hvigor/hvigor-config.json5`、`AppScope/app.json5`。
- 补齐 `library/` 下的 HAR 模块配置与包导出入口。
- 提供仓库内可直接执行的构建命令，优先支持 `./hvigorw --mode module -p module=library assembleHar --no-daemon`。
- README 补充安装和构建步骤，并记录本机验证结果。

## 非目标

- 本轮不引入可运行的 `HAP` 示例应用。
- 本轮不处理签名、上架或真机运行。
- 本轮不改变 SDK 对外 API 语义。

## 验收场景

### 场景 1：工程可被 hvigor 识别

- 假如开发机已安装 Harmony Command Line Tools
- 当我在仓库根目录执行 `./hvigorw --mode project tasks --no-daemon`
- 那么项目壳与 `library` 模块应能被 `hvigor` 正确识别

### 场景 2：项目级清理可执行

- 假如仓库根目录存在完整工程壳
- 当我执行 `./hvigorw --mode project clean --no-daemon`
- 那么 `hvigor` 应能完成基础清理命令

### 场景 3：模块构建有明确结论

- 假如仓库根目录存在项目壳与 `library` 模块
- 当我执行 `./hvigorw --mode module -p module=library assembleHar --no-daemon`
- 那么要么完成 HAR 构建，要么输出明确的源码/依赖阻塞，而不是缺少工程配置

### 场景 4：环境缺失时可审查

- 假如本机未安装 Harmony 构建工具链
- 当我查看仓库内容
- 那么仍应能看到完整的 Harmony 工程配置、模块配置、同步脚本和 README 步骤，而不是只有源码目录
