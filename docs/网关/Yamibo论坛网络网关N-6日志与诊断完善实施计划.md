# Yamibo 论坛网络网关 N-6 日志与诊断完善实施计划

## 范围

N-6 在 N-1 到 N-5 已完成统一传输迁移的基础上，补齐 Yamibo 请求的可观测性。目标是让日志和同步诊断都能回答“这是哪类请求、为什么发起、属于哪个模块、同一次请求的日志和诊断如何对应”。

本阶段聚焦 `YamiboHttpGateway`、`YamiboRequestLogger` 和 `NetworkDiagnosticRecorder` 的上下文传递，不迁移新的业务链路。

## 非目标

- 不改变首页 HTML-first 数据源。
- 不改变搜索、回复、发帖、附件、收藏、漫画目录的业务 parser。
- 不新增完整日志查看 UI。
- 不打印 Cookie、密码、完整表单 body 或完整 HTML。
- 不删除任何 API、repository、provider 或测试资产。

## 设计

### 请求标识

- `YamiboHttpGateway` 为每个请求生成短 request id。
- request id 同时写入 `[YamiboHTTP]` 日志和 `NetworkDiagnosticRecorder`。
- request id 使用进程内递增序号生成，格式为 `yhttp-1`、`yhttp-2`，足够用于用户贴日志时关联同一次请求。

### 诊断上下文

扩展 `NetworkDiagnosticRecorder.recordHttpRequest` 的可选字段：

- `kind`
- `operation`
- `module`
- `pageKind`
- `requestId`

`YamiboHttpGateway` 从 `YamiboRequestContext` 填入这些字段。非 Yamibo 调用方可以继续不传，保持兼容。

`DefaultSyncDiagnosticRecorder` 写入 JSON 行时增加这些字段，便于后续按 `kind`、`operation` 或 `requestId` 过滤。

### 日志格式

成功日志保留现有格式前缀，并追加 request id 字段，避免破坏已有按 `[YamiboHTTP][kind][operation]` 的过滤方式：

```text
[YamiboHTTP][html][forum.home.html] GET https://bbs.yamibo.com/index.php?mobile=2 -> 200 183ms requestId=yhttp-1 body=String(length=42851)
```

失败日志：

```text
[YamiboHTTP][html][forum.home.html] GET https://bbs.yamibo.com/index.php?mobile=2 -> failed 502 518ms requestId=yhttp-1 error=badResponse
```

日志仍只输出 body 摘要：

- `String(length=...)`
- `Bytes(length=...)`
- `Map(length=...)`
- `Iterable(length=...)`

### 安全策略

- 请求日志不输出 headers，因此不会打印 Cookie。
- 表单和 multipart 请求不输出 body 字段和值。
- HTML 响应不输出正文，只输出长度。
- 诊断只保存 host/path/query/status/elapsed/request context，不保存 Cookie 和表单正文。

## 修改清单

- 更新 `NetworkDiagnosticRecorder` 接口和 no-op 实现，增加可选 Yamibo 上下文字段。
- 更新 `DefaultSyncDiagnosticRecorder`，将可选上下文字段写入 JSON `fields`。
- 更新 `YamiboRequestLogger`，支持 request id 并保持 body 摘要安全。
- 更新 `YamiboHttpGateway`，为每次请求生成 request id，并传递给日志和诊断。
- 更新网关和同步诊断测试，覆盖 request id、kind、operation、module、pageKind 进入日志/诊断。
- 更新 `docs/开发文档.md` 顶部，记录 N-6 可观测性变化。

## 测试计划

- `flutter analyze`
- `flutter test test\core\network\yamibo\yamibo_http_gateway_test.dart`
- `flutter test test\features\library_shared\data\sync_diagnostic_recorder_impl_test.dart`

## 验收点

- `[YamiboHTTP]` 日志能看到 `kind`、`operation` 和短 request id。
- 同步诊断 JSON 能看到 `kind`、`operation`、`module`、`pageKind`、`requestId`。
- 日志和诊断仍不泄露 Cookie、密码、完整表单 body 或完整 HTML。
- 已有业务请求语义不变。
