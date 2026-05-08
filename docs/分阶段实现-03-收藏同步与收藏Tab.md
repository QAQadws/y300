# 分阶段实现 03：收藏同步与收藏 Tab

本阶段目标是实现新的“收藏”模块：从 `myfavthread` 拉取全部收藏帖，进帖补全 `fid/typeid/tagName`，根据统一规则判定漫画/小说/普通论坛帖，并同步驱动漫画和小说模块。

## 目标

1. 新增主 Tab：“收藏”。
2. 请求 `module=myfavthread&version=4&page=N`，支持全量和增量同步。
3. 本地缓存所有收藏帖的 `tid/fid/typeid/tagName/contentKind` 等信息。
4. 收藏中的漫画同步到漫画模块，小说同步到小说模块。
5. 漫画/小说模块的内容由收藏同步数据表示。
6. 论坛模块中的旧收藏版块功能先禁用。
7. 收藏页复用 `UnifiedShelfPage`，默认列表显示。
8. 收藏页系统分类为“漫画”“小说”“默认”，默认分类不能包含漫画和小说。

## 当前已有基础

已有文件：

- `lib/features/favorites/data/favorite_repository.dart`
- `lib/features/favorites/data/models/favorite_models.dart`

当前能力：

- `getFavoriteThreads(page: page)` 已能解析单页。
- `FavoriteThreadsPage` 已有 `totalCount/perPage/items/hasMore`。

缺少能力：

- 全量读取所有页。
- 本地持久化。
- count 变化检测。
- 进帖补全。
- 内容类型判定。
- 与 comic/novel repository 同步。
- 收藏 Tab UI。

## 本地表设计

建议继续使用现有 SQLite 入口 `ComicLocalDb.open()`，先不要为收藏单独建库，降低迁移复杂度。

文件：`lib/features/comic/data/local/comic_local_db.dart`

DB 版本在阶段 01 的标签迁移之后继续增加，例如阶段 01 使用 v10，则本阶段使用 v11。

### 1. favorite_sync_state

```sql
CREATE TABLE IF NOT EXISTS favorite_sync_state (
  sync_key TEXT PRIMARY KEY,
  remote_count INTEGER NOT NULL DEFAULT 0,
  local_active_count INTEGER NOT NULL DEFAULT 0,
  last_synced_at INTEGER,
  last_full_synced_at INTEGER,
  status TEXT,
  message TEXT
)
```

`sync_key` 固定使用 `myfavthread`。

### 2. favorite_threads

```sql
CREATE TABLE IF NOT EXISTS favorite_threads (
  tid TEXT PRIMARY KEY,
  favid TEXT,
  title TEXT NOT NULL,
  description TEXT,
  author TEXT,
  replies INTEGER NOT NULL DEFAULT 0,
  url TEXT,
  dateline INTEGER,
  remote_order INTEGER,

  source_fid TEXT,
  source_typeid TEXT,
  source_tag_name TEXT,
  content_kind TEXT NOT NULL DEFAULT 'unknown',
  work_id TEXT,

  detail_loaded_at INTEGER,
  first_seen_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  removed_at INTEGER
)
```

字段说明：

- `content_kind`：`unknown/comic/novel/forum`。
- `work_id`：
  - 漫画：`yamibo:<tid>`，沿用当前 `ThreadDetailController._buildComicId`。
  - 小说：`novel:<fid>:<tid>`。
  - 普通论坛帖可以为空，或使用 `thread:<tid>`。
- `removed_at` 为 null 表示当前仍在远程收藏列表中。
- `detail_loaded_at` 非 null 表示已经进帖补全过 `fid/typeid/tagName`。

### 3. favorite_categories

收藏页需要自定义分类，但“漫画/小说/默认”是系统分类，不建议写死进表。表只存用户自定义分类：

```sql
CREATE TABLE IF NOT EXISTS favorite_categories (
  category_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  created_at INTEGER NOT NULL
)
```

### 4. favorite_thread_category

收藏帖的自定义分类绑定：

```sql
CREATE TABLE IF NOT EXISTS favorite_thread_category (
  tid TEXT PRIMARY KEY,
  category_id TEXT NOT NULL,
  assigned_at INTEGER NOT NULL,
  FOREIGN KEY (tid) REFERENCES favorite_threads(tid) ON DELETE CASCADE,
  FOREIGN KEY (category_id) REFERENCES favorite_categories(category_id) ON DELETE CASCADE
)
```

分类规则：

- 有自定义分类的收藏帖，只显示在自定义分类里。
- 没有自定义分类时：
  - `content_kind=comic` => “漫画”
  - `content_kind=novel` => “小说”
  - 其它 => “默认”

这能满足“漫画帖子不在漫画分类时，它一定在自定义分类；否则至少在漫画分类”的要求。

### 5. 索引

```sql
CREATE INDEX IF NOT EXISTS idx_favorite_threads_kind_order
ON favorite_threads(content_kind, remote_order);

CREATE INDEX IF NOT EXISTS idx_favorite_threads_removed
ON favorite_threads(removed_at);

CREATE INDEX IF NOT EXISTS idx_favorite_thread_category_category
ON favorite_thread_category(category_id);
```

## 数据层建议

新增目录：

```text
lib/features/favorites/data/local_favorite_repository.dart
lib/features/favorites/data/favorite_sync_service.dart
lib/features/favorites/data/favorite_providers.dart
lib/features/favorites/domain/favorite_models.dart
lib/features/favorites/presentation/favorite_shelf_page.dart
lib/features/favorites/presentation/adapters/favorite_shelf_adapter.dart
```

### LocalFavoriteRepository

职责：

- upsert API 返回的收藏页数据。
- 查询本地 active 收藏。
- 查询 unknown 或未补全 detail 的收藏。
- 标记远程已消失。
- 管理收藏页自定义分类。
- 为 `FavoriteShelfAdapter` 提供分类和列表查询。

关键方法：

```dart
abstract class LocalFavoriteRepository {
  Future<FavoriteSyncSnapshot?> getSyncSnapshot();

  Future<void> upsertRemotePage({
    required FavoriteThreadsPage page,
    required int pageStartOrder,
  });

  Future<List<FavoriteThreadCacheRecord>> getMissingDetailRecords({
    int limit = 20,
  });

  Future<void> updateThreadDetailMeta({
    required String tid,
    required String fid,
    required String typeid,
    required String? tagName,
    required ThreadContentKind contentKind,
    required String? workId,
  });

  Future<void> markRemovedTids(Set<String> activeRemoteTids);

  Future<List<LibraryCategory>> loadVisibleCategories();

  Future<List<LibraryWorkItem>> loadCategoryItems(String categoryId);
}
```

## 同步服务设计

新增：`FavoriteSyncService`

职责：

1. 拉取远程收藏页。
2. 判断全量/增量。
3. 进帖补全 detail。
4. 同步 comic/novel 本地库。
5. 标记消失的收藏并从 comic/novel 模块移除。

### 首次同步

流程：

1. 请求 page 1。
2. 读取 `count/perpage/list`。
3. 根据 count 计算页数：`ceil(count / perpage)`。
4. 顺序拉取所有页。
5. 写入 `favorite_threads`。
6. 逐个未补全帖子调用 `ThreadRepository.getThreadDetail(tid, page: 1)`。
7. 读取 `fid/typeid`，通过 `ForumTagLookup` 得到 `tagName`。
8. 用 `ThreadContentClassifier` 得到 `contentKind`。
9. 如果是漫画，写入 comic repository。
10. 如果是小说，写入 novel repository 并刷新章节。
11. 更新 `favorite_sync_state.remote_count`。

### 增量同步

远程 `list` 是按收藏时间倒序，前面为最新。

推荐策略：

1. 每次同步先请求 page 1。
2. 如果 `remote_count == local_active_count` 且 page 1 中没有未知 tid：
   - 更新 `last_synced_at`，结束。
3. 如果 `remote_count > local_active_count`：
   - 从 page 1 开始向后读，直到遇到一整页都是已知 active tid，或读完远程页。
   - 对未知 tid 进帖补全并同步。
4. 如果 `remote_count < local_active_count`：
   - 必须读取所有远程页，得到完整 active tid 集合。
   - 本地 active 但不在远程集合中的 tid 标记 `removed_at`。
   - 对移除的漫画/小说执行同步移除。
5. 如果 count 相等但 page 1 有未知 tid：
   - 可能是用户取消了一些旧收藏又新增了一些新收藏。
   - 读取所有远程页，做完整 diff。

### 进帖补全并同步

伪代码：

```dart
final detail = await threadRepository.getThreadDetail(tid: tid, page: 1);
final tagName = tagLookup.findName(fid: detail.fid, typeid: detail.typeid);
final kind = classifier.classify(
  fid: detail.fid,
  typeid: detail.typeid,
  tagName: tagName,
);

switch (kind) {
  case ThreadContentKind.comic:
    await comicIngestService.upsertFromThreadDetail(
      detail: detail,
      sourceTagName: tagName,
    );
  case ThreadContentKind.novel:
    await novelIngestService.upsertFromThreadDetail(
      detail: detail,
      sourceTagName: tagName,
    );
  case ThreadContentKind.forum:
    break;
}
```

建议单独做 ingest service，而不是让收藏同步直接操作太多 repository 细节：

```text
lib/features/comic/data/comic_favorite_ingest_service.dart
lib/features/novel/data/novel_favorite_ingest_service.dart
```

### 并发与限流

首次同步可能有上百个收藏帖。建议：

- 详情补全并发数限制为 2。
- 每批失败记录保留，下次同步继续补。
- UI 显示同步进度，不阻塞用户浏览已有缓存。
- 遇到登录失效时停止同步并提示登录。

## 漫画/小说模块同步规则

### 漫画

当收藏帖判定为漫画：

- `workId = yamibo:<tid>`
- 保存 `fid/typeid/tagName/title/author/translationGroup/intro/episodes/cover`
- 分类初始进入漫画模块“默认”分类，除非后续用户在漫画模块移动到自定义分类。
- 后续刷新由收藏同步触发或详情页手动刷新触发。

替代当前评分候选逻辑：

- `ComicDetector` 不再决定是否能进入漫画模块。
- 它可以保留为 debug 辅助，例如解析失败时记录原因。

### 小说

当收藏帖判定为小说：

- `workId = novel:<fid>:<tid>`
- 一个小说只对应一个主 `tid`。
- `NovelRefreshSeed` 传入 `fid/tid/typeid/tagName`。
- 刷新章节时使用规则化后的 `NovelEpisodeDiscoveryService`。

### 收藏消失时

当远程收藏中某个 tid 消失：

1. `favorite_threads.removed_at = now`。
2. 如果是漫画：
   - 从漫画 shelf 表中移除该 `comicId`。
   - 删除或标记由收藏同步产生的漫画缓存记录。
3. 如果是小说：
   - 从小说 shelf 表中移除该 `novelId`。
   - 删除或标记由收藏同步产生的小说缓存记录。
4. 不建议自动删除用户主动下载的存储文件。

这里要区分：

- 缓存：可以随收藏消失清理。
- 下载存储：用户主动下载的内容，除非用户明确删除，不应该静默删除。

## 收藏页 UI

### 主 Tab

文件：`lib/features/startup/presentation/main_shell_page.dart`

新增页面：

```dart
final _pages = const <Widget>[
  ForumHomePage(),
  FavoriteShelfPage(),
  ComicTabPage(),
  NovelTabPage(),
  MorePage(),
];
```

新增 destination：

```dart
NavigationDestination(
  icon: Icon(Icons.favorite_border),
  selectedIcon: Icon(Icons.favorite),
  label: '收藏',
),
```

Tab 顺序建议：论坛、收藏、漫画、小说、更多。因为收藏现在是漫画/小说数据入口，把它放在论坛之后更符合使用路径。

### FavoriteShelfAdapter

复用 `UnifiedShelfPage`：

```dart
class FavoriteShelfAdapter implements ShelfModuleAdapter {
  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.favorite; // 需要扩 enum

  @override
  String get moduleTitle => '收藏';

  @override
  LibraryDisplayMode get defaultDisplayMode => LibraryDisplayMode.list;
}
```

当前 `LibraryModuleKey` 只有 `comic/novel`，需要增加：

```dart
favorite
```

注意对应 `LocalLibraryStateRepository._moduleKeyToContentType` 也要增加映射，或者收藏模块不使用统一状态表的读写功能。

### 系统分类

收藏页系统分类：

- `favorite:comic`，展示名 `漫画`
- `favorite:novel`，展示名 `小说`
- `default`，展示名 `默认`

展示规则：

- “默认”没有内容时隐藏。
- “漫画”没有内容时隐藏。
- “小说”没有内容时隐藏。
- 自定义分类是否隐藏可以沿用当前统一书架逻辑；建议空自定义分类仍保留，方便用户管理。

如果 `UnifiedShelfController` 当前只对 default 做隐藏，需要给 adapter 增加一个可选分类可见性策略，或者让 `FavoriteShelfAdapter.loadCategories()` 只返回当前应该可见的系统分类。

### 列表项点击

收藏列表中 `workId` 建议使用 tid 作为稳定 key：

- 收藏普通帖：`favorite:<tid>`
- 收藏漫画：`favorite:<tid>`，内部记录有 `workId=yamibo:<tid>`
- 收藏小说：`favorite:<tid>`，内部记录有 `workId=novel:<fid>:<tid>`

`FavoriteShelfPage.onOpenWork` 根据本地记录决定跳转：

- `contentKind=comic` => `ComicDetailPage(comicId: record.workId!)`
- `contentKind=novel` => `NovelDetailPage(novelId: record.workId!)`
- 其它 => `ThreadDetailPage(tid: record.tid, subject: record.title)`

### 同步入口

`UnifiedShelfPage` 已有下拉刷新和 more 菜单“更新书架”。收藏 adapter 的 `refreshShelf()` 应调用 `FavoriteSyncService.sync()`。

首次进入收藏页：

- 先加载本地缓存。
- 如果没有 sync state，自动触发一次同步。
- 同步过程中可以显示顶部进度条或 snackbar。

## 禁用论坛模块旧收藏功能

当前论坛首页通过：

- `ForumHomeRepository`
- `FavoriteRepository.getFavoriteForums`
- `ForumHomeController._mapFavoriteForums`

展示“我收藏的版块”。

用户要求“论坛模块中的收藏功能先禁用”，建议阶段 03 做：

1. `ForumHomeRepository` 不再请求 `myfavforum`。
2. `ForumHomeController` 不再构造 favorite section。
3. `ForumHomePage` 删除或隐藏“暂无收藏版块”的特殊 UI。
4. 对应测试更新。

注意：这不影响“收藏 Tab”的 `myfavthread`。

## 测试建议

1. `FavoriteThreadsPage.fromVariables` 解析 count/perpage/list。
2. 首次同步会请求所有页。
3. count 增加时，只补新 tid。
4. count 减少时，完整 diff 并标记 removed。
5. `fid=30,tag!=公告` 的收藏同步进漫画模块。
6. `fid=49/55,tag!=公告` 的收藏同步进小说模块。
7. `公告` 收藏不会进入漫画/小说分类。
8. 收藏页系统分类计数满足：
   - 只有“漫画/小说/默认”三个分类时，它们的总数等于 active 收藏总数。
   - 默认分类不包含漫画和小说。
9. 取消收藏后，漫画/小说模块中对应作品消失。

## 完成标准

- 主 Tab 出现“收藏”。
- 首次进入收藏页能拉取全部收藏并缓存。
- 再次进入优先显示本地缓存，不重复大量进帖。
- 远程 count 变化时能做增量或完整 diff。
- 漫画/小说模块内容来自收藏同步。
- 论坛首页旧收藏版块入口已禁用。
