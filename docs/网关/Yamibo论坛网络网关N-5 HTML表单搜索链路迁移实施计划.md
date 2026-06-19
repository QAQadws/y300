# Yamibo 论坛网络网关 N-5 HTML/表单/搜索链路迁移实施计划

## 范围

N-5 收口 N-4 后仍绕过统一网关的 Yamibo 站点 HTML、表单和资源请求。目标是让搜索、回复准备、回复提交、发帖提交、附件上传、帖子收藏和漫画目录 HTML 获取进入 `YamiboHttpGateway` 的 Cookie、日志、诊断和 session 管线。

已经通过 `ApiClient` 进入 `YamiboApiClient` 的 `forumindex/profile/myfavforum/forumdisplay` 等移动 API 不重复迁移，只保留现有业务 repository 语义。

## 非目标

- 不重写 UI/controller。
- 不删除旧 repository、模型或测试。
- 不改变业务 parser 归属；搜索 HTML parser、回复表单 parser、发帖响应 parser、漫画目录 parser 仍在对应 feature。
- 不改变小说 `version=1` 约束。
- 不把所有表单业务合并成一个巨型 service；每条链路只替换传输层。

## 迁移清单

### 搜索

- `DiscuzSearchService` 由自建 `Dio` 改为依赖 `YamiboHttpGateway`。
- 搜索提交使用 `postForm`，`followRedirects=false`，保留读取 `Location` 的行为。
- 搜索结果页和下一页使用 `getText`。
- operation 使用 `search.forum.submit`、`search.forum.result`、`search.forum.nextPage`。

### 回复

- `DiscuzReplyFormPreparationDataSource` 改为依赖 `YamiboHtmlClient` / `YamiboHttpGateway.getText` 拉 HTML 表单。
- `DiscuzReplyDioRemoteDataSource` 改为 `DiscuzReplyGatewayRemoteDataSource`，通过 `YamiboHttpGateway.postForm` 提交 `sendreply`。
- 保留 `ReplyFormParser` 和 `DiscuzReplyApiRepository` 业务逻辑。

### 发帖

- `DiscuzNewThreadDioRemoteDataSource` 改为网关传输，提交 `newthread` form。
- `PostingFormMetadataRepository` 已经通过 `ApiClient` 进入 N-4 网关，不重复迁移。

### 附件

- `DiscuzComposerAttachmentDioDataSource` 的 `checkpost` 已经是 API 语义，改为通过 `YamiboApiClient` 或 `ApiClient` 获取。
- `forumupload` 需要 multipart，N-5 扩展 `YamiboHttpGateway.postMultipart`，仅用于附件上传，日志只输出 body 摘要，不打印文件内容。

### 收藏

- `DiscuzThreadFavoriteApiRepository` 仍自建 `Dio`，N-5 改为通过 `YamiboHttpGateway.postForm`。
- `DefaultForumFavoriteRepository` 已经通过 `ApiClient.postDiscuzForm` 进入 N-4 网关，不重复迁移。

### 漫画目录 HTML

- `DioCatalogHtmlFetcher` 改为 `YamiboCatalogHtmlFetcher`，通过 `YamiboHttpGateway.getText` 获取 catalog HTML。

## 网关扩展

`YamiboHttpGateway` 在 N-5 增加：

- `followRedirects` 参数，支持搜索提交读取 302 Location。
- `postMultipart`，支持 `FormData` 附件上传。
- 请求 method/operation 保持进入 `[YamiboHTTP]` 日志；普通图片缓存加载仍不接入业务日志。

## 测试计划

- 更新搜索服务测试，断言搜索提交/结果/下一页仍工作，并使用网关测试 adapter。
- 更新回复准备/提交测试，断言 cookie、referer、form body 与旧语义一致。
- 更新发帖提交、附件上传、帖子收藏测试，断言 query/body/header 与旧语义一致。
- 更新漫画目录 fetcher 测试或补充单测，断言 catalog HTML 通过网关返回失败时保持 `null` 降级。
- 跑 `flutter analyze` 和相关 targeted `flutter test`。

## 验收点

- 新迁移链路不再直接创建 Yamibo 站点相关 `Dio`。
- 搜索、回复、发帖、附件、收藏、漫画目录请求日志能区分 `html/api/resource` 与 operation。
- 业务 parser 不进入 core。
- API 资产继续保留，后续 N-6/N-7 聚焦日志诊断和库边界稳定。
