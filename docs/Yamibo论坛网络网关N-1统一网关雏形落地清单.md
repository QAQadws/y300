# Yamibo 论坛网络网关 N-1 统一网关雏形落地清单

## 1. 范围

N-1 只落地最小 Yamibo 网络网关雏形，把原生论坛首页 HTML 请求和轮播首图尺寸探测接入统一 Cookie、日志与诊断管线。

本阶段新增：

- `lib/core/network/yamibo/yamibo_request_context.dart`
- `lib/core/network/yamibo/yamibo_http_response.dart`
- `lib/core/network/yamibo/yamibo_request_logger.dart`
- `lib/core/network/yamibo/yamibo_http_gateway.dart`
- `lib/core/network/yamibo/yamibo_html_client.dart`
- `lib/core/network/yamibo/yamibo_resource_client.dart`

本阶段迁移：

- `DiscuzForumHomeChromeRepository` 的 `index.php?mobile=2` HTML 请求。
- `ForumHomeCarouselImageProbe` 的轮播首图 bytes 请求。

## 2. 非目标

- 不迁移、删除或弱化 `ApiClient`。
- 不改 `ForumHomeRepository` 的首页聚合方式。
- 不移除首页当前 `forumindex/profile/myfavforum` 三次 API 请求。
- 不迁移搜索、回复、发帖、收藏、上传、漫画 catalog HTML 等其它直接 `Dio` 入口。
- 不实现 `YamiboApiClient`、session store、formhash extractor 或 HTML-first 首页。

N-1 后首页仍可能出现 `forumindex/profile/myfavforum` 三次 API 请求，这是预期行为；N-2 才处理首页初始渲染的数据源切换。

## 3. 新增文件职责

| 文件 | 职责 |
| --- | --- |
| `yamibo_request_context.dart` | 定义 `YamiboRequestKind` 和 `YamiboRequestContext`，为日志和诊断提供请求意图 |
| `yamibo_http_response.dart` | 保存 uri、statusCode、headers、body，供上层 client 解包 |
| `yamibo_request_logger.dart` | 输出统一日志摘要，不打印 Cookie 或完整 HTML/bytes |
| `yamibo_http_gateway.dart` | 实现 `getText`、`getBytes`，统一 Cookie attach/save、Dio 错误映射、耗时统计、诊断和日志 |
| `yamibo_html_client.dart` | 封装移动端 HTML 页请求头，固定 mobile UA、HTML Accept 和站点 Referer |
| `yamibo_resource_client.dart` | 封装资源 bytes 请求，本阶段用于 `imageProbe` |

## 4. Provider 装配

`lib/core/network/network_providers.dart` 新增：

- `yamiboHttpGatewayProvider`
- `yamiboHtmlClientProvider`
- `yamiboResourceClientProvider`

它们复用现有：

- `cookieStoreProvider`
- `loggerProvider`
- `syncDiagnosticRecorderProvider`

`imageRequestHeaderBuilderProvider` 继续负责图片请求头和同站 Cookie 构建，普通图片缓存加载不接入 N-1 业务日志。

## 5. 首页 HTML 迁移清单

- `DiscuzForumHomeChromeRepository` 改为依赖 `YamiboHtmlClient`。
- 首页 HTML 请求仍只请求 `/index.php?mobile=2`。
- HTML client 负责 mobile UA、HTML Accept、Referer 和网关调用。
- `ForumHomeChromeParser` 继续只解析业务 DOM，不接触 Cookie、Dio 或日志。
- `ForumHomeChromeData`、repository 接口和首页聚合 payload 语义保持不变。

## 6. imageProbe 迁移清单

- `ForumHomeCarouselImageProbe` 改为依赖 `YamiboResourceClient` 和 `ImageRequestHeaderBuilder`。
- probe 继续保留 PNG/JPEG/WebP 尺寸解析。
- probe 继续保留比例 clamp、失败返回 `null`、`fallbackAspectRatio` 常量。
- probe 请求使用 `YamiboRequestContext(kind: imageProbe, operation: forum.home.carouselProbe)`。
- 普通图片缓存加载不走该业务日志，避免日志刷屏。

## 7. 预期日志样例

首页 HTML 请求成功时：

```text
[YamiboHTTP][html][forum.home.chrome] GET https://bbs.yamibo.com/index.php?mobile=2 -> 200 123ms body=String(length=42851)
```

轮播首图尺寸探测成功时：

```text
[YamiboHTTP][imageProbe][forum.home.carouselProbe] GET https://bbs.yamibo.com/data/attachment/block/95/banner.jpg -> 200 45ms body=Bytes(length=8192)
```

请求失败时：

```text
[YamiboHTTP][html][forum.home.chrome] GET https://bbs.yamibo.com/index.php?mobile=2 -> failed 503 88ms error=badResponse
```

## 8. API 资产保留清单

N-1 保留全部现有 API 能力，包括但不限于：

- `forumindex`
- `profile`
- `myfavforum`
- `myfavthread`
- `forumdisplay`
- `viewthread`
- `favforum/favthread`
- `login/logout`
- `newthread/sendreply/forumupload/checkpost`

这些 API 可以暂时不被某个页面调用，但不能删除。后续应逐步迁移进 `YamiboApiClient` / Dart 网络库，保持 repository、provider、模型、parser 和测试覆盖语义。

## 9. 测试覆盖

新增 `test/core/network/yamibo/yamibo_http_gateway_test.dart` 覆盖：

- `getText` 附加 Cookie。
- 保存 `Set-Cookie`。
- 记录 HTTP 诊断。
- 输出 `String(length=...)` 日志摘要。
- `getBytes` 使用 `imageProbe` context 并输出 `Bytes(length=...)`。
- 失败时保留 `statusCode`。

更新 `test/features/forum/data/forum_home_chrome_repository_test.dart` 覆盖：

- 仍只请求 `https://bbs.yamibo.com/index.php?mobile=2`。
- HTML 请求使用 mobile UA。
- 能解析轮播。
- 能通过新 client/gateway 链路探测首图比例。

按照 `AGENTS.md`，实现者不运行 `flutter test`、`flutter analyze`、`dart format`、`flutter pub get`，由用户运行并贴输出。

## 10. N-2 交接事项

N-2 应继续在保留 API 资产的前提下，把首页主数据源切到 `index.php?mobile=2` HTML：

- 首页 body 的轮播、收藏分区、普通分区、版块标题、描述和今日数优先来自 HTML。
- 首页初始渲染不再触发 `forumindex/profile/myfavforum`。
- HTML 请求失败时进入首页错误/重试状态，不静默 fallback 到 API 拼页面。
- `forumindex/profile/myfavforum` 能力仍保留，后续迁移进 `YamiboApiClient` / Dart 网络库。
