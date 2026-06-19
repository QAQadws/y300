# Yamibo 论坛帖子列表页 HTML-first 实施计划

## 范围

本阶段把原生模式的版块帖子列表页改为移动端 HTML-first：进入 `ForumDisplayPage(fid, title)` 时，请求 `forum.php?mod=forumdisplay&fid=...&page=...&mobile=2`，解析 `docs/html/某一个帖子列表页.html` 中体现的移动端 DOM，并在 Flutter body 中尽量复刻 `docs/html/theme-a0-screenshots/帖子列表页.png` 的列表视觉。

## 非目标

- 不删除 `ApiClient`、`YamiboApiClient`、`DiscuzForumDisplayRepository` 或 `forumdisplay` API 能力。
- 不改发帖 metadata 的 `module=forumdisplay` API 链路。
- 不实现 WebView 版页面替换。
- 不改页面 AppBar；本阶段只复刻 body 区域。
- 不把 feature 层 UI/controller/provider 纳入未来 package 边界。

## 资料依据

- `docs/html/某一个帖子列表页.html`
- `docs/html/theme-a0-screenshots/帖子列表页.png`
- 现有论坛首页 HTML-first 实现：`ForumHomeHtmlRepository`、`ForumHomeHtmlParser`。

## 数据层设计

新增 `ForumDisplayHtmlParser`，职责只解析移动端 HTML DOM，不发请求、不读 Cookie、不写日志。

解析内容包括：

- 版块头：fid、标题、图标、今日发帖数、主题数、排名。
- 操作链接：发帖、搜索本版、收藏本版。
- 筛选栏：全部/最新/热门/新帖/精华。
- 类型筛选：公告、長篇連載、短篇漫畫等横向分类。
- 顶部条目：公告和置顶帖。
- 普通帖子：tid、标题、作者、uid、头像、时间、摘要、分类、typeid、浏览数、回复数、锁定标签。
- 分页：当前页、下一页存在性、末页页码。

扩展现有 `ForumDisplayData` 与 `ForumThreadSummary`，为 HTML 字段提供可选属性和默认值，确保 API 解析路径继续可用。

新增 `ForumDisplayHtmlRepository`：

- 依赖 `YamiboHtmlClient`。
- 使用 `YamiboRequestContext(kind: html, operation: forum.display.html, pageKind: forum.display)`。
- 请求路径固定为 `/forum.php`，query 包含 `mod=forumdisplay`、`fid`、`page`、`mobile=2`。
- 将网络失败包装为“帖子列表 HTML 加载失败”，解析失败包装为“帖子列表 HTML 解析失败”。

保留 `DiscuzForumDisplayRepository`：

- 继续作为 `forumdisplay` API 资产。
- 后续可沉淀进 `YamiboApiClient` / 独立 Dart 网络库。

## UI 设计

`ForumDisplayPage` body 改为 HTML-first 视觉：

- 浅黄色页面背景。
- 版块信息头：图标、标题、今日/主题/排名、发帖按钮。
- 两层横向筛选栏：主筛选和类型筛选。
- 顶部公告/置顶区域：小标签 + 彩色标题。
- 普通帖子列表：头像、作者、时间、标题、摘要、浏览/回复 chip、右侧分类标签。
- 底部分页：上一页禁用、当前页、下一页/没有更多。

AppBar、搜索按钮和帖子详情跳转保持现有行为。

## 测试计划

- 新增 `forum_display_html_parser_test.dart`，覆盖给定 HTML 样本的版块头、筛选、公告/置顶、普通帖子和分页解析。
- 更新 `forum_display_page_test.dart`，确认 body 能渲染 HTML-first 字段、分页按钮仍触发加载更多、搜索按钮仍存在。
- 如有必要补充 repository 测试，确认请求 `forum.php?mod=forumdisplay&fid=...&page=...&mobile=2`。

## 验证

按 `AGENTS.md`，Flutter/Dart 系列命令需要在沙箱外执行。实现后用 `require_escalated` 运行必要验证：

- `flutter analyze`
- 与本次改动相关的 `flutter test` 子集

## 后续交接

- 如果后续要把帖子列表作为请求库的一等能力，应在库边界新增 `YamiboForumApi` 或 `DiscuzForumApi.getForumDisplayHtml/getForumDisplayApi`，App feature 层继续保留 Riverpod provider、页面状态和 UI。
- `forumdisplay` API 可以暂时不被页面调用，但不能删除；它仍是发帖 metadata、未来请求库和兼容路径的资产。

## 交互补完

依据 `docs/html/某一个帖子列表页.html` 的移动端行为，帖子列表不是静态列表：

- `#dhnav_li > ul` 的主筛选项可点击，点击后复用对应链接里的 `filter/orderby/digest/page` 等 query 重新加载当前版块。
- 类型横栏和帖子底部 `#tag` 可点击，点击后复用对应链接里的 `filter=typeid&typeid=...` 重新加载当前版块。
- 公告/置顶条目可点击；能解析 `tid` 的置顶条目进入原生帖子详情，公告链接保留为不可解析时的 no-op 降级。
- 底部分页是左右翻页，不再把下一页追加为无限滚动；上一页/下一页按对应页码替换当前列表。
- `第xx页` 可点击，弹出页码选择对话框；用户输入合法页码后按当前筛选 query 加载目标页。

实现上通过 `ForumDisplayQuery` 保存当前 `forumdisplay` 查询参数，repository 支持按 query 请求 HTML；controller 提供 `openFilter`、`openThreadTag`、`loadPreviousPage`、`loadNextPage`、`loadPageNumber`，页面只负责把 HTML parser 解析出的 URL 转交给 controller。
