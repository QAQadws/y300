# Yamibo 论坛帖子列表页顶部版块图实施计划

## 范围

本次补齐移动端 `forumdisplay` HTML 中的版块顶部图片：当页面存在 `#forum > div.forum-headimg img` 时，原生帖子列表页在版块信息头之前展示该图片。

## 非目标

- 不改 `forumdisplay` API 数据源资产。
- 不改帖子列表页的筛选、分页、发帖和帖子详情跳转逻辑。
- 不引入 WebView 或额外图片探测请求。
- 不把 DOM 解析逻辑写入 Flutter Widget。

## 实现设计

- `ForumDisplayHtmlParser` 解析 `#forum > div.forum-headimg img`，并通过 `SiteUrlResolver` 归一化图片 URL。
- `ForumDisplayData` 增加可选 `headImageUrl`，API 解析路径默认保持 `null`。
- `ForumDisplayPageState` 搬运 `headImageUrl`，controller 只做字段映射。
- `ForumDisplayPage` 在 `_ForumDisplayHeader` 之前渲染稳定比例的顶部图片；加载失败时显示轻量占位，不阻断列表主体。

## 测试计划

- parser 测试读取 `docs/html/海域区.html`，确认解析到 `forum-headimg` 图片 URL。
- widget 测试确认有 `headImageUrl` 时页面渲染顶部图片区块。
- 运行 `flutter analyze` 和本次相关 forum display 测试子集。

## Review 重点

- 海域区这类带头图的版块，图片应位于帖子列表 body 顶部、版块统计头之前。
- 不带 `forum-headimg` 的版块应保持现有布局。
- 图片失败不应影响筛选、置顶、帖子列表和分页。
