# neptune-sdk-harmony

NeptuneKit v2 Harmony SDK 骨架，当前目标是先把“本地落地 + 本地 HTTP 导出服务”跑通到可继续开发的结构层。

## 当前能力

- 统一 v2 日志模型定义
- 本地内存队列，支持 overflow 计数
- 导出服务骨架：
  - `GET /v2/export/health`
  - `GET /v2/export/metrics`
  - `GET /v2/export/logs?cursor&limit`
- 先用 in-memory 存储，后续再替换成持久化实现

## 队列参数

- 容量：`2000`
- 批量：`50`
- flush 间隔：`1s`
- 重试阶梯：`0.5s / 1s / 2s / 4s / 8s`

## 开发依赖

- `hdc`：连接设备、安装/拉起应用、查看 `hilog`
- `ohpm`：依赖安装与包管理
- `hvigorw`：构建与打包

## 后续 TODO

- 把 `ExportServer` 绑定到真实 transport 层
- 接入持久化存储，替换纯内存队列
- 增加 `cursor` 分页与 `platform/appId/sessionId` 过滤
- 接入 `AppServiceExtensionAbility` 或等效能力做后台服务承载
- 补齐构建配置与样例入口
