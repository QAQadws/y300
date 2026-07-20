# 小说阅读器 HTML-first 混合分页分阶段实施方案

> 状态：方案设计，尚未实施
>
> 编写日期：2026-07-20
>
> 适用范围：小说阅读器的新 HTML-first 分页模式
>
> 关联文档：
> - `docs/小说阅读器分页算法重构与性能优化方案.md`
> - `docs/小说阅读器全新分页阅读模式分阶段实施方案.md`
> - `docs/开发文档.md`

## 1. 结论先行

当前小说分页使用“候选 HTML + `flutter_widget_from_html_core` 真实测量”的方案 A。它能最大程度复用现有 HTML-first 视觉管线，但长章节首次分页会产生大量重复的 HTML 解析、Widget 构建和 Flutter Layout。

对于 80 页左右的正文，当前 Debug 模式已经出现约 100 秒的布局计算时间。这说明继续调整二分次数、缓存容量或事件循环让出频率，不能从根本上解决问题。后续分页应重构为混合分页：

```text
规范化 SQLite 正文
  -> 现有 ForumHtmlRenderPreparer
  -> prepared HTML / render document
  -> pagination atoms
  -> 分类
       |-- 安全纯文本
       |     -> TextSpan/TextPainter 增量分页
       |
       |-- 普通正文图片
       |     -> 独立图片页
       |
       |-- ruby/rt 注音
       |     -> rubyInline 复杂 block
       |
       |-- 折叠、表格、图片、WidgetSpan、复杂 HTML
             -> ForumHtmlWidgetPostRenderer 原子测量
  -> 页面组合
  -> 有界真实 renderer 校验
  -> NovelReaderPaginationPlan
  -> 继续使用 ForumHtmlWidgetPostRenderer 展示最终页面
```

核心决策：

1. `TextPainter` 只负责安全纯文本的分页边界计算，不负责最终 HTML 视觉渲染。
2. `flutter_widget_from_html_core` 继续作为最终页面的视觉渲染权威。
3. 复杂 HTML 不强行转换成 TextSpan，不用 TextPainter 近似表格、折叠块、图片或 WidgetSpan。
4. 普通正文图片继续独立成页，避免图片尺寸不确定性污染前后文字页。
5. 复杂内容默认作为原子 block，先保证页序、交互和恢复稳定，再考虑细粒度优化。
6. 分页派生数据只保存在进程内缓存，小说离线正文仍唯一来自规范化 SQLite 正文。

## 2. 样本 HTML 证据与范围

本方案以以下文件作为主要兼容样本：

- `docs/html/特殊格式/文字背景色.html`
- `docs/html/特殊格式/折叠目录.html`
- `docs/html/特殊格式/字颜色字号.html`
- `docs/html/特殊格式/注音.html`

用户消息中重复出现的 `折叠目录.html` 视为同一份 fixture，不建立第二份语义基线。

### 2.1 主楼正文边界

小说导入的主要正文应继续使用现有帖子解析和水合链路得到的主楼 message HTML。分页器不能重新从完整论坛页面猜测正文，也不能把帖子标题、作者、楼层 header、点评、评分或 footer 作为小说正文分页。

现有职责保持：

```text
小说 repository
  -> SQLite novel_episode_content
  -> NovelReaderController
  -> NovelHtmlChapterRenderPreparer
  -> ForumHtmlPreparedRenderDocument
  -> NovelReaderPaginationAtomExtractor
```

分页只接收已经准备好的章节视觉文档，不读取网络、不访问 SQLite、不重建小说正文副本。

### 2.2 背景色、字色和字号样本

`文字背景色.html` 与 `字颜色字号.html` 的主楼 message 包含：

- 多层嵌套 `<font>`。
- `color` 属性、命名颜色和十六进制颜色。
- `style="color:..."`。
- `style="background-color:..."`。
- `style="font-size:...px"`。
- `font size="3"` 至 `font size="6"` 等 Discuz 字号语义。
- `font face="..."` 字体族提示。
- `<strong>`、链接、多个 `<br>`、`&nbsp;` 和连续空白。
- 背景色包裹文字，而不是只给整个段落设置背景。
- 图片和图片链接可能出现在正文附近或正文内部。

因此，安全文字路径不能只读取 `element.text`。它必须保留每个文字 run 的文本范围、颜色、背景色、字号、粗细、斜体、字体族映射、链接身份和稳定 anchor。

### 2.3 折叠目录样本

`折叠目录.html` 使用 Discuz 特殊结构：

```html
<div class="showcollapse_box">
  <div class="showcollapse_title">...</div>
  <div class="showcollapse_content">...</div>
  <div class="showcollapse_gather">收起</div>
</div>
```

样本还包含：

- `.showcollapse_active` 初始展开状态。
- 默认折叠和初始展开两种状态。
- 嵌套折叠 block。
- `onclick` 中通过 class 切换状态。
- 折叠内容中的链接、文字和可能存在的图片。

分页器不能执行 HTML JavaScript。折叠语义必须继续由现有 `ForumCollapseBlock` 负责，HTML class 只用于初始状态和稳定 block identity。

### 2.4 注音样本

`注音.html` 的小说正文使用标准 ruby 结构：

```html
<ruby>特莉絲<rt>トリス</rt></ruby>
<ruby>鬼魂<rt>Ghost</rt></ruby>
<ruby>召<rt>・</rt></ruby>
```

当前 fixture 包含 47 个 `<ruby>` 和 47 个 `<rt>`，没有 `<rp>`。注音内容既有日文假名，也有英文和间隔点，且 ruby 与前后普通文字处于同一行内排版上下文。

ruby 不能直接进入普通 TextPainter safe path：

- `rt` 位于基础文字上方，会增加 line box 高度。
- ruby cluster 的实际宽度可能由基础文字或注音中较宽的一方决定。
- 基础文字和 `rt` 必须作为不可拆分的 inline cluster。
- 把 `rt` 当普通正文会改变文本顺序、行宽、搜索摘要和页边界。
- `flutter_widget_from_html_core` 已经负责最终 ruby 渲染，分页不能建立不兼容的简化规则。

第一版将“包含 ruby 的整个行内 block”路由到 `rubyInline`/complex renderer，不只截出单个 `<ruby>` 后再与 TextPainter 行拼接。后续如性能需要，可实现专用 Ruby layout adapter，但必须先与最终 renderer 做 fixture/golden 一致性验证。

### 2.5 表格范围

小说主楼有时包含 `<table>`、`<tr>`、`<td>`、`<th>`。表格不是第一版 TextPainter 安全子集，因为单元格换行、共同列宽、border/padding/background、colspan/rowspan 和 viewport 都会影响高度。

第一版把表格视为复杂原子 block。只有真实样本和 renderer 行为稳定后，才考虑独立的表格布局测量器。

## 3. 目标与非目标

### 3.1 目标

- 80 页以上的文字型长章节不再为每个文本候选反复构建 HTML Widget。
- 首屏能够在可接受时间内显示。
- 普通段落、简单颜色、背景色、字号、粗体、斜体和链接保持视觉语义。
- 折叠目录保持默认状态、嵌套和点击交互。
- 表格不被截断、不被错误转换为普通文本。
- ruby 基础文字和注音保持成对、不可拆分，不能把 `rt` 摊平成正文。
- 复杂 block 的空白来源和 overflow 状态可解释。
- 现有 anchor、书签、搜索定位、章节恢复和阅读进度语义保持不变。
- 纵向和分页模式共用同一份 prepared HTML、主题、图片序列和 renderer policy。

### 3.2 非目标

- 不重新实现完整 CSS 引擎。
- 不把所有 HTML 转成另一套独立 Flutter 文档模型。
- 不用 TextPainter 近似表格、折叠内容、图片或复杂 Widget。
- 不在第一版用普通 TextSpan 近似 ruby 注音排版。
- 不把分页 HTML 写入 SQLite、作品 metadata 或下载目录。
- 不改变小说正文水合协议，网络请求继续使用 `version=1`。
- 不复制第二份离线正文或导出 EPUB/ZIP。
- 不在第一版实现跨页面表格拆行。
- 不为了提高填充率修改用户字号、行高、颜色或背景色。

## 4. 模块边界

### 4.1 继续复用的模块

| 现有模块 | 混合分页中的职责 |
| --- | --- |
| `NovelReaderHtmlPreparationService` | 生成 prepared HTML 和 render document |
| `NovelHtmlChapterRenderPreparer` | 复用 HTML 清洗、繁简转换、图片和主题准备 |
| `NovelReaderPaginationAtomExtractor` | 提取 atom、文本 offset、图片 index 和 anchor |
| `ForumHtmlStylePolicy` | 提供样式分类和复杂 block 判定依据 |
| `ForumHtmlWidgetPostRenderer` | 最终渲染、复杂 block 测量和有界校验 |
| `ForumCollapseBlock` | 折叠目录 Flutter 交互和展开状态 |
| `NovelReaderPaginationCache` | 缓存完整 plan |
| `NovelReaderPaginationMeasureCache` | 缓存复杂 block 和校验 metrics |
| `NovelReaderPreparedChapterCache` | 缓存 prepared document |
| `NovelReaderPaginationRestorePolicy` | 按 key、anchor 和百分比恢复位置 |
| `NovelReaderProgressCommitter` | 只接收真实可见页 |

### 4.2 新增模块

新增代码优先放在 `lib/features/novel/presentation/services/`：

```text
novel_reader_pagination_atom_classifier.dart
novel_reader_pagination_text_run_extractor.dart
novel_reader_pagination_text_style_adapter.dart
novel_reader_text_pagination_engine.dart
novel_reader_ruby_pagination_adapter.dart
novel_reader_complex_block_pagination_engine.dart
novel_reader_hybrid_pagination_planner.dart
novel_reader_pagination_renderer_validator.dart
novel_reader_pagination_page_composer.dart
novel_reader_pagination_performance_policy.dart
```

如果 `ForumHtmlStylePolicy` 无法直接提供 TextStyle，应在 `thread/presentation/html_rendering/` 增加共享 style resolution port，而不是在 novel 中复制颜色、字号和背景色解析。

## 5. 设计原则

### 5.1 单一视觉权威

`ForumHtmlWidgetPostRenderer` 仍是最终视觉权威。TextPainter 只做规划阶段的快速范围计算。

### 5.2 保守分类

只要 atom 高度依赖未知 Widget、图片尺寸、复杂 CSS 或容器共同布局，就归为复杂 atom。错误地把复杂内容归入 TextPainter，比少走 fast path 更危险。

### 5.3 可降级

降级顺序：

```text
TextPainter safe path
  -> 当前 atom 使用真实 HTML renderer
  -> 当前章节分页失败
  -> 回到纵向 HTML-first 阅读
```

不能把失败候选当作高度 0，也不能显示空白页后继续推进。

### 5.4 规划与渲染分离

planner 不持有 `PageController`、`BuildContext`、SQLite repository 或进度写入器。真实 HTML 测量通过 interface 注入，最终页面由 paged surface 展示。

### 5.5 不改变正文来源

所有分页结果都是水合 SQLite 正文的 process-local 派生数据。清理缓存不会删除正文，取消收藏时仍由现有 purge 链路删除正文、进度和书签。

## 6. 领域模型与接口

### 6.1 Atom 路由

```dart
enum NovelReaderPaginationRoute {
  safeText,
  rubyInline,
  isolatedImage,
  collapseBlock,
  tableBlock,
  complexHtml,
}

final class NovelReaderClassifiedPaginationAtom {
  const NovelReaderClassifiedPaginationAtom({
    required this.atom,
    required this.route,
    required this.isBreakable,
    required this.reason,
  });

  final NovelReaderPaginationAtom atom;
  final NovelReaderPaginationRoute route;
  final bool isBreakable;
  final String reason;
}
```

`reason` 只记录稳定诊断枚举，例如 `containsRuby`、`containsWidgetSpan`、`containsTable`、`unsupportedStyle`，不能记录正文 HTML。

### 6.2 Text run

```dart
final class NovelReaderPaginationTextRun {
  const NovelReaderPaginationTextRun({
    required this.text,
    required this.style,
    required this.startAnchor,
    required this.endAnchor,
    required this.htmlNodeId,
    this.href,
    this.isParagraphBreak = false,
  });

  final String text;
  final TextStyle style;
  final NovelReaderTextAnchor startAnchor;
  final NovelReaderTextAnchor endAnchor;
  final String htmlNodeId;
  final String? href;
  final bool isParagraphBreak;
}
```

该模型属于 presentation service，因为 `TextStyle` 和 `TextPainter` 属于 Flutter。稳定 anchor 仍来自现有 novel domain model。

### 6.3 Text metrics

```dart
final class NovelReaderTextLayoutMetrics {
  const NovelReaderTextLayoutMetrics({
    required this.runId,
    required this.lineRanges,
    required this.totalHeight,
    required this.width,
    required this.typographySignature,
  });

  final String runId;
  final List<NovelReaderTextLineRange> lineRanges;
  final double totalHeight;
  final double width;
  final String typographySignature;
}
```

metrics key 至少包含 content hash、run/range、viewport width、typography、theme/style revision 和 text layout adapter revision。

### 6.4 Complex block port

```dart
abstract interface class NovelReaderComplexBlockMeasurer {
  Future<NovelReaderComplexBlockMetrics> measure({
    required NovelReaderClassifiedPaginationAtom atom,
    required NovelReaderPaginationViewport viewport,
    required NovelReaderPaginationKey key,
  });
}
```

实现可以依赖 `ForumHtmlWidgetPostRenderer` 和 offstage probe，但不能写 plan、进度或 repository。

### 6.5 Hybrid planner

```dart
abstract interface class NovelReaderHybridPaginationPlanner {
  Future<NovelReaderPaginationPlan> plan({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
    required NovelReaderPaginationViewport viewport,
    required NovelReaderPaginationCancellationToken cancellationToken,
  });
}
```

planner 只负责 atom 路由、safe text 分页、complex block 决策、图片页、页面组合、anchor 和有界校验。章节切换、PageView、进度、SQLite 和下载不属于 planner。

## 7. 样式兼容策略

### 7.1 样式来源只能有一套

不能在小说分页器中重新解释 `font`、`color`、`background-color` 和 `font-size`。应复用现有 preparation 和 `ForumHtmlStylePolicy` 的结果。

建议增加共享 port：

```dart
abstract interface class ForumHtmlTextStyleResolver {
  ForumHtmlResolvedTextStyle resolveTextStyle({
    required html_dom.Element element,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required ForumHtmlResolvedTextStyle parent,
  });
}
```

Flutter adapter 输出颜色、背景色、字号、粗细、斜体、字体族、行高、方向和对齐。

### 7.2 颜色与背景色

- `font color` 和 inline style color 沿用现有作者颜色/主题适配。
- inline text background 可以映射为 `TextStyle.backgroundColor`。
- block background、padding、border、圆角一律归为 complex HTML。
- 背景包裹图片或 WidgetSpan 时归为 complex。
- 主题改变时 metrics 和 plan cache 必须失效。

### 7.3 字号

Discuz `<font size="1..7">` 已有共享字号语义。分页器必须使用准备阶段归一化后的字号，不能再次解释原始 size。

inline `font-size:27.2px` 只有在共享 resolver 能输出与 final renderer 相同的逻辑字号时进入 safe path，否则标记 `unsupportedStyle`。

### 7.4 字体族

`font face` 是布局敏感属性：

1. resolver 将 HTML 字体映射到平台可用字体。
2. 已知且可用字体进入 TextPainter。
3. fallback 无法保证与 final renderer 一致时，该 block 进入 complex path。
4. 字体加载或系统字体变化时增加 typography revision。

### 7.5 链接

链接文字可以进入 safe path，run 保留 href 和 anchor，最终点击仍由 `ForumHtmlWidgetPostRenderer` 提供。

### 7.6 Ruby 注音

第一版分类规则：

```text
inline formatting context contains ruby/rt/rp
  -> route = rubyInline
  -> containing inline block is non-breakable by TextPainter
  -> ForumHtmlWidgetPostRenderer measures the block once
```

不能只把 `<rt>` 隐藏后按基础文字分页，因为 final renderer 的 ruby 会增加高度并影响换行。也不能将 `<rt>` 拼接为括号文本，这会改变用户实际看到的内容。

ruby cluster 的 anchor 规则：

- 保留现有 prepared DOM 的 source range，不执行数据库迁移。
- 基础文字和 `rt` 的 source offset 不得在分页切分中分离。
- 页面搜索和书签优先锚定 ruby 所在语义 node/cluster 起点。
- 第一版不在 ruby 内部生成分页断点。
- 如果未来支持 `<rp>`，继续交给 final renderer 处理 fallback 语义。

未来可选的 `NovelReaderRubyPaginationAdapter` 应输出 ruby cluster metrics：

```dart
final class NovelReaderRubyClusterMetrics {
  const NovelReaderRubyClusterMetrics({
    required this.baseRange,
    required this.annotationRange,
    required this.width,
    required this.height,
    required this.baselineOffset,
  });
}
```

专用 adapter 只有在以下条件全部满足后才能进入 fast path：

- cluster 宽度、总高度和 baseline 与 `flutter_widget_from_html_core` 在允许误差内。
- CJK、假名、英文和间隔点注音通过 fixture/golden。
- 相邻多个 ruby cluster 和普通文字的换行一致。
- renderer revision 和 metrics key 包含 ruby adapter revision。

## 8. 折叠目录策略

### 8.1 折叠是原子组件

`.showcollapse_box` 一律路由到 `collapseBlock`，不把 title/content/gather 摊平成普通文字。

### 8.2 初始状态

```text
存在 showcollapse_active -> initialExpanded = true
否则                     -> initialExpanded = false
```

fixture 必须锁定默认状态，分页器不能强制全部展开或折叠。

### 8.3 页内行为

分页不能因为点击折叠导致后续 page index 随意漂移。推荐：

- 折叠 block 在当前页或下一页作为独立 block。
- 展开内容使用受限 viewport/inner scroll。
- 展开只影响 block 内部，不重新切割后续 page fragments。
- 如现有 `ForumCollapseBlock` 不支持页内约束，为分页模式增加 adapter，不修改纵向默认行为。

若以后允许展开后重新分页，必须建立新 layout revision 并按 anchor 恢复，不能隐式改变现有 PageView。

### 8.4 测量预算

```text
collapsed state:        1 次真实测量
initial expanded state: 1 次真实测量
用户展开:               不重新测量整章
```

## 9. 表格策略

### 9.1 第一版作为复杂原子 block

```text
table fits remaining height
  -> 放入当前页

table does not fit and current page non-empty
  -> flush current page
  -> table 独立页

table exceeds page height
  -> requiresInnerScroll = true
  -> 不裁切、不静默拆行
```

### 9.2 第一版不拆表格行

拆行必须同时处理 thead 重复、colspan/rowspan、列宽、边框、合法 HTML 和横纵滚动。在没有稳定样本和独立 table adapter 前，不做表格跨页拆分。

## 10. 混合分页算法

### 10.1 预处理

```text
prepared chapter
  -> extract atoms
  -> classify all atoms
  -> safe text -> text runs
  -> complex atom -> block metrics request
```

分类先于分页，不能等候选超高后再临时猜测类型。

### 10.2 安全文本布局

连续 safe text runs：

1. 按 DOM 顺序生成 TextSpan。
2. 复用共享 style resolver。
3. 按 viewport 宽度一次布局 run/paragraph。
4. 得到行范围和行高。
5. 将完整行按当前页剩余高度加入 composer。
6. 在合法 line/range 边界生成 HTML fragment。
7. 记录起止 anchor、node identity 和 text offset。

普通文字不再执行“猜字符终点 -> HtmlWidget -> 等待 frame -> 重复”。

### 10.3 标题规则

- 标题不拆成半个字符页。
- 当前页放不下时放到下一页。
- 可以携带下一段至少一行正文。
- 标题超过整页时进入 atomic overflow policy。

### 10.4 复杂 block 组合

复杂 block 使用自身 metrics 和明确 margin 组合，默认不与整页前缀反复拼接测量。组合 mismatch 时先移动到下一页，再校验一次，仍失败则标记 overflow/inner scroll。

### 10.5 图片与表情

普通 readable image 继续：

```text
flush text -> emit isolated image page -> start new text page
```

第一版的表情/小型 inline image 如果不能用稳定 PlaceholderSpan 表示，则整个所在 block 走 complex HTML；不能把表情计入普通正文图片序列。

### 10.6 Ruby 注音

包含 `<ruby>` 的 inline context 第一版按不可拆分 cluster 处理：

```text
safe text before ruby
  -> flush at legal boundary
ruby-containing inline block
  -> ForumHtmlWidgetPostRenderer measurement
  -> current page or dedicated complex page
safe text after ruby
  -> continue from a new legal range
```

这不是把每个 ruby 独立显示成一页，而是避免在无法准确表达 ruby line box 时把它混进 TextPainter 的普通行。若一个段落同时包含大量普通文字和少量 ruby，第一版可以将整个 containing paragraph 作为 `rubyInline` complex block；不能只删除 `rt` 后继续按普通文字分页。

Ruby block 必须保留：

- base text 和 annotation text 的原始 HTML。
- base/annotation 的 source offsets 和所在语义 node。
- `rubyCluster` 的稳定 identity。
- final renderer 的字体、主题和方向设置。

### 10.7 有界 renderer 校验

不能对每个 safe text page 都启动真实 HTML probe，否则只是把上百次候选测量减少成几十次整页测量。

| 构建模式 | 纯文本校验策略 |
| --- | --- |
| Debug | 首页、复杂边界和可配置全量校验 |
| Profile | 首页、每 16 页一次、所有复杂边界 |
| Release | 首页、复杂边界和风险 style signature 的有界校验 |

safe style resolver 必须先通过 fixture/golden 测试，Release 不能依赖每页实时 HTML 测量证明正确。

## 11. Renderer 校验与降级

### 11.1 校验输入必须一致

校验 probe 和最终页面必须复用相同的 prepared HTML fragment、`ForumHtmlPreparedRenderDocument`、阅读设置、主题、图片 fallback、dimension index、style policy、collapse builder、viewport 和 chrome inset。

不能用 TextPainter 结果替代复杂样式的 final renderer。

### 11.2 mismatch 处理

```text
TextPainter candidate
  -> renderer validation
  -> match: accept
  -> overflow: backoff to previous complete line
  -> still mismatch: route atom to complex HTML
```

记录 `rendererValidationCount`、`rendererValidationMismatchCount`、`safeTextFallbackCount` 和短 `fallbackReason`。不记录正文、Cookie、请求头或完整路径。

### 11.3 故障降级

- TextPainter 初始化或字体异常：当前 atom 走 HTML renderer。
- HTML probe 超时：复杂 block 生成明确 overflow 状态。
- 计划整体超时：显示可重试错误并回到纵向模式。
- 任何分页失败：保留正文、书签、阅读进度和 SQLite 数据。
- 图片加载失败：保留图片占位，不清空前后文字。

## 12. 性能与复杂度对比

### 12.1 当前全 HTML 二分方案

令 `N` 为正文规模，`P` 为页数，`I` 为每次文本范围二分次数，`R(x)` 为构建并 Layout HTML 候选的成本。当前首次分页约为：

```text
O(P × I × R(page prefix + candidate))
```

由于每个候选可能重新解析 atom、拼接页前缀、构建 Widget 和等待 Flutter frame，最坏情况下接近 `O(I × N²)`。

### 12.2 混合方案

令 `N_text` 为安全纯文本规模，`C` 为普通复杂 block 数量，`U` 为 ruby-containing block 数量，`R_block` 为普通复杂 block 的真实 renderer 成本，`R_ruby` 为 ruby block 的真实 renderer 成本：

```text
safe text:       O(N_text + P)
ruby blocks:     O(U × R_ruby)
complex blocks:  O(C × R_block)
page composing:  O(P)
```

目标整体复杂度为 `O(N_text + P + U × R_ruby + C × R_block)`。章节几乎全是表格、折叠、ruby 或 Widget 时仍可能退化到复杂 renderer 成本，但退化原因应与复杂 block 数量相关，而不是普通文本每个字符重复测量。

### 12.3 预计性能目标

以下是工程验收目标，不是未经真机测试的承诺：

#### 80 页文字型长章节

- Profile/Release 真机首屏可见时间目标 `<= 500ms`。
- 完整 plan 生成目标 `<= 2s`。
- 纯文字每页不启动一次 HTML probe。
- HTML probe 数量只来自有界校验和复杂边界。

#### 80 页混合格式章节

- 首屏可见时间目标 `<= 800ms`。
- 完整 plan 生成目标 `<= 5s`，具体取决于复杂 block 和图片数量。
- 每个表格/折叠 block 默认最多一次初始状态测量。
- 不允许连续几十秒 loading。

现有 100 秒样本的目标不是依靠 Release 优化降低一点，而是让主要普通文字进入 TextPainter fast path，减少 HTML Widget Layout 次数，并优先显示首屏。

预期文字占比高的长文章可获得约 5 至 20 倍首次布局提速；复杂格式较多的文章预计约 2 至 5 倍。最终数值必须通过固定 fixture、Profile 真机和 Release 真机确认，不能把范围当作保证。

## 13. 缓存策略

### 13.1 Text metrics cache

扩展现有 metrics cache，key 包含：

```text
contentHash
atomId/runId
range
viewportWidth
typographySignature
themeSignature
textLayoutAdapterRevision
```

只缓存派生行范围和高度，不把正文副本写入 SQLite。

### 13.2 Complex block cache

复杂 block key 还必须包含 collapse initial state、table layout revision、image dimension revision、renderer revision 和 viewport width。

折叠展开交互不应污染章节 plan cache。若以后允许展开后重新分页，应创建新的 layout identity。

### 13.3 Plan cache

混合算法接入后应升级 renderer revision，例如 `rendererRevision = 3`。旧全 HTML plan 不得与 hybrid plan 复用。

## 14. 首屏优先与增量计划

第一版 hybrid planner 可以继续返回完整 `NovelReaderPaginationPlan`，但不能让用户等待整章完成后才看到正文。

推荐演进：

```dart
abstract interface class NovelReaderIncrementalPaginationPlanner {
  Stream<NovelReaderPaginationProgress> planIncrementally(...);
}

final class NovelReaderPaginationProgress {
  const NovelReaderPaginationProgress({
    required this.pages,
    required this.isComplete,
    required this.processedAtomCount,
  });

  final List<NovelReaderPageFragment> pages;
  final bool isComplete;
  final int processedAtomCount;
}
```

阶段性行为：

1. 先生成当前页和下一页。
2. surface 立即显示第一页。
3. 后台按 atom/page 批次继续生成。
4. 总页数未完成时显示“计算中”，不伪造总页数。
5. 当前页位置和进度只在真实可见时提交。

不要一开始同时重写 PageView、位置恢复和章节导航。先让 hybrid planner 在现有完整 plan contract 下通过正确性测试，再引入增量 plan。

## 15. 分阶段实施计划

### Phase 0：样本和性能证据基线

目标：拆开真实样本结构和当前 100 秒成本。

交付：

- 为四个 HTML fixture 建立脱敏结构报告。
- 记录主楼 message、普通文字、font style、背景色、图片、折叠和表格数量。
- 记录当前测量次数、renderer validation 数量、等待 frame 次数和总时长。
- 不改变生产分页行为。

验收：能明确回答 100 秒中有多少时间来自 HTML probe、DOM slice、图片和 Flutter frame；fixture 不包含 Cookie、auth 或完整请求头。

### Phase 1：安全文字子集和共享 style resolver

目标：在不改变最终 HTML renderer 的前提下生成 TextPainter runs。

交付：

- `NovelReaderPaginationTextRunExtractor`。
- `ForumHtmlTextStyleResolver` 共享接口。
- font color、background color、font size、font weight、font style、font family 和链接 run。
- 安全子集 classifier。
- ruby/rt/rp classifier，第一版明确排除普通 TextPainter fast path。
- 不支持的 style 明确进入 complex route。

验收：嵌套 font 继承正确；`font size=3..6` 不被重复解释；颜色和背景色在 light/sepia/dark 下与 renderer policy 一致；ruby、表格、折叠、图片和未知字体不进入普通 safe path。

### Phase 2：TextPainter 纯文本分页器

目标：消除普通文字的候选 HTML 二分测量。

交付：

- `NovelReaderTextPaginationEngine`。
- 一次布局获取 line ranges。
- 按完整行和合法 HTML range 生成 page fragment。
- 标题最小可读和段落 spacing 规则。
- Text metrics cache。

验收：纯文本章节不再为每个范围创建 HTML probe；CJK、中英混排、数字、空格、`&nbsp;` 和换行稳定；ruby 不会误进入普通 TextPainter；样式和 anchor 与 renderer 校验一致。

### Phase 3：复杂 block、折叠和表格原子页

目标：把样本中的复杂结构纳入 hybrid planner。

交付：

- complex block measurer。
- `rubyInline` complex route 和 ruby-containing block 的一次测量策略。
- `.showcollapse_box` 到 `ForumCollapseBlock` 的 pagination adapter。
- collapsed/expanded 初始状态识别。
- 表格完整 block 测量和 oversized/inner-scroll policy。
- 图片继续使用 isolated image page。

验收：ruby base/rt 不分离且最终视觉与 renderer 一致；嵌套折叠状态正确；折叠点击不改变后续 page index，或明确触发新 layout revision；表格不被非法拆分或截断；超高 block 有内部滚动或纵向入口。

### Phase 4：Page composer 和 renderer validation

目标：组合 safe text、complex block 和 isolated image。

交付：

- `NovelReaderHybridPaginationPlanner`。
- safe text/complex/image 路由。
- bounded renderer validation。
- mismatch backoff 和 complex fallback。
- gap reason、route reason 和性能指标。

验收：普通文字页 fullness 达标；低 fullness 有明确原因；mismatch 不产生空白假成功页；回退不删除进度、书签或正文。

### Phase 5：首屏优先和增量 plan

目标：避免长章节必须等完整 plan 才能开始阅读。

交付：

- 当前页/下一页优先生成。
- 增量 page batch 或 progress stream。
- 总页数未知时的明确 UI 状态。
- 取消旧 batch 和 generation 隔离。

验收：首屏不等待后续所有页面；章节切换、字号和主题变化不会污染新页面；退出/后台只提交真实可见页。

### Phase 6：性能基准、真机和灰度

目标：确认长文章在实际设备上可发布。

矩阵：

- 三份 HTML fixture。
- 默认折叠和初始展开变体。
- 至少一份包含表格的脱敏 fixture。
- `注音.html` 的 ruby/rt fixture，以及相邻普通文字和多个连续 ruby cluster 变体。
- 纯文字 20/80/200 页。
- Android 13/14/15，小屏和大屏。
- 当前支持版本的 iOS。
- sepia、light、dark、最小/默认/最大字号。
- LTR/RTL 页面流向。
- 图片已知/未知尺寸、慢加载、失败、缓存命中。
- 锁屏、后台、进程回收、断网读取水合正文。

灰度规则：默认仍为滚动模式，分页作为显式设置开放；超过性能预算自动回到滚动模式；诊断不包含正文。

## 16. 接口装配建议

```text
NovelReaderHtmlPagedSurface
  -> NovelReaderPaginationCoordinator
      -> NovelReaderHybridPaginationPlanner
          -> AtomClassifier
          -> TextPaginationEngine
          -> ComplexBlockPaginationEngine
          -> PageComposer
          -> RendererValidator
      -> PreparedChapterCache
      -> PaginationMeasureCache
      -> PaginationPlanCache
```

Riverpod/provider 只负责依赖组合和生命周期，不承担分页算法细节。自定义 renderer adapter 通过 interface 注入，测试可以使用确定性高度 adapter，不依赖真实 Flutter frame。

## 17. 测试计划

### 17.1 Fixture 结构测试

- 四份样本能提取主楼 message，不纳入 header、作者、footer、评分和点评。
- `文字背景色.html` 识别颜色、背景色、字号、字体族和嵌套 font。
- `字颜色字号.html` 识别多个 message 的正文 style run。
- `折叠目录.html` 识别 collapsed、active、nested collapse。
- `注音.html` 识别 47 个 ruby/rt cluster，确认当前没有 rp，并保留 base/annotation 成对关系。
- 表格 fixture 识别为 table block。

### 17.2 TextPainter 测试

- 中文连续文本、中英混排、数字、多个 inline style、背景色 run、相邻字号、粗体、斜体、链接、`br`、空段落、`&nbsp;`。
- CJK 标点不能产生明显错误断行。
- 生成片段保持合法 HTML，anchor offset 不重复、不跳过。
- ruby-containing block 不进入普通 TextPainter，且不会在 base 与 rt 之间生成断点。

### 17.3 Complex block 测试

- 折叠默认/active 状态和嵌套折叠。
- 折叠内容链接继续使用 link callback。
- ruby 日文假名、英文注音、间隔点和连续 ruby cluster 的最终 renderer 高度与顺序。
- ruby base/annotation 的 source anchor、搜索和书签恢复。
- 表格完整保留，过高时设置 `requiresInnerScroll`。
- 图片独立页不改变前后文字页数量，失败不删除文字。

### 17.4 Renderer 一致性测试

- TextPainter 高度与 renderer 高度在允许误差内。
- 主题、字号和行高变化使 metrics cache 正确失效。
- unknown font 进入 complex fallback。
- mismatch 不产生空白页。

### 17.5 位置和进度测试

- page fragment anchor range 连续。
- 搜索 anchor 可以定位到 hybrid page。
- 书签恢复到同一文本附近。
- measurement、preload、cache hit 和 validator 不写阅读进度。
- 小说水合、已读语义和 `version=1` 请求不改变。

### 17.6 性能测试

记录 preparation、classification、safe run count、complex block count、TextPainter layout count、HTML probe count、renderer validation count、mismatch count、first page duration、full plan duration、page count、cache hit rate、low fullness page count 和 cancelled plan count。

性能结论不能只依赖 `pumpAndSettle`，必须使用 Profile/Release 真机和固定 fixture。

## 18. Review 清单

- TextPainter 是否只处理明确安全子集。
- 是否复制了 `ForumHtmlStylePolicy`、作者颜色和字号解析。
- HTML renderer 是否仍是最终视觉权威。
- 是否对每个普通文本候选重新创建 HtmlWidget。
- 是否把表格、折叠、图片或 WidgetSpan 错归为纯文本。
- 折叠展开是否造成后续 page index 隐式漂移。
- 表格是否被非法拆分或静默裁切。
- `font face` 无法复现时是否进入 complex fallback。
- `<ruby>/<rt>/<rp>` 是否保持 base/annotation 成对，且没有被摊平成普通文本。
- ruby 是否在 base 与 annotation 之间产生非法分页断点。
- `<font size>` 是否被重复解释。
- CJK、`br`、`&nbsp;` 和空段落是否保持语义。
- mismatch 是否有明确回退。
- 是否把测量、plan、build 或 preload 写入阅读进度。
- 是否将分页片段写入 SQLite 或作品 metadata。
- 是否保留小说 `version=1` 请求链路。
- 是否有 80 页长文的首屏和完整 plan 数据。

## 19. 完成定义

混合分页只有同时满足以下条件才算完成：

1. 纯文本长章节不再通过每个候选 HTML 的二分测量分页。
2. 文字颜色、背景色、字号、粗体、斜体、链接和字体 fallback 有明确兼容策略。
3. ruby 的 base、annotation、source anchor 和 line box 语义正确。
4. 折叠目录初始状态、嵌套状态和交互正确。
5. 表格不被错误转换、截断或拆成非法 HTML。
6. 普通图片、表情和复杂 Widget 不污染正文图片索引。
7. TextPainter 只负责规划，最终视觉仍由 `ForumHtmlWidgetPostRenderer` 提供。
8. mismatch 有有界校验和可靠降级，不显示空白假成功页。
9. 80 页文字型长章节首屏和完整 plan 达到 Phase 6 性能预算。
10. 位置恢复、搜索、书签和真实可见页进度通过自动化和真机测试。
11. 所有缓存都是进程内派生缓存，SQLite 正文仍是唯一离线内容来源。
