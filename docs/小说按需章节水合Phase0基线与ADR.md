# 小说按需章节水合 Phase 0 基线与 ADR

> 状态：已完成
> 日期：2026-07-13
> 关联方案：`docs/小说按需章节水合与增量更新分阶段实施方案.md`
> 范围：fixture、契约测试、迁移基线和架构决策；不切换生产链路

## 1. 阶段结论

Phase 0 已建立后续改造需要的输入样本、请求契约和数据保护基线，但没有修改生产行为。

当前事实与目标事实必须分开理解：

- 当前收藏详情通过共享 `ApiThreadRepository` 加载，未显式传版本时由 API client 使用默认 `version=4`。
- `FavoriteDetailContext` 已经持有这份 `ThreadDetailData`，`NovelFavoriteContentIngestHandler` 也会把同一个对象实例传给小说 ingest service。
- 当前 `RepositoryNovelFavoriteIngestService` 仍会调用 `upsertNovelBySeed()` 和 `refreshEpisodes()`，因此“分类为小说后零个额外请求”尚未成为生产事实；该切换属于 Phase 2。
- 当前 `ApiNovelThreadGateway` 已固定 `version=1` 和 `ppp=200`，但尚未携带 `authorid`；语义化 gateway 和生产调用切换属于 Phase 1。
- Phase 0 通过共享 API client 请求探针固定目标 query，防止 Phase 1 对参数语义继续猜测。

因此，Phase 0 的完成含义是“后续改造有可执行护栏”，不是“目标小说同步链路已经上线”。

## 2. Fixture 基线

fixture 位于 `test/features/novel/fixtures/phase0/`，只作为测试输入，不加入 Flutter assets，也不会进入 release 包。

| 文件 | API 语义 | 用途 |
| --- | --- | --- |
| `favorite_detail_v4_later_posts_unsafe.json` | 收藏通用 `version=4` page 1 | 首楼含发布者、简介和来源目录；后续楼包含旧百分号编码 URL 与不完整 HTML |
| `author_posts_v1_observed_page_1_default_ppp.json` | 用户提供的真实 `version=1 + authorid=121222` page 1；未传 `ppp` | 固定服务端默认 `ppp=20`、过滤后 replies 和楼层重编号语义 |
| `author_posts_v1_page_1.json` | `version=1 + ppp=200 + authorid=406769`, page 1 | 楼主过滤抓取第一页的脱敏边界摘录 |
| `author_posts_v1_page_2.json` | 同上，page 2 | 固定过滤页 2 与普通页 265 的坐标差异 |
| `author_posts_v1_page_3.json` | 同上，page 3 | 固定过滤页 3 与普通页 722 的坐标差异和末页 23 条语义 |

### 2.1 数据来源和脱敏

- 用户提供的 `tid=564823` 完整 API 响应经脱敏后保留了真实的 20 个 PID、作者、序号和时间；认证字段与约 29 万 UTF-8 字节正文未写入仓库。
- 该响应证明：只传 `authorid` 不会自动启用 `ppp=200`；服务端返回默认 `ppp=20`。它还证明 `thread.replies` 是过滤后的 38 个回复，而 `thread.allreplies=181` 是普通全帖回复数，过滤结果的 `post.number` 被重编号为 `1..20`。
- 三页目标样本基于仓库已有的真实长篇小说线程 `tid=521519` 的本地 HTML 捕获整理，并按上述真实 API 字段语义校正。
- 楼主 UID `406769`、目录 PID 边界和 423 个目录项来自该本地样本。
- `pid=40692958` 的普通页 265、`pid=41397522` 的普通页 722，于 2026-07-13 通过公开 `findpost` 301 跳转只读核对。
- fixture 不保存 cookie、auth、formhash、完整帖子正文或用户隐私数据。
- 章节正文替换为短占位文本；每个 200 条响应只保留首尾代表项，并通过 `FixtureMetadata.originalPostCount` 记录原始分页计数。因此它们适合契约和边界测试，不应被误用为性能样本。

### 2.2 `version=4` 危险后续楼

首楼是可消费的元数据来源。后续楼 `pid=40213902` 包含 GBK 风格 `%D2...` 旧编码 query；直接读取 Dart `Uri.queryParameters` 会抛 `FormatException`。另一个后续楼保留不完整 HTML 结构。

Phase 2 的 `NovelSourceMetadataParser` 必须只取得 `posts.first`，不得遍历、预验证、复制或标准化其余楼层。后续楼损坏不能阻断首楼元数据入库。

## 3. 请求契约基线

目标 author-page 请求固定为：

~~~text
GET api/mobile/index.php
  ?module=viewthread
  &tid=<tid>
  &page=<author-filtered-page>
  &version=1
  &ppp=200
  &authorid=<publisherId>
~~~

约束：

1. `version=1` 必须显式传入，不能依赖全局默认版本。
2. `ppp=200` 必须显式传入。
3. `authorid` 必填且来自首楼发布者 ID。
4. 不允许降级成不带 `authorid` 的全帖抓取。
5. Phase 0 的请求探针只验证共享 API client 能准确表达并解析该契约；Phase 1 再把生产 gateway 收窄为 `loadAuthorPostsPage(...)`。

用户提供的对照请求没有 `ppp`，真实响应因此为 `ppp=20`。这不是目标请求的替代形式，而是“`authorid` 与分页大小互相独立”的契约证据。

## 4. 收藏详情复用基线

现有测试现在锁定以下边界：

- `DefaultFavoriteDetailContextLoader.load(..., preloadedDetail: detail)` 不调用详情 loader。
- 返回的 `FavoriteDetailContext.detail` 与传入对象保持 `identical`。
- `NovelFavoriteContentIngestHandler` 把 context 中的同一个 detail 对象传给小说 ingest service，不复制、不重新加载。

Phase 2 需要在此边界后替换 repository ingest：只本地摄取首楼元数据，并删除 `upsertNovelBySeed + refreshEpisodes` 的收藏调用。届时增加生产 service 的“gateway 调用数为 0”测试；Phase 0 不用 fake 掩盖当前仍存在的额外请求。

## 5. DB 28 用户数据保护基线

`novel_phase0_persistence_baseline.dart` 提供可复用的 seed/read helper。当前测试在 DB 28 写入、关闭、重开并逐字段核对：

| 用户数据 | 表 / 载体 | 已固定字段 |
| --- | --- | --- |
| 小说详情 | `works` | 来源 ID、标题、作者、远端/本地/自定义封面 |
| 章节和正文 | `work_episodes`, `novel_episode_content` | PID、旧 source page、顺序、HTML、纯文本、段落 JSON |
| 书架关系 | `novel_shelf_items` | 分类和用户排序 |
| 用户简介/最近阅读 | `library_work_state` | `intro_text`, `last_read_episode_id` |
| 已读/下载/书签摘要 | `library_episode_state` | 三个状态位及时间 |
| 阅读进度 | `novel_reading_progress` | flow、页码、anchor、offset、百分比 |
| 阅读器书签 | `reader_bookmarks` | 定位、标题、摘要、用户备注 |
| 下载文件协议 | `novel_download_service_test.dart` | `.nomedia`、`meta.json`、章节 JSON 的往返读取 |

Phase 1 的 DB 28 -> 29 测试必须复用同一 helper：先用 28 schema seed，再执行真实增量迁移，最后读取相同快照，并额外断言新 source state/staging 表。不得用“新建 DB 29 后再写数据”的测试替代迁移验证。

## 6. ADR-001：来源目录不是章节权威

### 状态

Accepted。

### 决策

首楼解析出的目录只保存为 source metadata。章节集合、章节顺序和章节标题均由 `version=1 + ppp=200 + authorid` 返回的楼主楼层建立。

### 原因

- 来源目录可能缺项、重复、过期或只有部分链接。
- 目录链接标题不是稳定的章节正文标题来源。
- 把目录同时用于简介边界、章节生成和路由会重新制造多职责 parser。
- 稳定章节身份应为 `novelId + ':' + pid`，而不是目录位置或目录文字。

### 后果

- 目录可以用于来源核对、诊断和未来独立展示。
- 目录不得生成占位章节，也不得决定章节删除。
- 简介 parser 可以把“目录”视为右边界，但不得因此读取第二楼及后续楼层。

## 7. ADR-002：author-filtered page 禁止用于帖子路由

### 状态

Accepted。

### 决策

`authorid + ppp=200` 的过滤页码只属于小说章节同步 checkpoint。跳转原帖必须使用 `tid + pid` 经 `ThreadPostLocator/findpost` 解析普通帖子页码。

### 证据

| PID | author-filtered page | 普通帖子 page |
| --- | ---: | ---: |
| `40692958` | 2 | 265 |
| `41397522` | 3 | 722 |

### 后果

- `NovelEpisodeItem.sourcePage` 在新链路中只能解释为 author-filtered crawl page，不能直接传给 `ThreadDetailPage.initialPage`。
- 原帖打开能力依赖稳定 PID 定位；定位失败必须报错或提供打开帖子首页的显式备选。
- Phase 4 的路由测试必须复用上述反例，防止两个页码坐标再次混淆。

## 8. Phase 0 测试入口

~~~text
flutter test test/features/novel/data/novel_phase0_api_fixture_contract_test.dart
flutter test test/features/novel/data/novel_thread_gateway_test.dart
flutter test test/features/favorites/data/favorite_detail_context_loader_test.dart
flutter test test/features/favorites/data/favorite_content_ingest_handler_test.dart
flutter test test/features/novel/data/novel_phase0_persistence_baseline_test.dart
flutter test test/features/novel/data/novel_download_service_test.dart
~~~

## 9. 下一阶段入口条件

Phase 1 开始前不得改写这些基线。Phase 1 应先新增领域状态和 DB 29 增量迁移，再建立语义化 author-page gateway 和 700ms governor。收藏同步的生产切换留在 Phase 2，以便每一阶段都能独立回退和 review。
