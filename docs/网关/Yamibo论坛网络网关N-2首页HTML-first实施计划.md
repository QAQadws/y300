# Yamibo 论坛网络网关 N-2 首页 HTML-first 实施计划

## 范围

N-2 只调整原生论坛首页的初始渲染数据源：页面主体、轮播、收藏版块和普通版块均来自 `https://bbs.yamibo.com/index.php?mobile=2` 的移动端 HTML。首页刷新路径不再调用 `forumindex`、`profile`、`myfavforum` 三个移动端 API。

本阶段继续保留 `ApiClient`、`ForumRepository`、`FavoriteRepository`、`ProfileRepository`、`forumindex/profile/myfavforum` 相关模型、provider 和测试。页面不再依赖这些 API，不等于删除 API 资产；后续阶段会把它们迁入 `YamiboApiClient` / Dart 网络库。

## 非目标

- 不迁移 `ApiClient` 内部实现，N-4 再处理 API 客户端统一网关化。
- 不引入公共 session store，N-3 再处理 `formhash/profile` 解耦。
- 不迁移搜索、回复、发帖、收藏操作等 HTML/form 请求，N-5 再处理。
- 不重写论坛首页 UI，只复用现有 `ForumHomeViewData`、`ForumSection` 和版块点击导航。

## 设计

### 数据模型

新增 `ForumHomeHtmlData`、`ForumHomeHtmlSection`、`ForumHomeHtmlForumItem`：

- `ForumHomeHtmlData` 聚合轮播和分区。
- `ForumHomeHtmlSection` 记录分区标题、是否收藏分区、初始折叠状态和版块列表。
- `ForumHomeHtmlForumItem` 记录 fid、标题、描述、今日数、跳转链接和图标链接。

模型位于 `lib/features/forum/data/models/forum_home_html_models.dart`，仍属于论坛 feature 数据层，不进入 core 网关。

### Parser

新增 `ForumHomeHtmlParser`，基于移动端首页 DOM 解析：

- `.index-top-wrapper .yami-swiper .swiper-slide` 中的轮播图片和跳转链接。
- `.forumlist` 内每个 `.subforumshow` 与其指向的 `.sub-forum`。
- 收藏分区识别 `#sub-forum-myfav`。
- 普通分区标题来自 `.subforumshow h2`。
- 版块项来自 `a.murl`，解析 fid、标题、描述、今日数和链接。
- 相对 URL、根路径 URL、协议相对 URL 统一通过 `SiteUrlResolver` 解析。

保留 `ForumHomeChromeParser` 给 N-1 chrome 仓库和既有测试使用；N-2 首页新路径使用 `ForumHomeHtmlParser`，避免把旧 chrome parser 扩成含义不清的多职责类。

### Repository

新增 `ForumHomeHtmlRepository` 实现 `ForumHomeRepository`：

- 通过 `YamiboHtmlClient.getMobilePage(path: '/index.php', queryParameters: {'mobile': '2'})` 只请求一次移动端首页 HTML。
- 使用 `YamiboRequestContext(kind: html, operation: forum.home.html, pageKind: forum.home)`，让日志明确区别于 N-1 的 chrome 兼容仓库。
- HTML 加载或解析失败时直接返回失败，不静默 fallback 到 API。
- 解析成功后只对轮播首图执行 `ForumHomeCarouselImageProbe` 宽高比探测。
- 将 HTML sections 映射为现有 `ForumIndexData`、`FavoriteForum`、`ForumHomeChromeData`，从而复用现有 controller 和 UI 映射，降低改动面。

Provider `forumHomeRepositoryProvider` 切换到 `ForumHomeHtmlRepository`。旧 `DiscuzForumHomeRepository` 继续保留为 API 聚合资产和测试对象。

## 测试计划

- 新增 `forum_home_html_parser_test.dart`：
  - 使用内联 HTML 覆盖收藏分区、普通分区、fid、标题、描述、今日数、链接解析。
  - 使用 `docs/html/论坛首页.html` 样本覆盖真实移动端首页结构。
- 更新 `forum_home_repository_test.dart`：
  - 保留 `DiscuzForumHomeRepository` 既有 API 聚合语义测试。
  - 新增 `ForumHomeHtmlRepository` 测试，断言只请求 `index.php?mobile=2`，解析轮播和分区，探测首图比例。
  - 新增失败测试，断言 HTML 失败直接返回错误。
  - 用会抛错的旧 API loader 证明 HTML-first repository 不调用 `forumindex/profile/myfavforum`。
- 保留页面测试现有语义；controller 继续消费 `ForumHomePayload`。

## 验收点

- 原生首页初始刷新只出现 `[YamiboHTTP][html][forum.home.html]` 对 `index.php?mobile=2` 的请求。
- 轮播首图尺寸探测仍可能出现 `[YamiboHTTP][imageProbe][forum.home.carouselProbe]`。
- 首页刷新不再调用 `forumindex`、`profile`、`myfavforum`。
- 收藏版块和普通版块内容均来自移动端 HTML。
- 版块点击仍使用 fid/title 进入 `ForumDisplayPage`。
- API 资产完整保留，后续迁移进 `YamiboApiClient` / Dart 网络库。
