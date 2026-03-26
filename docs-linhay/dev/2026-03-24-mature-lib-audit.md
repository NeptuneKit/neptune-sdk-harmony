# neptune-sdk-harmony 成熟库优先审计

日期：2026-03-24

## 审计范围

- HTTP 导出实现
- 数据序列化与响应输出
- 脚本工具

## 结论

当前仓库没有发现需要替换的“手搓基础设施”：

- HTTP 服务已经由 `@cxy/webserver` 承担，项目侧只做路由注册和业务装配。
- 数据响应通过 `res.status(...).json(...)` 输出，没有自定义 JSON 编码器。
- 脚本工具使用 `curl`、`node` 和标准 `JSON.parse` 做验证，没有引入自写协议解析器或自研 HTTP 客户端。

因此本次未修改运行时逻辑，只补充审计记录与验证命令。

## 依据

### HTTP 导出

`src/main/ets/server/ExportServer.ets` 中：

- `HttpServer`、`HttpRequest`、`HttpResponse` 均来自 `@cxy/webserver`
- 路由仅包含 `GET /v2/export/health`
- 路由仅包含 `GET /v2/export/metrics`
- 路由仅包含 `GET /v2/logs`
- 路由仅包含 `GET /v2/export/sources`

项目侧没有自己实现 socket accept、请求解析、header/body 编码或状态行拼装。

### 序列化

响应体通过 webserver 的 `.json(...)` 输出，入参是普通对象或数组：

- `health()`
- `metrics()`
- `queryLogs(...)`
- `sourcesSnapshot()`

项目侧没有额外写一层 JSON stringify / parse 封装，也没有自己维护协议 schema 编解码器。

### 脚本工具

`scripts/verify-sources-endpoint.sh`：

- 使用 `curl` 调接口
- 使用 `node` 和 `JSON.parse` 校验返回值

`scripts/verify-source-dedup.mjs`：

- 仅用于验证去重逻辑
- 使用标准 Node 断言，不依赖自写解析器

这两份脚本属于验证工具，不是生产基础设施实现。

## 验证命令

在 `neptune-sdk-harmony/` 目录下执行：

```bash
bash -n scripts/verify-sources-endpoint.sh
node scripts/verify-source-dedup.mjs
```

如果本地已经启动了导出服务，再补一条运行时验证：

```bash
./scripts/verify-sources-endpoint.sh http://127.0.0.1:18765 1
```

## 后续建议

- 继续保持 HTTP、序列化、CLI 验证只做薄适配，不在项目内重复造底层实现。
- 若后续要补持久化、鉴权或协议兼容，再优先评估成熟库。
