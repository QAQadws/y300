# Yamibo 论坛网络网关与原生 HTML 聚合分阶段实施方案

## 1. 背景与目标

当前论坛原生首页处在从 WebView/移动端 API 过渡到原生 UI 的中间态：页面 body 视觉希望尽量还原 `https://bbs.yamibo.com/index.php?mobile=2` 的移动端 HTML，但现有首页刷新仍会触发 `forumindex`、`profile`、`myfavforum` 三次移动端 API 请求；轮播和部分收藏版块信息才来自 HTML。与此同时，HTML 请求和轮播图片尺寸探测各自创建 `Dio`，没有进入现有 `ApiClient` 的日志、Cookie、诊断链路，因此用户在日志里能看到 API 请求，却不容易看到 HTML 请求。

本方案的目标是系统性解决这类问题，而不是只修某一个页面：

- 原生论坛首页改为 HTML-first：首页渲染优先且默认只依赖移动端首页 HTML，不再为了首页 body 默认请求 `forumindex/profile/myfavforum`。
- 所有 Yamibo/Discuz 相关的 API、HTML、资源探测、表单提交请求统一走一个网络网关。
- 公共会话数据统一管理：`formhash`、登录态、用户名、UID、Cookie 更新来自 API 或 HTML 都能被提取、缓存和复用。
- 日志统一、可读、可追踪：用户能明确看到“请求了什么、为什么请求、请求属于 API/HTML/resource 哪类、耗时和结果是什么”。
- 现有 API 能力全部保留：页面后续可以不再依赖某些 API 做初始渲染，但不得删除 API repository、provider、测试入口或 module 能力；这些都是未来 Dart 网络请求库完整性的一部分。
- 先内部库化，不一开始拆 package：优先在 Y300 内部稳定架构边界，后续再评估抽成独立 Dart package。

## 2. 当前问题定义

### 2.1 原生首页数据源不符合目标

当前 `DiscuzForumHomeRepository` 的聚合逻辑仍以移动端 API 为主：

- `forumindex`：拉论坛分类和版块主体。
- `profile`：刷新 session，判断登录态并获取 `formhash`。
- `myfavforum`：拉收藏版块。
- `index.php?mobile=2` HTML：只作为轮播和部分收藏描述补充。

这导致原生首页刷新后会出现多次 API 请求，而用户期望的是“移动端 HTML body 原生化”，也就是首页主体数据应优先来自移动端 HTML。

### 2.2 HTML 请求绕过统一基础设施

`ForumHomeChromeRepository` 和 `ForumHomeCarouselImageProbe` 自己管理 `Dio`、请求头、Cookie 保存和错误映射，没有复用统一日志与诊断记录。结果是：

- HTML 请求没有和 API 请求一样稳定出现在日志中。
- 请求头策略分散，容易再次出现桌面 UA 请求移动端页面的问题。
- Cookie 读写、错误摘要、耗时统计和诊断记录不一致。

### 2.3 `formhash/profile` 与页面渲染耦合

`profile` 请求目前常被用来刷新登录态和拿 `formhash`，但首页渲染本身不应该为了判断“是否展示收藏版块”而强制请求 `profile`。`formhash` 是论坛会话公共数据，应由会话仓库统一维护，而不是分散在首页、搜索、回复、收藏、登录登出等模块中各自触发。

### 2.4 直接 `Dio` 调用继续扩散

项目中除了 `ApiClient` 外，还存在若干直接 `Dio` 调用：搜索、回复表单准备、附件上传、发帖、收藏操作、漫画章节发现、首页 HTML chrome、图片探测等。若不建立统一网关，后续会持续出现：

- 日志不统一。
- Cookie/UA/Referer 策略不统一。
- `formhash` 重复拉取。
- API 与 HTML 错误处理不一致。
- 新原生页面继续复制临时网络代码。

### 2.5 API 资产保留约束

“原生首页 HTML-first”只表示首页初始渲染的数据来源要从移动端 API 聚合切换为移动端 HTML，并不表示废弃或删除现有 API。`forumindex`、`profile`、`myfavforum` 以及其它已经接入的 Discuz mobile API 都属于后续 Dart 网络请求库需要沉淀的资产。

因此后续阶段必须遵守：

- 可以让某个页面不再调用某个 API，但不能删除该 API 的 repository、provider、模型、测试或解析能力。
- 可以迁移 API 到 `YamiboApiClient` / `YamiboHttpGateway`，但迁移应保持现有 module 能力和业务语义。
- 页面数据源调整与 API 能力保留是两件事：N-2 调整首页数据源，N-4/N-5 才逐步把现有 API 和表单请求迁进统一网络库。
- 如果某个 API 暂时没有页面使用，也应保留为内部库能力，除非后续有明确文档和 review 决策证明它确实不可用或重复。

## 3. 设计原则

- **单一网络入口**：Yamibo 站点相关请求不得在新代码中直接 `Dio()` 后绕过网关。
- **分层清晰**：`core/network/yamibo` 只处理传输、Cookie、日志、诊断和公共会话数据；具体论坛首页、搜索、回复、收藏解析仍留在对应 feature。
- **HTML 与 API 并列一等公民**：API 不是唯一主数据源，HTML 页面也是稳定输入，需要拥有同等的日志、Cookie 和 session extraction 能力。
- **原生首页 HTML-first**：论坛首页原生模式以移动端 HTML 为准，避免“API 数据拼出的页面”和原站 HTML body 逐渐偏离。
- **API 资产不删除**：页面可以减少对 API 的运行时依赖，但已有 API 能力必须保留并迁移进统一网络库，服务后续 Dart package 完整性。
- **兼容迁移**：不一次性改完所有 repository；先建立网关，再用兼容适配层逐步迁移。
- **可观测优先**：每个阶段都要能从日志解释请求来源，避免用户看到“莫名其妙的请求”。
- **不把 core 变成业务垃圾桶**：core 不解析版块列表、不解析帖子正文、不决定页面 UI；业务 parser 仍属于 feature/data 或 domain。

## 4. 目标架构

```text
Feature Repository / Data Source
        |
        v
YamiboApiClient / YamiboHtmlClient / YamiboResourceClient
        |
        v
YamiboHttpGateway
        |
        v
Shared Dio + Interceptors
        |
        +-- Cookie attach/save
        +-- Request logging
        +-- Network diagnostics
        +-- Session/public data extraction
        +-- API version injection
        +-- Mobile/browser header policy
```

建议内部目录：

```text
lib/core/network/yamibo/
  yamibo_http_gateway.dart
  yamibo_api_client.dart
  yamibo_html_client.dart
  yamibo_resource_client.dart
  yamibo_request_context.dart
  yamibo_request_logger.dart
  yamibo_session_snapshot.dart
  yamibo_session_store.dart
  yamibo_session_extractor.dart
  yamibo_network_error_mapper.dart
```

## 5. 核心接口方向

### 5.1 请求上下文

`YamiboRequestContext` 用于让日志、诊断和调用方都能知道请求意图。

```dart
enum YamiboRequestKind {
  api,
  html,
  resource,
  imageProbe,
}

class YamiboRequestContext {
  const YamiboRequestContext({
    required this.kind,
    required this.operation,
    this.module,
    this.pageKind,
    this.silent = false,
  });

  final YamiboRequestKind kind;
  final String operation;
  final String? module;
  final String? pageKind;
  final bool silent;
}
```

约定：

- `kind=api`：Discuz mobile API，例如 `module=forumindex`。
- `kind=html`：论坛 HTML 页面，例如 `index.php?mobile=2`、搜索结果页、回复表单页。
- `kind=resource`：附件、上传、一般资源。
- `kind=imageProbe`：只用于尺寸探测或轻量图片信息读取，不代表正常图片缓存加载。
- `operation` 使用稳定点分命名，例如 `forum.home.html`、`forum.home.carouselProbe`、`auth.profile`、`reply.prepareForm`。

### 5.2 HTTP 网关

`YamiboHttpGateway` 是唯一底层传输入口。

```dart
abstract class YamiboHttpGateway {
  Future<YamiboHttpResponse<String>> getText(
    Uri uri, {
    required YamiboRequestContext context,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  });

  Future<YamiboHttpResponse<dynamic>> getJson(
    Uri uri, {
    required YamiboRequestContext context,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  });

  Future<YamiboHttpResponse<dynamic>> postForm(
    Uri uri, {
    required YamiboRequestContext context,
    required Map<String, String> data,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  });

  Future<YamiboHttpResponse<List<int>>> getBytes(
    Uri uri, {
    required YamiboRequestContext context,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  });
}
```

`YamiboHttpGateway` 负责：

- 根据 URI 自动附加 Cookie。
- 从 `Set-Cookie` 保存 Cookie。
- 设置统一超时、重定向策略和响应类型。
- 调用统一日志。
- 记录 `NetworkDiagnosticRecorder`。
- 将 API/HTML 响应交给 `YamiboSessionExtractor` 尝试刷新公共 session snapshot。
- 保护隐私，不在日志中打印 Cookie、密码、完整表单正文。

### 5.3 API 客户端

`YamiboApiClient` 封装 Discuz mobile API。

```dart
abstract class YamiboApiClient {
  Future<ApiResult<DiscuzResponse>> getDiscuz({
    required String module,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool treatMessageAsBusinessError = true,
  });

  Future<ApiResult<DiscuzResponse>> postDiscuzForm({
    required String module,
    required Map<String, String> data,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  });
}
```

迁移原则：

- 先让现有 `ApiClient` 内部改走 `YamiboApiClient`，保持旧方法签名，避免一次性重写所有 repository。
- 默认 API version 仍来自 `AppConfig.defaultApiVersion`。
- 已有明确要求的版本不能被改坏，尤其小说解析相关请求要继续使用 `version=1`。

### 5.4 HTML 客户端

`YamiboHtmlClient` 封装论坛 HTML 页面请求。

```dart
abstract class YamiboHtmlClient {
  Future<ApiResult<String>> getMobilePage({
    required String path,
    Map<String, String> queryParameters = const <String, String>{},
    required YamiboRequestContext context,
    Uri? referer,
    CancelToken? cancelToken,
  });

  Uri resolveSiteUri(
    String rawUrl, {
    Uri? baseUri,
  });
}
```

约定：

- 移动端首页请求固定为 `https://bbs.yamibo.com/index.php?mobile=2`。
- HTML 请求使用移动端浏览器 UA。
- Referer 默认使用站点根地址，必要时由调用方覆盖。
- HTML client 不解析业务 DOM，只返回文本和统一错误。

### 5.5 资源客户端

`YamiboResourceClient` 负责图片尺寸探测、附件资源等轻量请求。

```dart
abstract class YamiboResourceClient {
  Future<ApiResult<List<int>>> getBytes({
    required Uri uri,
    required YamiboRequestContext context,
    Map<String, String>? headers,
    int? maxBytes,
    CancelToken? cancelToken,
  });
}
```

首页轮播首图尺寸探测应迁移到这里，日志中显示为 `imageProbe`，但不要让普通图片缓存加载全部进入业务日志刷屏。

### 5.6 公共会话数据

```dart
class YamiboSessionSnapshot {
  const YamiboSessionSnapshot({
    required this.isLoggedIn,
    required this.uid,
    required this.username,
    required this.formhash,
    required this.updatedAt,
    required this.source,
  });

  final bool isLoggedIn;
  final String uid;
  final String username;
  final String formhash;
  final DateTime updatedAt;
  final String source;
}
```

`YamiboSessionStore` 负责：

- 内存缓存当前 session snapshot。
- 必要时持久化 snapshot 的非敏感字段。
- 提供 `readCurrent()`、`saveExtracted()`、`clear()`、`readFreshFormhash()`。
- Cookie 仍由 `CookieStore` 维护，session store 不复制 Cookie。

`YamiboSessionExtractor` 负责：

- 从 API `Variables` 提取 `formhash`、`member_uid`、`member_username`、`auth` 等字段。
- 从 HTML hidden input、脚本变量、登录区域提取 `formhash` 和登录态线索。
- 新提取值为空时不覆盖已有有效 snapshot。
- 标记来源，例如 `api:profile`、`api:forumindex`、`html:forum.home`。

## 6. 请求生命周期

1. feature repository 调用 `YamiboApiClient`、`YamiboHtmlClient` 或 `YamiboResourceClient`。
2. client 构造 `Uri`、请求头和 `YamiboRequestContext`。
3. `YamiboHttpGateway` 附加 Cookie、执行请求、保存 `Set-Cookie`。
4. 网关记录耗时、状态码、响应摘要和诊断。
5. 网关把 API/HTML 响应交给 `YamiboSessionExtractor`。
6. `YamiboSessionStore` 根据提取结果更新 snapshot。
7. client 将响应映射为 `ApiResult<T>`。
8. feature parser 只解析业务模型，不处理 Cookie、日志、Dio 细节。

## 7. 日志规范

### 7.1 成功日志

```text
[YamiboHTTP][html][forum.home.html] GET https://bbs.yamibo.com/index.php?mobile=2 -> 200 183ms body=String(length=42851)
[YamiboHTTP][api][forumindex] GET https://bbs.yamibo.com/api/mobile/index.php?module=forumindex&version=4 -> 200 96ms body=Map(length=3, keys=[Version, Charset, Variables])
[YamiboHTTP][imageProbe][forum.home.carouselProbe] GET https://bbs.yamibo.com/data/attachment/block/xx.jpg -> 200 41ms body=Bytes(length=8192)
```

### 7.2 失败日志

```text
[YamiboHTTP][html][forum.home.html] GET https://bbs.yamibo.com/index.php?mobile=2 -> failed 502 518ms error=badResponse
```

### 7.3 日志级别

- `info`：请求完成摘要。
- `warning`：HTTP 失败、业务错误、解析失败、session 提取异常但主请求成功。
- `debug`：请求头摘要、响应截断文本、图片探测细节。
- `silent`：调用方可标记不输出普通 info，但诊断仍可记录。

隐私约束：

- 不打印完整 Cookie。
- 不打印密码。
- 不打印完整表单正文。
- 表单日志只输出字段名或脱敏摘要。

## 8. 分阶段实施

| 阶段 | 预计耗时 | 目标 |
| --- | ---: | --- |
| N-0 审计与约束固化 | 0.5 天 | 固化现有直接网络入口、公共数据来源和首页目标数据源 |
| N-1 统一网关雏形 | 1 天 | 建立 `YamiboHttpGateway`，让 HTML 请求也进入统一日志和 Cookie 管线 |
| N-2 首页 HTML-first 改造 | 1 到 1.5 天 | 原生论坛首页只请求一次移动端 HTML，API 不再参与首页渲染 |
| N-3 公共会话数据仓库 | 1 到 1.5 天 | `formhash/profile` 从页面渲染链路中解耦，API/HTML 都能刷新 session snapshot |
| N-4 现有 API 客户端迁移 | 1 到 2 天 | `ApiClient` 迁移为 `YamiboApiClient` 适配层，保持业务 repository 行为不变 |
| N-5 HTML/表单/搜索链路迁移 | 2 到 3 天 | 搜索、回复准备、发帖元数据、收藏操作逐步走统一网关 |
| N-6 日志与诊断完善 | 0.5 到 1 天 | 请求日志可读、可过滤、能解释“为什么发了这个请求” |
| N-7 内部库稳定与外部 package 预留 | 1 天 | 整理 public API、测试覆盖和 package 抽取边界 |

## 9. N-0 审计与约束固化

### 9.1 实施内容

- 建立当前网络入口清单，至少覆盖：
  - `ApiClient`
  - `ForumHomeChromeRepository`
  - `ForumHomeCarouselImageProbe`
  - `DiscuzSearchService`
  - `ReplyFormPreparationDataSource`
  - `ComposerAttachmentRemoteDataSource`
  - `DiscuzThreadFavoriteApiRepository`
  - `ComicEpisodeDiscoveryService`
- 记录每个入口的请求类型、是否读写 Cookie、是否输出日志、是否依赖 `formhash`。
- 明确原生首页 P0 数据原则：页面主体、轮播、收藏版块展示、分区标题、版块描述、今日数优先来自 `index.php?mobile=2` HTML。
- 明确首页 API 请求迁移目标：`forumindex/profile/myfavforum` 不参与原生首页初始渲染。

### 9.2 验收标准

- 能解释当前首页刷新每个请求为什么发生。
- 能列出 N-2 中应从首页路径移除的 API 请求。
- 新代码约束写清楚：不得新增绕过网关的 Yamibo 站点直接 `Dio` 请求。

## 10. N-1 统一网关雏形

### 10.1 实施内容

- 新增 `YamiboRequestContext`、`YamiboRequestKind`、`YamiboHttpGateway`、`YamiboRequestLogger`。
- 网关底层持有共享 `Dio`，统一连接超时、接收超时、重定向、responseType。
- 网关接入 `CookieStore`，自动读写 Cookie。
- 网关接入 `NetworkDiagnosticRecorder`，记录 method、uri、status、elapsed、success、error。
- 迁移 `ForumHomeChromeRepository` 到 `YamiboHtmlClient` 或直接经由 `YamiboHttpGateway.getText`。
- 迁移 `ForumHomeCarouselImageProbe` 到 `YamiboResourceClient` 或 `YamiboHttpGateway.getBytes`。
- 保持首页业务数据来源暂时不变，N-1 只解决“HTML 请求不可见、Cookie/日志不统一”。

### 10.2 验收标准

- 请求 `index.php?mobile=2` 时日志出现 `[YamiboHTTP][html][forum.home...]`。
- 轮播图片尺寸探测出现 `[YamiboHTTP][imageProbe][forum.home.carouselProbe]` 或等价诊断。
- 现有 `ForumHomeChromeParser` 行为不变。
- 不再为首页 chrome 单独创建未接入日志的 `Dio`。

## 11. N-2 首页 HTML-first 改造

### 11.1 实施内容

- 新增或扩展 `ForumHomeHtmlParser`，从移动端首页 HTML 解析：
  - 轮播图图片 URL、跳转 URL、可选宽高比。
  - 收藏版块区域。
  - 普通分区标题。
  - 版块 fid、标题、描述、今日数、跳转 URL。
  - 分区折叠初始状态所需的 DOM 信息。
- 新增 `ForumHomeHtmlRepository`，只负责加载 `index.php?mobile=2` 和调用 parser。
- 将 `ForumHomePayload` 或新增 payload 调整为 HTML 首页模型优先。
- 保留现有 `ForumHomeViewData` 映射层，避免 UI 大面积重写。
- 移除原生首页初始渲染路径中的 `forumindex/profile/myfavforum`。
- HTML 失败时首页失败并显示现有错误/重试，不静默回退到 API。

### 11.2 数据模型建议

```dart
class ForumHomeHtmlData {
  const ForumHomeHtmlData({
    required this.carouselItems,
    required this.sections,
    required this.sessionSnapshot,
  });

  final List<ForumHomeCarouselItem> carouselItems;
  final List<ForumHomeHtmlSection> sections;
  final YamiboSessionSnapshot? sessionSnapshot;
}

class ForumHomeHtmlSection {
  const ForumHomeHtmlSection({
    required this.title,
    required this.items,
    required this.isFavoriteSection,
  });

  final String title;
  final List<ForumHomeHtmlForumItem> items;
  final bool isFavoriteSection;
}
```

### 11.3 验收标准

- 原生首页刷新日志只出现一次 `index.php?mobile=2` HTML 请求。
- 必要时只额外出现轮播首图尺寸探测请求。
- 首页刷新不再触发 `module=forumindex`、`module=profile`、`module=myfavforum`。
- 首页收藏版块和普通版块内容来自 HTML，而不是 API 拼接。
- 点击版块仍能进入 `ForumDisplayPage(fid, title)`。

## 12. N-3 公共会话数据仓库

### 12.1 实施内容

- 新增 `YamiboSessionSnapshot`、`YamiboSessionStore`、`YamiboSessionExtractor`。
- 网关在 API/HTML 成功响应后调用 extractor，提取到有效 session 数据后写入 store。
- `FormhashProvider` 改为优先读取 store 中未过期 formhash。
- store 缺失或过期时，`FormhashProvider` 再走刷新策略，例如轻量 API 或 HTML 页面。
- `profile` 只作为 session 刷新策略之一，不再作为首页渲染依赖。

### 12.2 默认策略

- `formhash` 软过期时间：30 分钟。
- 空 `formhash` 不覆盖旧有效值。
- 提交类请求遇到 session/formhash 相关错误时，可由业务层触发强制刷新后重试一次。
- logout 后清空 `YamiboSessionStore` 和 `CookieStore`。

### 12.3 验收标准

- 首页 HTML 响应中若能提取 `formhash`，后续提交类请求可复用。
- 搜索、回复、收藏等不再为了每次动作重复打 `profile`。
- 未登录状态能稳定表达为 `isLoggedIn=false`，不导致首页额外请求。

## 13. N-4 现有 API 客户端迁移

### 13.1 实施内容

- 新增 `YamiboApiClient` 并封装 `getDiscuz`、`postDiscuzForm`。
- 将现有 `ApiClient` 改为兼容适配层，内部委托 `YamiboApiClient` 或共用 `YamiboHttpGateway`。
- 保持现有业务 repository 方法签名不变，降低迁移风险。
- API 响应成功后统一经过 session extraction。
- 保持现有错误映射语义：超时、未授权、业务错误、解析错误、服务端错误。

### 13.2 验收标准

- 现有 API 请求日志统一变为 `[YamiboHTTP][api][module]` 形式。
- repository 不需要一次性改构造参数。
- 小说相关 `version=1` 约束不被破坏。
- 登录、登出、收藏、帖子详情等现有 API 行为保持。

## 14. N-5 HTML/表单/搜索链路迁移

### 14.1 迁移优先级

1. 搜索：`DiscuzSearchService`，因为它依赖 HTML 表单、`formhash` 和结果页。
2. 回复准备：`ReplyFormPreparationDataSource`，因为它能从 HTML 拿到准备好的 formhash。
3. 发帖元数据和发帖提交。
4. 附件上传。
5. 帖子收藏和版块收藏。
6. 漫画章节发现等只读 HTML 抓取。

### 14.2 实施原则

- HTML 表单页通过 `YamiboHtmlClient` 拉取。
- 表单提交通过 `YamiboHttpGateway.postForm` 或 `YamiboApiClient.postDiscuzForm`。
- parser 只解析业务字段，不读 Cookie，不创建 Dio，不打印日志。
- 每迁移一个模块都补最小单测，不要求一次性全站迁移。

### 14.3 验收标准

- 迁移后的模块不再直接创建 Yamibo 站点相关 `Dio`。
- 搜索、回复、发帖、收藏请求在日志里能区分 `html/api/resource`。
- `formhash` 来源能被 session store 解释。

## 15. N-6 日志与诊断完善

### 15.1 实施内容

- 扩展 `NetworkDiagnosticRecorder` 数据结构，增加：
  - `kind`
  - `operation`
  - `module`
  - `pageKind`
  - `requestId`
- 为每个请求生成短 request id，方便用户贴日志时定位同一次请求。
- 支持按 `kind` 和 `operation` 过滤日志。
- 为 HTML 响应摘要提供安全截断：只输出长度、标题或关键 selector 命中数，不直接打印完整 HTML。

### 15.2 验收标准

- 用户能从日志看出首页刷新到底请求了几次、每次属于什么目的。
- 同步诊断或调试记录能区分 API 与 HTML。
- 日志不会泄露 Cookie、密码或完整表单内容。

## 16. N-7 内部库稳定与外部 package 预留

### 16.1 实施内容

- 整理 `lib/core/network/yamibo/` public export。
- 核心类型避免依赖 Flutter Widget。
- Riverpod provider 放在 `network_providers.dart` 或独立 provider 文件，不进入纯 core 类型。
- 明确哪些 API 可以未来抽 package，哪些仍属于 Y300 app。

### 16.2 抽包前条件

- API、HTML、资源探测都已稳定走网关。
- session store 与 extractor 已覆盖主要来源。
- 搜索、回复、发帖、收藏至少完成一轮迁移验证。
- 单测覆盖核心请求与解析策略。

### 16.3 外部 package 边界

未来 package 只包含：

- Yamibo/Discuz 请求基础设施。
- Cookie/session/formhash 管理。
- API/HTML 基础响应模型。
- 可复用 parser 工具。

未来 package 不包含：

- Y300 页面 UI。
- Riverpod 页面 controller。
- 书架/漫画/小说业务模型。
- Flutter theme 或 WebView UI 逻辑。

## 17. 测试计划

### 17.1 网关单测

- Cookie 自动附加与保存。
- API version 自动注入。
- HTML 请求使用移动端 UA。
- `YamiboRequestContext` 正确进入日志摘要。
- HTTP 成功、超时、非 2xx、解析失败映射正确。
- body summary 对 String、Map、Iterable、bytes 都能安全截断。

### 17.2 session 单测

- 从 API Variables 提取 `formhash`。
- 从 HTML hidden input 提取 `formhash`。
- 空值不覆盖旧有效 snapshot。
- 过期 snapshot 不再作为 fresh formhash 返回。
- logout 清空 session store。

### 17.3 首页单测

- 基于 `docs/html/论坛首页.html` 解析轮播、收藏分区、普通分区、描述、今日数、相对链接和 `&amp;`。
- HTML 成功时 repository 返回完整首页 view data。
- HTML 失败时首页失败，不 fallback 到 API。
- 首页路径 fake API loader 不被调用。
- 点击版块仍进入 `ForumDisplayPage`。

### 17.4 迁移回归

- `ApiClient` 兼容层迁移后，现有登录、登出、收藏、帖子详情测试语义不变。
- 搜索、回复、发帖、附件迁移后，保留原有业务断言。
- 按 `AGENTS.md`，实现者不运行 `flutter test`、`flutter analyze`、`dart format`、`flutter pub get`，由用户运行检查并贴输出。

## 18. 风险与回滚策略

- 首页 HTML 结构变更风险：parser 应有样本测试和缺字段降级；HTML 失败时明确失败，不静默混用 API，方便定位。
- session 提取误判风险：extractor 只在字段非空且来源可信时更新 snapshot；空值不覆盖。
- API 迁移风险：先保留 `ApiClient` 兼容层，避免业务 repository 大面积同时改动。
- 日志过多风险：普通图片加载不进入业务日志；只有业务请求和尺寸探测记录摘要。
- 抽包过早风险：先内部稳定，不在第一阶段引入 package 管理和跨仓维护成本。

## 19. Review Checklist

- 原生论坛首页刷新是否不再出现 `forumindex/profile/myfavforum`。
- HTML 请求是否稳定显示在统一日志中。
- 请求日志是否能看出 kind、operation、URL、status、elapsed。
- 新增网络代码是否没有直接 `Dio()` 绕过网关。
- `formhash` 是否由 session store 统一维护，而不是散落在页面 repository。
- API 默认 version 与小说 `version=1` 约束是否保持。
- parser 是否仍在 feature 层，不进入 core 网关。
- 文档和 `docs/开发文档.md` 是否同步记录架构变化。
