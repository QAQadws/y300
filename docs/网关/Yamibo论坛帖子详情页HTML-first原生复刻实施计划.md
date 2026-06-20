# Yamibo 论坛帖子详情页 HTML-first 原生复刻实施计划

## 范围

本阶段把原生模式的帖子详情页改为“电脑端 HTML 解析、移动端原生呈现”：进入 `ThreadDetailPage(tid, subject)` 时，请求电脑端 `forum.php?mod=viewthread&tid=...&page=...`，解析 `docs/html/帖子详细页` 中的电脑端 DOM，并在 Flutter 页面中复刻移动端帖子详情的信息层级和主要功能。

## 非目标

- 不删除 `ApiThreadRepository`、`viewthread` API 能力、回复 API、收藏 API、漫画/小说入库链路。
- 不在本阶段实现“只看楼主”“倒序浏览”“评分/点评”的完整交互；先解析并展示主信息，后续再逐步接入动作。
- 不使用移动端 HTML 作为数据源；移动端 HTML 和截图只作为视觉与功能对照。
- 不把帖子详情做成 WebView。

## 资料依据

- `docs/html/帖子详细页/一个电脑端单选帖.html`
- `docs/html/帖子详细页/一个电脑端多选帖.html`
- `docs/html/帖子详细页/一个电脑端漫画帖子.html`
- `docs/html/帖子详细页/对应移动端单选帖.html`
- `docs/html/帖子详细页/对应的移动端多选帖.html`
- `docs/html/帖子详细页/对应的移动端漫画帖子.html`
- `docs/html/帖子详细页/*.png`
- 帖子列表 HTML-first 参考提交 `8b5140d2285cb91b91e41968001590e464d2f789`

## 数据层设计

新增 `ThreadDetailHtmlParser`，职责只做 DOM 解析：

- 主题信息：tid、fid、typeid、标题、作者、查看数、回复数、当前页、末页。
- 楼层列表：pid、楼层号、作者、uid、头像、发表时间、正文 HTML、回复链接。
- 投票信息：单选/多选、说明、截止提示、选项、票数、百分比、颜色、提交地址、formhash。
- 评分摘要：先保留为楼层可选摘要文本，完整评分明细交给后续阶段。

新增 `ThreadDetailHtmlRepository`：

- 依赖 `YamiboHtmlClient`。
- 请求电脑端 `/forum.php?mod=viewthread&tid=...&page=...`，不附加 `mobile=2`。
- 使用 `YamiboRequestContext(kind: html, operation: thread.detail.html, pageKind: thread.detail)`。
- 网络失败包装为“帖子详情 HTML 加载失败”，解析失败包装为“帖子详情 HTML 解析失败”。

保留 `ApiThreadRepository`：

- API 可以暂时不被帖子详情页面调用，但不能删除。
- 后续如果抽成 Dart 网络库，应把 HTML 与 API 两条能力都沉淀进 Yamibo/Discuz 网络边界。

## UI 设计

帖子详情页继续保留 AppBar 收藏、搜索本版、漫画/小说入库、回复提交能力，body 改为原生移动端风格：

- 浅米色背景，与论坛首页/帖子列表同源。
- 顶部主题卡展示分类、标题、查看/回复、当前页。
- 每楼以移动端样式呈现：左侧头像，右侧作者、楼层、时间、正文。
- 首楼后展示投票卡：单选/多选语义、说明、进度条、选项和提交按钮；本阶段提交按钮可先禁用或只展示，避免误提交未接入的投票动作。
- 漫画贴图片继续走 `ThreadPostHtml` 和现有图片 header/cache 管线，确保电脑端附件图片能以移动端阅读流展示。
- 底部保留回复输入栏和加载更多回复按钮。

## 测试计划

- 新增 `thread_detail_html_parser_test.dart`：
  - 覆盖单选投票帖标题、fid/typeid、查看/回复数、楼层、头像、正文、投票选项解析。
  - 覆盖多选投票帖选项百分比/票数/颜色解析。
  - 覆盖漫画帖附件图片从电脑端正文中保留为可渲染 HTML。
- 更新 `thread_detail_page_test.dart`：
  - 验证原生详情页渲染主题头、楼层头像/作者/楼层/正文。
  - 验证投票卡可构建并显示单选/多选信息。
  - 保留加载更多、收藏、回复、漫画/小说入库测试语义。
- 更新 `thread_post_html_test.dart` 如有必要，确保 `file/zoomfile/data-original` 图片属性仍可通过共享图片管线正常渲染。

## 验证

按 `AGENTS.md`，Flutter/Dart 系列命令需要用 `require_escalated` 在沙箱外执行：

- `dart format` 相关 Dart 文件。
- `flutter analyze`。
- `flutter test test/features/thread/data/thread_detail_html_parser_test.dart test/features/thread/presentation/thread_detail_page_test.dart test/features/thread/presentation/widgets/thread_post_html_test.dart`。

## 后续交接

- 接入投票提交动作，并把投票提交纳入 formhash/session 统一维护。
- 接入只看楼主、倒序浏览、评分、点评、楼层回复准备等移动端功能。
- 按帖子列表同样方式补强视觉微交互和分页跳转。
