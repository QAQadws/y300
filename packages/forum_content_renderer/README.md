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

段落输入按需保存自身不可变的准入描述：硬换行、缩进/方向/空白约束和原样式顺序内的
独立字号。每次请求仍先校验宽度，再调用当前 TextScaler 并核对有效值；后续样式错误
保留此前缩放调用及错误顺序。band 的各上下文仍独立读数并检查同字号一致性。
该描述不保存缩放值或 native 资源，不充当来源 coverage；显示切片与空白投影各自重新
建立描述，不沿用旧文本的单行结论。几何与输入 revision 保持不变。

格式处理者可通过 `ForumBodyParagraphContent.anonymousInline` 创建无来源的空字体支撑框。
它没有 DOM path、文字或 run；真实空 TextPainter 提供字体高度和字母基线，不伪造文字行、
字形或精确命中。相同字体/样式/缩放的支撑框复用既有缓存。它只能作为显式原子子项，
不得进入父显示投影、来源包络或独立页面段落；其零长度子窗口不能代替真实文字 coverage。

原生文字流为 `editStatus`（`.pstatus`）选择该模式。默认使用读者字号的 0.88、斜体、读者颜色的 0.62 alpha 和下方 8 逻辑像素 padding；显式作者声明及对应角色的读者覆盖策略仍经过同一个样式解析器。文字和行内样式保留来源，内部 BR 与 Unicode 空白通过显式 singleLine 投影归一化。仅当其后直接同级节点出现 BR 时，才一起移除周边结构空白；不跨父容器删除换行，无 BR 的预格式化空白仍保留。该过程按原事件预算消费，不重写 IR 或 DOM 坐标。

编辑提示目前接入文字及普通行内内容；其中的嵌套块或资源仍明确失败，不能以容器准入为由静默展开或丢弃。style、text-flow 和 block-flow revision 分别为 6、3、3，Host 须将其纳入布局身份。

## 原生 ruby 分组几何

`ForumBodyRubyGroupLayout` 接收已分组、同文档/字体/样式版本的基字与注音 `intrinsicSingleLine` 内容，从阅读 owner 的 `ForumBodyParagraphCache` 借用两个实际布局。基字提供字母基线，注音按显式 side 居中置于上方或下方，组宽为二者固有宽度的较大值；不缩小长注音，不把 rt 排入基字行。两侧保持独立的字素、双向文字、来源投影和非线性缩放输入，绘制、分侧选区框和命中共用同一组偏移。

`placeholderDimensions` 是已经缩放的直接 TextPainter 行内几何；父排版不得再次进行 inline Widget 自动缩放。gap 使用已解析的逻辑像素；改变 gap 或有效最大宽度可重组几何而复用原生字形。空注音不建立额外布局或保留空白上行。组宽超过显式最大值、无效几何、不同来源/字体或非固有单行内容均明确失败；失败与 `close` 仅释放本组 lease，owner 关闭使活跃组立即失效，不能晚访问已销毁的 native 布局。

作者给两侧设置紧行高时，组装使用同一个 native 布局的完整字体选区范围及行框共同保留空间；补偿偏移同时用于基线、绘制、选区和分侧命中，不裁掉超出小行框的字体部分，也不通过重新排字猜高度。分组几何 `ForumBodyRubyGroupLayout.revision` 为 4，父段落/页布局身份须纳入该值，和原生段落 backend revision 分开维护。

单个孤立 RT 的匿名空基字使用所在 ruby 根的正文样式和实际空字体基线，注音保持自己的
半字号及逐字号缩放。父显示和来源只含实际 RT；空基字区域的命中指向该 RT 且标为近似，
不能返回空支撑框的零来源或证明已读。基字与注音同时为空仍明确失败。

`ForumBodyRubyGroupMetrics.measure` 从当前同 owner 的字形租约借用上述真实数值几何，
不排字、不准备图片、不消费或释放调用方句柄，失败也保持借用规则。它同样核对实际
注音上下文对象和完整输入范围；相同文字的旧上下文不能替代当前内容。返回值仅含尺寸、
基线、实际字体 ascent/descent、偏移和分侧命中分界，不保留内容/native/owner，也不证明绘制或可见 coverage。
既有 `ForumBodyRubyGroupLayout.adopt` 复用唯一几何实现，继续接管句柄并要求图片已准备；
批次字形可用于计划阶段，数值测量不能绕过可读交付门槛；几何 revision 为 4。

`ForumBodyRubyLevelMetrics` 是同一实际 ruby 根、同一物理行及同一注音侧的纯数值层级并集，
包含基字/注音的最大 ascent/descent 和 gap。`alignedTo` 只用当前真实字体基线计算
偏移，不排字、不再次缩放；目标必须包含该列的实际字体范围。可读 `adopt` 和
`fromRequests` 接收同一可选层级目标，重新核对当前租约的实际几何，绘制、选区与命中
共用对齐后的偏移。它不是可见 coverage 或已读证明，不能将不同 ruby 根合成一层。

唯一 resolver 解析继承的 `ruby-position`，默认 `alternate`，同时保留 `over`、`under`、
`alternate over`、`alternate under` 和 `inter-character`。非法组合整条回退到继承值并报告，
角色级读者属性恢复不丢失该值。注音层配对决定实际 side：隐式层取 ruby 根，显式层取
RTC；RT 自己的声明不会改变其父注音层的位置。`sideAfter` 保留相邻层上下交替的规则，
当前单层首先解析为 over 或 under；完整多层堆叠仍待组合层完成。

测量与可读准备通过同一不可变请求传递 side，重试替换 band 时也保持它。下方注音依据
实际基字 descent 与注音 ascent 对齐，基字仍提供同一个字母基线；两侧的行级并集分开，
不把上方/下方的字体框合成一层。绘制、选区、命中和匿名空基字近似区域共用偏移，
不增加 native 排字或缓存预算。`inter-character` 保留解析值但当前横向组合明确拒绝，
不能当作上方注音吞并；专项文字方向后端另行接入。

计划阶段通过既有 `ForumBodyRubyGroupPreparation.forMetrics` 准备同一组请求：每次
advance 仍在首次 native 排字后返回，cache-only 可使用未录图的字形，且两条路径均不
准备子图片。完成实际几何测量后先释放本组全部 pin，再经代次检查进入 ready；等待
takeMetrics 时也不常驻子句柄。数值结果不替代可读 layout，取错结果类型不会消费事务。
同一套外部压力/自身预算检查、owner/取消/重入保护和终态清理继续生效；转移前仍核对
起始阅读代次，不能因数值已算出而交付退休会话结果。完整格式计划仍须处理父空白、
结构化子组、band 兼容和实际来源绑定，不能把该局部事务宣称为正式 ruby 会话接入。

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
该端口已供 Session 父计划与可见页准备共同消费；分层和完整阅读器仍待完成。

这是行内排版的分组端口，不是完整 ruby 页面 consumer。父段落通过下述混合输入显式使用独立的 engine/display/source 投影；分页、复制与完整无障碍接入仍由组合层实现。普通 paragraph 排字端口继续拒绝 ruby；正式文字流将其保留为独立的未测量格式，不分流旧 renderer。

`ForumBodyRubyContentCursor.openCurrent` 从唯一 styled IR flow 中分组实际 ruby 内容，按 [HTML ruby 分段规则](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-ruby-element)区分基字、注音与回退。它借用当前 ruby 的流，逐步产生不可变组；同一基字的多个注音分别保留，嵌套 ruby 保持子组结构，空注音、孤立注音和未注音尾部不伪造或丢弃文字。根样式、文档身份和构建时字体/样式版本随组保存，子文字保留自己的来源、样式和字素上下文。

`openInlineSequence` 只为专门格式处理者提供已打开行内根中的纯文字片段，显式保留折叠边缘空格；它不把 ruby/资源包装节点变成普通段落。括号回退、隐藏子树和注音间空白通过 `takeIgnored` 返回来源记录，这些记录不证明阅读 coverage。样式诊断继续由借用 flow 的 owner 按批次取走。

RT 及 RTC 内匿名文字片段的投影按 [CSS Ruby 的强制换行合并](https://www.w3.org/TR/css-ruby-1/#anonymous-ruby)
规则，使用核心 `suppressLineBreaks` 将 BR、文本 CR/LF 及原生行/段分隔符合为单行
空格，保留真实来源范围、样式所有权及原始字符/run 计费。它不使用编辑提示的宽泛
singleLine 空白策略；pre/pre-wrap 的普通空格、Tab、NBSP 和全角空格继续保留。
基字与外部正文的换行不受影响。该策略只作用于注音格式根，普通段落仍拒绝直接消费
ruby。投影 revision 为 7；可见字形覆盖、语义锚点和已读资格仍由 Host 独立核对。

parser revision 为 2；显式 `rb` 与 `rtc` 分别保存为 `rubyBase` 与
`rubyAnnotationContainer`，保留原始 child-path 和来源范围。它们默认保持行内继承，
RTC 不提前缩小字体，真正的 RT 继续由唯一 resolver 设置注音字号。普通文字收集器和
叶子计划不得把这些结构当作透明未知标签吞并；RB 分组及逐列配对保留如下，RTC 语法结构已保留，显式注音范围配对和层级几何仍待完成。

`ForumBodyRubyAnnotationContent` 是区分真实 RT 与 RTC 的封闭类型：既有构造入口产生
`ForumBodyRubyTextAnnotationContent`，`ForumBodyRubyAnnotationContainerContent` 保留
真实 RTC 的 path、完整来源范围、实际继承样式及有序子部分。Group.annotations 按原始
顺序保存根级 RT/RTC，容器 parts 内才是其 RT 子框；匿名文字、层内空白、嵌套 ruby、
空 RT 和空 RTC 均不丢弃或提前拆成平面列。RTC 匿名片段保留其实际样式，不伪造 RT
节点或在语法阶段猜测注音范围和最终字号。注音输入服务消费同一语法，接受一个 RTC
内的实际 RT 列，按对应基字逐列配对；缺少 RT 保留实际基字，多余 RT 复用无来源的
匿名空基字。容器首尾的结构空白只在存在实际 RT 子框时省略，保留子框真实样式、
来源和字素；空 RTC 没有额外注音行。来源重排接缝仍保留近似性，不能伪造连续坐标。

容器内的匿名文字、独占的空白注音、层内间隔、多 RTC 或直接 RT/RTC 混合仍交给各自的
范围/层级布局，当前明确拒绝；即使匿名内容只有一个纯文字片段，也不能把整个 RTC
当作一列 RT。未支持内容不会因单层容器接入而压平、丢弃或切回旧 renderer。

`ForumBodyRubyBaseContent` 保留每个显式 RB 的 path、来源、实际样式及不可变子部分，
普通隐式文字仍在原先位置保留。空 RB 和仅含空白的 RB 也保留为单独单位，不能在配对前
吞掉或并入相邻基字；内部嵌套 ruby 保持结构。格式端口 `openInlineSequence` 可收集已经
打开 RB 的文字，普通段落准入保持独立。每个单位及其空内容都计入结构预算，退出、失败
与取消清理当前 RB 借用状态，不关闭调用方 flow 或修改已交付的组。

`advance(maxEvents)` 同时限制实际读取及已缓冲空白的延后消费，返回二者区分的 `eventsRead/workDone`；在嵌套层累计核对文字、run、组、深度和结构条目上限。BR 同普通段落一样计一个原始字符和 run，不能在多个组间绕过总输入限制；空注音、空 RTC 和回退元数据也计结构预算。隐藏同级节点不终止注音阶段，不把其相邻空白误分成新基字。关闭、错误或发现 flow 被其他消费者推进后，不发布半组，不关闭调用者的 flow；已交付的纯组不会被后续失败修改。分组 revision 为 6，不进行字体测量、DOM 切片、语义锚点迁移或页面发布。分层 ruby 几何仍待组合层完成，叶子计划和 App 页面经下述同一会话接入。

没有实际基字的连续 RT 按 [CSS Ruby 的匿名基字配对](https://www.w3.org/TR/css-ruby-1/#ruby-pairing)
保留全部实际注音和忽略来源；每个直接孤立 RT 仍计一个 group 预算，但到下一个真实
基字段或 ruby 关闭才交付完整分段，避免后来的 RTC 层失去前面的列。返回组数和
groupCount 预算计数因此不必相等。下一个基字事件仍经同一有界延后路径消费，不重复
读取或收费，取消不改变已发布完整组。没有 RTC 的平面输入继续由下述单层列计划
逐列使用匿名空基字；RTC 层级、显式范围和嵌套几何仍待完成。

正式 `ForumBodyTextFlowCursor` 在同一次 styled 遍历中独占借用上述分组器，返回
`ForumBodyTextFlowInline` 与不可变 `ForumBodyInlineFlowContent`。前后普通文字和所有
ruby 组属于同一个父格式上下文；嵌套、多注音、孤立注音和忽略来源保持结构，不拆段
或压平 RT。普通片段完成时可保留原始折叠边缘，交由父格式计划器处理行边空白；这个
中间值尚无拼接显示投影、占位尺寸或 native 句柄，不能直接当作可读页面。

普通与混排共用段落索引、延后 BR、终止空行和块边界。文字/run/组/结构预算覆盖整个
上下文，多个独立 ruby 根不能绕过限制；关闭和失败清理借用状态，已交付值保持不变。
TextFlow、BlockFlow 的 `workDone` 包含零新事件的延后消费，maxEvents 同时限制工作量；
BlockFlow 只附加既有宽度/缩进和 margin/padding 几何。Session 同步传递 flowWorkDone，
这种进展不会误判成停滞；Session 经下述格式计划器消费未测量结构，再进入同一 composer。

样式解析只把 `rt` 及其后代标为注音角色，基字保留其正文/标题等上下文角色，正文级读者设置不会因此跳过基字。注音默认字号为继承字号的一半，行高为 1，参照 [CSS Ruby 的 UA 样式](https://www.w3.org/TR/css-ruby-1/)；显式作者声明及逐角色读者覆盖仍经过唯一 resolver，`line-height:inherit` 取真实父级值，非法声明保留注音默认值并报告。固有行内排字不重复应用所在块的首行缩进，普通 wrap/fit 的缩进准入没有因此放宽。当前 style 和 paragraph backend revision 分别为 6、5。

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
边缘、可见 coverage、分页、缓存预算和阅读锚点。同一原始 run 的显示窗口经显式
runIndexMap 共享父样式归属，只保留实际使用的 run，按对象身份去重，不合并相同样式
的不同来源。原始流仍独立核对输入预算；窗口拆分不重复计费，也不提高 maxRuns。
显示上下文重排必须显式传入完整的 sourceOrder，由纯坐标包核对实际来源范围；默认仍
要求来源顺序。它不放宽原子绑定或子来源身份。组合输入 revision 为 7，父布局身份还
须纳入 projection、原子几何、完整样式和有效字体
缩放；分层几何尚未完成，不能据此宣称完整复杂正文已通过原生阅读器验收。

`ForumBodyInlineParagraphLayout` 持有一个实际父 TextPainter。与普通段落共用唯一的
原生逻辑行提取实现；`ForumBodyParagraphLine` 明确记录 display 和 engine 的 paint／
coverage 范围，前者保留真实子文字，后者用于引擎边界。物理 fallback 行允许记录未
对齐字素的偏移，但不能在非法边界建立分片；硬换行和末尾空行继续保留完整 coverage。
父布局支持 wrap 和固有单行，不隐式缩小 ruby；超宽原子及不支持的缩进/混合方向明确
失败。准入只核对父引擎实际使用的 `parentRuns`，子文字的方向、字号缩放归独立布局。
native 段高舍入与实际占位框可能不同；外层画框保留占位框及真实子尺寸的上下外溢，
仅以同一原点平移绘制、行/占位框、命中与普通文字选区，保留实际排字和基线关系。
无偏移时保留原几何快路径，不累加舍入行高或重新排字。可见 view 使用矩形硬裁剪，
避免小数边缘重复抗锯齿裁剪改变已准备子绘图的 alpha；字形覆盖仍检查完整未裁剪框。

分片以单调的占位框上下包络保留所属子项的真实高度，常数时间取得合法行窗口的画框。
相邻原生行的小数范围可能重叠，不能直接把下一行 top 当作前一页的裁剪底部；完整段高、
实际基线和两套 coverage 保持不变，不累加舍入行高。父普通文字仍按原逻辑行窗口裁剪，
子项只绘制本分片拥有的原子，命中也优先该窗口，不能借到相邻隐藏行的占位框。
每行两个 Float64 边界的保留字节纳入同一 cache 估算预算。

父原生命中先检查实际占位框，返回原子索引和子局部点；其余命中才投影普通文字来源。
选区分别返回普通字形框和实际子 display 窗口，不把矩形占位框冒充注音/基字选区。
分片借用同一引擎，按合法行框裁剪并保持两套 coverage；`paintParent` 只绘制父文字，
consumer 仍须准备、核对并绘制实际子布局，不能据此单独发布可读页。父布局只拥有自己
的 native 对象，dispose 使其全部借用分片失效，不关闭子 owner。混排布局 revision 为 5；
正式 Session 使用同一父布局分页，不引入整段常驻子租约。

显式软间隙原子通过 `textSpanWithDimensions` 消费已经测量、缩放的逻辑尺寸；父
TextPainter 只接收真正不透明占位框的尺寸。引擎 SPACE 使用包内 1004 字节的
`ForumBodyInlineSpace` 布局资源：仅含空白字形，1024 units/em 中的一个单位 advance，
零垂直度量和零墨迹。内部字号为已测逻辑宽度乘 1024，以保留 Android 原生字号量化
之前的细分系统字体宽度；这是资源单位换算，不再应用读者缩放。最大逻辑宽度仍为
16384，严格原生 advance/零字体框/coverage 误差标准保持不变。
它不进入用户字体列表，也不代替基字/注音的真实字体；既有字体解析和缩放保持。
资源通过包 pubspec 的字体清单装配，生成来源为 `tool/generate_inline_space_font.py`，
使用固定 FontTools 版本与时间戳可重复生成。资源变更须重建 bundle 并验证引擎注册，
不能把普通热重载当作新字体已生效的证据。

仓库根目录执行以下命令，可在独立 profile 应用的新引擎中联验打包字体与真实小说页面：

```powershell
tool/run_novel_pagination_profile.ps1 -Device <设备 ID> -MainPage -Backend native -InlineSoftSpace
```

启动检查不调用 FontLoader；十四组实际父布局覆盖双向、换行裁边、超大间隙、
分数缩放和两端对齐，并核对 warm 不排字及 owner 释放。请求该检查后，缺少任一组
都会使整套 suite 失败。系统字体的原生行高取整以同机对照核对，不固定为跨平台像素值。
这项检查证明 bundle 启动与几何/生命周期；帧耗时仍由随后真实页面的 profile 窗口统计，
不能据此宣称整套格式、真机或 native heap/GPU 已验收。

可断注音间隙使用独立的真实页面语料，保留原有 baseline 的 `safe`/`complex` 样本：

```powershell
tool/run_novel_pagination_profile.ps1 -Device <设备 ID> -MainPage -Backend both -Corpus ruby-gaps
```

它分别运行 LTR、RTL 和 24 层密集注音的完整生成章节，沿生产打开、后台封页、设置重排、
可见翻页与退出流程采样。旧后端仅作为显式对照，不是原生失败的兜底。加 `-Baseline`
才执行既定的每样本 5 次预热、30 次打开、3 组各 200 次翻页；冒烟结果不满足正式统计门槛。
极小字号导致单页超过句柄容量的独立压力样本保留在测试中，要求明确拒绝并释放所有权，
不能把预期超限混进成功矩阵，也不能扩大预算使它通过。机器记录包含 corpus 名称，
缺少任一样本或未完成翻页均不能通过 suite。

真实页面任务随已完成交付附带不可变 `NovelReaderNativePageWork` 数值记录。它只记录
准备/覆盖阶段的 wall 时间、同步 advance 时间、主动等待下一帧次数与原生排字/录图次数，不持有
内容、Context、owner 或租约，也不参与覆盖证明、恢复和布局 identity。同步调用耗时
不是线程 CPU 时间；最终 view adoption 和绘制在该区间之外。profile 在原有真实可见
条件成立后输出 `page_work`，用于区分冷目标准备与覆盖核对；不以计量替代可见验收。

软间隙只有在两侧原子同属实际原生行时保留。换行后的间隙不提供可见原子、选区或
页面高度，即使其原宽高超过行框也不生成空行。保留时核对原生 advance、零字体度量
与实际行基线；两端对齐扩展的是分配区，真实间隙框仍按原宽居中。额外数值掩码与
分配区纳入同一缓存预算，无软间隙路径不分配这些向量。行边或空白填充分配区的父
插入点不能冒充精确字形来源。正式注音配对通过同一 Plan、Session 与 Page 协议接入，
测量、可见准备和物理页覆盖使用同一原始来源窗口。

`ForumBodyRubySoftSpaceRequest` 保留同一原始列边缘的真实基字/注音空白请求，按基字、
原始注音 rank 排序；只有 null rank 表示实际基字空白，不增加 RB、RT 或另一侧的空字体
支撑框。成员必须是有来源的非空 ASCII space/TAB 单行内容，并保留同一文档/字体/样式
scope、独立来源对象、原生请求和重绑后的原始顺序。CSS 空白处理仍归原始内容准备。

`ForumBodyRubySoftSpaceMetrics` 复用既有真实字体框和唯一垂直 stack。各层内宽度求和，
共享宽度取各层最大值，按各自实际宽度居中；RTL 只镜像物理位置，不改变成员顺序。
缺失基字的 ascent/descent 为零，缺失注音层保留原始 rank 与 side，均不借用字形。
内部数值组合按 rank/member 有界推进；行目标只扩展已证明的字体范围和垂直坐标，
不重新排字或改变水平几何。结果只保留不可变数字，不提供 source/paint/已读证明。
原始 Plan 只把真实、可折叠的注音层间空白作为这种可裁边间隙；保留空白模式仍明确失败。

`ForumBodyRubyAtomMetrics.softSpace` 与列、跨度共用同一数值行对齐流程。间隙必须紧邻
同一原始根和层级拓扑的两个不透明原子；存在间隙时，即使原始列相同，也必须取得真实
父行。临时父布局只用已测间隙宽度与零高度/基线决定换行，原始字体几何完整保留；
只有机械 SPACE 允许零高度，不透明子项仍须正高度。它不提供可读字形覆盖证明。

实际裁边掩码随父行附加为独立数值快照。被裁掉的间隙不参加行并集、目标检查或对齐；
可见间隙只把实际字体贡献给基字或原始注音 rank，并让同一层级的真实相邻列保留完整
字体范围，即使列自身没有 RT 字形。所有 rank/member 合并、检查及定位仍有界推进。
间隙对齐复用同一组合器，保留原始成员、横向宽度/顺序与 RTL 位置，不再次测量。

带间隙的临时父布局必须退役，不能因 `hasChanges=false` 作为最终结果复用；最终父布局
恢复实际尺寸，并有界复核每个原子的物理行和实际裁边掩码。既有 PlanPreparation 遵循
此协议，owner/预算等待/临时租约释放保持。

`ForumBodyRubyAtomRequest.softSpace`/`ForumBodyRubyAtomPlan.softSpace` 传递原始请求与行目标。
同一 `ForumBodyRubySoftSpacePreparation` 的 `forMetrics` 和 `fromRequests` 复用既有单文字
准备端口：测量逐成员释放 pin，既不录图也不借另一侧字体；可见准备保留且逐项核对当前
来源对象、真实字体框/基线、rank/side/gap 与 paint-ready 状态，再交付实际间隙布局。
原生 shape 或 picture 每次最多一项；纯工作按 rank/member/发布计量。外部压力沿同一
请求等待，完整自身占用超限明确失败，预算探测包含真实共享 band 与所属页的前缀。
错误保留精确失败请求供既有 band 隔离重试，取消只释放本次所有权，不退休其它别名。

`ForumBodyRubySoftSpaceLayout` 只持有真实成员租约与数值目标。绘制、选区与命中共用每个
成员偏移；空白填充、缺失另一侧和对齐留白中的命中保持近似，不伪造基字/注音来源。
close 释放本次成员并清除来源引用。父 View/Assembly 接收独立 `rubySpaces`，要求它和
列/跨度映射互斥、与原生软间隙类型相符，且恰好覆盖该行窗口的实际可见原子。来源 cursor
按真实成员顺序消费当前窗口；临时零高度槽不能代替可读字形尺寸。

纯 `ForumBodyInlinePageContent` 记录最终父布局给出的不可变 `trimmedAtomIndices`。
预算、native handle 数量和可见准备排除这些原子；显示前逐原子复核真实父布局的类型、
坐标窗口和裁边结果，包括隐藏原子。错误或省略的裁边快照不能交付页面。空 RT 来源围栏
保留但没有字形/选区；逐页只持有实际可见列与间隙，暖缓存不重新排字或录图。
原始 HTML Plan 在包含非空注音间隙的实际相邻列边缘生成独立 soft-space 原子，并合并
同一边缘的真实基字空白；缺失另一侧不补字体或来源。只有真实非空跨列注音才形成
不可分组件，空匿名层不阻止独立列换行。所有基字窗口和每个注音层的原文顺序单独保留，
display 顺序与 band 的 source 顺序明确分离；band 重试不改写来源对象、rank 或边缘索引。
转换后为空的 LF 上下文仅保留来源围栏，不增加原子或字形。正式 Session/Reader 覆盖
左右翻页、密集层级、Unicode、裁边、预算等待/取消，以及物理 EOF 和只读恢复；原文末尾
注音先于未读基字显示时，仍须实际读到物理末页才能确认章节完成。Host 布局指纹同时纳入
Plan 与 SoftSpaceMetrics 版本，不修改格式 1 锚点或持久化阅读模式。

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
heap/GPU 观测。App 页面 typed 消费仍待接入。

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

每个活跃缓存条目只索引最近一次传入的不可变 band 身份，重复子项获取可复用该条目的完整
key 和已计算哈希；每次请求仍重新读取全部实际字号缩放值与 gutter，不能用 TextScaler
的对象身份或相等性代替。输入的 UTF-16/run 总量在构造时计算，沿用原字节准入公式。
等值新输入仍核对完整来源与样式，租约绑定本次 content；条目淘汰、清理及 owner 关闭时
同步移除索引，不产生第二套 native 缓存或延长已退休资源的生命周期。

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
为 5。它们是有界纯值，不持有 DOM、Widget 或 native 资源；不得从相同文字、长度或
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

本绑定当前消费叶子 ruby 列；App 页面已消费同一 typed 分片，显式分层和嵌套仍待完成。单项/分片
像素和来源验证不能代替实际复杂正文页面的 profile 验收。

## 普通与混排共享分页

`ForumBodyTextPageComposer.appendInline` 接管已测量的父租约，与普通 append 共用同一
行扫描、合法断界、段距/续页及稳定封页流程。只保留一个活跃父输入；完成、退出或失败
释放父租约，组合器不接管子组。真实显示 coverage 与原始 sourceHint 来自父 display
投影，不能把 U+FFFC 引擎范围用作显示或小说语义 offset；hint 仍不证明实际可见覆盖。

sourceHint 是实际显示窗口全部来源范围的包络，不能只取重排后首尾坐标，也不能代替
实际可见覆盖。行追加只合并新消费窗口的包络，避免重复扫描已经消费的草稿前缀。
快照只追加数值元数据并标记 `ForumBodyTextPageFragmentKind`，composer revision 为 9。

Session 可显式提供 `maxNativeHandlesPerPage`，不超过既有 issued-handle 总容量。
Composer 在真实合法行组边界同时核对高度与可见请求成本；同段续行只保留一次父句柄，
被原生裁掉的间隙不计入成本。完整行组仍超限时明确失败，保留此前稳定前缀，不切原子、
缩字或改变阅读模式。未指定此可选约束的底层调用保持既有高度分页行为。
InlinePageContent 在原有输入核对过程中建立数值前缀和，范围查询通过二分定位实际原子，
拒绝内部切断；不重排字、不持有 native 引用，也不按每行重新扫描整个段落。

小说 Host 将一页上限设为实际 session 总句柄容量的一半，为 PageView 同时显示当前页与
目标页保留容量，默认仍是总计 512、一页 256，缓存条数/字节预算保持。上限进入冻结布局
指纹，创建 Session 时再次核对，不能将不同资源封页规则混用为同一布局。极端单行过密
输入仍走明确预算失败；正式阅读不会自动切换模式或把来源 EOF 当作物理末页。
排字、子租约或回调不进入已发布页；超高不可拆组明确失败，已封页前缀不受晚失败影响。
只接受普通租约的旧页面绑定明确拒绝 inline 分片，不能用同尺寸的普通字形或父占位框
冒充完整交付。本组合能力不启用旧 renderer 兜底或自动切换阅读模式。

普通和混排行窗口共用实际 native 行校验；`appendInline` 同样接受 full、BR 前内容和
末尾空行窗口。非完整窗口要求 engine/display 两套坐标都确认真实末尾分隔与零覆盖行，
注音内部换行或软换行不能伪造父空行。分页保留引擎给出的实际空行高度，不猜默认字号。
typed 空行交付只准备父句柄，不保留隐藏原子；选区为空，点击只给近似来源，不能把
空覆盖当作实际字形或阅读完成证明。普通零覆盖行与 display/engine 同时零覆盖的混排行
不绘制父文字，避免紧行高下上一行字形透入空行；绘制入口仍核对 owner 生命周期。
实际行高、来源与近似命中保持不变。无效窗口不接管输入租约，可由调用方纠正后重试。

`ForumBodyPreparedTextFragment` 是当前挂载的交付句柄，分别持有普通段落租约/行窗口
或完整的混排 view，不进入数值快照。普通句柄构造失败只释放传入别名；close 只退休
本次交付引用。nativeLeases 借用现有句柄供同 owner 的整页预算及生命周期计数，不创建
别名或转移所有权；应按仍活跃的句柄计数，不能只统计父分片数量。

分片的 projection/runs 保留当前显示文本与来源；lines 只返回当前窗口的实际行，物理
坐标统一相对该分片。glyphBoxes 借用实际父文字及基字/注音的 native 字形框，限制查询
显示范围但不裁切字形框。可见覆盖检查必须核对完整字形框与页面/分片裁切边界，不能
用父占位框或已被 UI 裁切的选区冒充精确可见证明；这些查询不排字、不取得新句柄。

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
并发预留、部分释放和上限共用同一套账本。Session 保留输入已统一为 PageContent，
同时容纳普通与实测混排计划；不能因核心会话接入而宣称完整 ruby 阅读器已完成。

Session 的 rubyLimits 原样传给既有 BlockFlow/TextFlow 与 ruby grammar，默认仍使用
512 个结构项。Host 可明确设置有界的纯结构额度；正文间隔、文本子项、注音容器和组
分别计数，不能把结构项等同于 glyph run 或 native 句柄。小说 Host 的结构额度为 2048，
既有文字/run/group、缓存与 issued 句柄上限仍分别约束原本的资源。

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

正式 TextFlow/BlockFlow 的未测量结构由 Session 的唯一 pending 格式计划消费：纯输入
服务组装当前上下文/原子与请求，原生准备服务复用 pair.forMetrics，再以独立工作单元
准备实际父租约。纯计划进入既有保留输入预算，父租约进入既有 composer，传递实际
Flow 行窗口；没有第二个阅读会话、cache 或 scheduler。每次 Session.advance 最多一次
native 排字，warm 格式工作最多 32 单元；formatUnitsPrepared/layoutsBuilt 计入实际进展。

原生批次依来源顺序和方向/对齐/locale、64 子项/16k 文字/512 run 上限装配；不兼容
ink 使用同 owner 的普通固有字形请求。隔离失败只更新未发布请求并让步，下一工作单元
按真实 gutter 提示重试一次；再次失败转同一引擎的逐子项请求。不会在同一次 advance
连续 shape，也不增加现有 cache 预算。发布前的请求改绑不改变已发布计划或来源身份。

普通首尾折叠边缘经 ParagraphContent.displayWindow 使用真实显示/来源投影裁剪；字素
边界、样式和 affinity 保留，不切 HTML。无注音尾部作为父普通文字换行，空 RT 不占
额外 native 行。单行注音独立修剪 normal/pre-line 折叠边缘，通过同一来源窗口保留
样式/字素/affinity，纯空白注音不保留空白上行；pre 与 NBSP 保留。不能切开的组合字素
仍明确失败，裁剪连接处沿用真实双侧来源，不伪造精确命中。基字首尾折叠空格经原始
显示窗口提取为注音盒前后的父普通文字，保留原 run、字素与样式，实际父 TextPainter
负责行边换行。计划从同一次 IR 收集显示索引与原始 sourceOrder，经纯坐标包联验，
不改写原始源码点或把空格固定在不可拆盒内。段首/段尾修剪、相邻折叠空格合并，
真实 BR 前删除待定折叠空格，保留的换行重置行首；空尾部上下文不保活前一个空格。
pre-wrap/NBSP 的字面空白不误折叠。sourceHint 使用实际来源包络，粗候选仍须经当前
可见字形覆盖证明确认，不能以重排后首尾或包络内部缺口冒充精确位置。
孤立 RT 各列的空基字请求不打断相邻注音 band，密集组共享同一空字体布局；计划仍不
录图，页面只准备实际可见的 RT 图片，句柄和预算继续由同一会话管理。
直接连续的 RT 按同一注音层的列配对：首列使用实际文本基字，其余列复用无来源的
匿名空基字，不重复基字的显示、来源或绘图。语义 IR 中的注音关联保持不变，原生子
请求仍通过同一计划、缓存和页面准备消费。基字尾部折叠空格位于整个注音范围之后，
显式 sourceOrder 仍将它放在所有 RT 之前核对原始来源，不插入两列之间。

显式 RB 按原始单元顺序与直接 RT 逐列配对；缺少 RT 的显式基字仍保留实际字体几何，
多余 RT 使用匿名空基字。空 RB 使用其实际样式的空字体度量，隐式未注音尾部继续作为
父普通文字换行。RB 外的首尾格式空白省略，中间空白交给父文字布局且不消耗 RT；
`<rb> </rb>` 中的被标注空格保留在基字列内。原生 band 也按同一个显式 sourceOrder
筛选实际子上下文，不能按显示列顺序装配或用源码点排序重建来源。原有结构、输入、
条目/字节和单步 native 工作预算保持。单层列按实际根及物理行统一基字与注音基线，
跨页末尾由 Host 按实际末页、可见覆盖和稳定阅读资格独立确认，不能以某页的最大源码点
或语义 offset 判断章末：缺少 RT 时，源码末尾可能位于较早的物理页，最后一页的基字
反而对应较早源码点。逐列配对、数值对齐和来源包络均不替代真实阅读证明。

计划先有界检查原始列的数值层级；已对齐时只构建一次父段落。需要对齐时，用同一
缓存的一次临时真实父排字确定物理行，再按行计算目标；全根并集只用于是否需要检查
的快路径，不能作为换行后的发布几何。所有冲突列分到不同行时直接复用临时父布局，
避免给其他行增加空白。确需修改时先释放临时父租约，再取得最终父布局，并有界核对
实际行数与各列所属行，核对通过才发布 PageContent。纯数值扫描计入既有 maxParts，
同一工作单元至多一次 native 排字，不预录制子图片、不改变缓存预算。

`ForumBodyInlineParagraphLease.releaseProvisional` 只在最后一个别名释放时移除该临时
缓存条目，保留仍活跃的别名与其他字形 band。取消、失败或 owner 退休释放当前临时
租约；可读页继续使用同一会话、缓存及页面准备事务。PageContent 仅保留各列不可变
数值层级目标，不保留测量 session 或 native 引用。

当前正式计划接入隐式文本与显式 RB 基字、直接 RT 列、单个 RTC 中的实际 RT 列及独立的非空孤立 RT 列；隐式纯空白基字、显式分层、嵌套及拟合混排
仍明确失败，不丢弃或压平结构，不把隐式缩进空白当作显式 RB 的被标注空格。
这些格式与长段、完整复杂正文性能门槛仍须完成，不能扩张预算或切回旧 renderer 绕过。
Session.inlinePlanRevision 为 17，Host 指纹须纳入它及混排/间隙/批次/投影版本。
