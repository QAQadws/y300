# 统一浏览记录页 Phase 0 基线与 ADR

> 状态：Accepted
> 日期：2026-07-16
> 决策范围：浏览记录语义、页面接入点、存储边界、重开策略与 Phase 0 测试基线
> 对应总方案：`docs/统一浏览记录页分阶段实施方案.md`

## 1. Phase 0 结论

Phase 0 只冻结语义、接入点和现有行为，不创建 `history` 生产模块，不修改 UI，不创建数据库，也不写入任何浏览记录。

后续实现必须遵守以下五项决策：

1. 记录由“用户可见内容成功提交”触发，不由 HTTP、repository 或 parser 成功触发。
2. 同一目标按 `(targetType, targetId)` 聚合成一行；新访问更新该行，不连续插入重复行。
3. 历史数据由独立的 `history_records.db` 持有，不加入 `comic_shelf.db`。
4. 帖子从记录页重开时遵循用户当前论坛模式，不固化首次访问时的原生或 WebView 表面。
5. 第一版只记录帖子详情、漫画详情和小说详情，不记录漫画阅读器、小说阅读器或图片阅读器 session。

这些决定是后续 Phase 1 至 Phase 7 的架构约束。若要改变，必须新增 ADR，而不是在某个页面内局部绕过。

## 2. 背景与问题

应用中的网络请求并不等同于用户浏览：

- 收藏同步会请求帖子 JSON 并触发漫画解析、小说首楼同步或章节水合。
- 漫画更新会执行目录发现、搜索 fallback、图片预加载和后台刷新。
- 原生帖子详情可能从 parsed snapshot 或页面缓存直接显示，不一定产生新的 HTML 请求。
- WebView 会产生主文档、图片、脚本和 CSS 请求，同一主文档还可能重定向。
- 楼层定位请求只为计算页码，用户尚未看到目标帖子。

若在网关或 repository 监听成功请求，收藏同步会污染浏览记录，而缓存命中的真实浏览反而可能漏记。因此记录事件只能在 presentation 层确认内容已经可见后提交。

## 3. 决策一：记录可见提交，而不是 HTTP

### 3.1 正式触发条件

| 页面 | 成功提交条件 | 当前路由内不重复的行为 |
| --- | --- | --- |
| `UnifiedDetailPage` | 有效 `LibraryDetailHeader` 已进入可渲染状态 | 更新、外部刷新信号、章节状态变化、从阅读器返回后的 reload |
| `ThreadDetailPage` | `ThreadDetailPageState.posts` 非空并进入正文分支 | 刷新、翻页、倒序、正序、只看楼主、投票后 reload |
| `ForumWebViewPage` | 当前 generation 的帖子主文档已可见，且 TID/标题元数据准备完成 | 同帖刷新、分页、排序；不同 TID 是新的可见访问 |

失败页、空楼层、权限提示、主题不存在、仅路由创建但内容未显示的情况都不提交。

### 3.2 禁止接入点

不得从以下位置写记录：

- `YamiboHttpGateway`、Dio interceptor 或 WebView 子资源回调。
- `ThreadRepository`、漫画/小说 repository 的读取成功分支。
- 收藏同步、漫画解析、小说水合、目录发现或搜索刷新队列。
- 图片缓存、预加载、下载、封面预热或楼层定位。
- `MainShellPage` 的 Tab 点击事件。

历史记录失败属于 best-effort 旁路错误，不得让详情页进入错误态或白屏。

## 4. 决策二：目标聚合与会话幂等

目标主键固定为：

```text
(target_type, target_id)
```

- 帖子：`targetType=thread`，`targetId=tid`。
- 漫画：`targetType=comic`，`targetId=workId`。
- 小说：`targetType=novel`，`targetId=workId`。

每次新的可见访问会话通过 UPSERT 更新 `lastVisitedAt`、展示快照和 `visitCount`，并保留 `firstVisitedAt`。当前路由内的 rebuild、reload 或分页不产生新计数。

页面幂等边界如下：

- 漫画/小说详情：一个详情 route session 最多提交一次。
- 原生帖子详情：一个 `ThreadDetailPage` route session 最多提交一次。
- WebView：一个页面 route 中可以依次浏览多个帖子；以 navigation generation 和 TID 迁移识别新的可见访问，同帖操作不重复提交。

## 5. 决策三：独立数据库

第一版使用 `history_records.db`，由 `history/data/local` 独占 schema、迁移和连接生命周期。

选择独立数据库的原因：

- 记录与漫画、小说、收藏表没有事务或外键需求。
- 避免 `history` 反向依赖 `comic/data/local/ComicLocalDb`。
- 清空记录和保留策略可以独立执行。
- 不触碰现有 `comic_shelf.db` 版本和迁移链。

记录只保存重开和列表展示所需快照，不保存 HTML、Cookie、认证参数或正文。时间统一写 UTC epoch，UI 再按本地自然日分组。

首版不按时间自动过期，最多保留 2000 个唯一目标；超过上限时由 `HistoryRetentionPolicy` 删除最早访问项。重复访问只更新原行，不额外占用条数。

## 6. 决策四：帖子按当前论坛模式重开

历史实体不把 `native` 或 `webview` 当作永久目标身份。访问表面可以作为诊断快照，但重开策略读取用户当时的 `ForumShellMode`：

- 当前为原生模式：打开 `ThreadDetailPage`。
- 当前为 WebView 模式：通过受控 `ForumWebViewPage` 打开规范化 viewthread URL。

这样用户切换论坛模式后，记录页行为与当前偏好一致。旧 GBK `highlight=%D2...` 等参数不得通过 `Uri.queryParameters` 解码整段 query；TID 解析继续复用项目已有 raw-query-safe 规则。

## 7. 决策五：第一版不记录 reader session

第一版不记录以下访问：

- 漫画阅读器章节和页码。
- 小说阅读器章节和滚动位置。
- 帖子公共图片阅读器。

阅读进度已由漫画/小说模块分别维护。把 reader session 混入浏览记录会引入章节级身份、进度快照和恢复策略，超出本期范围。未来若增加，必须定义独立目标类型或访问事件表，不能复用作品详情记录含糊表达。

## 8. 页面接入契约

### 8.1 统一作品详情

未来在 `UnifiedDetailPage` 增加与 history 无关的纯回调，例如 `onFirstContentPresented`。共享页只通知有效 Header 首次提交，不 import `history`；`ComicDetailPage` 和 `NovelDetailPage` 薄壳负责映射并调用 recorder port。

回调要求：

- 初始加载失败不调用，重试成功后可调用一次。
- Header 有效且页面仍 mounted 时调用。
- 当前 route 的更新、reload 和章节变化不重复调用。
- 回调失败不改变 `UnifiedDetailController` 状态。

### 8.2 原生帖子详情

接入点位于 `ThreadDetailPage` 的可渲染状态边界，而不是 `ThreadDetailController._loadPage()` 或 repository。

回调要求：

- `posts.isNotEmpty` 后提交，网络、snapshot 和 cache 路径一致。
- 初始失败不提交，重试得到有效正文后可提交一次。
- 当前 route 内翻页、排序和只看楼主不重复提交。
- 页面销毁后的迟到状态不得提交。

### 8.3 论坛 WebView

WebView 后续由独立 `ForumWebViewHistoryCoordinator` 管理状态机。页面只转发主文档生命周期与抽取后的元数据。

门禁至少包括：

```text
onPageStarted -> generation + 1
visible(generation) + metadataReady(generation, tid)
  -> generation 仍为 current
  -> 页面仍 mounted
  -> 提交该 TID 的可见访问
```

高级引擎优先使用 `onPageCommitVisible`；不支持时使用受控 fallback。任何迟到的 title、DOM、menu 或 finish 结果都必须先比较 generation，再更新状态或提交记录。

## 9. 生产入口盘点

### 9.1 漫画详情

| 调用方 | 场景 |
| --- | --- |
| `features/comic/presentation/comic_shelf_page.dart` | 漫画书架打开详情 |
| `features/favorites/presentation/favorite_shelf_page.dart` | 收藏书架打开已导入漫画 |

两者最终都进入 `ComicDetailPage -> UnifiedDetailPage`，无需调用方手工记录。

### 9.2 小说详情

| 调用方 | 场景 |
| --- | --- |
| `features/novel/presentation/novel_shelf_page.dart` | 小说书架打开详情 |
| `features/favorites/presentation/favorite_shelf_page.dart` | 收藏书架打开已导入小说 |

两者最终都进入 `NovelDetailPage -> UnifiedDetailPage`，无需调用方手工记录。

### 9.3 原生帖子详情

| 调用方 | 场景 |
| --- | --- |
| `features/forum/presentation/forum_home_page.dart` | 论坛首页帖子 |
| `features/forum/presentation/forum_display_page.dart` | 版块帖子与楼层定位结果 |
| `features/search/presentation/forum_search_page.dart` | 搜索结果 |
| `features/tags/presentation/yamibo_tag_thread_page.dart` | 标签帖子列表 |
| `features/favorites/presentation/favorite_shelf_page.dart` | 普通收藏帖子 |
| `features/thread/presentation/thread_detail_page.dart` | 正文内帖子链接和楼层链接 |
| `features/forum/presentation/webview/forum_webview_page.dart` | 原生模式拦截 WebView 帖子链接 |
| `features/comic/presentation/comic_detail_page.dart` | 漫画来源帖 |
| `features/comic/presentation/comic_reader_page.dart` | 阅读器来源帖 |
| `features/novel/presentation/novel_detail_page.dart` | 小说章节原帖 |
| `features/novel/presentation/novel_reader_page.dart` | 小说阅读器中的来源帖和正文链接 |

这些路径都创建 `ThreadDetailPage`，因此只在该页面接入一次即可覆盖，不在十一类调用方散布 recorder。

### 9.4 论坛 WebView

| 调用方 | 场景 |
| --- | --- |
| `features/forum/presentation/forum_shell_page.dart` | 论坛 WebView 主 Tab |
| `features/thread/presentation/thread_detail_page.dart` | 原生正文中的受管 WebView 链接 |
| `features/more/presentation/more_page.dart` | 用户资料 WebView |

资料页本身不是帖子，不会提交；若用户随后在受管站点导航到帖子，则仍由同一 `ForumWebViewPage` generation 状态机判断。

## 10. 主壳现状基线

Phase 0 固定当前主壳行为：

- `NavigationBar` 恰好五项：`论坛 / 收藏 / 漫画 / 小说 / 更多`。
- `_pageCount == 5`。
- `IndexedStack` 初始只构建 index 0，其余位置为 `SizedBox.shrink()`。
- 用户首次选择某 Tab 后才加入 `_builtIndexes`；已构建页面保留在栈内。
- 只有当前 Tab 的 `TickerMode.enabled == true`。
- 书架多选激活时 `SelectionActionBar` 替换 `NavigationBar`，退出多选后恢复。

Phase 2 增加“记录”后必须显式更新这些断言为六项，并继续保持懒构建、TickerMode 和 selection bar 行为。

## 11. Characterization Tests

Phase 0 新增或强化以下测试：

- `main_shell_page_test.dart`
  - 固定五个 destination 的顺序。
  - 固定初始只构建论坛、访问后五页都保留、仅当前页启用 ticker。
  - 既有 selection action bar 测试继续固定替换与恢复行为。
- `unified_detail_page_test.dart`
  - 固定 Header 在初始异步加载完成后才出现。
  - 固定初始加载一次，当前 route 点击更新后原地 reload，不创建新页面。
- `thread_detail_page_test.dart`
  - 固定空加载态不构建帖子列表，有非空 posts 后才进入正文。
  - 固定下一页替换发生在同一 `ThreadDetailPage` route 内。
- `forum_webview_page_test.dart`
  - 固定新的 `onPageStarted` 推进 generation。
  - 固定旧 generation 的迟到 `onPageFinished/title` 结果不能覆盖新页面，也不能执行旧页面清理。

这些测试描述的是接入前行为，不验证 history 数据。后续阶段应在此基础上增加 recorder 调用次数，而不是删除基线断言。

## 12. 后果与后续约束

### 正向后果

- 收藏同步和后台解析天然不会污染记录。
- 网络、snapshot、cache 和 WebView 路径得到一致的“看见才记录”语义。
- 三个页面级接入点覆盖全部生产入口，避免调用点遗漏和重复写入。
- history 数据库可以独立演进、清理和诊断。

### 代价

- WebView 必须维护可见提交与元数据完成的双门禁，不能只依赖 `onPageFinished`。
- 页面侧需要 route-session 幂等状态。
- 历史列表采用写入时快照，来源标题或封面变化不会自动回写，只有下次访问更新。

### Phase 0 非目标

- 不创建 `HistoryEntry`、repository、provider 或 SQLite schema。
- 不增加底部“记录”Tab。
- 不接入任何 recorder 回调。
- 不实现记录查询、搜索、删除、撤销、清空或重开路由。
- 不改变漫画、小说、帖子和 WebView 的现有用户行为。
