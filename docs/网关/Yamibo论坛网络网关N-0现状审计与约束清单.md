# Yamibo 论坛网络网关 N-0 现状审计与约束清单

## 1. 目的与边界

N-0 是 `Yamibo论坛网络网关与原生HTML聚合分阶段实施方案.md` 的第一步，只做现状审计和后续约束固化。

本阶段做：

- 固化当前论坛相关网络入口清单。
- 解释原生论坛首页刷新时为什么会出现 `forumindex/profile/myfavforum` 三次 API 请求。
- 标注哪些入口直接创建 `Dio`，哪些入口已经走 `ApiClient`。
- 标注每个入口是否读写 Cookie、是否统一日志、是否依赖 `formhash`。
- 明确 N-1 与 N-2 的交接边界，避免后续实现时把阶段目标混在一起。

本阶段不做：

- 不新增 `lib/core/network/yamibo/`。
- 不实现 `YamiboHttpGateway`。
- 不修改 `ForumHomeRepository`。
- 不删除首页当前 API 请求。
- 不删除任何现有 API repository、provider、模型、测试或 module 能力。
- 不改变 `ApiClient`、provider、parser 或页面行为。
- 不运行 `flutter test`、`flutter analyze`、`dart format`、`flutter pub get`。

## 2. 当前首页刷新链路

当前原生论坛首页刷新链路如下：

```text
ForumHomeController.build / refresh
        |
        v
ForumHomeRepository.getForumHomePayload
        |
        +-- ForumRepository.getForumIndex
        |      -> ApiClient.getParsed(module: forumindex)
        |
        +-- AuthRepository.refreshSession
        |      -> SessionVerifier.refreshSession
        |      -> ApiClient.getParsed(module: profile)
        |
        +-- FavoriteRepository.getFavoriteForums
        |      -> ApiClient.getParsed(module: myfavforum)
        |      -> 仅在 profile 判断已登录后调用
        |
        +-- ForumHomeChromeRepository.loadChrome
               -> Dio GET https://bbs.yamibo.com/index.php?mobile=2
               -> 解析轮播与首页 HTML 中的收藏版块补充信息
               -> ForumHomeCarouselImageProbe 可能额外探测首张轮播图尺寸
```

用户日志里出现三次 API 请求的原因是当前 `DiscuzForumHomeRepository` 仍以 API 聚合为首页主数据：

- `forumindex`：当前首页主体数据来源，负责分类和普通版块列表。
- `profile`：用于刷新 session 并判断登录态。
- `myfavforum`：登录态为 true 时拉取收藏版块。
- `index.php?mobile=2`：当前只作为 chrome 补充来源，用于轮播图和收藏版块描述兜底，不是首页主体数据。

这和后续目标存在方向差异：原生首页希望尽量还原移动端 HTML body，因此 N-2 后首页初始渲染应以 `index.php?mobile=2` HTML 为主数据源，而不是 API 聚合。

## 3. 当前首页请求解释表

| 请求 | 当前触发入口 | 当前用途 | 是否应保留到 N-2 后首页初始渲染 | 说明 |
| --- | --- | --- | --- | --- |
| `module=forumindex` | `ForumRepository.getForumIndex` | 首页普通分区和版块主数据 | 否 | N-2 后首页主数据改为 HTML 解析；API 可保留给其它页面或兼容路径 |
| `module=profile` | `AuthRepository.refreshSession` | 首页判断登录态 | 否 | 登录态和 `formhash` 后续应由统一 session store 维护，不应绑定首页渲染 |
| `module=myfavforum` | `FavoriteRepository.getFavoriteForums` | 首页收藏版块 | 否 | N-2 后首页收藏分区来自 HTML；收藏管理动作另行保留 API |
| `GET /index.php?mobile=2` | `ForumHomeChromeRepository.loadChrome` | 轮播与收藏描述补充 | 是 | N-2 后升级为首页主数据源 |
| 轮播首图 bytes 请求 | `ForumHomeCarouselImageProbe.resolveAspectRatio` | 获取真实图片比例 | 可选 | N-1 先纳入统一日志；N-2 可继续保留或由 HTML/缓存策略替代 |

## 4. 网络入口总表

| 入口 | 文件 | 请求类型 | 直接 `Dio` | Cookie 读写 | 统一日志/诊断 | `formhash` 依赖 | 后续阶段 | 当前风险 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `ApiClient` | `lib/core/network/api_client.dart` | Discuz mobile API GET/POST | 是，作为现有统一 API 入口 | 是 | 有基础 `[HTTP]` 日志和诊断 | 间接承载 | N-4 | 只覆盖 API，不覆盖 HTML/resource；日志缺少 kind/operation |
| `ForumHomeChromeRepository` | `lib/features/forum/data/forum_home_chrome_repository.dart` | 首页 HTML | 是 | 是 | 否 | 否 | N-1 | HTML 请求不在统一日志中，无法解释给用户看 |
| `ForumHomeCarouselImageProbe` | `lib/features/forum/data/forum_home_carousel_image_probe.dart` | 图片 bytes 探测 | 是 | 由调用方传 headers | 否 | 否 | N-1 | 请求不可见，异常被吞掉，只返回 null |
| `DiscuzSearchService` | `lib/features/search/data/discuz_search_service.dart` | HTML 表单 POST + 搜索结果 HTML GET | 是 | 是 | 否 | 是 | N-5 | 有局部 formhash 缓存，但仍首次依赖 `ProfileRepository.getProfile()` |
| `ReplyFormPreparationDataSource` | `lib/features/reply/data/reply_form_preparation_data_source.dart` | 回复表单 HTML GET | 是 | 是 | 否 | 从 HTML 解析 prepared formhash | N-5 | 表单页请求不可观测，无法进入统一 session extraction |
| `DiscuzReplyRemoteDataSource` | `lib/features/reply/data/discuz_reply_remote_data_source.dart` | 回复提交 API POST | 是 | 是 | 否 | 是 | N-5 | 提交类请求绕过 `ApiClient` 日志和统一错误映射 |
| `ComposerAttachmentRemoteDataSource` | `lib/features/composer_shared/data/composer_attachment_remote_data_source.dart` | 附件权限 API + 上传 | 是 | 是 | 否 | 响应含 formhash | N-5 | 上传和权限请求无法统一诊断 |
| `DiscuzThreadFavoriteApiRepository` | `lib/features/thread/data/discuz_thread_favorite_api_repository.dart` | 帖子收藏/取消收藏 API POST | 是 | 是 | 否 | 是 | N-5 | 每次操作通过 profile 取 formhash，且日志不统一 |
| `NewThreadRemoteDataSource` | `lib/features/posting/data/new_thread_remote_data_source.dart` | 发帖提交 API POST | 是 | 是 | 否 | 是 | N-5 | 提交类请求绕过统一 API 入口 |
| `ComicEpisodeDiscoveryService.DioCatalogHtmlFetcher` | `lib/features/comic/domain/services/comic_episode_discovery_service.dart` | catalog HTML GET | 是 | 否 | 否 | 否 | N-5 | domain 层直接抓 HTML，无 Cookie/日志/诊断 |

## 5. 直接 `Dio` 清单

当前 `lib` 中直接 `Dio(` 创建点共 10 个。

### 5.1 可作为兼容入口保留并在 N-4 内部迁移

| 入口 | 当前职责 | N-0 结论 |
| --- | --- | --- |
| `ApiClient` | 现有移动端 API 统一入口，注入 API version、读写 Cookie、输出基础日志 | N-4 之前继续保留；后续改为 `YamiboApiClient` 兼容外壳或委托网关 |

### 5.2 N-1 优先收口

| 入口 | 当前职责 | N-1 要求 |
| --- | --- | --- |
| `ForumHomeChromeRepository` | 请求 `index.php?mobile=2` 并解析轮播/收藏描述 | 改走 `YamiboHtmlClient` 或 `YamiboHttpGateway.getText`，日志必须显示 `[YamiboHTTP][html][forum.home...]` |
| `ForumHomeCarouselImageProbe` | 下载轮播首图 bytes 并解析宽高比 | 改走 `YamiboResourceClient` 或 `YamiboHttpGateway.getBytes`，日志或诊断必须标记 `imageProbe` |

### 5.3 N-5 逐步收口

| 入口 | 当前职责 | N-5 迁移方向 |
| --- | --- | --- |
| `DiscuzSearchService` | 提交搜索表单、跟随搜索结果页、解析 HTML | HTML POST/GET 走网关；formhash 改从 session store 读取；保留搜索调度器与限流器 |
| `ReplyFormPreparationDataSource` | 拉回复表单 HTML 并解析 prepared formhash | HTML GET 走网关；解析结果写入或刷新 session snapshot |
| `DiscuzReplyRemoteDataSource` | 提交回复 | 表单 POST 走网关或 API client；日志脱敏表单正文 |
| `ComposerAttachmentRemoteDataSource` | 检查上传权限、上传图片 | 权限 API 和上传 resource 走网关；上传日志只输出字段摘要 |
| `DiscuzThreadFavoriteApiRepository` | 帖子收藏和取消收藏 | formhash 由 session store 提供；POST 走统一 API/form 网关 |
| `NewThreadRemoteDataSource` | 发帖提交 | POST 走统一 API/form 网关；保留 payload 到 form 的映射类 |
| `DioCatalogHtmlFetcher` | 漫画 catalog HTML 抓取 | HTML GET 走网关；domain 服务不再直接持有 Dio |

## 6. ApiClient 消费清单

当前 `ApiClient` 是移动端 API 的事实统一入口，消费者如下。

| 模块 | 入口 | API module | 用途 | 后续迁移 |
| --- | --- | --- | --- | --- |
| `profile` | `ProfileRepository.getProfile` | `profile` | 获取 UID、用户名、formhash | N-3/N-4：作为 session 刷新来源之一，不再被首页渲染强绑定 |
| `auth` | `SessionVerifier.verifyAuthByForumIndex` | `forumindex` | 校验 cookie auth 是否生效 | N-4：保留语义，内部走网关 |
| `auth` | `SessionVerifier.refreshSession` | `profile` | 刷新 session | N-3：接入 session store |
| `auth` | `ApiFormhashProvider.loadFormhash` | `forumindex/profile` | 获取 formhash | N-3：优先读 session store，缺失再刷新 |
| `auth` | `DiscuzMobileAuthApi.login/logout` | `login/logout` | 登录登出 | N-4：保持现有签名，内部走网关 |
| `favorites` | `FavoriteRepository.getFavoriteForums` | `myfavforum` | 收藏版块列表 | N-2：首页不再依赖；收藏功能保留 |
| `favorites` | `FavoriteRepository.getFavoriteThreads` | `myfavthread` | 线程收藏页 | N-4：内部走网关 |
| `thread` | `ThreadRepository.getThreadDetail` | `viewthread` | 帖子详情 API 数据 | N-4：内部走网关 |
| `forum` | `ForumRepository.getForumIndex` | `forumindex` | 当前首页普通版块主数据 | N-2：首页移除依赖；其它用途保留 |
| `forum_display` | `ForumDisplayRepository.getForumDisplay` | `forumdisplay` | 版块帖子列表 | N-4：内部走网关 |
| `forum_favorite` | `ForumFavoriteRepository.favoriteForum/unfavoriteForum` | `favforum/favthread` | 版块收藏动作 | N-3/N-4：formhash 统一化，API 走网关 |
| `posting` | `PostingFormMetadataRepository` | `forumdisplay` | 发帖元数据、threadtypes、formhash | N-4：内部走网关，注意版本策略 |
| `novel` | `NovelThreadGateway` | `viewthread` | 小说线程详情 | N-4：保持小说相关 `version=1` 约束 |

## 7. 公共数据来源清单

| 数据 | 当前来源 | 当前使用点 | 当前问题 | 目标方向 |
| --- | --- | --- | --- | --- |
| Cookie | `CookieStore`，由 `ApiClient` 和部分自建 Dio 拦截器各自读写 | API、HTML、表单、上传 | 写法重复，部分入口没有诊断，策略不统一 | N-1 起由 `YamiboHttpGateway` 统一附加和保存 |
| `formhash` | `forumindex/profile` API、回复表单 HTML、上传权限响应等 | 登录、登出、搜索、回复、发帖、收藏 | 来源分散，多处先拉 `profile`，没有统一有效期和覆盖规则 | N-3 建立 `YamiboSessionStore` 与 extractor |
| UID | `profile`、部分 API Variables、上传权限响应 | profile、上传权限、会话判断 | 不统一维护 | N-3 作为 session snapshot 字段 |
| 用户名 | `profile`、部分 API Variables | profile、上传权限、会话判断 | 不统一维护 | N-3 作为 session snapshot 字段 |
| `auth/isLoggedIn` | `forumindex.auth`、`profile.member_uid` | 登录校验、首页是否加载收藏版块 | 首页渲染依赖 `profile`，导致额外请求 | N-3 由 session store 表达；首页不为判断登录态额外请求 |
| 首页版块数据 | `forumindex` API | 当前原生首页普通分区 | 与 HTML-first 目标不一致 | N-2 改为 `index.php?mobile=2` HTML |
| 首页收藏版块 | `myfavforum` API + HTML 兜底描述 | 当前原生首页收藏分区 | 登录时额外 API 请求；HTML 已含展示信息 | N-2 改为 HTML 分区 |
| 首页轮播 | `index.php?mobile=2` HTML | 当前原生首页轮播 | 请求不可统一观测 | N-1 纳入网关，N-2 继续作为首页主数据的一部分 |

## 8. 首页 HTML-first 约束

N-2 完成后，原生论坛首页初始渲染必须满足：

- 主请求为 `GET https://bbs.yamibo.com/index.php?mobile=2`。
- 首页 body 的轮播、收藏分区、普通分区、版块标题、版块描述、今日数优先来自 HTML。
- 初始渲染不得为了首页主体触发：
  - `module=forumindex`
  - `module=profile`
  - `module=myfavforum`
- HTML 请求失败时应明确进入首页错误/重试状态，不静默 fallback 到 API 拼页面。
- 轮播首图尺寸探测可以保留，但必须通过网关或诊断可观测。
- 版块点击、轮播点击等后续交互可以继续调用对应功能 repository，不属于首页初始渲染约束。
- `forumindex/profile/myfavforum` 不参与首页初始渲染，并不代表删除这些 API；它们必须继续作为可迁移 API 资产保留。
- 任何 API 若暂时没有页面调用，也应保留到后续 `YamiboApiClient` / Dart 网络库迁移阶段，不得因为页面不使用就顺手删除。

## 9. API 资产保留约束

Yamibo 网络网关的最终目标之一是沉淀可复用 Dart 请求库。因此现有 API 是资产，不是临时页面实现细节。后续阶段必须区分“页面不调用”和“能力不存在”。

| 约束项 | 规则 | 原因 |
| --- | --- | --- |
| API repository | 可以迁移实现，不得直接删除 | 后续 Dart 网络库需要完整覆盖现有移动端 API 能力 |
| provider | 可以调整依赖注入，不得无替代移除 | 保持业务模块可测试、可渐进迁移 |
| model/parser | 可以重构命名或位置，不得丢失字段语义 | 避免后续恢复 API 时重新逆向 |
| tests | 可以随迁移更新，不得删除覆盖面 | 保护 API 行为兼容性 |
| 页面调用 | 可以改为 HTML-first 或其它数据源 | 页面数据源选择不等于 API 能力废弃 |

必须保留的当前 API 能力至少包括：

- `forumindex`：论坛首页/分类/登录 auth 校验相关能力。
- `profile`：UID、用户名、`formhash`、登录态来源。
- `myfavforum`：收藏版块列表。
- `myfavthread`：收藏帖子列表。
- `forumdisplay`：版块帖子列表与发帖元数据来源。
- `viewthread`：帖子详情。
- `favforum/favthread`：版块与帖子收藏变更。
- `login/logout`：登录登出。
- `newthread/sendreply/forumupload/checkpost`：发帖、回复、附件上传相关能力。

## 10. N-1 交接清单

N-1 的目标是统一网关雏形和日志收口，不改变首页数据源。

N-1 应做：

- 新增 `YamiboRequestKind`、`YamiboRequestContext`、`YamiboHttpGateway`、`YamiboRequestLogger` 的最小实现。
- 接入 `CookieStore`，自动读写 Cookie。
- 接入 `NetworkDiagnosticRecorder`，记录 HTML 和 imageProbe 请求。
- 迁移 `ForumHomeChromeRepository`，让 `index.php?mobile=2` 请求显示统一日志。
- 迁移 `ForumHomeCarouselImageProbe`，让轮播图片尺寸探测可见。

N-1 不应做：

- 不移除 `forumindex/profile/myfavforum`。
- 不删除或弱化任何现有 API 能力；N-1 只新增 HTML/imageProbe 网关路径。
- 不改 `ForumHomePayload` 主数据结构。
- 不实现 session store。
- 不迁移搜索、回复、发帖、收藏等其它直接 `Dio` 入口。

## 11. N-2 交接清单

N-2 的目标是首页 HTML-first。

N-2 应做：

- 新增或扩展首页 HTML parser，覆盖轮播、收藏分区、普通分区、版块 fid、标题、描述、今日数和链接。
- 新增 HTML-first repository 或调整当前 `ForumHomeRepository` 的数据源组合。
- 保留现有 `ForumHomeViewData` 映射层，避免 UI 大面积重写。
- 移除首页初始渲染路径中的 `forumindex/profile/myfavforum`。
- 保留 `forumindex/profile/myfavforum` 的 API 能力和测试，只是不再服务首页初始渲染。
- 更新首页 repository 测试，断言 fake API loader 不被调用。

N-2 不应做：

- 不迁移全站 API client。
- 不实现完整 session store。
- 不改 WebView 模式。
- 不把搜索/回复/收藏迁移混进首页改造。
- 不删除任何“暂时不被首页调用”的 API。

## 12. 后续迁移优先级

| 优先级 | 阶段 | 入口 | 原因 |
| --- | --- | --- | --- |
| P0 | N-1 | `ForumHomeChromeRepository`、`ForumHomeCarouselImageProbe` | 直接解决用户当前看不到 HTML 请求日志的问题 |
| P0 | N-2 | `ForumHomeRepository` 首页数据源 | 直接解决首页刷新 API 请求过多且不符合 HTML-first 的问题 |
| P1 | N-3 | `FormhashProvider`、`ProfileRepository` 使用方 | 解决 `profile` 被多处当公共数据仓库的问题 |
| P1 | N-4 | `ApiClient` 消费链路 | 统一 API 日志和 session extraction |
| P2 | N-5 | 搜索、回复、发帖、收藏、附件、漫画 catalog HTML | 逐步消除直接 `Dio` 扩散 |

## 13. Review Checklist

- N-0 是否只改文档，没有改 Dart 代码。
- 直接 `Dio(` 清单是否覆盖当前 `lib` 中 10 个创建点。
- 首页链路是否能解释用户日志中的 `forumindex/profile/myfavforum`。
- 文档是否明确 HTML 请求不可见的原因是 `ForumHomeChromeRepository` 自建 `Dio`。
- 文档是否明确图片探测不可见的原因是 `ForumHomeCarouselImageProbe` 自建 `Dio` 且吞异常。
- 文档是否明确搜索当前有局部 formhash 缓存，但首次仍依赖 `ProfileRepository.getProfile()`。
- 文档是否明确 N-1 不移除首页 API 请求，N-2 才做首页 HTML-first。
- 文档是否明确 N-2 后首页初始渲染不得触发 `forumindex/profile/myfavforum`。
- 文档是否明确“页面不调用 API”不等于“删除 API”，现有 API 要为后续 Dart 网络库完整保留。
- `docs/开发文档.md` 顶部是否追加 N-0 记录。
