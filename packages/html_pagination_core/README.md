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

`HtmlDisplayTextProjection` 的普通模式保留 NBSP 和全角空格语义。格式处理者可显式
选用 `HtmlDisplayWhiteSpace.singleLine`，将 BR、Unicode 空白与不换行空格合为一个
空格并修剪边缘；原始源码点边界、跨 run 的 CRLF 和折叠范围仍可显式查询。
来源缺口处继续区分上下游边界；坐标投影不证明边界之间的全部内容已经可见。
该策略不删除零宽连接符等非空白控制字符，不承担论坛格式识别或语义锚点迁移。
`isSingleLineWhitespace` 供同一格式处理者判定外围空白。行内片段可显式使用
`preserveCollapsibleEdges: true`，将两端可折叠空白保留为有真实来源范围的一个空格，
交由父格式化上下文决定摆放或修剪；实际硬换行边缘仍不保留折叠空白。
默认段落行为保持修剪边缘，预格式化、NBSP/全角空格和来源缺口规则不变。
该选项不插入虚构字元，也不决定 ruby 分段、可见 coverage 或语义身份。

`HtmlDisplayTextProjection.concatenate` 组合已经独立排版的文字上下文，不重新折叠空白，
不跨上下文合并字素；通过 `HtmlDisplayTextSegment.runIndexOffset` 显式绑定父级样式表。
普通相邻样式 span 仍应一次 build，避免把样式边界误当成独立字素上下文。
`slice` 仅裁出显示坐标窗口，端点必须是现有完整字素边界，不是 HTML 切片。
窗口保留原 run 编号，以及两端来源缺口的上下游亲和性，空窗口也遵循此约定。
组合输入须按真实来源排序，并受输出文字和片段数量预算限制。
来源映射相等还需核对字素分段与边缘亲和性；只比较相同文字不足以复用来源映射。
`displaySegmentationHash`/`hasSameDisplaySegmentation` 仅描述文字与独立字素边界，
不证明字体、样式或排版参数相等，也不证明语义身份或可见 coverage。投影 revision 为 4。

`HtmlInlineTextProjection` 为父排版引擎单独建立 UTF-16 坐标：每个显式原子范围仅在
`engineText` 中占一个 U+FFFC，原来的 `display` 仍保存子文字、独立字素和真实来源。
原子范围必须非空、有序、不重叠且位于完整显示字素边界，受原子数、显示文字和引擎
文字三个预算限制；普通正文中的 U+FFFC 仍是有真实来源的文字，不自动当作原子。
`engineAtDisplayUtf16` / `displayAtEngineUtf16` 保留上下游亲和性，原子内部或普通
字素内部的位置返回边界近似，不能冒充精确子命中。子布局必须提供其实际命中结果。
`sourceAtEngineUtf16` 继续保留来源缺口；`displayRangeForEngineRange` 严格核对整字素
和原子边界，但其结果不是可见 coverage。原子几何、绘制、分页与生命周期仍归 renderer。
映射 revision 为 1；缓存还需核对完整样式、几何和 owner，映射相等不替代这些条件。
`displayOffsetAtEngineUtf16` 只做原始 UTF-16 变换，供真实物理行记录坐标：fallback
字素可能跨行，原始偏移必须保留，同时用 `displayAtEngineUtf16.isExact` 禁止在其间
分页。该原始值不是合法光标、语义锚点、显示窗口或 HTML 切片边界。

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
