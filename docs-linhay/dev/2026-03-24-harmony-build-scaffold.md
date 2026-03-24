# neptune-sdk-harmony Harmony HAR 骨架设计

## 设计结论

本仓库以 `Harmony project shell + HAR library module` 的两层结构补齐最小构建骨架，而不是新增可运行 HAP。原因：

- 仓库本质是 SDK，不是独立应用。
- Harmony 官方包结构中，面向外部复用的共享代码更适合 `HAR`。
- `hvigor` 即便以 `--mode module` 运行，也要求仓库根目录具备项目级 `build-profile.json5` 与 `modules` 数组。

## 目录策略

- 保留现有 `src/main/ets/**` 作为真实实现和唯一源码来源。
- 新增项目级配置：
  - `build-profile.json5`
  - `hvigorfile.ts`
  - `hvigor/hvigor-config.json5`
  - `AppScope/app.json5`
- 新增 `library/` 作为 HAR 模块，包含：
  - `library/oh-package.json5`
  - `library/build-profile.json5`
  - `library/hvigorfile.ts`
  - `library/Index.ets`
  - `library/Index.d.ets`
  - `library/src/main/module.json5`
- 新增 `scripts/sync-harmony-module.sh`，在构建前把顶层 `src/main/ets` 同步到 `library/src/main/ets`。
- `./hvigorw` 负责两件事：
  - 先执行同步脚本，避免双份源码长期漂移
  - 再调用系统中的 `hvigorw`，并兼容常见本机 SDK 环境变量缺省场景

## 已验证命令

```bash
./hvigorw --mode project tasks --no-daemon
./hvigorw --mode project clean --no-daemon
./hvigorw --mode module -p module=library assembleHar --no-daemon
```

## 本机验证结论（2026-03-24）

已通过：

- `project tasks`
- `project clean`

已失败但配置链路完整：

- `module assembleHar`

当前真实阻塞：

1. ArkTS 编译器对现有 SDK 源码执行严格检查时，`RdbLogStore`、`LogStoreBase`、`LogQueue`、`ExportServer` 仍存在不兼容语法。
2. `@cxy/webserver` 依赖未能从当前私有 registry 拉取。
3. `RdbLogStore` 仍需按 API 12 的 `@kit.ArkData` 导入与类型规则继续收敛。

## 风险

- 若开发机未安装 Harmony Command Line Tools，`./hvigorw` 只能给出明确缺失提示，无法真实编译。
- 当前模块已经脱离“缺工程配置”状态，但尚未脱离“源码不符合 ArkTS 严格子集”的状态。
- 若后续直接复制源码而不是继续走同步脚本，容易出现顶层源码与模块内副本漂移。
