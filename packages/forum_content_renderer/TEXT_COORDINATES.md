# 文字坐标与来源投影

唯一实现位于 `lib/src/text/`，公开入口为 `package:forum_content_renderer/forum_text.dart`，也由渲染主入口重导出。模块本身不导入 Flutter、Widget、Context、App 或传输；包具有 Flutter 传递依赖，独立运行使用 Flutter 工具链。

`HtmlTextCoordinates` 区分源码点、UTF-16 和扩展字素。`HtmlSourceDomIndex` 在一次 repaired DOM 上建立全局来源与跨样式字素分段，只读借用原节点，不修改、切片或序列化 HTML。原节点不可被调用方改写。`HtmlSourceTextMap` 只保留 child-path 范围与边界，不保留 DOM；BR 占一个源码点，文字为空的 widget 占零，script/style 不进入来源文字。解析端口和保护 predicate 保持显式注入。

旧开发分页包通过这个公开基础入口复用唯一索引；DOM 克隆、切片序列化、合法分页边界与 fit 搜索仍归旧包。坐标移动不改变业务语义锚点、文本身份、来源转换或持久化。`HtmlPaginationCancellation` 与 `HtmlPaginationWorkSlice` 保留既有合同，实际 owner/generation、取消信号和异步会话仍归宿主。

`HtmlDisplayTextProjection` 的普通模式保留 NBSP 和全角空格语义。格式处理者可显式
选用 `HtmlDisplayWhiteSpace.singleLine`，将 BR、Unicode 空白与不换行空格合为一个
空格并修剪边缘；原始源码点边界、跨 run 的 CRLF 和折叠范围仍可显式查询。
来源缺口处继续区分上下游边界；坐标投影不证明边界之间的全部内容已经可见。
该策略不删除零宽连接符等非空白控制字符，不承担论坛格式识别或语义锚点迁移。
`isSingleLineWhitespace` 供同一格式处理者判定外围空白。

格式处理者也可显式使用
`suppressLineBreaks: true`，只将 BR、CR/LF、NEL、Unicode 行/段分隔符合为有真实来源
范围的 U+0020；连续换行合并，跨样式 CRLF 仍只占一次显示。原有 normal/pre-line 的
空白折叠和 pre/pre-wrap 的普通空格、Tab、NBSP、全角空格保持各自规则。该策略不做
语言启发式删除，不承担论坛格式识别。只修改显示投影，不改写来源或原始输入预算。
显示投影以稀疏位置保留实际可折叠段换行来源，`slice` 和 `concatenate` 保留该记录；
不能从投影后的普通空格猜测是否存在源码换行。纯空白上下文可通过
`resolveWhitespaceSegmentBreaks` 接收格式处理者的显式策略及相邻完整字素，
只删除具有该来源记录的完整空格字素，保留样式 run 编号、未删除的文字和上下游来源围栏。
空结果不生成字形或来源；源码区间形成缺口时，边界仍为近似。语言策略不由包推断，
保留空格和 Tab、NBSP、硬换行的原有规则。`firstGrapheme` / `lastGrapheme`
仅提供实际显示字素上下文，不是语义锚点。显示投影 revision 为 8。
行内片段可独立使用 `preserveCollapsibleEdges: true`，将两端可折叠空白保留为有真实来源范围的一个空格，
交由父格式化上下文决定摆放或修剪；实际硬换行边缘仍不保留折叠空白。
默认段落行为保持修剪边缘，预格式化、NBSP/全角空格和来源缺口规则不变。
该选项不插入虚构字元，也不决定 ruby 分段、可见 coverage 或语义身份。

`HtmlDisplayTextProjection.concatenate` 组合已经独立排版的文字上下文，不重新折叠空白，
不跨上下文合并字素；通过 `HtmlDisplayTextSegment.runIndexOffset` 显式绑定父级样式表。
同一原始样式表的多个窗口可改用 `runIndexMap`，逐实际使用的 run 显式映射到父表，
避免复制原样式表；与非零 offset 互斥，缺失或负数归属明确失败。只映射样式所有权，
不改变文字、字素、源码点、亲和性或来源顺序；组合结果不保留调用方的可写 Map。
普通相邻样式 span 仍应一次 build，避免把样式边界误当成独立字素上下文。
`slice` 仅裁出显示坐标窗口，端点必须是现有完整字素边界，不是 HTML 切片。
窗口保留原 run 编号，以及两端来源缺口的上下游亲和性，空窗口也遵循此约定。
组合输入须按真实来源排序，并受输出文字和片段数量预算限制。
显示顺序确需不同于来源顺序时，可显式提供 `sourceOrder`：它是全部显示片段索引按
原始来源顺序排列的完整双射，每个片段内部仍须来源有序。实际源码点范围及空窗口
亲和性必须通过顺序/重叠检查，重复、遗漏或重叠不能靠排列参数绕过；默认仍拒绝重排。
输出保留原展示顺序、样式、独立字素和实际来源，不保留调用方可写的排列数组。
`sourceEnvelope` 查询完整显示窗口内实际来源的最小/最大范围，保留隐藏缺口，不能
证明中间内容可见或语义精确。来源有序时使用端点快路径，重排窗口只扫描其实际文字，
不额外常驻来源索引；增量消费者应合并新增窗口包络，避免反复扫描增长前缀。
来源映射相等还需核对字素分段与边缘亲和性；只比较相同文字不足以复用来源映射。
`displaySegmentationHash`/`hasSameDisplaySegmentation` 仅描述文字与独立字素边界，
不证明字体、样式或排版参数相等，也不证明语义身份或可见 coverage。投影 revision 为 8。

`HtmlInlineTextProjection` 为父排版引擎单独建立 UTF-16 坐标：每个显式原子范围仅在
`engineText` 中默认占一个 U+FFFC，原来的 `display` 仍保存子文字、独立字素和真实来源。
revision 3 可显式加入一个 `enginePrefix` 机械单元：只进入引擎开头，不进入 display、
原子子项/样式归属或来源，完整 UTF-16 长度计入引擎字符预算。其起点可作为完整引擎单元
的边界（`isLegalEngineBoundary`），但不是精确来源 caret；前缀内部不可截断，前缀自身
对应空显示区间，不能提供字形或阅读 coverage。原子索引保持原值，engine 坐标整体后移
前缀长度；真实文本中的同字符仍保留独立来源。前缀不能用来隐藏真实正文；具体机械字符、
实际缩进宽度、字体缩放、布局/绘制与 owner 校验继续归 renderer。
格式处理者可显式传入 `softSpaceAtoms`，让两个紧邻不透明原子之间的真实 ASCII
空白范围仅在引擎中占一个可折叠 SPACE。边缘、相邻软间隙、跨普通文字或非空白范围
不准入；是否满足实际 CSS 可折叠规则仍由格式处理者决定。标记不会增加来源文字，
与同范围的不透明原子拥有不同映射身份；宽度、行边修剪及真实字形仍须由 native 验证。
原子范围必须非空、有序、不重叠且位于完整显示字素边界，受原子数、显示文字和引擎
文字三个预算限制；普通正文中的 U+FFFC 仍是有真实来源的文字，不自动当作原子。
`engineAtDisplayUtf16` / `displayAtEngineUtf16` 保留上下游亲和性，原子内部或普通
字素内部的位置返回边界近似，不能冒充精确子命中。子布局必须提供其实际命中结果。
`sourceAtEngineUtf16` 继续保留来源缺口；`displayRangeForEngineRange` 严格核对整字素
和原子边界，但其结果不是可见 coverage。原子几何、绘制、分页与生命周期仍归 renderer。
映射 revision 为 2；缓存还需核对完整样式、几何和 owner，映射相等不替代这些条件。
`displayOffsetAtEngineUtf16` 只做原始 UTF-16 变换，供真实物理行记录坐标：fallback
字素可能跨行，原始偏移必须保留，同时用 `displayAtEngineUtf16.isExact` 禁止在其间
分页。该原始值不是合法光标、语义锚点、显示窗口或 HTML 切片边界。

`HtmlTextBandProjection` 为有界的一组独立子文字建立显式 engine 窗口；子文字继续
保有自己的显示投影、字素和来源缺口。批次间使用的换行/零宽 spacer 仅存在于引擎，
不计入 DOM 源码点、子 display 或语义锚点。输入须按实际来源排序，默认最多 64 个子项、
16384 个真实显示 UTF-16 单位和 16573 个引擎单位（另计每个间隔的 3 个虚拟单位）。
已知子项的命中若落在引擎间隔或其他子行，会 clamp 并标记近似；子选区只扩展到自身
完整字素，不选择引擎间隔。纯映射允许空子窗口并保留亲和性；实际排版端口可额外准入。
该映射 revision 为 1，不证明批次字体度量、绘制隔离、资源预算或可见 coverage。

算法合成语料只在 `test/text/` 维护。App 保留字体、章节转换、搜索、复制、锚点与数据库时序集成；不引用包测试 fixture。
