# neptune-sdk-harmony Demo App 设计

## 设计结论

这次新增的是“可上模拟器的 Demo App”，不是把 SDK 改造成应用。

因此工程仍然保持两层结构：

- `library/`：SDK HAR，保留 Neptune 日志模型、队列、持久化和导出能力。
- `entry/`：可运行 HAP，只负责 UI、启动和演示编排。

Demo 页面对 SDK 的使用方式是：

1. 通过 `oh-package.json5` 依赖本地 `library` HAR。
2. 页面按钮触发 `demoRuntime.seedBatch()`。
3. `demoRuntime` 内部调用 `createExportServer(new LogQueue())` 生成内存版导出服务。
4. 每次按钮点击写入 3 条示例日志。
5. 页面同步渲染 `metrics`、`sources` 和最近日志摘要。

## 目录策略

- 保留顶层 `src/main/ets` 作为 SDK 真实源码来源。
- `library/` 继续通过 `scripts/sync-harmony-module.sh` 从顶层源码同步。
- 新增 `entry/` 作为 HAP demo 模块，不参与 core SDK 源码同步。
- `entry/src/main/resources/base/profile/main_pages.json` 用于声明首页路由。
- `entry/src/main/module.json5` 用于声明 Stage 模块、Ability 和页面入口。
- `AppScope/app.json5` 需要补齐 `icon` / `label`，否则 `entry` 无法通过 `PreBuild`。
- `build-profile.json5` 需要开启 `buildOption.strictMode.useNormalizedOHMUrl`，否则 `@cxy/webserver` 这种 bytecode HAR 依赖无法参与 HAP 构建。

## 构建链路

- SDK 构建仍使用：

```bash
./hvigorw --mode module -p module=library assembleHar --no-daemon
```

- Demo App 构建使用：

```bash
./hvigorw --mode module -p module=entry assembleHap --no-daemon
```

- 本地便捷脚本：

```bash
./scripts/build-demo-entry.sh
```

- 一键拉起脚本：

```bash
./scripts/start-demo-via-hdc.sh
```

## 模拟器运行步骤

### DevEco Studio

1. 打开 `neptune-sdk-harmony` 工程。
2. 等待 `ohpm install` / 项目同步完成。
3. 选择 `entry` 模块和一个 Harmony 模拟器。
4. 点击 Run。
5. 在模拟器中打开 demo 页面，点击“写入 Demo 日志批次”按钮。

### hdc

推荐直接使用一键脚本：

```bash
./scripts/start-demo-via-hdc.sh
```

脚本行为：

- 自动识别已连接的 hdc target，或使用 `--target` / `HDC_TARGET`
- 自动寻找 `entry/build/default/outputs/default/entry-default-unsigned.hap`
- 如果 HAP 不存在，默认先执行 `./scripts/build-demo-entry.sh`
- 启动前会尽力执行 `power-shell timeout -o`、`power-shell wakeup` 和 `uinput swipe`
- 安装完成后执行 `aa start -b io.github.neptune.sdk.harmony -a EntryAbility -W`
- 通过 `aa dump -l EntryAbility` 复核是否已进入前台

如果自动解锁仍然失败，脚本会打印最短人工步骤并等待回车后重试。

手工流程仍然保留：

1. 先用 DevEco Studio 启动一个 Harmony 模拟器。
2. 安装 Demo HAP：

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

5. 如果遇到 `screen locked during launch`，先解锁模拟器再重试。
6. 回到模拟器界面，点击页面上的按钮验证日志写入。

## 校验策略

- `node ./scripts/verify-demo-entry.mjs`：静态校验 entry 模块结构。
- `./hvigorw --mode project tasks --no-daemon`：确认根工程识别两个模块。
- `./hvigorw --mode module -p module=entry assembleHap --no-daemon`：确认 demo 可打包。
- `./hvigorw --mode module -p module=library assembleHar --no-daemon`：确认 SDK HAR 不回退。
- `./scripts/build-demo-entry.sh`：确认包装脚本可直接完成 Demo HAP 构建。

## 风险

- 如果本机没有安装 Harmony Command Line Tools，`hvigorw` 只能报缺失，无法真实构建。
- `entry` 当前使用内存队列来保持 demo 稳定性，没有启用网络服务端口。
- 页面目前展示的是摘要视图，不是完整日志管理界面。
- `entry` 的 `startWindowIcon` 需要放在 `entry/src/main/resources/base/media`，否则启动窗 schema 校验会失败。
