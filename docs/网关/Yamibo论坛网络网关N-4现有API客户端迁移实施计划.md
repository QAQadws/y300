# Yamibo 论坛网络网关 N-4 现有 API 客户端迁移实施计划

## 范围

N-4 将现有 `ApiClient` 改为兼容适配层，内部委托新的 `YamiboApiClient` 执行 Discuz mobile API GET/POST。业务 repository、provider、模型和测试继续保留，调用方仍可使用 `ApiClient.getDiscuz`、`postDiscuzForm`、`getParsed`。

本阶段目标是让 API 请求进入统一 `YamiboHttpGateway` Cookie、日志、诊断和 session extraction 管线，日志形态变为 `[YamiboHTTP][api][module] ...`。

## 非目标

- 不重写所有业务 repository 的构造参数。
- 不删除 `ApiClient`、`ForumRepository`、`FavoriteRepository`、`ProfileRepository` 或任何 API 资产。
- 不迁移搜索、回复表单准备、发帖、附件上传等直接 HTML/form 请求，N-5 再处理。
- 不改变业务错误映射语义；`Message` 节点仍按调用方指定的 `treatMessageAsBusinessError` 决定是否视为业务失败。
- 不改变小说 `version=1` 请求约束，调用方传入的 query `version` 必须优先于默认版本。

## 设计

### YamiboApiClient

新增 `lib/core/network/yamibo/yamibo_api_client.dart`：

- `getDiscuz(module, queryParameters, cancelToken, treatMessageAsBusinessError)`
- `postDiscuzForm(module, data, queryParameters, cancelToken, options)`

职责：

- 构建 `AppConfig.apiBaseUrl` URI。
- 注入默认 `version=4`，但尊重调用方传入的 `version`。
- 通过 `YamiboHttpGateway.getText` / `postForm` 发起请求。
- 解析 JSON 到 `DiscuzResponse`。
- 保持 `DioException` 已由 gateway 映射为 `ApiError`，JSON/业务解析错误在 client 层映射。

### YamiboHttpGateway 扩展

在 N-1/N-3 的 `getText/getBytes` 基础上新增 `postForm`，统一：

- Cookie attach/save。
- NetworkDiagnosticRecorder。
- `[YamiboHTTP][api][module]` 日志摘要。
- session extraction。

### ApiClient 兼容层

`ApiClient` 构造函数继续接受旧参数，内部默认创建 `YamiboHttpGateway` 与 `YamiboApiClient`；测试也可注入 `Dio` adapter。`ApiClient` 方法签名保持不变，内部委托 `YamiboApiClient`。

## 测试计划

- 新增或扩展 `yamibo_api_client_test.dart`：
  - GET API 注入默认 `version=4`。
  - 调用方传入 `version=1` 时不被覆盖。
  - `Message` 节点按 `treatMessageAsBusinessError` 映射。
  - POST form 发送 urlencoded body。
- 更新 `api_client_post_form_test.dart`，确认旧 `ApiClient.postDiscuzForm` 兼容行为不变。
- 更新 auth/novel/forum favorite 相关测试，确保旧 repository 仍通过。
- 跑 `flutter analyze`。

## 验收点

- 现有 API 请求走 `[YamiboHTTP][api][module]` 日志。
- repository 不需要大面积改造。
- `forumindex/profile/myfavforum` 能力完整保留。
- 小说 `viewthread` 仍使用 `version=1`。
- API 响应继续刷新 `YamiboSessionStore`。
