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
