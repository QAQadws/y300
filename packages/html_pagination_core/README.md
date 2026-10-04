# html_pagination_core

Y300 的本地纯 Dart HTML 切片与分页边界决策核心。通过仓库内 path 依赖使用，
运行时仅依赖 `characters` 和 `html`；不依赖 Flutter，不执行字体排版。

唯一公开入口为 `package:html_pagination_core/html_pagination_core.dart`。
`lib/src` 是内部实现，DOM 索引树不对消费者公开。包内纯算法及合成样本只维护一份。

## 坐标与切片

- `HtmlTextCoordinates` 转换 UTF-16 与 Unicode 码点，并按完整字素生成搜索上下文。
- `HtmlTextRangeSlicer` 的源坐标使用 DOM 码点：inline BR 占一个码点，文本空白保留；
  无文字组件只占合成字素，不占源码点。连续 inline 文本跨 span 按同一字素串分段。
- `DefaultHtmlComplexBoundaryIndexer` 提供合法字素边界、对应源码点与受保护范围。
  Ruby 自动作为完整单元；Host 通过 `HtmlProtectedInlinePredicate` 判定其他稳定组件。
  `HtmlComplexSliceSession.slice` 要求两端合法，不能在受保护范围内部切开。
- `HtmlTextRangeSliceSession` 是底层范围切片能力：`slice` 保留上界 clamp 行为，
  `sliceRunes` / `sliceGraphemes` 严格检查范围。需要合法分页边界时使用 complex session。
- 切片保留祖先、属性和受保护/不透明节点，并直接统计克隆树的节点数。
  沿用原序列化语义：元素用 `outerHtml`，文字 escape，顶层不透明节点用 `node.text`。
  因而顶层注释输出其文字，元素内部注释仍由 `outerHtml` 保留；parse 端口不改变此规则。

源码点、DOM 字素和 UTF-16 是不同单位。作品/章节的持久化语义锚点及转换来源属于
Host，必须显式投影；不能用语义锚点直接切 HTML，也不能以虚拟组件污染文字位置。

## Fit 与协作端口

`DefaultHtmlComplexFitSearcher` 从邻页容量窗口起步，在合法边界上扩张、二分和选择
已验证前缀，保持探测数量、候选 HTML/DOM 大小与最小不可拆片段的有限预算。
结果记录 probe/cache hit、fresh-page 和 budget 状态；非单调观测按原错误分类退出，
不保证任意非单调 HTML 布局的全局最优边界。

`HtmlPaginationMeasure` 必须测量 candidate 的**完整 HTML**（含已有页 buffer），
返回有限非负高度与缓存命中标记。候选 start/end 是当前复杂片段的字素范围，不能
代替完整内容/布局缓存 identity。最小片段可能超过页高，Host 决定既有溢出/回退策略。

`HtmlPaginationCancellation` 由 Host 实现，负责信号、等待中断和事件循环让步；
`HtmlPaginationWorkSlice` 沿用协作切片。取消不等于强制中断同步解析或排版。
纯搜索错误使用 `HtmlPaginationException`；Host 回调及取消端口的错误原样传播。
输入 HTML 与保护 predicate 应在同一 session 内稳定，predicate 不应持有 UI 资源。

实际 parser/论坛保护规则、Flutter 测量 session、缓存 identity、owner/generation、
业务锚点投影、composer、流式发布、章节/会话缓存和持久化继续由应用负责。
包不提供完整阅读器、HTML sanitizer、renderer 或随机恢复检查点。

## 验证

在本目录执行：

```shell
dart pub get
dart analyze --fatal-infos
dart test --reporter expanded
dart run example/paginate_html.dart
```

示例使用确定性的合成高度验证纯决策和内容守恒，不代表真实字体排版性能。
App 继续验证章节转换、搜索/书签、真实 renderer、数据库和阅读时序；两层均接入 CI。
变更坐标、序列化、保护规则或搜索策略时须同步兼容说明与相应回归。
