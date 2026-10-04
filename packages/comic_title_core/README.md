# comic_title_core

Y300 使用的本地纯 Dart 漫画标题核心，运行时只依赖 `petitparser`。
应用和工具统一通过 `package:comic_title_core/comic_title_core.dart` 消费，
不导入 `src`。包暂不发布。

```dart
import 'package:comic_title_core/comic_title_core.dart';

const analyzer = PetitComicTitleAnalyzer();
final analysis = analyzer.analyze('[Scan] Comic Title Vol.2');
// cleanBookName: Comic Title; episodeLabel: Vol.2; chapterNumber: 2
```

## 公开契约与兼容行为

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

`ComicSubjectMetadata` 映射、重复作品匹配、provider、搜索/刷新、数据库和 UI 归应用。
刷新和重复匹配继续使用完整名称；小说标题规则独立，不并入本包。

## 验证与样本归属

在本包目录执行：

```shell
dart pub get
dart analyze --fatal-infos
dart test --reporter expanded
dart run example/analyze_title.dart
```

包级测试覆盖公开 API、grammar/rules/number parser 原语与生成 Unicode 序列性质，
不依赖 Flutter、App 文件或私有 fixture。漫画标题语料仍只在仓库
`test/features/comic/domain/services/comic_title_parser_cases.dart` 添加和维护；
App analyzer 回归消费本包，subject/详情/收藏测试验证业务映射与完整标题刷新。
不复制语料或维护生成副本。仓库架构测试守护纯依赖、唯一公开入口及旧核心路径退役；
包级分析、测试、示例和 App 验证均已进入仓库 CI。
