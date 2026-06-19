# Yamibo 论坛网络网关内部库边界与抽包预留说明

## 当前内部库入口

Yamibo 网络基础能力集中在：

```text
lib/core/network/yamibo/yamibo.dart
```

该文件是内部 public export，面向 app 内 feature repository、data source 和测试使用。新增 Yamibo 网络能力时，优先判断是否属于这个边界，再决定是否导出。

## 可抽包候选

未来独立 Dart package 可以包含：

- `YamiboHttpGateway`：HTTP 传输、Cookie attach/save、日志、诊断和错误映射入口。
- `YamiboApiClient`：Discuz mobile API GET/POST form 基础封装。
- `YamiboHtmlClient`：移动端 HTML 页面请求封装。
- `YamiboResourceClient`：资源 bytes 请求封装，包含 image probe 等轻量场景。
- `YamiboRequestContext` / `YamiboRequestKind`：请求意图上下文。
- `YamiboHttpResponse`：网关响应载体。
- `YamiboSessionSnapshot` / `YamiboSessionStore` / `YamiboSessionExtractor`：公共 session/formhash 管理。
- 可复用的 Discuz 响应模型、错误模型和解析工具。

这些类型不得依赖 Flutter Widget、Riverpod 页面 controller、Y300 UI 状态或书架业务模型。

## 不进入独立 package 的内容

以下内容属于 Y300 app 边界，不应抽进通用 Yamibo 网络 package：

- Riverpod provider 装配，例如 `network_providers.dart`。
- 论坛首页、帖子详情、搜索页、回复页、发帖页等 UI/controller。
- 漫画、小说、收藏、书架、本地下载和历史记录业务模型。
- `ForumHomeHtmlParser`、帖子内容分类器、漫画章节发现策略等强绑定 Y300 业务体验的 parser/service。
- Flutter theme、Widget、页面导航和本地持久化 UI 流程。

## Provider 装配约束

- `lib/core/network/yamibo/` 内的核心类型保持纯 Dart/network/service 形态。
- Riverpod provider 继续放在 `lib/core/network/network_providers.dart` 或 app 侧 provider 文件。
- feature repository 通过 provider 获取 client/gateway，但具体 parser 仍留在 feature 层。

## API 资产保留原则

页面可以暂时不调用某些 API，但不能删除已有 API repository、provider、模型、测试或 module 能力。`forumindex`、`profile`、`myfavforum` 等能力应继续作为 Dart 网络库资产保留，并在后续维护中迁移/沉淀进 `YamiboApiClient` 或独立 package。

小说相关请求的 `version=1` 约束必须继续保留，不得被默认 `version=4` 覆盖。

## 抽包前检查清单

- API、HTML、表单、资源探测都已经走 `YamiboHttpGateway`。
- `formhash`、UID、用户名和登录态可以从 API/HTML 响应进入 `YamiboSessionStore`。
- 搜索、回复、发帖、附件、收藏至少完成一轮网关迁移验证。
- 统一日志中能通过 `kind`、`operation`、`requestId` 定位请求。
- package 候选类型没有依赖 Flutter Widget 或 Riverpod。
- 关键核心测试覆盖 public export、网关请求、session 提取和 API 版本策略。
