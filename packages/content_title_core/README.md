# content_title_core

Y300 使用的本地纯 Dart 内容标题核心，漫画和小说策略分别位于 `src/comic` 与
`src/novel`。运行时依赖 `petitparser` 和 `characters`；应用和工具统一通过
`package:content_title_core/content_title_core.dart` 消费。包暂不发布。

```dart
import 'package:content_title_core/content_title_core.dart';

const analyzer = PetitComicTitleAnalyzer();
final analysis = analyzer.analyze('[Scan] Comic Title Vol.2');
// cleanBookName: Comic Title; episodeLabel: Vol.2; chapterNumber: 2

const sanitizer = DefaultNovelTitleSanitizer();
final title = sanitizer.sanitize('[Author] Novel Title Vol.2');
// title: Novel Title Vol.2
```

## 漫画策略

- `ComicTitleAnalyzer`、`PetitComicTitleAnalyzer`、`ComicTitleAnalysis` 提供分析入口和结果。
  `rawTitle` 保留 trim 后的原文；`cleanBookName` 保持完整，`searchKeyword` 最长为
  18 个 Unicode runes，不是 UTF-16 code units 或 grapheme clusters。
- `ComicTitleGrammar`、`ComicLeadingMetadata`、`ComicLeadingBracketToken` 暴露已有
  前缀元数据能力。只识别 `[` / `【` 前缀，空 token 消耗但不返回，未闭合内容留在 remainder。
- `ComicTitleRules` 保留现有规范化、author/group 提示与标记规则；不进行大小写或简繁转换。
- `ComicTitleNumberParser` 保留 ASCII/全角小数、中文、Roman 与圈号的 best-effort 转换；
  analyzer 的 `grammar` / `numberParser` 命名构造参数及 const 用法保持。
- 多语言章节、特殊标签、候选章节号顺序及 `extractTidFromUrl` 的宽容字符串提取保持。
  TID 提取只提供现有辅助能力，不验证 URL 的来源或请求权限。
- 章节范围保留完整 `episodeLabel`，`chapterNumber` 取范围起点并沿用分段修饰；
  `isChapterRange` 显式区分范围与候选数字，不通过候选号数量推断。裸范围和带章节单位
  的范围共用分隔符规则，日期、型号及无效裸范围不回退为最后一个数字。App 正文识别
  要求整个链接文字都是范围标签，合并仍按 TID 去重，一个帖子保留一个章节入口。

## 小说策略

- `NovelTitleSanitizer` / `DefaultNovelTitleSanitizer` 清洗作品标题：只解一层 `&amp;`，
  连续剥除行首英文、中文及全角方括号，保留正文内括号、更新日期及章节尾巴。
- `NovelChapterTitlePolicy` / `FirstMeaningfulSentenceNovelChapterTitlePolicy` 消费已准备的
  纯文本，跳过编辑通知、简介/目录标识，选取有效首句并按 grapheme clusters 截断。
  默认最多 36 个显示字符，保持 ACT13.5 等小数、emoji 和省略号规则；构造参数不变。

唯一 barrel 显式导出 12 个既有类型，不导出第三方类型或测试数据。两组规则和输出契约
分别维护。`ComicSubjectMetadata` 映射、重复作品匹配、provider、搜索/刷新、数据库和
UI 归应用，刷新和重复匹配继续使用完整名称；小说 HTML 准备、分页与同步也归应用。

## 验证与样本归属

在本包目录执行：

```shell
dart pub get
dart analyze --fatal-infos
dart test --reporter expanded
dart run example/analyze_title.dart
```

包级测试覆盖漫画完整语料、公开原语/生成性质，以及小说清洗和章节标题契约；
不依赖 Flutter、App 文件或私有 fixture。新增算法样本的唯一维护入口：

- 漫画：`test/fixtures/comic_title_fixtures.dart`。
- 小说：`test/fixtures/novel_title_fixtures.dart`。

应用仍维护漫画 subject 映射、重复匹配与交互 fixture。小说的原 App fixture 入口只在
测试层转发包内标题语料；HTML wrapper 持有同一纯章节 case，HTML/分页标识保留 App。
这是仓库内明确的测试复用边界，不属于生产 API。其它 App 文件不直接访问包测试目录，
包内测试也不反向读取 App。仓库架构守护限制纯依赖、公开入口、精确桥接和旧路径退役；
包级分析、测试、双策略示例和 App 验证均已进入 CI。
