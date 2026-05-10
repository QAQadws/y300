# 分阶段实现 01：标签与 typeid

本阶段目标是建立所有后续需求共用的标签基础能力：解析 `typeid`、用 `fid + typeid` 查标签名、让漫画/小说基础模型知道自带标签，并用统一规则判断帖子类型。

## 目标

1. `ThreadDetailData` 解析 `typeid`。
2. `assets/tag.json` 能被 Flutter 正确打包并加载。
3. 建立标签查询服务，通过 `fid + typeid` 得到标签名。
4. 漫画、小说本地模型和详情模型保存 `sourceTypeId/sourceTagName`。
5. 帖子详情页从“漫画评分候选”改为“标签规则判定”。
6. `UnifiedDetailPage` 在简介下方显示标签条：第一个为论坛自带标签，后续为用户自定义标签。

## 代码改动点

### 1. 声明 asset

当前 `pubspec.yaml` 没有声明 `assets/tag.json`。需要补充：

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/tag.json
```

注意：`assets/tag.json` 需要保持 UTF-8 编码。Windows PowerShell 输出中文可能会显示乱码，这不一定代表文件本身有问题；以 Flutter `rootBundle.loadString` 读取结果为准。

### 2. 扩展帖子详情模型

文件：`lib/features/thread/data/models/thread_detail_models.dart`

`ThreadDetailData` 增加字段：

```dart
final String typeid;
```

构造函数增加 `required this.typeid`。

`fromVariables` 中解析：

```dart
typeid: ParseUtils.asString(thread['typeid']),
```

如果发现部分接口把 `typeid` 放在 `Variables` 或帖子列表项中，可以再加 fallback：

```dart
typeid: ParseUtils.asString(
  thread['typeid'],
  fallback: ParseUtils.asString(variables['typeid']),
),
```

建议同步扩展 `ThreadDetailPageState`：

- `typeid`
- `sourceTagName`
- `contentKind`

这样 UI 和控制器不需要重复查标签。

### 3. 扩展论坛列表摘要

文件：`lib/features/forum/data/models/forum_display_models.dart`

如果 `forumdisplay` 返回的 `forum_threadlist` 中包含 `typeid`，建议在 `ForumThreadSummary` 中也解析：

```dart
final String typeid;

typeid: ParseUtils.asString(json['typeid']),
```

这样论坛列表可以直接显示标签；如果列表接口没有 `typeid`，则只在帖子详情页显示，不影响主流程。

文件：`lib/features/forum/presentation/forum_display_page.dart`

如果 `ForumThreadSummary.typeid` 非空，可以在 `ListTile.subtitle` 上方或标题前增加一个小标签。推荐复用后续 `_TagChip` 的轻量样式，不要做成醒目的实心 badge：

```dart
if (thread.sourceTagName != null)
  Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: _ForumThreadTag(label: thread.sourceTagName!),
  )
```

为了避免 UI 层读取 asset，建议由 `ForumDisplayController` 或 repository 映射时注入 `sourceTagName`。如果列表接口拿不到 `typeid`，就只在进入 `ThreadDetailPage` 后显示标签。

### 4. 新增标签模型和查询服务

推荐目录：

```text
lib/features/tags/data/forum_tag_repository.dart
lib/features/tags/domain/forum_tag_models.dart
lib/features/tags/domain/forum_tag_lookup.dart
lib/features/tags/data/tag_providers.dart
```

模型建议：

```dart
class ForumTagDefinition {
  const ForumTagDefinition({
    required this.fid,
    required this.typeid,
    required this.name,
  });

  final String fid;
  final String typeid;
  final String name;
}

class ForumBoardTagSet {
  const ForumBoardTagSet({
    required this.fid,
    required this.name,
    required this.tags,
  });

  final String fid;
  final String name;
  final List<ForumTagDefinition> tags;
}
```

查询对象建议：

```dart
class ForumTagLookup {
  ForumTagLookup(List<ForumBoardTagSet> boards)
      : _byFidTypeid = {
          for (final board in boards)
            for (final tag in board.tags) '${tag.fid}:${tag.typeid}': tag,
        };

  final Map<String, ForumTagDefinition> _byFidTypeid;

  ForumTagDefinition? find({
    required String fid,
    required String typeid,
  }) {
    return _byFidTypeid['$fid:$typeid'];
  }

  String? findName({
    required String fid,
    required String typeid,
  }) {
    return find(fid: fid, typeid: typeid)?.name;
  }
}
```

Provider 建议：

```dart
final forumTagLookupProvider = FutureProvider<ForumTagLookup>((ref) async {
  final raw = await rootBundle.loadString('assets/tag.json');
  final decoded = jsonDecode(raw) as List<dynamic>;
  final boards = decoded.map(ForumBoardTagSet.fromJson).toList();
  return ForumTagLookup(boards);
});
```

### 5. 新增统一内容分类服务

推荐目录：

```text
lib/features/thread/domain/thread_content_classifier.dart
```

建议实现：

```dart
enum ThreadContentKind {
  unknown,
  comic,
  novel,
  forum,
}

class ThreadContentClassifier {
  const ThreadContentClassifier();

  static const Map<String, String> announcementTypeIds = {
    '30': '65',
    '49': '121',
    '55': '147',
  };

  ThreadContentKind classify({
    required String fid,
    required String typeid,
    String? tagName,
  }) {
    final normalizedTag = tagName?.trim();
    final isAnnouncement =
        normalizedTag == '公告' || announcementTypeIds[fid] == typeid;

    if (fid == '30' && !isAnnouncement) {
      return ThreadContentKind.comic;
    }

    if ((fid == '49' || fid == '55') && !isAnnouncement) {
      return ThreadContentKind.novel;
    }

    return ThreadContentKind.forum;
  }
}
```

### 6. 替换帖子详情页候选逻辑

文件：`lib/features/thread/presentation/thread_detail_controller.dart`

当前 `_detectAndParseComic` 依赖 `ComicDetector` 评分。阶段 01 后建议：

1. 首屏加载帖子详情后拿到 `data.fid` 和 `data.typeid`。
2. 通过 `ForumTagLookup` 得到 `tagName`。
3. 通过 `ThreadContentClassifier` 得到 `contentKind`。
4. `contentKind == comic` 时才解析漫画首楼并显示漫画入口。
5. `contentKind == novel` 时显示小说入口。

旧 `ComicDetector` 可以暂时保留给调试或测试，但不再作为用户可见入口的判定依据。

伪代码：

```dart
final lookup = await ref.read(forumTagLookupProvider.future);
final tagName = lookup.findName(fid: data.fid, typeid: data.typeid);
final kind = ref.read(threadContentClassifierProvider).classify(
  fid: data.fid,
  typeid: data.typeid,
  tagName: tagName,
);

final isComic = kind == ThreadContentKind.comic;
final parsedComicPost = isComic
    ? parser.parse(message: aggregation.parseMessage).copyWith(
        subjectMetadata: subjectParser.parse(subject),
      )
    : ParsedComicPost.empty;
```

文件：`lib/features/thread/presentation/thread_detail_page.dart`

按钮文案从“漫画候选（评分 xx）”改为更直接的标签结果：

- `漫画 · <标签名>`
- `小说 · <标签名>`

如果标签名为空，可以退化为：

- `漫画 · typeid=<typeid>`
- `小说 · typeid=<typeid>`

### 7. 扩展漫画模型

相关文件：

- `lib/features/comic/domain/models/comic_detail_models.dart`
- `lib/features/comic/domain/models/comic_shelf_models.dart`
- `lib/features/comic/data/local/comic_local_models.dart`
- `lib/features/comic/data/local_comic_repository.dart`
- `lib/features/comic/data/comic_repository.dart`
- `lib/features/comic/presentation/adapters/comic_shelf_adapter.dart`
- `lib/features/comic/presentation/adapters/comic_detail_adapter.dart`

建议给漫画主记录增加：

```dart
final String? sourceTypeId;
final String? sourceTagName;
```

SQLite `comics` 表新增列：

```sql
ALTER TABLE comics ADD COLUMN source_typeid TEXT;
ALTER TABLE comics ADD COLUMN source_tag_name TEXT;
```

`addToShelf` 或后续收藏同步写入漫画时，要带入：

- `fid`
- `typeid`
- `tagName`

详情适配器 `ComicDetailAdapter.loadHeader` 将 `sourceTagName` 映射到统一详情 header。

### 8. 扩展小说模型

相关文件：

- `lib/features/novel/data/models/novel_models.dart`
- `lib/features/novel/data/models/novel_local_models.dart`
- `lib/features/novel/data/local_novel_repository.dart`
- `lib/features/novel/data/novel_repository.dart`
- `lib/features/novel/presentation/adapters/novel_shelf_adapter.dart`
- `lib/features/novel/presentation/adapters/novel_detail_adapter.dart`

小说当前存在通用 `works` 表。建议给 `works` 表新增：

```sql
ALTER TABLE works ADD COLUMN source_typeid TEXT;
ALTER TABLE works ADD COLUMN source_tag_name TEXT;
```

`NovelRefreshSeed` 增加：

```dart
final String? typeid;
final String? tagName;
```

`upsertNovelBySeed` 保存到 `works` 表。

### 9. 扩展统一详情模型

文件：`lib/features/library_shared/domain/models/library_models.dart`

`LibraryDetailHeader` 建议增加：

```dart
final String? sourceTagName;
final String? sourceTypeId;
final List<LibraryTag> customTags;
```

如果不想让 `LibraryDetailHeader` 直接携带自定义标签，也可以在 `UnifiedDetailState` 增加：

```dart
final List<LibraryTag> customTags;
```

推荐放在 header 里，因为它属于详情头部/简介区域展示信息。

漫画/小说的 detail adapter 在 `loadHeader` 中同时读取：

- 主表的 `sourceTagName/sourceTypeId`
- `LibraryStateRepository.getWorkTags`

### 10. 在统一详情页展示标签条

文件：`lib/features/library_shared/presentation/pages/unified_detail_page.dart`

位置：简介区域下方、章节数量上方。

建议新增 `_TagStrip`：

```dart
class _TagStrip extends StatelessWidget {
  const _TagStrip({
    required this.sourceTagName,
    required this.sourceTypeId,
    required this.customTags,
  });

  final String? sourceTagName;
  final String? sourceTypeId;
  final List<LibraryTag> customTags;

  @override
  Widget build(BuildContext context) {
    final labels = <String>[
      if (sourceTagName?.trim().isNotEmpty == true) sourceTagName!.trim(),
      ...customTags.map((e) => e.name.trim()).where((e) => e.isNotEmpty),
    ];
    if (labels.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            _TagChip(label: labels[i]),
            if (i != labels.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}
```

标签样式：方形圆角、中空、文字居中。

```dart
class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}
```

## 测试建议

1. `ThreadDetailData.fromVariables` 能解析 `typeid`。
2. `ForumTagLookup` 能通过 `fid=30,typeid=65` 找到 `公告`。
3. `ThreadContentClassifier`：
   - `fid=30,typeid=65,tag=公告` => `forum`
   - `fid=30,typeid=398` => `comic`
   - `fid=49,typeid=121` => `forum`
   - `fid=49,typeid=293` => `novel`
   - `fid=55,typeid=147` => `forum`
   - `fid=55,typeid=295` => `novel`
4. 帖子详情页不再出现“评分候选”文案。
5. 统一详情页在简介下方显示自带标签和自定义标签。

## 完成标准

- `ThreadDetailData`、漫画记录、小说记录都能携带 `typeid`。
- 收藏同步尚未实现时，帖子详情页已经能用标签规则判定漫画/小说。
- `UnifiedDetailPage` 能展示“自带标签 + 自定义标签”。
- 不依赖远程图片 URL 或收藏同步即可完成本阶段测试。
