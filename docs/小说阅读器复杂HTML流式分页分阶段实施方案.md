# 小说阅读器复杂 HTML 流式分页分阶段实施方案

> 状态：Phase 0-4 已完成（2026-07-21）；Phase 5-8 待实施
>
> 编写日期：2026-07-21
>
> 适用范围：Y300 小说阅读器 HTML-first 分页模式
>
> 关联文档：
> - `docs/小说阅读器复杂HTML流式分页Phase0基线与ADR.md`
> - `docs/小说阅读器HTML-first混合分页分阶段实施方案.md`
> - `docs/小说阅读器分页算法重构与性能优化方案.md`
> - `docs/小说阅读器全新分页阅读模式Phase0基线与ADR.md`
> - `docs/开发文档.md`

## 1. 结论先行

当前生产分页已经解决了普通文字反复构建 HTML Widget 的性能问题，但仍将多种性质完全不同的内容统一归入 `complexHtml`。`complexHtml` 当前按一个不可拆 block 测量，除 `rubyInline` 外，追加后会立即封页。因此，只有一行文字的未知字体、异常旧式 `<font face>` 或不支持样式，也可能独占整页。

本方案将“渲染复杂”与“不可分页”彻底分离。最终规则固定为：

```text
安全普通文字
  -> TextPainter 一次布局
  -> 按完整行切页

以文字为主体的复杂 HTML
  -> DOM 只解析和索引一次
  -> 在合法语义边界上二分查找
  -> 使用真实 ForumHtmlWidgetPostRenderer 测量候选
  -> 可以填入当前页剩余空间
  -> 接受片段后页面继续开放

正文图片
  -> 独占页

表格
  -> 独占页

折叠块
  -> 独占页

真正不可拆的嵌入组件
  -> atomicWidget 独占页或受限内部滚动
  -> 不再混在 complexHtml 文本策略中
```

“二分”必须是基于 DOM 文本范围和合法边界的 upper-bound 搜索，不能按 HTML 字符串长度截断。每个候选片段必须标签闭合、Ruby cluster 完整、anchor 连续，并由最终 HTML renderer 测量。

## 2. 当前问题与根因

### 2.1 真实样本

本次问题样本开头包含：

```html
<strong><strong><font face="&amp;quot">喜歡的人和義妹</font></strong></strong>
<br>
<strong><font face="&amp;quot">第一話（１）</font></strong>
<div align="left">　　</div>
<div align="left">　　如果能轉世重生的話，我想成為像她那樣的人。</div>
```

`face="&amp;quot"` 不是可映射字体族。当前共享 style resolver 将其报告为 `unsupportedFontFamily`，classifier 再将两个短标题路由为 `complexHtml`。

当前 composer 行为是：

```text
标题 complexHtml
  -> 空页上测量整个 atom
  -> appendComplexBlock
  -> 立即 emit 第 1 页

章节名 complexHtml
  -> 空页上测量整个 atom
  -> appendComplexBlock
  -> 立即 emit 第 2 页

后续 div safeText
  -> 从第 3 页开始
```

因此，该现象不是页面高度计算错误，也不是正文必须独占页，而是路由粒度和页面组合策略错误地把“样式无法快速解释”推导成了“内容不可分页”。

### 2.2 当前生产算法并非复杂文本二分

当前生产路径应准确描述为：

| 路径 | 当前算法 | 当前问题 |
| --- | --- | --- |
| `safeText` | TextPainter 一次布局，按行切片，少量 renderer 校验 | 正常 |
| renderer mismatch backoff | 按高度比例缩小预算，再布局和校验一次 | 不是二分，只是有界回退 |
| `rubyInline` | 整个 atom 真实测量 | 长 Ruby 段落不能跨页 |
| `complexHtml` | 整个 atom 真实测量，通常立即封页 | 短文本浪费整页；长文本可能内部滚动 |
| `isolatedImage` | 独立图片页 | 符合目标 |
| `tableBlock` | 整块测量，可尝试与前文组合，随后封页 | 新规则要求始终独占页 |
| `collapseBlock` | 整块测量并使用受限交互 | 新规则要求始终独占页 |

旧 `NovelReaderHtmlPageBreaker` 中的全 HTML 候选二分不是本方案要恢复的实现。新实现必须复用当前 hybrid planner、持久 measurement session、缓存、取消令牌和增量页面发布能力。

## 3. 目标与非目标

### 3.1 目标

- 只有正文图片、表格、折叠块和真正不可拆 Widget 使用独占页。
- 不支持字体、颜色、字号、背景、内联标签或 Ruby 等以文字为主体的复杂 HTML 可以跨页。
- 短复杂文本可以与前文和后文共同填充一页，不因 `complexHtml` 路由自动封页。
- 长复杂文本在 DOM 合法边界上查找每页最大可容纳范围。
- 所有候选仍由 `ForumHtmlWidgetPostRenderer` 作为最终高度权威。
- 不在 Ruby base 与 `rt/rp` 之间切页。
- 不在 grapheme cluster、HTML entity、不可拆 inline widget 内部切页。
- 页片段 anchor 连续，不丢字、不重复、不改变书签、搜索和恢复语义。
- 普通 safe text 的线性快速路径不退化为 HTML 二分。
- 复杂 HTML 二分成本只与复杂文字 atom 数量及其页面数相关。
- 首屏优先、generation 隔离、取消、性能降级和进程内缓存继续生效。
- 小说正文请求继续固定使用 `version=1`。

### 3.2 非目标

- 不实现完整浏览器 CSS layout engine。
- 不按原始 HTML 字符串下标或字节长度截断。
- 不跨页拆分表格行、单元格或 colspan/rowspan。
- 不跨页拆分折叠 block 的内部状态。
- 不把正文图片重新放回文字流。
- 不把 `iframe`、`video`、`audio`、`canvas` 等组件伪装成可流动文字。
- 不把分页 plan 或 DOM 索引写入 SQLite。
- 不修改纵向 HTML-first 阅读模式。
- 不为了填满页面删除作者正文中的有效空行、颜色、背景、链接或 Ruby。
- 不把未知字体静默映射为任意平台字体；只允许明确的 no-op 恢复规则。

## 4. 术语与最终行为矩阵

### 4.1 Safe text

共享 style resolver 能完整映射为 TextSpan，并且最终 renderer 与 TextPainter 已有一致性证据的文字内容。

### 4.2 Flowable complex text

内容主体是可连续阅读的文字，但因为 Ruby、未知字体、受支持范围外的内联样式或复杂 inline DOM，不能可靠进入 TextPainter 快速路径。它仍然存在单调增长的文本范围和合法分页边界，因此可以交给真实 renderer 做范围搜索。

### 4.3 Dedicated content

产品规则明确要求独占页面的内容：

- 正文 readable image。
- 表格。
- 折叠块。

这些内容无论是否能放入上一页剩余空间，都在前后执行 page flush。

### 4.4 Atomic widget

没有可靠文本范围、不能通过克隆 DOM wrapper 安全拆分的嵌入组件，例如 `iframe`、`video`、`audio`、`canvas`、`object` 或自定义 Flutter WidgetSpan。它不是 flowable complex text，也不再由含糊的 `complexHtml` 默认行为决定。

### 4.5 行为矩阵

| 内容 | 最终 route | 测量 | 可跨页 | 可与前文同页 | 可与后文同页 | 超高处理 |
| --- | --- | --- | --- | --- | --- | --- |
| 普通文字 | `safeText` | TextPainter | 是 | 是 | 是 | 最小文字片段保护 |
| 无效 no-op `font face` | 规范化后 `safeText` | TextPainter | 是 | 是 | 是 | 同 safe text |
| 未知但有效字体的纯文字 | `flowableComplexText` | HtmlWidget + DOM 二分 | 是 | 是 | 是 | 最小合法片段或纵向降级 |
| 特殊内联颜色/背景/字号 | safe 优先，否则 `flowableComplexText` | TextPainter 或 HtmlWidget + DOM 二分 | 是 | 是 | 是 | 同上 |
| Ruby 段落 | `rubyInline` + flowable policy | HtmlWidget + Ruby 边界二分 | 是 | 是 | 是 | 不拆 cluster |
| 小型 inline smiley | flowable protected cluster | HtmlWidget + DOM 二分 | 在 cluster 外可拆 | 是 | 是 | 单 cluster 过高则 atomic |
| 正文图片 | `isolatedImage` | HtmlWidget/尺寸索引 | 否 | 否 | 否 | 独占页内部 contain/scroll |
| 表格 | `tableBlock` | HtmlWidget | 否 | 否 | 否 | 独占页内部横纵滚动 |
| 折叠块 | `collapseBlock` | HtmlWidget | 否 | 否 | 否 | 独占页内部滚动 |
| iframe/video/audio/canvas | `atomicWidget` | HtmlWidget | 否 | 否 | 否 | 独占页内部滚动或纵向入口 |

## 5. 架构总览

```text
NovelReaderHtmlPagedSurface
  -> NovelReaderPaginationCoordinator
      -> NovelReaderHybridPaginationPlanner
          -> NovelReaderPaginationAtomExtractor
          -> NovelReaderPaginationAtomClassifier
              -> ForumHtmlTextStyleResolver
              -> NovelReaderLegacyMarkupNormalizer
              -> NovelReaderPaginationLayoutPolicyResolver
          -> SafeTextPaginationEngine
          -> FlowableComplexPaginationEngine
              -> ComplexHtmlBoundaryIndexer
              -> ComplexHtmlSliceSession
              -> ComplexHtmlFitSearcher
              -> Persistent HtmlWidget MeasureSession
          -> DedicatedContentPaginator
              -> isolated image
              -> table
              -> collapse
          -> AtomicWidgetPaginator
          -> NovelReaderPaginationPageComposer
          -> NovelReaderPaginationRendererValidator
      -> PaginationPlanCache
      -> PaginationMeasureCache
```

依赖方向必须保持：

```text
models/policies
  <- pure index/slice/search services
  <- planner/composer orchestration
  <- Flutter renderer measurement adapter
  <- paged surface/provider assembly
```

planner 不直接操作 Overlay、PageController、SQLite、repository 或阅读进度。真实测量继续通过 `NovelReaderPaginationMeasureSession` 注入。

## 6. 设计原则与不变量

### 6.1 单一渲染权威

`ForumHtmlWidgetPostRenderer` 仍是复杂内容最终高度和视觉效果的唯一权威。二分搜索只决定候选范围，不自行近似复杂 CSS 或 Ruby 高度。

### 6.2 分类与分页能力正交

“为什么复杂”与“能否拆分”是两个维度：

```text
route/reason: 内容语义和风险来源
layoutPolicy: 采用哪种测量、拆分、放置和溢出策略
```

不能继续使用 `route == complexHtml` 推导 `isBreakable == false`。

### 6.3 一次解析，多次切片

一个 flowable complex atom 只允许建立一次 DOM/index session。二分候选必须从该不可变索引克隆范围，不得为每次 probe 重新 `parseFragment` 全 atom。

### 6.4 搜索必须单调

只有满足“候选文本范围增加时布局高度不会下降到破坏 upper-bound 搜索”的内容才能进入二分路径。以下 CSS 或结构必须排除：

- `position:absolute/fixed/sticky`。
- float 及依赖 sibling 重排的布局。
- script 驱动布局。
- 宽高取决于外部异步状态且没有稳定占位的 Widget。
- 表格共同列宽布局。
- 折叠展开状态。

不满足单调性时必须分类为 dedicated 或 atomic，不能强行二分。

### 6.5 合法边界优先于字符数量

搜索空间不是 `0..html.length`，而是一个有序合法边界列表。任何页面切点必须：

- 位于 grapheme cluster 之间。
- 不切开 HTML entity。
- 不切开 Ruby base/annotation cluster。
- 不切开 protected inline widget。
- 可以重建闭合 wrapper。
- 对应稳定 text anchor。

### 6.6 页面组合单飞且可取消

每次 layout key 只允许一个 active generation。旧主题、旧字号、旧 viewport 或旧章节的测量结果不得写入新 plan。

### 6.7 分页不等于阅读

DOM 索引、候选测量、缓存、预加载和增量 page publish 都不能写阅读进度。只有真实可见页面继续通过现有进度入口提交。

## 7. 领域模型

### 7.1 Route 演进

建议演进为：

```dart
enum NovelReaderPaginationRoute {
  safeText,
  flowableComplexText,
  rubyInline,
  isolatedImage,
  tableBlock,
  collapseBlock,
  atomicWidget,
}
```

迁移完成后不再保留拥有默认原子语义的通用 `complexHtml`。迁移期可以暂时保留 deprecated route，但 classifier 必须将每个旧 reason 显式映射到新 route。

### 7.2 Layout policy

```dart
enum NovelReaderPaginationMeasurePolicy {
  textPainter,
  htmlRendererRange,
  htmlRendererWholeAtom,
}

enum NovelReaderPaginationSplitPolicy {
  lineRanges,
  domBoundaries,
  none,
}

enum NovelReaderPaginationPlacementPolicy {
  flow,
  dedicatedPage,
}

enum NovelReaderPaginationOverflowPolicy {
  minimumTextFragment,
  innerScroll,
  fallbackToVertical,
}

final class NovelReaderPaginationLayoutPolicy {
  const NovelReaderPaginationLayoutPolicy({
    required this.measure,
    required this.split,
    required this.placement,
    required this.overflow,
    required this.keepPageOpenAfterAppend,
  });

  final NovelReaderPaginationMeasurePolicy measure;
  final NovelReaderPaginationSplitPolicy split;
  final NovelReaderPaginationPlacementPolicy placement;
  final NovelReaderPaginationOverflowPolicy overflow;
  final bool keepPageOpenAfterAppend;
}
```

policy 由独立 resolver 生成，composer 只执行 policy，不重新判断 HTML 标签。

### 7.3 合法切点

```dart
enum NovelReaderComplexBoundaryKind {
  blockEnd,
  hardBreak,
  sentenceEnd,
  wordEnd,
  graphemeEnd,
  rubyClusterEnd,
  protectedInlineEnd,
  atomEnd,
}

final class NovelReaderComplexHtmlBoundary {
  const NovelReaderComplexHtmlBoundary({
    required this.textOffset,
    required this.anchor,
    required this.kind,
    required this.preference,
  });

  final int textOffset;
  final NovelReaderTextAnchor anchor;
  final NovelReaderComplexBoundaryKind kind;
  final int preference;
}
```

同一 offset 只保留最高优先级边界。优先级固定为：

```text
blockEnd > hardBreak > sentenceEnd > wordEnd > graphemeEnd
```

Ruby 和 protected inline 边界是合法性保护，不允许在 cluster 内生成其它候选。

### 7.4 DOM slice session

```dart
abstract interface class NovelReaderComplexHtmlSliceSession {
  int get textLength;
  List<NovelReaderComplexHtmlBoundary> get boundaries;

  NovelReaderComplexHtmlSlice slice({
    required int startOffset,
    required int endOffset,
  });
}

final class NovelReaderComplexHtmlSlice {
  const NovelReaderComplexHtmlSlice({
    required this.html,
    required this.startAnchor,
    required this.endAnchor,
    required this.startOffset,
    required this.endOffset,
    required this.hasRenderableContent,
  });

  final String html;
  final NovelReaderTextAnchor startAnchor;
  final NovelReaderTextAnchor endAnchor;
  final int startOffset;
  final int endOffset;
  final bool hasRenderableContent;
}
```

现有 `NovelReaderHtmlTextRangeSliceSession` 应扩展或抽取共享索引核心，不能复制第二个互不一致的 DOM slicer。

### 7.5 Fit search

```dart
abstract interface class NovelReaderComplexHtmlFitSearcher {
  Future<NovelReaderComplexHtmlFitResult> findLargestFittingPrefix({
    required NovelReaderComplexHtmlSliceSession session,
    required int startOffset,
    required String bufferedPageHtml,
    required double availableHeight,
    required NovelReaderPaginationMeasureContext context,
    required NovelReaderPaginationCancellationToken cancellationToken,
  });
}

final class NovelReaderComplexHtmlFitResult {
  const NovelReaderComplexHtmlFitResult({
    required this.slice,
    required this.measuredHeight,
    required this.probeCount,
    required this.cacheHitCount,
    required this.fits,
    required this.exhaustedAtom,
    required this.requiresFreshPage,
    required this.budgetExceeded,
  });

  final NovelReaderComplexHtmlSlice slice;
  final double measuredHeight;
  final int probeCount;
  final int cacheHitCount;
  final bool fits;
  final bool exhaustedAtom;
  final bool requiresFreshPage;
  final bool budgetExceeded;
}
```

`availableHeight` 表示整页正文高度上限，而不是扣除当前 buffer 后的估算剩余
高度；候选始终以 `bufferedPageHtml + slice.html` 的完整 renderer 高度判定。
`measuredHeight` 同样是该完整候选的高度。`requiresFreshPage=true` 表示当前页连
最小合法片段都放不下，searcher 已在空白整页上重新搜索，调用方必须先封当前页
再追加返回片段。

fit searcher 不写 composer，也不发布页面。它只返回最大已验证可放入前缀和测量
证据；`budgetExceeded=true` 时返回的是预算内 offset 最大的已验证 fit，而不是
未经测量的推测边界。

### 7.6 Flowable engine

```dart
abstract interface class NovelReaderFlowableComplexPaginationEngine {
  Future<NovelReaderFlowableComplexPaginationResult> paginate({
    required NovelReaderClassifiedPaginationAtom atom,
    required NovelReaderPaginationPageContext page,
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
    required NovelReaderPaginationCancellationToken cancellationToken,
  });
}
```

engine 负责从 `startOffset` 循环产生片段，但页面是否 emit 仍由 composer 决定。

## 8. 分类和规范化规则

### 8.1 Legacy markup normalizer

新增职责单一的 `NovelReaderLegacyMarkupNormalizer`，只处理可证明无视觉意义或损坏的遗留属性。它必须运行在共享 preparation 边界，纵向与分页 renderer 看到同一份 prepared HTML。

第一批允许规则：

```text
font face is empty
font face is only quote entities
font face normalizes to " or '
font face contains no usable family token
  -> remove face attribute
  -> preserve font element, color, size, strong and text
```

不允许：

- 删除整个 `<font>`。
- 删除 `color`、`size` 或背景样式。
- 把任意未知非空字体强制改成 Roboto。
- 修改正文文本。

每条规范化规则必须有 fixture 和稳定 reason，例如 `invalidQuoteOnlyFontFace`。

### 8.2 Route 决策表

| 当前 reason | 新决策 |
| --- | --- |
| `safeTextSubset` | `safeText` |
| `isolatedReadableImage` | `isolatedImage` + dedicated |
| `containsTable` | `tableBlock` + dedicated |
| `containsCollapse` | `collapseBlock` + dedicated |
| `containsRuby` | `rubyInline` + DOM boundary split |
| `unsupportedFont`，文字型 | `flowableComplexText` |
| `unsupportedStyle`，仅文字且单调 | `flowableComplexText` |
| `unsupportedAttribute`，仅展示属性且单调 | `flowableComplexText` |
| `unsupportedTag`，后代仅文字且单调 | `flowableComplexText` |
| `containsWidgetSpan` | `atomicWidget`，除非存在已注册 protected-inline adapter |
| `atomicWidget` | `atomicWidget` |
| `containsImage` | readable image 提取为 dedicated；smiley 进入 protected-inline；其它图片 atomic |

### 8.3 Flowability inspector

新增纯结构 inspector，回答：

```dart
final class NovelReaderComplexHtmlFlowability {
  const NovelReaderComplexHtmlFlowability({
    required this.isTextBearing,
    required this.isMonotonic,
    required this.hasProtectedInlineNodes,
    required this.requiresRubyBoundaries,
    required this.failure,
  });
}
```

classifier 不应通过“未知标签”直接推导 atomic。若未知 wrapper 只包含文字和允许的 inline descendants，可以保留原 HTML 并进入真实 renderer range path。

## 9. DOM 边界索引

### 9.1 一次解析

对每个 flowable atom：

1. `parseFragment` 一次。
2. 深度优先遍历 DOM。
3. 为文本建立 grapheme offset，不继续使用可能切开组合字符的 UTF-16 或裸 rune 边界作为最终候选。
4. 为元素记录 start/end offset、wrapper attributes 和 protected state。
5. 为 Ruby 建立 base + annotation cluster 范围。
6. 为 smiley/inline widget 建立零宽或占位 cluster 范围。
7. 生成有序、去重的合法 boundaries。

### 9.2 边界数量控制

默认不把每个 grapheme 都放入首轮搜索数组。建议建立分层边界：

```text
Tier 1: blockEnd / hardBreak / sentenceEnd
Tier 2: wordEnd / CJK punctuation
Tier 3: graphemeEnd
```

搜索先使用 Tier 1+2。只有整页连一个 Tier 1+2 片段都放不下时，才在局部范围展开 Tier 3，避免长 CJK 正文产生不必要的大候选数组。

### 9.3 切片正确性

slice 必须：

- 克隆与范围相交的祖先 wrapper。
- 只保留范围内文本和完整 protected node。
- 输出合法、闭合 HTML。
- 保持原始属性，不重新解释 CSS。
- 不复制范围外图片、表格、折叠或 widget。
- 保持 start/end anchor 连续。
- 对空白片段返回 `hasRenderableContent=false`，不得生成空白页。

## 10. 有界二分算法

### 10.1 搜索目标

给定当前页面已有 HTML、剩余高度和 atom remainder，查找最大的合法 `endOffset`：

```text
measure(bufferedPageHtml + slice(startOffset, endOffset))
  <= pageAvailableHeight
```

这里使用 upper-bound 搜索，结果必须是“已验证可容纳的最远边界”，不能只返回最后一次 probe。

### 10.2 搜索步骤

```text
1. 若整个 remainder 与当前 buffer 组合后可容纳
     -> 接受整个 remainder
     -> 页面保持开放

2. 若当前页已有内容，且最小合法片段也放不下
     -> flush 当前页
     -> 在空白整页上重试

3. 在候选边界数组上执行 upper-bound 二分
     -> low 表示已验证 fit
     -> high 表示已验证 overflow 或 atom end
     -> 每次只测量合法 DOM slice

4. 接受最大 fit 前缀
     -> appendFlowableComplexChunk
     -> 若 remainder 存在则 flush 满页
     -> 从 accepted endOffset 继续下一页

5. 若空白整页连最小合法片段都放不下
     -> 标记 minimumComplexFragment
     -> 使用受限内部滚动或章节纵向降级
     -> 不能丢弃该片段或无限重试
```

### 10.3 Probe 预算

每个页面片段的真实 renderer probe 上限：

```text
whole remainder probe: 1
binary probes: ceil(log2(candidateBoundaryCount))
final accepted probe: 通常命中 cache，不额外 layout
hard maximum: 12 probes / fragment
```

超过 12 次仍无法收敛时：

- 记录 `complexSearchBudgetExceeded`。
- 使用最后一个已验证 fit 边界。
- 若没有 fit 边界，走最小片段失败策略。
- 不继续无界搜索。

### 10.4 为什么不是原始全 HTML 二分

新算法与旧算法的区别：

| 旧方案 | 新方案 |
| --- | --- |
| 对所有正文候选二分 | 只对少量 flowable complex atom 二分 |
| 反复解析 HTML | atom DOM 只解析一次 |
| 可按字符串中点落在标签内部 | 只搜索合法语义边界 |
| 每次创建一次性 probe | 复用持久 measurement session |
| 缺少 protected cluster | Ruby、smiley、inline widget 有不可拆范围 |
| 普通文字也支付 renderer 成本 | safe text 继续 TextPainter 线性路径 |

## 11. Page composer 改造

### 11.1 新增 flowable complex chunk

```dart
void appendFlowableComplexChunk(
  NovelReaderFlowableComplexChunk chunk, {
  required bool keepPageOpen,
});
```

行为：

- append 前使用搜索结果中的组合实际高度更新 `usedHeight`。
- 不因为来源 route 是复杂 HTML 自动 flush。
- `keepPageOpen=true` 时允许后续 safe 或 complex text 继续填充。
- remainder 存在且当前页已经达到搜索上限时显式 flush。
- pending structural break 与 complex slice 使用同一页面高度预算。

### 11.2 Dedicated content

新增明确接口：

```dart
void appendDedicatedPage(...);
```

固定执行：

```text
discard/resolve pending structural breaks
flush current text page
emit dedicated content page
start a new empty page
```

图片、表格和折叠块只能调用该入口，不再尝试与当前 buffer 组合。

### 11.3 Atomic widget

atomic widget 同样使用 dedicated placement，但 `gapReason`、overflow 和 diagnostics 必须与产品指定的图片/表格/折叠区分：

```text
dedicatedImage
dedicatedTable
dedicatedCollapse
atomicWidget
```

## 12. Ruby 和 inline widget

### 12.1 Ruby

Ruby 段落进入 flowable renderer path，但切点不能落在 cluster 内：

```html
<ruby>鬼魂<rt>Ghost</rt></ruby>
```

整个 `<ruby>` 是一个 protected cluster。允许在 cluster 前后分页，不允许生成只含 base 或只含 `rt` 的页面。

一个长 Ruby 段落可以：

```text
普通文字 + ruby cluster + 普通文字
  -> 按合法边界二分
  -> 跨多页
  -> 每个 slice 保留完整 ruby wrapper
```

### 12.2 Inline smiley

已有稳定尺寸和 renderer adapter 的 smiley 作为 protected inline cluster 参与复杂文字测量，不进入正文图片独占页。它不计入小说 readable image page count。

未知尺寸、异步布局会破坏单调性的 inline image：

- 先尝试从现有 image dimension index 取得稳定占位。
- 无稳定占位则将所在最小 wrapper 路由为 `atomicWidget`。
- 不允许图片加载后改变已发布 complex page 边界。

## 13. Anchor、恢复与进度

### 13.1 Anchor 连续性

对同一 atom 的连续 slices 必须满足：

```text
slice[i].endOffset == slice[i + 1].startOffset
slice[i].endAnchor 与下一片 startAnchor 指向同一语义位置
```

空白-only 范围可以被页面边界吸收，但必须在 anchor 诊断中记录，不能造成可见文字 offset 跳跃。

### 13.2 恢复

- 同 layout key 优先恢复 page index。
- key 变化时继续按 anchor 定位包含该 offset 的 slice。
- 找不到精确 offset 时使用最近前置合法 boundary。
- 只有 complete plan 才允许 percentage/legacy fallback。
- route 迁移必须提升 renderer revision，防止旧独占页 page index 被误用于新 flowable plan。

### 13.3 阅读进度

不新增进度入口。真实 PageView 可见页继续通过现有 `onPositionChanged` 提交。二分 probe、candidate slice、cache hit 和后台 plan 不得上报可见页。

## 14. 缓存、并发与取消

### 14.1 Boundary index cache

key 至少包含：

```text
episodeId
contentHash
atomId
normalizerRevision
boundaryIndexerRevision
```

value 只在进程内保存，不持久化 DOM。

### 14.2 Measure cache

复用 `NovelReaderPaginationMeasureCache`，key 继续包含完整候选 HTML 和 layout identity，并增加：

```text
flowableComplexRevision
sliceStartOffset
sliceEndOffset
bufferSignature
```

同一个 accepted candidate 的最终验证应命中已有 probe 结果。

### 14.3 单飞

- 同 layout key、atom、range 的并发测量共享 Future。
- 同 atom 只创建一个 boundary index Future。
- 旧 generation 的结果在写 composer 前再次检查 cancellation token。
- 页面已发布后，迟到 mismatch 不得重排已发布页面；只允许取消当前 generation 并按现有策略回到纵向。

### 14.4 生命周期

- coordinator cancel 时终止未开始的搜索。
- 正在执行的 renderer probe完成后丢弃结果，不写新 plan。
- session dispose 必须完成 pending completer，不能让 widget test 或 App 退出悬挂。

## 15. 性能模型与预算

### 15.1 复杂度

令：

- `N_s`：safe text 总规模。
- `N_c`：flowable complex text 总规模。
- `P_s`：safe text 页面数。
- `F_c`：complex text 生成的页面片段数。
- `B_i`：第 i 个复杂片段可搜索边界数。
- `R_i`：真实 renderer 测量一个候选的成本。
- `D`：dedicated/atomic 内容数量。

目标复杂度：

```text
safe text:
  O(N_s + P_s)

complex DOM parse/index:
  O(N_c)

complex fit search:
  O(sum(F_c × log(B_i) × R_i))

dedicated content:
  O(D × R_block)
```

最坏情况下，一篇几乎全部由复杂 HTML 组成的长章节仍会支付 renderer 二分成本；本方案不把它伪装成线性算法。但普通文字不受影响，复杂 atom 只解析一次，并且 probe 有硬上限。

### 15.2 性能门禁

在现有预算基础上增加：

| 指标 | 目标 |
| --- | --- |
| 无 complex 的 80 页章节 | 不增加 HTML probe 数量 |
| 单个短 flowable complex atom | 最多 1 次 whole-composition probe |
| 单个跨 2 页 complex atom | 每页最多 12 次 probe，目标中位数不超过 6 |
| boundary index | 每 atom 只构建一次 |
| accepted candidate | 最终校验应命中 measurement cache |
| 首屏 | complex 搜索不得绕过现有 800ms 最大门禁 |
| 完整 plan | 继续受现有 5s 最大门禁保护 |

性能超预算时继续使用现有纵向模式降级，不显示空白页或无限 loading。

## 16. Diagnostics

新增结构化指标：

```text
normalizedLegacyAttributeCount
normalizationReasonCounts
flowableComplexAtomCount
flowableComplexFragmentCount
complexBoundaryCount
complexSearchProbeCount
complexSearchCacheHitCount
complexSearchBudgetExceededCount
minimumComplexFragmentCount
dedicatedImagePageCount
dedicatedTablePageCount
dedicatedCollapsePageCount
atomicWidgetPageCount
flowabilityFailureReasonCounts
```

禁止记录：

- 正文 HTML。
- 正文片段。
- Cookie、auth、formhash。
- 本地绝对路径。
- 用户搜索词。

低 fullness 页面必须能够由 `gapReason` 解释。短 flowable complex text 独占页且没有 overflow/dedicated reason 应视为测试失败。

## 17. 故障与降级策略

| 故障 | 处理 |
| --- | --- |
| legacy normalization 异常 | 保留原 HTML，进入 flowability classifier |
| boundary index 失败 | 当前 atom 进入 atomic fallback，并记录 reason |
| slice 生成空 HTML 但有可见范围 | 终止当前 plan，不能跳过正文 |
| renderer probe 超时 | 使用最后已验证 fit；没有 fit 时触发最小片段/纵向降级 |
| 搜索不满足单调性 | 终止该 atom 二分，路由 atomic，不继续错误搜索 |
| candidate overflow | 继续 upper-bound 搜索 |
| 整页最小片段仍 overflow | 内部滚动或纵向降级，不裁切 |
| plan 超预算 | 使用现有 performance policy 回到纵向 |
| generation 取消 | 丢弃所有迟到结果，保留正文、书签和进度 |

任何降级不得删除 SQLite 正文或改变 `version=1` 请求链路。

## 18. 分阶段实施计划

### Phase 0：基线、ADR 与真实样本

> 实施状态：已完成（2026-07-21）。两份用户 `version=1` JSON 已按最小
> 结构脱敏，复用已有 pid `41425060` fixture；异常字体标题、图片、表格、
> 折叠、safe text 和 Ruby 路由均有自动化基线。当前两个标题分别以
> `complexHtml/unsupportedFont` 独占页面、fullness 均为 `0.05`；目标行为
> 以 skipped test 固定，生产 classifier/planner/composer 本阶段未修改。

目标：锁定当前问题、路由和性能数据，避免实现阶段凭截图猜测。

交付：

- 新增脱敏 UTF-8 fixture：本次 `face="&amp;quot"` 标题 + `div` 正文样本。
- 记录当前 route reason、页数、每页 fullness、probe 数和首屏时长。
- 建立 Phase 0 ADR，裁定本文的 route、dedicated policy、atomic boundary 和 rollback。
- 锁定当前 safe text、Ruby、图片、表格、折叠 fixture 结果。
- 建立“短 complex text 不应独占页”失败测试，Phase 0 允许红测但不得修改生产行为。

验收：

- 能证明两个标题分别因 `unsupportedFont` 进入 `complexHtml`。
- 能证明当前 `appendComplexBlock` 导致立即封页。
- fixture 不包含账号、Cookie、formhash 或完整 API 响应。
- 基线测试可稳定复现前两页低 fullness。

### Phase 1：能力模型和分类器拆分

目标：将 route reason 与 layout policy 解耦，不改变最终页面行为。

> 实施状态：已完成（2026-07-21）。本阶段只建立能力契约和诊断，
> `NovelReaderHybridPaginationPlanner` 仍将 `flowableComplexText` 交给既有
> whole-atom complex engine，并继续立即封页；DOM 范围切片、二分测量和
> 与相邻正文合页仍分别属于 Phase 3-5。

交付：

- `NovelReaderPaginationLayoutPolicy`。
- `NovelReaderPaginationLayoutPolicyResolver`。
- `flowableComplexText` 和 `atomicWidget` route。
- `NovelReaderComplexHtmlFlowabilityInspector`。
- 旧 `complexHtml` reason 到新 route 的完整迁移表。
- 新 diagnostics，但 composer 暂时仍按旧行为输出。

实际落地：

- 新增正交的 measure、split、placement、overflow 和
  `keepPageOpenAfterAppend` policy；`isBreakable` 由 split policy 派生，
  不再由 route 名称手写推断。
- 新增 `flowableComplexText` 与 `atomicWidget`。迁移期保留
  `complexHtml`，但正常 classifier 路径不再产出该 route；legacy route
  固定映射为 whole-atom atomic policy，防止隐式获得流式能力。
- 新增纯结构 `NovelReaderComplexHtmlFlowabilityInspector`：未知字体、未知
  文字 wrapper 和单调复杂样式可声明为 flowable；表格/折叠、嵌入组件、
  事件处理器、script 和非单调 CSS 必须拒绝 DOM range path。
- classifier 的判定优先级固定为 dedicated/atomic 内容先于 Ruby，避免包含
  Ruby 的表格、折叠或嵌入组件被误赋予流式 policy。
- plan 与 runtime diagnostics 新增 flowable complex、atomic widget 和
  dedicated content 原子计数，不记录正文 HTML。
- 两份用户提供的脱敏 `version=1` JSON 继续通过生产 parser、preparation、
  extractor 和 classifier：`tid=511960` 锁定图片/表格，`tid=565218` 锁定
  flowable invalid-font/折叠，既有样本继续锁定 safe text/Ruby。
- 无效字体最小样本的可见基线仍为 3 页、2 次 whole-atom 测量，前两页
  fullness 均为 `0.0500`；只将诊断 route 从 `complexHtml` 明确为
  `flowableComplexText`，没有提前启用目标合页行为。

验收：

- 每个 atom 都有明确 route、reason 和 layout policy。
- 未知文字 wrapper 不再自动等于 atomic。
- 图片、表格、折叠固定得到 dedicated policy。
- iframe/video/audio/canvas 固定得到 atomic policy。
- 现有生产页面数量暂时不变，便于隔离 classifier 风险。

### Phase 2：Legacy 属性规范化

目标：让可以证明为 no-op 的损坏属性尽早回到 safe path。

> 实施状态：已完成（2026-07-21）。规范化位于小说共享 chapter
> preparation 边界：文字转换之后、`ForumHtmlRenderPreparer` 的主题与图片
> preparation 之前。纵向阅读、分页 atom 提取和最终 renderer 因而使用同一份
> normalized HTML；论坛帖子 preparation 不受小说规则影响。

交付：

- `NovelReaderLegacyMarkupNormalizer`。
- quote-only/empty `font face` 规则。
- 规范化 reason 和 revision。
- 纵向与分页共用同一 prepared HTML 的验证。

实际落地：

- 新增可注入的 `NovelReaderLegacyMarkupNormalizer`，默认实现只扫描存在
  `<font ... face ...>` 候选的 HTML，再使用结构化 DOM parser 删除无效属性；
  普通章节不会额外构建 normalizer DOM。
- 第一版规则只删除空 `face`、单双引号/quote entity-only `face`，以及只由
  引号、空白和逗号组成的空 family 列表。删除属性时保留 `<font>`、外层
  wrapper、正文、`color`、`size`、style、链接和其它属性。
- 未知但具有实际 family token 的值保持原字符串，例如
  `Uninstalled Fantasy Font` 和 `'Noto Serif CJK TC', serif`；它们仍由
  classifier 路由为 `flowableComplexText/unsupportedFont`。
- 新增稳定 reason：`emptyFontFace`、`invalidQuoteOnlyFontFace` 和
  `invalidNoUsableFontFamilyToken`。summary 随 `NovelHtmlPreparedChapter` 和
  `NovelReaderPreparedChapter` 传递，runtime diagnostics 只记录 revision、
  count 和 reason 分布，不记录正文。
- normalizer revision 当前为 `1`，并同时进入 preparation cache key 和
  prepared chapter `contentHash`。规则升级或通过
  `NoopNovelReaderLegacyMarkupNormalizer` 回滚时，不会复用不同规范化版本的
  prepared chapter 或分页 plan。
- 无效字体最小样本默认路径由 2 个 `flowableComplexText` 标题变为全
  `safeText`，从 3 页降为 1 页，complex block 为 0；safe path 仍保留 1 次
  最终 renderer validation。注入 no-op 后旧 3 页、前两页 fullness
  `0.0500` 的 Phase 0 基线仍可稳定复现。
- light、sepia、dark 三种主题下，损坏 `face` 的最终 prepared renderer HTML
  与手工移除该无效属性的 control 完全一致；简繁转换输出也在进入主题适配前
  执行相同规范化。

验收：

- 本次两个标题移除无效 `face`，保留 strong、文字和其它有效属性。
- 标题进入 `safeText`，可以与后续正文合页。
- 有效未知字体不被误删，而是进入 `flowableComplexText`。
- light/sepia/dark 最终 renderer 视觉无回归。

### Phase 3：DOM boundary index 与合法切片

目标：建立与 renderer 解耦的纯 DOM 范围基础设施。

> 实施状态：已完成（2026-07-21）。本阶段新增的 grapheme boundary 和
> complex slice session 仍是纯 service，未接入 hybrid planner、真实 renderer
> measurement 或 page composer；用户可见分页行为除 Phase 2 已完成的 legacy
> normalization 外不再变化。

交付：

- 扩展现有 `NovelReaderHtmlTextRangeSliceSession` 的共享 index core。
- grapheme、段落、硬换行、句末、Ruby 和 protected-inline boundaries。
- `NovelReaderComplexHtmlSliceSession`。
- protected range 和 anchor mapping。
- 空白范围和零文本节点策略。

实际落地：

- 抽取 `NovelReaderHtmlDomTextIndex` 作为唯一 DOM parse/index/clone core。
  既有 `NovelReaderHtmlTextRangeSliceSession` 改为委托该 core，并继续使用 rune
  坐标以兼容 TextPainter source range；新的 complex session 使用 grapheme
  坐标，避免拆开代理对、ZWJ emoji 和 combining sequence。
- 新增 `NovelReaderComplexHtmlBoundaryIndexer`、
  `NovelReaderComplexHtmlSliceSession`、boundary、protected range 和 slice 模型。
  Session 持有不可变 index，多次 boundary 查询和 slice 不会重新 parse HTML。
- Boundary kind 覆盖 block end、hard break、sentence end、word end、grapheme
  end、Ruby cluster end、protected-inline end 和 atom end；同一 offset 只保留
  preference 最高者。Boundary 保留原 episode/node anchor，并将 grapheme offset
  映射为连续 text anchor。
- `<ruby>` 整体作为 protected range，base、`rt`、`rp` 之间不生成切点；已知
  smiley 或显式 `data-y300-protected-inline` 节点使用一个合成 grapheme 占位，
  只能整体进入一个 slice。未知尺寸 inline widget 的 production 分类仍保持
  atomic，Phase 3 不放宽 classifier。
- Slice 只克隆与范围相交的祖先 wrapper 和节点，保留 strong/font/span/a、
  未知 wrapper 及原属性，并重新输出闭合 HTML。Entity 先由 DOM 解码为单个
  grapheme，序列化时重新 escape，不会切开 `&amp;`。
- 空白、NBSP、全角空格、零宽空白、纯 `<br>` 和空 block 的 slice 返回
  `hasRenderableContent=false`；protected inline/ruby 视为可渲染内容。空 atom
  只提供 offset `0` 的 atom-end boundary，不生成伪页面。
- Index 构建复杂度为 `O(N + G)`，其中 `N` 为 DOM 节点数、`G` 为 grapheme
  数；boundary 去重与排序为 `O(G log G)`（遍历阶段为 `O(G)`），slice 成本与
  相交节点和输出片段长度相关。Phase 4 可按 boundary kind 分层选择 coarse 与
  grapheme 候选，无需第二套 index。
- 自动化覆盖 CJK/Latin、ZWJ emoji、组合字符、HTML entity、嵌套 wrapper、
  异常 wrapper、Ruby+`rt/rp`、smiley、连续 anchor、boundary preference、
  空白范围和 31 组生成式嵌套组合；counting codec 证明 safe 与 complex session
  都只 parse 一次。

验收：

- 对任意合法 boundary pair 生成闭合 HTML。
- 连续 slices 可重新拼接出相同可见文本顺序。
- 不重复、不丢失 grapheme。
- 不拆 Ruby base/rt，不拆 smiley cluster。
- 同 atom 只解析一次。
- property test 覆盖嵌套 strong/font/span/a/ruby 和异常 wrapper。

### Phase 4：有界 fit searcher

目标：在确定性 fake measurer 下完成可验证的 upper-bound 搜索。

> 实施状态：已完成（2026-07-21）。本阶段新增纯 fit-search service 和结果
> 模型，只消费 Phase 3 的合法 boundary 与既有 pagination measure session；
> 尚未接入 hybrid planner、真实 renderer 或 page composer，因此不改变生产
> 分页页数与用户可见行为。

交付：

- `NovelReaderComplexHtmlFitSearcher`。
- 分层 boundary 搜索。
- whole remainder fast check。
- 当前页放不下最小片段时的 flush-and-retry。
- 12 probe 硬预算。
- cache hit、cancel 和非单调检测。

实际落地：

- 新增 `NovelReaderComplexHtmlFitSearcher`、
  `DefaultNovelReaderComplexHtmlFitSearcher`、
  `NovelReaderPaginationMeasureContext` 与
  `NovelReaderComplexHtmlFitResult`。Measure context 直接复用现有 persistent
  `NovelReaderPaginationMeasureSession`、chapter、pagination key 和 atom id，
  没有建立第二套 renderer 或缓存协议。
- 每次搜索先测完整 remainder；整段可容纳时一次 probe 返回。整段 overflow 后
  测最小合法片段，随后先在 block/hard-break/sentence/word/Ruby/protected-inline
  等 coarse boundary 上做 upper-bound，再只在已验证 fit 与首个 overflow 之间
  的 grapheme boundary 上细化。
- 当前 buffer 连最小片段都放不下时，以空 buffer 在同一搜索事务中重试，并通过
  `requiresFreshPage` 把“先封页”决策显式交给 Phase 5；空白整页仍放不下时返回
  `fits=false` 的已测最小片段，供后续 minimum-fragment 降级处理。
- 每次 measurement session 调用前后都检查 cooperative cancellation。单次搜索
  最多调用 session 12 次；预算不足时只返回 offset 最大的已验证 fit，并标记
  `budgetExceeded`，永远不返回未测候选。
- 每个 buffer composition 维护独立单调性 ledger。更长范围高度显著下降，或在
  较短候选 overflow 后较长候选重新 fit，都会抛出稳定错误码
  `complexFitSearchNonMonotonic`，留给 Phase 5 路由 atomic/vertical fallback。
- 相同 candidate 在单次搜索内按精确 HTML 与 range 复用；跨搜索缓存和并发
  single-flight 继续由现有 `NovelReaderCachingPaginationMeasureSession` 负责。
  Search result 分别记录 session probe 和 cache hit 数量，不记录正文。
- 高度判定沿用 renderer validator 的 `0.5` logical-pixel 容差。空 atom 直接
  返回 exhausted 的不可渲染空 slice，不创建 measurement probe 或伪页面。

验收：

- 返回结果始终是最大已验证 fit boundary。
- exact fit、全部 fit、全部 overflow、只有最小片段 fit 均有测试。
- 搜索不会返回未测量候选。
- 取消后不继续 probe。
- 相同 candidate 复用 cache。

自动化覆盖 whole remainder fast check、exact fit、部分 fit、全部 overflow、仅
最小片段 fit、buffer flush-and-retry、coarse-to-grapheme 搜索顺序、12 probe
硬预算、取消、measurement cache、非单调拒绝和空 atom；并与 Phase 3 boundary
测试共同验证 searcher 只消费合法闭合 slice。

### Phase 5：Flowable complex engine 与 composer 合页

目标：让文字型复杂 HTML 真正跨页并保持页面开放。

交付：

- `NovelReaderFlowableComplexPaginationEngine`。
- `appendFlowableComplexChunk`。
- safe -> complex -> safe 连续组合。
- complex remainder 跨多页循环。
- dedicated image/table/collapse 前后强制 flush。
- renderer revision 提升和旧 cache 失效。

验收：

- 短 flowable complex 标题不独占页。
- 长未知字体段落可以跨多页。
- accepted fragment 后续正文可以继续填充同页。
- 图片、表格、折叠始终独占页。
- anchor ranges 连续，恢复定位正确。
- 增量 plan 只发布已经封口的稳定页。

### Phase 6：Ruby 与 protected inline

目标：将 Ruby 和稳定 inline widget 纳入 flowable complex path。

交付：

- Ruby cluster boundary adapter。
- `<rp>` fallback 兼容。
- 已知尺寸 smiley/protected-inline adapter。
- 未知尺寸 inline widget 的 atomic fallback。

验收：

- Ruby 长段落跨页但 cluster 永不拆分。
- 日文、英文、间隔点注音和连续 Ruby 通过 fixture。
- smiley 可随文字分页，不进入正文图片独占页。
- inline widget 加载不会重排已发布页面。

### Phase 7：真实 renderer 集成、缓存和性能

目标：将 fake measurer 搜索替换为持久 HtmlWidget measurement session，并满足预算。

交付：

- production `NovelReaderPaginationMeasureSession` 接入。
- boundary index cache、range measurement cache 和 in-flight single-flight。
- 完整 diagnostics。
- first-page priority 和 generation cancellation。
- timeout、search budget 和纵向降级。

验收：

- 普通 safe text probe 数不增加。
- complex accepted candidate 的最终验证命中 cache。
- 80 页纯文字性能与当前实现相当。
- 混合文章成本与 flowable complex 页面数相关，而不是所有正文字符。
- 无无限 loading、悬挂 session 或迟到页面写入。

### Phase 8：全量回归、真机与旧路径清理

目标：完成兼容验证并删除通用 `complexHtml` 原子语义。

交付：

- 四份现有特殊格式 fixture + 本次异常字体 fixture + 表格 fixture。
- Android/iOS Profile/Release 验收矩阵。
- LTR/RTL、主题、字号、行高和 viewport 矩阵。
- 删除 deprecated `complexHtml` 默认原子分支。
- 更新 `docs/开发文档.md` 和原 HTML-first 方案的实施状态。

验收：

- 所有文字型 complex reason 均有 flowable 或明确 atomic 解释。
- 不存在“route=complexHtml 所以自动独占页”的代码分支。
- 图片、表格、折叠独占规则稳定。
- safe text、书签、搜索、恢复和真实可见页进度无回归。
- 用户完成目标设备真机验收后才将方案标记完成。

## 19. 测试计划

### 19.1 Classifier 与 normalizer

- quote-only `font face` 删除属性但保留正文。
- 空 face、单引号、双引号、重复 entity 和前后空白。
- 有效已知字体继续 safe。
- 有效未知字体进入 flowable complex。
- text-only unknown wrapper 进入 flowable complex。
- position/float/table/collapse/iframe 不进入 flowable complex。

### 19.2 Boundary 与 slicer

- CJK、Latin、emoji、组合字符、代理对和 `&nbsp;`。
- 嵌套 strong/font/span/a。
- `<br>`、连续空行和空 div。
- Ruby base/rt/rp。
- protected smiley。
- 任意连续 slice 可见文本不丢失、不重复。
- 不产生空白假成功页。

### 19.3 Searcher

- 0、1、2、N 个候选边界。
- 全部 fit、部分 fit、全部 overflow、exact fit。
- 当前 buffer 非空和空白页重试。
- 非单调 fake measurer 触发 fallback。
- 12 probe 上限。
- cache 和 single-flight。
- cancellation。

### 19.4 Composer

- safe -> flowable complex -> safe 同页。
- 两个短 flowable complex atom 同页。
- flowable complex 跨三页。
- pending `<br>` 与复杂文本高度正确。
- dedicated image/table/collapse 前后强制 flush。
- atomic widget reason 与 dedicated reason 不混淆。

### 19.5 Renderer 一致性

- 使用真实 `ForumHtmlWidgetPostRenderer` 逐页约束测试。
- 默认 `18.5 × 1.6`、最小/最大字号和 text scale。
- light/sepia/dark。
- 450×800、小屏、平板和横屏。
- 页面实际高度不超过 content constraint。
- 二分接受边界在真实 renderer 中无 RenderFlex overflow。

### 19.6 页面级验收

- 本次样本第一页不再只有“喜歡的人和義妹”。
- 第二页不再只有“第一話（１）”。
- 页面尽可能填充，但不删除作者空行。
- 页码、slider、搜索、书签和恢复位置正确。
- 前台/后台、切章和设置变化不会提交候选页进度。

### 19.7 性能

- 20/80/200 页 safe-only 合成文章。
- 10%、50%、100% flowable complex 文章。
- 每页边界数、probe 数、cache hit 和 full-plan 时长。
- Debug 只用于诊断；发布门禁使用 Profile/Release 真机。

## 20. 文件落点建议

```text
lib/features/novel/presentation/models/
  novel_reader_pagination_layout_policy.dart
  novel_reader_complex_html_boundary.dart
  novel_reader_flowable_complex_pagination.dart

lib/features/novel/presentation/services/
  novel_reader_legacy_markup_normalizer.dart
  novel_reader_complex_html_flowability_inspector.dart
  novel_reader_complex_html_boundary_indexer.dart
  novel_reader_complex_html_fit_searcher.dart
  novel_reader_flowable_complex_pagination_engine.dart
  novel_reader_pagination_layout_policy_resolver.dart

继续修改：
  novel_reader_pagination_atom_classifier.dart
  novel_reader_html_text_range_slicer.dart
  novel_reader_hybrid_pagination_planner.dart
  novel_reader_pagination_page_composer.dart
  novel_reader_pagination_measure_adapter.dart
  novel_reader_pagination_diagnostics.dart
  novel_reader_html_paged_surface.dart
```

如果 legacy normalizer 必须同时服务帖子页和小说纵向 renderer，应放入 `thread/presentation/html_rendering/` 的共享 preparation 模块，不得在 novel 内复制一份清洗规则。

## 21. Review 清单

- 是否仍存在 `complexHtml == non-breakable` 的隐式判断。
- 是否只对 flowable complex text 使用二分。
- 是否按 DOM 合法边界而不是 HTML 字符串下标切片。
- 是否每个 atom 只解析/index 一次。
- 是否会切开 grapheme、Ruby 或 protected inline widget。
- accepted candidate 是否经过真实 renderer 测量。
- 搜索是否返回最大已验证 fit，而不是最后一次 candidate。
- 是否有 12 probe 硬上限和取消检查。
- 短 complex text 后页面是否保持开放。
- 图片、表格和折叠是否始终独占页。
- atomic widget 是否与 flowable complex 分离。
- 无效 `font face` 是否只删除无效属性而不删除有效样式。
- 是否复制了共享 CSS、颜色、字号或字体解析。
- 是否提升 renderer/normalizer/index revision 并使旧 cache 失效。
- 是否保持 anchor、搜索、书签和恢复连续。
- 是否把 probe、candidate 或缓存误写为阅读进度。
- 是否保留 `version=1` 小说请求链路。
- diagnostics 是否不包含正文和敏感信息。

## 22. 完成定义

只有同时满足以下条件，本方案才算完成：

1. 本次异常字体样本不再产生两个标题独占页。
2. 普通 safe text 仍只进行一次 TextPainter 布局，不回退到全 HTML 二分。
3. 所有以文字为主体且满足单调性的复杂 HTML 可以在合法 DOM 边界跨页。
4. 短 flowable complex 片段可以与前后文字合页并保持页面开放。
5. 正文图片、表格和折叠块始终独占页。
6. iframe/video/audio/canvas 等真正不可拆组件使用独立 atomic policy。
7. Ruby base/annotation、grapheme 和 protected inline widget 不被拆开。
8. 每个 flowable atom 只解析一次，renderer probe 有界、可缓存、可取消。
9. 页面无空白假成功、无 RenderFlex overflow、无正文丢失或重复。
10. anchor、搜索、书签、恢复和真实可见页进度通过回归。
11. safe-only 长文章性能不低于当前 hybrid planner。
12. complex-heavy 长文章超预算时可靠回到纵向模式。
13. 所有分页派生数据只保存在进程内，SQLite 正文和 `version=1` 请求不变。
14. 自动化通过，且用户完成目标设备 Profile/Release 真机验收。

## 23. 推荐实施顺序

下一步应从 Phase 0 开始，不应直接修改 composer：

```text
先把真实样本变成稳定红测
  -> 再锁定 route/layout policy
  -> 再实现 no-op legacy normalization
  -> 再建设 DOM boundary/slicer
  -> 再实现纯搜索器
  -> 最后接入真实 renderer 和 composer
```

这样可以先用 Phase 2 的低风险规范化解决本次 `&amp;quot` 标题问题，同时保留 Phase 3-8 对其它 flowable complex HTML 的完整工程化能力，避免用一个样本驱动大范围、不可验证的 composer 特判。
