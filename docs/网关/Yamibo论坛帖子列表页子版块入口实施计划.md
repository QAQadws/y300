# Yamibo 论坛帖子列表页子版块入口实施计划

## 范围

本次补齐移动端 `forumdisplay` HTML 中的子版块入口：当页面存在 `#forum > div.forumlist.cl` 时，原生帖子列表页在筛选栏之后、公告/置顶列表之前展示子版块入口，点击后进入对应子版块的 `ForumDisplayPage`。

## 非目标

- 不改 `forumdisplay` API 资产，不删除旧 repository。
- 不把子版块作为首页论坛树数据处理；它是当前帖子列表页的 HTML chrome。
- 不引入 WebView 或外部浏览器跳转。
- 不改变已有筛选、分页、帖子详情、发帖入口行为。

## 实现设计

- 新增 `ForumDisplaySubForum` 模型，保存 `fid`、`title`、`url`、`iconUrl`。
- `ForumDisplayHtmlParser` 只解析 `#forum > div.forumlist.cl` 中的 `a.murl[href*="forumdisplay"]`，从链接中提取 `fid`，从 `.mtit`/图片 `alt` 读取标题，并通过 `SiteUrlResolver` 归一化链接和图标。
- `ForumDisplayData` 与 `ForumDisplayPageState` 增加 `subForums`，API 路径默认空列表，保持兼容。
- `ForumDisplayPage` 在类型筛选下方渲染子版块条；点击 push 新的 `ForumDisplayPage(fid: subForum.fid, title: subForum.title)`。

## 测试计划

- parser 测试读取 `docs/html/动漫区.html`，确认解析到 fid `52`、标题“百合会最萌世界杯专版！”和图标 URL。
- widget 测试确认子版块入口渲染，点击后进入新的帖子列表页路由。
- 运行 `flutter analyze` 和本次相关 forum display 测试子集。

## Review 重点

- 动漫区应在筛选栏下方显示“子版块”入口。
- 点击“百合会最萌世界杯专版！”应进入 fid `52` 的帖子列表页。
- 不含 `forumlist.cl` 的版块不应多出空白区域。
