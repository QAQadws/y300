# 小说详情页刷新策略升级：标题更新 + 增量章节解析

## 1. 目标

升级 `NovelDetailPage` 下拉刷新（`RefreshIndicator.onRefresh`）和右上「更新」菜单背后的策略：

1. **标题永远走 sanitizer 重新解析**——论坛常把更新时间戳塞进帖子标题（例如 `（6.30更新番外11）`），原标题不变但 sanitizer 输出可能变化。
2. **章节解析改为增量**——从已解析过的最大 `source_page`（包含该页本身重新拉一次）开始往后拉，最多拉 `_maxRefreshPages` 页；不再每次都从第 1 页全部重新请求。
3. **现有调用方（收藏首次同步、阅读器自愈、加入书架、Shelf 添加）保持原有「全量」语义**——这些场景需要发现整本目录/封面/简介，不能切到增量。

## 2. 现状梳理

`LocalNovelRepository.refreshEpisodes` 当前路径：

```
_fetchPages(tid, page=1..maxPages)
  └─ NovelEpisodeDiscoveryService.buildPlan(novelId, pages)
       ├─ 从 pages.first.posts 取 OP 跑 NovelSameThreadCatalogExtractor
       ├─ 命中：catalog 模式（前 10 楼锚点目录）
       └─ 未命中：rule 链遍历每楼
  └─ 事务写：episodes + content；删 plan 之外的旧行；更新 works.title/author/cover
  └─ _maybeWriteParsedIntro(pages)  // 仅当 work_state.intro_text 为空
```

调用点（共 6 处，全在 lib/）：
- `novel_favorite_ingest_service.dart` ←收藏同步
- `novel_shelf_controller.dart::addByForumThread` ← Shelf 添加
- `thread_detail_controller.dart` ← 帖子详情「加入书架」
- `novel_reader_controller.dart` ×2 ← 阅读器自愈
- `novel_detail_adapter.dart::refreshWork` ← **本次目标**

## 3. 设计

### 3.1 引入两枚值对象（domain 层）

**`NovelEpisodeRefreshMode`**（位于 `lib/features/novel/domain/models/novel_thread_models.dart`，与 `NovelRefreshPlan` 同文件）：

```dart
enum NovelEpisodeRefreshMode {
  /// 从第 1 页开始全量爬取并重建章节、封面、简介。
  full,

  /// 从已解析过的最大 source_page 开始增量拉取；
  /// 标题仍刷新；封面/简介/目录不动；不删除已存在的旧章节。
  /// 当本地无章节或已知最大页 ≤ 1 时自动降级为 full。
  incremental,
}
```

**`NovelDiscoveryOptions`**（同文件）：

```dart
class NovelDiscoveryOptions {
  const NovelDiscoveryOptions({
    this.orderIndexOffset = 0,
    this.skipCatalogExtraction = false,
    this.skipFirstChapterMetadata = false,
  });

  /// 新章节起始 orderIndex —— 会同时投影到 NovelParsingContext.currentOrderIndex，
  /// 让 CoverImageRule / IntroBeforeFirstChapterRule 自然失效（它们依赖 == 0 触发）。
  final int orderIndexOffset;

  /// 增量模式跳过 catalog —— 目录只出现在首页前 10 楼，
  /// 在非首页跑 catalog 既无效又会浪费 anchor 抽取。
  final bool skipCatalogExtraction;

  /// 进一步显式压制 cover/intro/catalog 元数据 —— 防御性兜底。
  final bool skipFirstChapterMetadata;

  static const NovelDiscoveryOptions defaults = NovelDiscoveryOptions();
}
```

### 3.2 `NovelEpisodeDiscoveryService.buildPlan` 接受 options

`buildPlan` 签名加可选 `NovelDiscoveryOptions options = NovelDiscoveryOptions.defaults`。
内部改动：

- `_NovelRefreshPlanBuilder` 增加 `orderIndexOffset` 字段；`episodeCount` getter 返回 `_episodes.length + orderIndexOffset`。这样 `currentOrderIndex` 和 `NovelEpisodeDraft.orderIndex` 都自动平移。
- `if (catalogEntries.isNotEmpty)` 分支前加 `if (!options.skipCatalogExtraction)` 防护。
- `acceptMeta` 在 `options.skipFirstChapterMetadata` 时丢弃 `intro` / `coverImageUrl`（rule 已经被 `currentOrderIndex != 0` 兜住，这里是显式防御）。

### 3.3 `NovelRepository.refreshEpisodes` 加 mode 参数

抽象类签名：

```dart
Future<NovelEpisodeRefreshResult> refreshEpisodes({
  required String novelId,
  NovelEpisodeRefreshMode mode = NovelEpisodeRefreshMode.full,
  FavoriteSyncExecutionContext? executionContext,
});
```

**默认 `full` 保持现有 5 个调用点行为不变**——不需要改它们。

### 3.4 `LocalNovelRepository.refreshEpisodes` 实现拆分

抽出三个私有方法，主入口只做策略选择：

```dart
Future<NovelEpisodeRefreshResult> refreshEpisodes({
  required String novelId,
  NovelEpisodeRefreshMode mode = NovelEpisodeRefreshMode.full,
  FavoriteSyncExecutionContext? executionContext,
}) async {
  final detail = await getDetail(novelId: novelId) ?? throw ...;
  // 增量降级守门：本地零章节 / maxPage <= 1 / catalog 模式（page=1 上多章节）—> 退回 full
  final resolvedMode = await _resolveRefreshMode(novelId: novelId, requested: mode);
  if (resolvedMode == NovelEpisodeRefreshMode.full) {
    return _refreshEpisodesFull(novelId: novelId, detail: detail, ctx: executionContext);
  }
  return _refreshEpisodesIncremental(novelId: novelId, detail: detail, ctx: executionContext);
}
```

**`_resolveRefreshMode`**：
- `requested == full` → `full`。
- 查 `SELECT MAX(source_page), COUNT(*), SUM(CASE WHEN source_page = 1 THEN 1 ELSE 0 END) FROM work_episodes WHERE work_id=? AND content_type='novel'`。
- 如果 `count == 0` 或 `MAX(source_page) <= 1` → 降为 `full`（一页内的全部不需要增量）。
- 如果 `MAX(source_page) >= 2` 但 `page=1 上的章节数 >= 2` → 是 catalog 模式。catalog 模式下增量拉取后续页会用 rule 链生成与目录不一致的标题/episodeId，所以这里也降为 `full`。否则 → `incremental`。

**`_refreshEpisodesIncremental`**：
1. 查 `MAX(source_page) AS startPage, MAX(order_index) AS maxOrder` from `work_episodes`。
2. `_fetchPages(tid, startPage: startPage)`，最多再拉 `_maxRefreshPages` 页（绝对终止页 = `startPage + _maxRefreshPages - 1`）。
3. 如果 `pages.isEmpty`（即起点已被删帖、超出末页）→ 还要刷标题，所以单独拉一次 `getThreadDetail(page: startPage)`，更新 `works.title`，返回 zero result。
4. `discoveryService.buildPlan(novelId, pages, options: NovelDiscoveryOptions(orderIndexOffset: maxOrder + 1, skipCatalogExtraction: true, skipFirstChapterMetadata: true))`。
5. 事务写：
   - 对每个 draft：`INSERT OR REPLACE work_episodes`；既有的 `episode_id` 保留原 `order_index` 与 `episode_title`（避免 rule 链生成的标题覆盖原 catalog 标题），新增的用 draft 提供的值。这一步在 SQL 层用 `INSERT ... ON CONFLICT DO UPDATE` 写法或者先 query existing。
   - **不删任何旧行**——增量模式语义是「合并新发现」。
   - `UPDATE works SET title = sanitize(plan.subject, fallback=detail.title), updated_at = now`。**不动 author/cover_image_url**——这两个我们没有可信新数据。
6. 不调 `_maybeWriteParsedIntro`——简介只在 full 模式跑（避免拿后续页的 OP HTML 误判）。
7. 计算 inserted/updated 同现有逻辑。

**`_refreshEpisodesFull`**：把当前 `refreshEpisodes` 函数体原样搬进来；`buildPlan` 不传 options（用 `defaults`）。语义不变。

### 3.5 `_fetchPages` 加 `startPage` 参数

```dart
Future<List<ThreadDetailData>> _fetchPages({
  required String tid,
  int startPage = 1,
  FavoriteSyncExecutionContext? executionContext,
}) async {
  final pages = <ThreadDetailData>[];
  for (var page = startPage; page < startPage + _maxRefreshPages; page++) {
    ...
  }
}
```

不改 `_maxRefreshPages` 含义——它仍然是单次刷新最多拉的页数，只是起点可平移。

### 3.6 `NovelDetailAdapter.refreshWork` 切到增量

```dart
@override
Future<DetailRefreshResult> refreshWork({required String workId}) async {
  await _repository.refreshEpisodes(
    novelId: workId,
    mode: NovelEpisodeRefreshMode.incremental,
  );
  return DetailRefreshResult.immediate;
}
```

仓库内部的「自动降级」会在零章节/单页/catalog 场景下自动回到 full，所以 adapter 不需要预判。

### 3.7 测试假实现的兼容性

`NovelRepository.refreshEpisodes` 加新可选参数会让 9 个 fake 全部编译失败。每个 fake 加一行：

```dart
Future<NovelEpisodeRefreshResult> refreshEpisodes({
  required String novelId,
  NovelEpisodeRefreshMode mode = NovelEpisodeRefreshMode.full,  // 新增
  FavoriteSyncExecutionContext? executionContext,
}) async { ... }
```

文件清单（9 处）：
- `test/features/novel/data/novel_download_service_test.dart`
- `test/features/novel/data/novel_reader_cache_service_test.dart`
- `test/features/novel/presentation/novel_detail_page_test.dart`
- `test/features/novel/presentation/novel_shelf_page_test.dart`
- `test/features/novel/presentation/novel_reader_page_test.dart`
- `test/features/novel/presentation/novel_reader_controller_test.dart`
- `test/features/novel/presentation/adapters/novel_detail_adapter_test.dart`
- `test/features/thread/presentation/thread_detail_page_test.dart`
- `test/features/startup/presentation/main_shell_page_test.dart`

## 4. 新增测试

`test/features/novel/data/local_novel_repository_test.dart`：

1. **`refreshEpisodes incremental refetches from last known page and merges new episodes`**
   - 第 1 次 full 刷新：4 章分布在 page 1, 2（rule 链路径）。
   - 模拟新增 1 章在 page 3，`page=2` 内容也变化。
   - 第 2 次 incremental 刷新：fake gateway 验证 page 1 没被请求；新章节插入；旧 page 1 章节保留。
   - `result.insertedCount == 1`，`updatedCount` 包含 page 2 的章节。

2. **`refreshEpisodes incremental updates title via sanitizer`**
   - 初次 subject = `[搬运] 标题 6.20更新番外5`，sanitize 后入库 = `标题 6.20更新番外5`。
   - 增量 fake gateway 返回 subject = `[搬运] 标题 7.1更新番外6`。
   - 增量后 `getDetail().title == '标题 7.1更新番外6'`。

3. **`refreshEpisodes incremental falls back to full when no episodes exist`**
   - 仅 `upsertNovelBySeed`，未 refreshEpisodes 过，直接 incremental。
   - 验证 fake gateway 收到 page=1 请求。

4. **`refreshEpisodes incremental falls back to full for catalog-mode novel`**
   - 第 1 次 full 触发 catalog 路径（首楼锚点 ≥ 2 个，目标 pid 分散在 page 2/3）。
   - 第 2 次 incremental，验证 fake 收到 page=1 请求（说明降级了）。

5. **`refreshEpisodes incremental does not overwrite intro`**
   - 用户在 work_state 里有 `introText = '我手写'`。
   - 增量后 introText 不变。

`test/features/novel/presentation/adapters/novel_detail_adapter_test.dart`：

6. **`refreshWork passes incremental mode to repository`**——给 `_FakeNovelRepository.refreshEpisodes` 加 `lastModeReceived` 字段，验证 adapter 传的是 `incremental`。

`test/features/novel/domain/services/novel_episode_discovery_service_test.dart`（如果存在；否则在仓库测试覆盖）：

7. **`buildPlan with skipCatalogExtraction ignores catalog`**
8. **`buildPlan with orderIndexOffset assigns continuing indices and disables cover/intro rules`**

## 5. 文档更新

`docs/开发文档.md` 顶部新增：

```
# 2026-06-15 小说详情页刷新升级：增量解析 + 标题刷新

- 新增 NovelEpisodeRefreshMode（full / incremental）。
- LocalNovelRepository.refreshEpisodes 加 mode 参数；默认 full 不变。
- 详情页下拉刷新与「更新」菜单切到 incremental 模式：
  - 仅从 MAX(source_page) 开始往后拉，省去前 N 页的请求。
  - 标题仍走 NovelTitleSanitizer 重写，覆盖论坛在标题里塞的更新时间。
  - 不动封面/简介/作者；不删旧章节。
- 增量在以下三种情况自动降级为 full（仓库内部判断，调用方无感）：
  - 本地零章节
  - 最大 source_page ≤ 1
  - catalog 模式（page=1 上有 ≥ 2 个章节）
- 9 个 fake 仓库实现同步加可选 mode 参数。

需要 review/测试的点：
- LocalNovelRepository 增量分支事务（不删旧行 + sanitize 标题）
- NovelDetailAdapter 切到 incremental 模式
- 既有 5 个 full 调用点行为完全不变
```

`docs/小说解析流程.md` 第二节末尾追加：

```
### 步骤 2 的两种模式（mode）

- `full`（默认）：当前流程不变。
- `incremental`：详情页下拉/更新触发；只 sanitize 标题 + 增量补章节，
  不重做封面/简介/目录抽取。降级条件见 LocalNovelRepository._resolveRefreshMode。
```

## 6. 修改文件清单

**新增/修改 lib：**
- `lib/features/novel/domain/models/novel_thread_models.dart`（+ enum + options 类）
- `lib/features/novel/data/novel_repository.dart`（接口加 mode 参数）
- `lib/features/novel/data/local_novel_repository.dart`（拆分实现 + 增量分支）
- `lib/features/novel/domain/services/novel_episode_discovery_service.dart`（buildPlan 接 options + builder offset）
- `lib/features/novel/presentation/adapters/novel_detail_adapter.dart`（切 incremental）

**修改 test（9 个 fake + 新增测试）：**
- `test/features/novel/data/local_novel_repository_test.dart`（+5 新测试 + fake gateway 升级支持多次刷新差异）
- `test/features/novel/presentation/adapters/novel_detail_adapter_test.dart`（fake 加 mode 记录 + 新测试）
- 7 个其它 fake：仅加 `mode` 参数让其编译通过

**新增/修改 docs：**
- `docs/开发文档.md`（顶部追加新章节）
- `docs/小说解析流程.md`（第二节追加 mode 说明）

## 7. 取舍与备注

- **为什么 catalog 模式降为 full**：catalog 用锚点文本作为章节标题（例如「第3章 序章」），rule 链路径可能在同一帖里通过 heading/regex 提取出不同标题（例如「第3章」），增量合并会引发标题漂移。降级最稳。
- **为什么不动封面/简介/作者**：这三项必须从首页 OP HTML 解析，增量不拉首页就拿不到可信源。维持现状即可。
- **为什么仍 sanitize 标题**：subject 字段 Discuz 在每页响应里都返回，刷哪页都能拿到当前最新标题；sanitize 是纯函数无副作用。
- **为什么默认仍 full**：所有现有调用点（收藏同步、shelf 添加、阅读器自愈）都需要完整发现章节，不能换语义。
- **不引入「reset incremental → full」按钮**：用户长按「更新」未来要做也好做（多传一个 mode 即可），现在不要过度设计。
