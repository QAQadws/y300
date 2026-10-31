# forum_content_renderer

本地 Flutter HTML 准备与渲染包，负责 prepared document、DOM 规范化、主题与文字样式、正文布局、折叠和图片 viewport 调度。

Core renderer 必须显式接收 `preparedDocument`、`options`、`labels` 和 `theme`。图片 `Host` 可选；宿主通过中立的准备、显示、尺寸和预取端口提供图片能力。准备资源与显示资源分别保持身份，迟到回调和取消仍受当前绑定与显示代次约束。

宿主可提供已解析、未缩放的 `textStyle` 和根 `textAlign`。提供 style 时不再应用 options.fontScale；系统缩放仍由 renderer 环境决定，作者 CSS 和段距策略继续生效。缺省参数保留默认样式及 start 对齐；仅改变对齐也会使缓存正文和根属性失效，不重挂图片/折叠状态。

应用偏好及其持久化、文字转换、本地化、默认 URL/缓存装配、provider、Cookie 和会话继续由宿主负责。包不依赖应用源码或 provider，不装配 Host 传输或会话，也不调用论坛客户端的网络请求 API。

首版通过同仓路径依赖 `yamibo_forum_client`，仅复用公开的图片来源纯策略，保留 DOM 属性优先级、来源规范化和附件判定的唯一实现。

`DiscuzFontSizePolicy`、颜色对比度/色调策略和 `ForumCollapseChrome` 的唯一实现也归本包。HTML、编辑器及其测试统一通过公开入口 `forum_content_renderer.dart` 使用；应用不保留同名副本或旧路径转发。应用共享的 `RichTextTypography` 和文字转换仍由宿主持有。

`ForumHtmlPreparationPipeline` 使用显式 URL resolver 和同步 image policy。prepared 资源实现须为不可变纯值，可随后台准备结果传递；它不持有服务、Widget、Ref 或闭包。renderer 不重做 Host 转换或图片准备，也不替代小说分页。

## 长正文与按需布局

`RenderMode.column` 生成 box 正文，适合卡片等 box 宿主。`RenderMode.sliverList` 需要真实的外层 sliver 视口。宿主应保留原有楼层懒构建：一次挂载每个楼层的 renderer，再仅让它们的 sliver 懒布局，会提前触发所有楼层的准备工作。内嵌 shrink-wrap 列表仍需测量正文总高度，不能用它证明屏外段落没有布局。

当前 fwfh 0.17.4 的 sliver 模式会先解析整份 HTML、处理样式并建立根 children 列表，之后按需挂载与布局子项。平级段落可减少初始 RenderObject 数量；一个带装饰的巨大容器、一个含大量 BR 的行内段落仍可能成为单个子项，初始构建不会随可见段落数减少。分别统计 DOM/样式访问、文字 Widget 创建、实际挂载和布局，不能将这些指标混为一项。

进一步减少整份 HTML 构建，需要宿主提供经过验证的显示片段，并在外层 lazy delegate 中按需创建 renderer。片段使用完整准备结果派生的 HTML，保留原始可读图片编号和完整 `sequence`；逐片段重新 preparation 会改变编号和资源身份。根 `sourceId` 还参与折叠身份，布局展示记录的键也需保持独立，不能通过任意换名解决两者的生命周期。

显示片段的边界须保留连续 inline 语境、换行、margin collapsing、祖先背景/边框/padding、列表编号和跨片段锚点。`compact` 会将每份 HTML 的末尾视为内容末尾；把每个 P 单独渲染会丢失内部段距。完整 DOM 节点或分页合法切点本身不证明连续滚动排版等价，复制祖先到多个片段也会重复祖先盒模型。

分块宿主负责定义当前可见位置、总高度是否准确和实际末尾是否已确认。sliver 的早期 scroll extent 可能是估算，renderer ready 只表示当前 root body 已构建。全文百分比恢复与读完确认不能直接采用可见前缀高度或把估算当完整正文高度。选区、图片返回定位和锚点跳转还需覆盖未挂载目标；`revealImage` 继续只接受实际挂载的图片锚点。

通用 renderer 保持整份 prepared document 的兼容路径；应用在自己的会话、布局和阅读契约下决定安全分块范围。收益验证应同时比较简单段落与复杂单块的首屏、尾部定位、返回滚动、字体/主题变化和内容顺序，不单凭理论段落减少比例启用分块。

## 转换、交互与图片生命周期

`ForumHtmlRenderOptions.enablePlainTextLinks` 默认关闭，开启后仅在显示准备的 DOM 中为完整 HTTP(S) 纯文本网址生成链接，不修改原始 HTML 或可见文字。启用值参与 options 的相等、hash 与 `copyWith`，宿主准备缓存须包含该配置。链接使用既有 URL 回调，renderer 不负责域名分类、导航或浏览器启动。已有 anchor、代码块、隐藏／非正文内容保持原样；跨作者行内标签打断的网址保守跳过，不生成可疑的半段链接。排除区域的有界首尾文字只用于拒绝跨边界前缀，不生成内部链接；两侧有空白分隔的完整网址仍可独立链接化。硬换行／块边界也不拼接网址，对边缘具有斜线、域名点或参数等明确续接迹象的前缀保守跳过，源文本硬行包括 CR／LF／U+2028／U+2029。原生折叠接管的首个直接 `.showcollapse_content` 子容器，其 `display:none` 属于折叠显示状态，展开后内部完整网址可点击；普通隐藏容器、hidden 属性及永久隐藏内容仍跳过。生成链接保留作者已适配颜色及字号、字重、行高，无作者颜色时使用主题 link 色。依赖 prepared HTML 的小说语义文档、分页与锚点消费者继续使用默认值；扩展启用范围前须独立验证身份兼容。

`ForumHttpTextLinkDetector` 是公开中立纯值能力，供 App 选区／剪贴板与 DOM 准备复用，不读取平台、不联网、不判断论坛目标。`detect` 返回原文 `text`、`uri` 和 UTF-16 `start`／`end`，按出现顺序保留重复网址。默认输入上限 64 Ki code unit、10 个出现位置、单个 URL 上限 8 Ki；`isLimited` 表明范围受限，要求唯一目标的消费者应忽略整次结果。超长候选不会以截断前缀返回，DOM 按完整行内文字范围调整输入／数量上限后扫描，不截断整篇正文。范围不能直接当小说语义码点或 DOM 源坐标。当前识别显式 HTTP(S) 与完整 DNS／IP／localhost host，保留 query／fragment／URL 内配对括号，排除外围中文标点；裸域名、相对路径及其他 scheme 保持普通文字。

缓存命中时 callbacks 与 labels 可更新，图片点击启用/禁用不会替换图片状态或拦截无图片回调的链接。options、完整 theme signature 与布局值变化会使正文样式失效。ready 可重复报告，宿主应保持幂等。

宿主可传入可写的 `collapseExpansion` Map 观察正文的有效折叠状态。renderer 为当前渲染的折叠补齐实际默认值，已有用户选择优先，嵌套折叠沿用同一状态容器。容器反映已渲染折叠，不是完整文档的预扫描结果，正文身份变化时由宿主管理其生命周期。宿主可将该状态纳入布局 revision，按实际可见布局重新测量几何；renderer 不决定章节是否已读，不要求展开折叠内容，也不区分目录与正文。未提供容器的消费者保持原行为。该能力不写入阅读记录或持久偏好。

`ForumHtmlRenderer.imageAnchorController` 可注入正文级 `ForumHtmlImageAnchorController`，嵌套折叠共享根正文的 readable sequence。`revealImage` 按 index、cacheKey 与 URL 校验当前已挂载图片，使用宿主提供的 ScrollController 在至多三帧内对齐真实上沿。关闭折叠、缺失锚点、正文换绑、取消或销毁不猜测目标；不下载图片、不保存阅读进度，也不持有卸载后的正文树。宿主负责在覆盖正文的阅读器退出前调用、校验来源代次并在会话结束时 dispose；未提供 controller 的消费者保持原行为。

`ForumHtmlImageViewportCoordinator` 默认保留磁盘预取。传入 `ForumHtmlImagePredecodePolicy` 可启用方向性邻图准备；宿主通过可选 `ForumHtmlImagePredecodeHost` 实现有界首帧预解码，返回 decoded／diskOnly／failed／cancelled，不暴露 App 缓存类型。成功预解码的邻图在进入视口前挂载显示组件。普通可见加载的成功帧也可保留：Host 通过同步 `canRetainDisplayedImage` 使用原始尺寸、显示宽度与 DPR 核对相同字节预算，不发起额外下载或解码；尺寸提示晚于首帧时可补充准入。失败只释放可见等待名额，不作为解码成功或自动重试。

`retained` 与 `display` 共用同一元素和有效回调代次，越过可见边缘不重新查询磁盘或插回占位。仅当前解码窗口内、张数限制内且通过预算准入的成功图片可保留组件；远离窗口／隐藏／绑定或解码宽度失效即释放。diskOnly／failed 不提前挂载。屏外保留组件通过 `TickerMode` 暂停动图，进入视口恢复。块图工作身份包含 Host、资源身份、显示宽度和 DPR；真实高度回填只更新布局，不退役宽度解码任务或重挂已经显示的图片。

可选任务完成后释放名额继续推进；两个可见首帧等待占满时暂停新任务，快速滚动推迟新增解码并在滚动停止后恢复。取消立即阻止迟到结果，但在途操作完成前仍占执行名额。预加载失败不自动循环重试，图片显示保留自身重试行为。Host 应复用实际显示的 provider key、限定解码像素预算并在首帧后释放临时监听；不持有长期 Context 或全帖 bitmap。设备档位、内存预算与启用范围由 App 注入，本包不读取 provider 或持久化偏好。

在包目录执行 `flutter pub get`、`flutter analyze --no-pub`、`flutter test --no-pub`。`example/` 是独立 Flutter 工程，显式组装准备与渲染；在该目录执行相同命令可验证公开入口及折叠交互。当前与 App 统一固定 HTML 库 0.17.4；后续升级仍须核对真实段距、列表与字号几何，并同步 App 分页布局修订号，避免复用旧布局页码。尚不对外发布。

## 原生段落的单行拟合

`ForumBodyParagraphContentBuilder` 的 `build`、`openCurrent` 和 `openSequence` 接收 `layoutMode`，默认 `ForumBodyParagraphLayoutMode.wrap`。`fitSingleLine` 要求已经投影为完整逻辑单行的文字；硬换行会明确失败，不裁剪或省略尾部，也不承担 HTML 格式识别、空白改写或来源投影。格式处理者仍须独立核对内容结构和来源。

拟合先按实际字体、行高及每个字号的 `TextScaler` 完成同一个 TextPainter 布局，超过可用宽度才等比缩小；短行不放大。行高、baseline、行矩形、完整及分片绘制、选区框和命中坐标共用这次变换，不能另用较小字号重新排版来猜高度。缓存键包含模式及实际缩放输入；普通换行与单行模式即使暂时尺寸相同也不共享布局条目。原生 backend revision 为 5，布局指纹和页绑定须使用公开 revision。

`intrinsicSingleLine` 提供 ruby 等行内布局所需的真实固有单行宽度，保留全部字形、行高、非线性系统缩放、预格式化空格及来源投影，不按请求宽度缩小或补足空白。请求宽度仍须通过准入，但不影响该模式的原生几何，缓存可跨有效请求宽度复用；与 wrap/fit 缓存保持隔离。硬换行及超过 16384 逻辑像素的固有宽度明确失败。它是排字端口，不识别 ruby、分组注音或自行启用格式支持。

原生文字流为 `editStatus`（`.pstatus`）选择该模式。默认使用读者字号的 0.88、斜体、读者颜色的 0.62 alpha 和下方 8 逻辑像素 padding；显式作者声明及对应角色的读者覆盖策略仍经过同一个样式解析器。文字和行内样式保留来源，内部 BR 与 Unicode 空白通过显式 singleLine 投影归一化。仅当其后直接同级节点出现 BR 时，才一起移除周边结构空白；不跨父容器删除换行，无 BR 的预格式化空白仍保留。该过程按原事件预算消费，不重写 IR 或 DOM 坐标。

编辑提示目前接入文字及普通行内内容；其中的嵌套块或资源仍明确失败，不能以容器准入为由静默展开或丢弃。style、text-flow 和 block-flow revision 分别为 5、3、3，Host 须将其纳入布局身份。

## 原生 ruby 分组几何

`ForumBodyRubyGroupLayout` 接收已分组、同文档/字体/样式版本的基字与注音 `intrinsicSingleLine` 内容，从阅读 owner 的 `ForumBodyParagraphCache` 借用两个实际布局。基字提供字母基线，注音居中置于上方，组宽为二者固有宽度的较大值；不缩小长注音，不把 rt 排入基字行。两侧保持独立的字素、双向文字、来源投影和非线性缩放输入，绘制、分侧选区框和命中共用同一组偏移。

`placeholderDimensions` 是已经缩放的直接 TextPainter 行内几何；父排版不得再次进行 inline Widget 自动缩放。gap 使用已解析的逻辑像素；改变 gap 或有效最大宽度可重组几何而复用原生字形。空注音不建立额外布局或保留空白上行。组宽超过显式最大值、无效几何、不同来源/字体或非固有单行内容均明确失败；失败与 `close` 仅释放本组 lease，owner 关闭使活跃组立即失效，不能晚访问已销毁的 native 布局。

作者给两侧设置紧行高时，组装使用同一个 native 布局的完整字体选区范围及行框共同保留空间；补偿偏移同时用于基线、绘制、选区和分侧命中，不裁掉超出小行框的字体部分，也不通过重新排字猜高度。分组几何 `ForumBodyRubyGroupLayout.revision` 为 1，父段落/页布局身份须纳入该值，和原生段落 backend revision 分开维护。

`ForumBodyRubyGroupMetrics.measure` 从当前同 owner 的字形租约借用上述真实数值几何，
不排字、不准备图片、不消费或释放调用方句柄，失败也保持借用规则。它同样核对实际
注音上下文对象和完整输入范围；相同文字的旧上下文不能替代当前内容。返回值仅含尺寸、
基线、偏移和分侧命中分界，不保留内容/native/owner，也不证明绘制或可见 coverage。
既有 `ForumBodyRubyGroupLayout.adopt` 复用唯一几何实现，继续接管句柄并要求图片已准备；
批次字形可用于计划阶段，数值测量不能绕过可读交付门槛。几何算法与 revision 均保持 1。

`tryCreateCached` 仅借用已准备的两侧，任一缺失不测量并释放本次部分命中；空注音只需
基字。`adopt` 接管显式传入的现有租约，不查缓存、不调用缩放或再次排字；成功和失败
都消费这些句柄，不关闭 owner 或外部别名。两侧须由同一阅读缓存持有且活跃，非空注音
的租约必须绑定调用者指定的当前内容对象，缺失/多余/异主/过期句柄明确失败。
`ForumBodyParagraphCache.ownsLease` 提供同步 owner 证明，不改变 LRU 或借用数量。
两种入口复用同一纯输入准入和实际几何实现，不能在可见 paint 中用普通 create 补冷缓存。

`ForumBodyRubyGroupPreparation` 对已经分组的单对基字/注音进行事务式准备：每次
`advance` 在首次 native 排字或单项图片录制后返回，纯缓存工作最多两侧；
`tryPrepareCached` 不测量、不录制图片，已有字形但无绘图时保留部分租约并返回未就绪。
准备完成前不暴露部分组，`takeLayout` 一次性交付全部句柄。空注音只需基字。
关闭、错误或 owner/generation 失效释放本次部分/完整引用，交付后不再控制接收方布局。
终态清除缓存、内容、缩放和回调引用，保留的计数只描述本次准备进度。

默认入口保持普通段落行为；`fromRequests` 通过不可变 `ForumBodyTextRequest` 描述
普通行或 band 子项，复用同一准备状态机和整组 footprint probe。requests 不保有原生
句柄，band 请求仍按完整批次去重/计账。字形和绘图分别占用工作单元，不在刚排完批次
的同次 advance 录制图片；`layoutsBuilt/picturesBuilt` 分开记录实际工作，字形已构建但
尚无可交付侧时仍算进展。只有两侧绘图都已准备才进行组装和一次性交付。

该准备器借用现有阅读缓存和显式 `ensureOwner` 代次检查，不创建 scheduler、timer 或
订阅。调用者在工作单元之间使用既有协作调度；外部 pin 阻塞先有界核对整组 footprint，
返回预算等待，由调用者监听现有 cache 的释放通知并重新准入。两侧自身无法容纳时
明确失败，不反复等待外部释放；检查中已发生的释放不会再等待相同 revision。
取消在缓存 miss、native 返回和组装/交付前都核对，未发布分组不泄露句柄。
该端口尚未接入正式分页，也不代表分层/多注音准备或可见整页预算已完成。

这是行内排版的分组端口，不是完整 ruby 页面 consumer。父段落通过下述混合输入显式使用独立的 engine/display/source 投影；分页、复制与完整无障碍接入仍由组合层实现。普通 paragraph 排字端口继续拒绝 ruby；正式文字流将其保留为独立的未测量格式，不分流旧 renderer。

`ForumBodyRubyContentCursor.openCurrent` 从唯一 styled IR flow 中分组实际 ruby 内容，按 [HTML ruby 分段规则](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-ruby-element)区分基字、注音与回退。它借用当前 ruby 的流，逐步产生不可变组；同一基字的多个注音分别保留，嵌套 ruby 保持子组结构，空注音、孤立注音和未注音尾部不伪造或丢弃文字。根样式、文档身份和构建时字体/样式版本随组保存，子文字保留自己的来源、样式和字素上下文。

`openInlineSequence` 只为专门格式处理者提供已打开行内根中的纯文字片段，显式保留折叠边缘空格；它不把 ruby/资源包装节点变成普通段落。括号回退、隐藏子树和注音间空白通过 `takeIgnored` 返回来源记录，这些记录不证明阅读 coverage。样式诊断继续由借用 flow 的 owner 按批次取走。

`advance(maxEvents)` 同时限制实际读取及已缓冲空白的延后消费，返回二者区分的 `eventsRead/workDone`；在嵌套层累计核对文字、run、组、深度和结构条目上限。BR 同普通段落一样计一个原始字符和 run，不能在多个组间绕过总输入限制；空注音/回退元数据也计结构预算。隐藏同级节点不终止注音阶段，不把其相邻空白误分成新基字。关闭、错误或发现 flow 被其他消费者推进后，不发布半组，不关闭调用者的 flow；已交付的纯组不会被后续失败修改。分组 revision 为 3，不进行字体测量、DOM 切片、语义锚点迁移或页面发布。分层 ruby 几何和正式阅读器接入仍待组合层完成。

正式 `ForumBodyTextFlowCursor` 在同一次 styled 遍历中独占借用上述分组器，返回
`ForumBodyTextFlowInline` 与不可变 `ForumBodyInlineFlowContent`。前后普通文字和所有
ruby 组属于同一个父格式上下文；嵌套、多注音、孤立注音和忽略来源保持结构，不拆段
或压平 RT。普通片段完成时可保留原始折叠边缘，交由父格式计划器处理行边空白；这个
中间值尚无拼接显示投影、占位尺寸或 native 句柄，不能直接当作可读页面。

普通与混排共用段落索引、延后 BR、终止空行和块边界。文字/run/组/结构预算覆盖整个
上下文，多个独立 ruby 根不能绕过限制；关闭和失败清理借用状态，已交付值保持不变。
TextFlow、BlockFlow 的 `workDone` 包含零新事件的延后消费，maxEvents 同时限制工作量；
BlockFlow 只附加既有宽度/缩进和 margin/padding 几何。Session 同步传递 flowWorkDone，
这种进展不会误判成停滞；未测量混排仍明确失败，待协作格式计划器接入后才进入 composer。

样式解析只把 `rt` 及其后代标为注音角色，基字保留其正文/标题等上下文角色，正文级读者设置不会因此跳过基字。注音默认字号为继承字号的一半，行高为 1，参照 [CSS Ruby 的 UA 样式](https://www.w3.org/TR/css-ruby-1/)；显式作者声明及逐角色读者覆盖仍经过唯一 resolver，`line-height:inherit` 取真实父级值，非法声明保留注音默认值并报告。固有行内排字不重复应用所在块的首行缩进，普通 wrap/fit 的缩进准入没有因此放宽。当前 style 和 paragraph backend revision 均为 5。

## 混合行内排版输入

`ForumBodyInlineSpanContent.compose` 组合已准备的独立纯文字上下文及显式显示原子范围，
严格核对文档、字体和样式版本、真实来源顺序、文字/run/上下文/原子预算。
样式 run 通过明确偏移保留原 path 和 visibility；普通相邻样式 span 应先在同一上下文
收集，不因样式变化打断字素。诊断仍归原来的 styled flow owner，不在组合时重读或复制。

实际基字和注音保存在 `projection.display`，包括各自字素和来源缺口。唯一父引擎输入
`textSpan` 在原子位置使用无 Widget 的 native `PlaceholderSpan`，其 plain text 与
`projection.engineText` 一致；不把注音作为正文行文字，不生成虚假的来源位置。
原子内部精确命中和选区必须来自实际子布局，不能用父占位符近似推断。坐标映射和
严格 engine 窗口使用 `html_pagination_core` 公开入口，不在 Flutter 包复制算法。

该 span 只供直接 `TextPainter` 使用。调用者按原子顺序设置已经缩放的子几何，必须是
有限、有界且基线在框内的 alphabetic baseline 占位，不重复应用父级字体缩放。
父引擎负责混合 bidi、换行和占位基线；子布局负责在实际占位框处绘制、命中及选区。
纯输入不持有 native 子租约、DOM、Context 或测量 session，也不自行决定 whitespace
边缘、可见 coverage、分页、缓存预算和阅读锚点。组合输入 revision 为 2，父布局身份
还须纳入 projection、原子几何、完整样式和有效字体缩放；正式 flow/session/page 接入
及分层/多注音几何尚未完成，不能据此宣称复杂正文已通过原生阅读器验收。

`ForumBodyInlineParagraphLayout` 持有一个实际父 TextPainter。与普通段落共用唯一的
原生逻辑行提取实现；`ForumBodyParagraphLine` 明确记录 display 和 engine 的 paint／
coverage 范围，前者保留真实子文字，后者用于引擎边界。物理 fallback 行允许记录未
对齐字素的偏移，但不能在非法边界建立分片；硬换行和末尾空行继续保留完整 coverage。
父布局支持 wrap 和固有单行，不隐式缩小 ruby；超宽原子及不支持的缩进/混合方向明确
失败。准入只核对父引擎实际使用的 `parentRuns`，子文字的方向、字号缩放归独立布局。

父原生命中先检查实际占位框，返回原子索引和子局部点；其余命中才投影普通文字来源。
选区分别返回普通字形框和实际子 display 窗口，不把矩形占位框冒充注音/基字选区。
分片借用同一引擎，按合法行框裁剪并保持两套 coverage；`paintParent` 只绘制父文字，
consumer 仍须准备、核对并绘制实际子布局，不能据此单独发布可读页。父布局只拥有自己
的 native 对象，dispose 使其全部借用分片失效，不关闭子 owner。混排布局 revision 为 1；
正式分页消费仍待接入，不引入整段常驻子租约。

普通与混排原生对象统一归 `ForumBodyParagraphCache` 的一套条数/估算字节预算、LRU、
pin、预算释放通知与 owner 关闭生命周期。`acquireInline` 返回 typed lease；
`tryAcquireInlineCached` 缺失时不测量，供协作准备完成后获取可见 view。
混排 key 核对文档/path、字体/样式及后端版本、完整父 span、来源/原子映射、实际尺寸和
alphabetic baseline、有效父字体缩放、对齐/方向/模式/宽度。固有模式跨有效请求宽度
复用，但 warm lookup 仍完整准入。子方向/缩放归其独立布局，不重复作用到父占位框。

缓存后的混排对象只保留坐标及实际父 native 资源；**当前子样式与交互必须从 lease.content
取得**，不能从复用引擎的旧输入恢复。`ForumBodyNativeParagraphLease` 的共同生命周期
只用于混合 pin 集合与释放，不擦除两种 layout 的绘制/命中类型。纯 budget probe 的
`includeInline` 与普通 include 共计 footprint、按实际 key 去重且不测量。
排版期间 owner 退役禁止回填；同 key 重入测量明确失败，不覆盖活跃条目；其他条目的
重入获取须在 native 返回后再次核对实际 pin。字节是保守准入估算，不能冒充真实 native
heap/GPU 观测。正式 flow/session/page 消费仍待接入。

## 有界子行批量排字

`ForumBodyTextBandContent` 将有序、同文档/字体/样式版本的独立 intrinsic 文本组成有界
批次，默认最多 64 个子项、16384 个显示 UTF-16 单位与 512 个 run。根方向、对齐和
locale 必须兼容；空子文字不占 native slot。复杂容器、阴影、描边及扩展 ink 的滤镜
需要其他排版/绘制端口，不能在本端口中裁剪后宣称支持。

`ForumBodyTextBandLayout` 用一个实际 TextPainter 产生各子项的宽高、字母基线、字体
选区及命中。批次根不继承首项的可选字体、字重或 paint；每个子上下文保持自己的完整
样式和逐字号 TextScaler。引擎坐标由纯包 `HtmlTextBandProjection` 提供，虚拟换行和
透明隔离行不进入源码点、子显示坐标、复制、语义或阅读锚点。

换行使用不参与用户缩放的零字号与微小正行高覆盖，避免引擎默认字体下限污染极小行高；
隔离行已经是逻辑像素，不再缩放。子高度按原生 ascent/descent 的像素舍入重建，并把
舍入差计入基线；不使用被至少一像素钳制的 LineMetrics.height 代替零高独立段落。
实际字体范围参与隔离检查，空间不足返回 requiredGutter，由调用者在新的有界工作单元
重试，绝不在一次 create 中循环排字。命中仅定位已知子行；极小行需要时使用实际 native
caret 几何，歧义保持近似，不从相同文字推断来源。

可见帧不能逐子项重绘整个批次。`recordPaint` 在准备阶段录制单项隔离的 ui.Picture，
返回带成本的 `ForumBodyTextBandPaint` 票据；缓存装配者核对全局预算后 `adoptPaint`，
拒绝则 close 票据。每个 slot 最多一个待交付票据，交付和失败都消费指定句柄。
`preparePaint` 仅供独立 owner 的便利调用；正式阅读器须先经共享 cache 准入。
view.paint 只复用已提交快照，未准备时明确失败，不在 paint 中测量、录制或补缓存。

绘图所有权由单个 band 的内部服务管理，没有第二套 LRU/预算。可查询待提交/已准备图片数
及 approximatePictureBytes；该值不含全部字体、图片引用或 GPU 内存，不能据此宣称内存
验收通过。owner 退役同时关闭字体资源、待提交票据和已提交图片，view 单独退休不关闭
兄弟 view；Picture 创建回调中的退休也禁止迟到提交。批次输入/排字 revision 均为 1。

`ForumBodyParagraphCache.acquireBandChild/tryAcquireBandChildCached` 返回当前来源绑定的
子行租约，所有子项共同 pin 一个批次条目，和普通/混排段落使用同一预算与 LRU；warm miss
不排字也不录制图片。key 核对全部子来源映射、span、字体/样式/后端版本、有效字号、
方向/对齐/locale 与隔离距离；租约暴露当前 content，不使用缓存资源的旧交互元数据。
纯 budget probe 的 includeBandChild 以完整批次去重，不创建 native 资源。

`prepareBandChildPaint` 在可见 paint 外录制一项、核算成本，再交付给同一批次。原始估算
为每项预留 4096 字节绘图容量，实际 approximateBytes 超过全部 slot 预留时增加同一条目
的成本并触发全局准入；字节估算不因失败下降，也不增加条目数量上限。拒绝只关闭新票据，
保留已交付图片。pinned 错误记录增量字节与所需新增条目数，以区分其他 view 的 pin 与
自身整页超限。图片构建数仅统计成功交付，已交付数量随淘汰/关闭清零。

native 释放钩子可重入获取、释放或关闭 owner。准入在每次淘汰后重新核对状态和预算，
pending key 在完整事务内禁止重入，单次淘汰次数有界；clearUnpinned 只清理仍匹配原
条目且仍未被 pin 的快照。close 先从索引移除全部条目，随后逐项退休，避免迟到回填、
重复扣账或 observer 修改正在迭代的索引。单子行 release 不关闭兄弟 view 的字形/图片。

`ForumBodyTextLayout` 提供来源局部的宽高、首行基线、投影、选区、命中和绘图准备状态；
普通段落与 band 子项分别实现它，不伪造 band 虚拟行的显示 coverage。对应的
`ForumBodyTextLease` 保留当前 ParagraphContent 和明确的 owner 生命周期，旧的普通
段落租约仍返回原来的具体 layout 类型。

`ForumBodyRubyGroupLayout.adopt` 可消费普通行、band 子行及二者混合，但必须同 owner、
同有效作用域且各项 paint 已准备；成功与失败都消费传入句柄，不退休其他别名或兄弟行。
几何、选区和命中只使用来源局部契约，字体框与极小行高仍参与完整分组尺寸计算。
页面准备器与整页预算装配尚待接入，并完成 profile 验收；不能只按 TextPainter 数量
计账，或用原语/缓存/分组的验证代替复杂正文阅读器验收。

## 可见混排文字分片

`ForumBodyInlineSpanContent.contexts` 保留实际独立子上下文及其父显示窗口，输入 revision
为 2。它们是有界纯值，不持有 DOM、Widget 或 native 资源；不得从相同文字、长度或
新偏好猜回旧子的来源。缓存仍只保存父 native 投影，绑定必须读取当前 lease.content。

`ForumBodyInlineParagraphView.adopt` 接管一个已准备父租约和该合法行窗口内恰好的 ruby
组。父子必须同一 owner，组内容必须就是当前父输入保留的子上下文，窗口覆盖和实际
尺寸/基线必须一致。缺失、多余、旧上下文或错配均失败并消费本次句柄，不退休兄弟别名。
普通文字与子组一起绘制，paint 不获取缓存或录制图片；单个分片不能静默 pin 整个长段。

命中通过实际子 native 几何返回源码点，并显式移到父显示坐标；源间隙保持近似，越出
窗口的点只钳制到当前分片且不标精确。选择使用父普通文字框及子 base/RT 的真实局部
选区，不用占位矩形冒充部分文字；保留字素、RTL 和分片边界。close 释放父及可见子租约，
清除分片、子内容和句柄引用，仅保留数值几何。

`ForumBodyInlineParagraphSurface` 只挂载已准备 view，与普通 ParagraphSurface 共用
内部 RenderBox 的布局/手势/退出逻辑。回调换绑读取最新回调，位置/视图/交互身份变化
取消旧手势，关闭 owner 后晚到 paint/tap 无效。基础语义使用当前可见正文、过滤隐藏
文字；完整 ruby 读屏、跨页选择与复制政策仍由 S8 联验，不能据此宣称无障碍完成。

本绑定当前消费已配对的叶子 ruby；分层/多注音及正式分页准备、flow/session/page
装配仍待完成。单项/分片像素和来源验证不能代替实际复杂正文页面的 profile 验收。

## 普通与混排共享分页

`ForumBodyTextPageComposer.appendInline` 接管已测量的父租约，与普通 append 共用同一
行扫描、合法断界、段距/续页及稳定封页流程。只保留一个活跃父输入；完成、退出或失败
释放父租约，组合器不接管子组。真实显示 coverage 与原始 sourceHint 来自父 display
投影，不能把 U+FFFC 引擎范围用作显示或小说语义 offset；hint 仍不证明实际可见覆盖。

快照只追加数值元数据并标记 `ForumBodyTextPageFragmentKind`，composer revision 为 6。
排字、子租约或回调不进入已发布页；超高不可拆组明确失败，已封页前缀不受晚失败影响。
只接受普通租约的旧页面绑定明确拒绝 inline 分片，不能用同尺寸的普通字形或父占位框
冒充完整交付。本组合能力不启用旧 renderer 兜底或自动切换阅读模式。

`ForumBodyPreparedTextFragment` 是当前挂载的交付句柄，分别持有普通段落租约/行窗口
或完整的混排 view，不进入数值快照。普通句柄构造失败只释放传入别名；close 只退休
本次交付引用。nativeLeases 借用现有句柄供同 owner 的整页预算及生命周期计数，不创建
别名或转移所有权；应按仍活跃的句柄计数，不能只统计父分片数量。

`validateForumBodyPreparedTextPageBinding` 联验类型、代次、当前来源/样式、行窗口、
真实数值几何和 sourceHint；全部父子句柄须活跃、同阅读 owner 且不重复使用同一别名。
校验只借用输入，失败不消费调用方的已准备分片。

既有 `ForumBodyTextPageSurface.prepared` 挂载通过完整校验的普通/混排页。旧普通入口
保留并转到同一实现；普通 key 使用原始 lease、混排 key 使用原始 view，重建交付包装
不会销毁正在显示的同一组句柄。挂载后由具体 Surface 释放引用；构造失败/未挂载 Widget
仍归调用方清理。真实挂载、点击和退出验证不代表复杂正文 profile 或整个 S6 已验收。

既有 `ForumBodyTextPagePreparation` 现以完整 typed 分片持有准备进度，并通过
`takeFragments` 完成同一预留事务的一次性交付；普通 `takeLeases` 复用它并只接受普通
分片，不悄悄丢弃混排子项。缓存 miss 后和 transfer 回调后仍核对 owner/代次，关闭或
失败释放全部本次引用，不发布迟到结果。全部完成后继续联验完整页面绑定。

`ForumBodyTextPageSession` 的 issued 账本持有完整分片，按仍活跃的 native 句柄计数；
失效复合分片在移出账本前关闭剩余引用。`preparePageFragments` 为同一事务的 warm-only
便利入口，冷缓存仍通过既有 openPagePreparation/advance 协作准备。普通接口继续兼容，
并发预留、部分释放和上限共用同一套账本。当前 Session 保留输入仍为普通段落；
不能因交付类型统一而宣称正式 ruby 会话已完成。

`ForumBodyTextPageContent` 显式区分普通输入和已测量的混排计划；后者保留父 span、
已缩放占位尺寸及逐原子的 base/RT 请求。请求必须对应当前父输入中的实际子上下文和
完整显示窗口，完整 band 的全部上下文也须位于该有界输入内，不能把未计入保留限制的
尾部带入 native 缓存。`resolveAtomicContexts` 是计划与可见绑定共用的纯来源校验。
计划不持有 native 句柄、Context、调度器或回调。

现有 PagePreparation 消费上述两种输入。一个格式局部服务只保管当前混排父句柄、
可见组及一个部分 pair；页面事务继续统一管控所有权、回滚、整页预算与交付。父实际
行窗口先核对数值快照，随后只准备可见组，全部完成后才交付完整分片。advance 同时
受 maxFragments/maxParts（默认 32）约束，遇到一次排字或图片录制便返回；cached-only
同样受 part 数约束，不排字或录图。计数分开记录图片、保留的部分进展和预算检查，
不能用被丢弃的排字冒充进展。原有 warm-only 便利入口使用预留总量内的完整检查预算，
交互调度继续使用有界单步接口；不会因新的单步上限把完整 warm 普通页当作缓存 miss。

整页预算逐父/子请求有界检查，按实际 native key 去重，并计入已常驻的绘图成本。
外部压力诊断包含本页已准备分片、当前父、已完成组和部分 pair 的全部句柄；同页自身
超限明确失败，不能等待自己释放。预算检查中发生释放会重试而非漏等；后续 native
构建/图片成本改变后重查整页，避免使用过期检查。实际 native 句柄数用于预留/退役，
不以父分片数量代替。入口、miss、native 返回、组装/交付前后均核对代次，禁止重入操作。

空注音不占子布局/图片或空白上行；空混排父和零宽固有布局保留实际物理框，不伪造
文字选区或精确来源。固有模式只用有效请求宽度通过 native 准入，实际零宽 frame 不变。
缩放变化导致父或子真实几何不匹配时拒绝本次准备，保留只读数值前缀，允许新请求重试。

正式 TextFlow/BlockFlow 已生产未测量混排结构；Session 还需据此生成上述混排计划、
有界按字形测量占位几何，并迁移 App 消费者后才能启用真实 ruby 会话。分层/多注音、
行边空白、长段及复杂正文 profile 仍未验收；不能通过提前录制整段全部子图片、扩张预算
或切回旧 renderer 绕过这些要求。
