# forum_content_renderer

本地 Flutter HTML 准备与渲染包，负责 prepared document、DOM 规范化、主题与文字样式、正文布局、折叠和图片 viewport 调度。

Core renderer 必须显式接收 `preparedDocument`、`options`、`labels` 和 `theme`。图片 `Host` 可选；宿主通过中立的准备、显示、尺寸和预取端口提供图片能力。准备资源与显示资源分别保持身份，迟到回调和取消仍受当前绑定与显示代次约束。

宿主可提供已解析、未缩放的 `textStyle` 和根 `textAlign`。提供 style 时不再应用 options.fontScale；系统缩放仍由 renderer 环境决定，作者 CSS 和段距策略继续生效。缺省参数保留默认样式及 start 对齐；仅改变对齐也会使缓存正文和根属性失效，不重挂图片/折叠状态。

应用偏好及其持久化、文字转换、本地化、默认 URL/缓存装配、provider、Cookie 和会话继续由宿主负责。包不依赖应用源码或 provider，不装配 Host 传输或会话，也不调用论坛客户端的网络请求 API。

首版通过同仓路径依赖 `yamibo_forum_client`，仅复用公开的图片来源纯策略，保留 DOM 属性优先级、来源规范化和附件判定的唯一实现。

`DiscuzFontSizePolicy`、颜色对比度/色调策略和 `ForumCollapseChrome` 的唯一实现也归本包。HTML、编辑器及其测试统一通过公开入口 `forum_content_renderer.dart` 使用；应用不保留同名副本或旧路径转发。应用共享的 `RichTextTypography` 和文字转换仍由宿主持有。

`ForumHtmlPreparationPipeline` 使用显式 URL resolver 和同步 image policy。prepared 资源实现须为不可变纯值，可随后台准备结果传递；它不持有服务、Widget、Ref 或闭包。renderer 不重做 Host 转换或图片准备，也不替代小说分页。

## 长正文与按需布局

`ForumHtmlRenderer.blockDecorator` 是可选的纯绘制装饰端口；宿主必须保持子项的布局和 intrinsic size，并在同一正文中稳定提供该能力。普通段落使用保留的完整 Widget，结构性外层 div 不合并全部段落；表格、引用、列表、折叠和具有背景／边框／padding 等盒样式的祖先按整体装饰，避免对子孙重复叠加变换。普通富文本块包含硬换行时，通过 `ForumHtmlParagraphMetrics` 暴露其真实排版后的段落矩形；`RenderForumHtmlParagraphMetrics.paragraphs` 是只读局部坐标，只在 layout 更新，不把 UTF-16 选区作为阅读锚点。空行仍保留在原始 RichText 中，不新建 renderer 或改写 BR 为 P；宿主可据真实段落边界绘制一次动画期间保留的纹理，不按任意屏幕条带分组。此端口不修改 prepared HTML、文本坐标、图片编号、准备／分页缓存身份，也不负责动画时钟或阅读导航。更新装饰回调通过保留的 child 绑定传递；切换是否提供该能力属于结构变化，会重建对应正文。

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

renderer 按变化用途发布配置：嵌套排版输入按值比较（主题使用完整 signature），折叠文案和装饰回调分别通知，图片继续通过独立 Host binding 更新。事件使用稳定的当前回调视图，保留 null 表示不处理的语义；只替换事件回调不会重建折叠正文或装饰器。相同排版输入在当前已挂载 State 内保留同一个 `HtmlWidget`，其缓存工厂通过当前状态读取事件、尾部标记及图片配置；该 Widget 不进入跨挂载／跨会话缓存。HTML、字号／文字样式、对齐、完整主题、段距／布局、baseUri、renderMode、构建／缓存模式或装饰能力变化仍替换对应输入。可写 `collapseExpansion` 的 owner 与值快照也参与折叠通知，同一个 Map 的外部编辑仍生效；文案变化保留有效展开状态，装饰回调替换只更新保留的正文 child。

宿主可传入可写的 `collapseExpansion` Map 观察正文的有效折叠状态。renderer 为当前渲染的折叠补齐实际默认值，已有用户选择优先，嵌套折叠沿用同一状态容器。容器反映已渲染折叠，不是完整文档的预扫描结果，正文身份变化时由宿主管理其生命周期。宿主可将该状态纳入布局 revision，按实际可见布局重新测量几何；renderer 不决定章节是否已读，不要求展开折叠内容，也不区分目录与正文。未提供容器的消费者保持原行为。该能力不写入阅读记录或持久偏好。

`ForumHtmlRenderer.imageAnchorController` 可注入正文级 `ForumHtmlImageAnchorController`，嵌套折叠共享根正文的 readable sequence。`revealImage` 按 index、cacheKey 与 URL 校验当前已挂载图片，使用宿主提供的 ScrollController 在至多三帧内对齐真实上沿。关闭折叠、缺失锚点、正文换绑、取消或销毁不猜测目标；不下载图片、不保存阅读进度，也不持有卸载后的正文树。宿主负责在覆盖正文的阅读器退出前调用、校验来源代次并在会话结束时 dispose；未提供 controller 的消费者保持原行为。

`ForumHtmlImageViewportCoordinator` 默认保留磁盘预取。传入 `ForumHtmlImagePredecodePolicy` 可启用方向性邻图准备；宿主通过可选 `ForumHtmlImagePredecodeHost` 实现有界首帧预解码，返回 decoded／diskOnly／failed／cancelled，不暴露 App 缓存类型。成功预解码的邻图在进入视口前挂载显示组件。普通可见加载的成功帧也可保留：Host 通过同步 `canRetainDisplayedImage` 使用原始尺寸、显示宽度与 DPR 核对相同字节预算，不发起额外下载或解码；尺寸提示晚于首帧时可补充准入。失败只释放可见等待名额，不作为解码成功或自动重试。

`retained` 与 `display` 共用同一元素和有效回调代次，越过可见边缘不重新查询磁盘或插回占位。仅当前解码窗口内、张数限制内且通过预算准入的成功图片可保留组件；远离窗口／隐藏／绑定或解码宽度失效即释放。diskOnly／failed 不提前挂载。屏外保留组件通过 `TickerMode` 暂停动图，进入视口恢复。块图工作身份包含 Host、资源身份、显示宽度和 DPR；真实高度回填只更新布局，不退役宽度解码任务或重挂已经显示的图片。

每个已挂载图片由内部 `ForumHtmlImageBinding` 管理来源与显示生命周期：来源代次保护尺寸查询，显示 lease 保护尺寸／首帧／失败／重试回调，可选准备任务继续使用 viewport 的执行名额。更换 Host 或图片来源会退役旧查询与显示；只更换 viewport 或主动重试会退役显示，但保留当前来源有效的尺寸查询。`display ↔ retained` 保持显示 lease，离开挂载模式立即退役，不等待 Widget 重建；handle 的 `isActive` 同时校验 viewport owner，已释放 owner 的最后一个显示模式不代表回调仍有效。Widget 仅保留几何、布局修正与帧调度，绑定不保存 Context、渲染树或 prepared document，也不新增队列／缓存。卸载永久关闭绑定；已取消的在途准备任务仍在实际完成后释放名额。

可选任务完成后释放名额继续推进；两个可见首帧等待占满时暂停新任务，快速滚动推迟新增解码并在滚动停止后恢复。取消立即阻止迟到结果，但在途操作完成前仍占执行名额。预加载失败不自动循环重试，图片显示保留自身重试行为。Host 应复用实际显示的 provider key、限定解码像素预算并在首帧后释放临时监听；不持有长期 Context 或全帖 bitmap。设备档位、内存预算与启用范围由 App 注入，本包不读取 provider 或持久化偏好。

## 可见首帧与回看观测

显示片段的图片身份优先使用准备阶段保留的原始可读编号，缺少编号时才回退到 DOM 位置；同一来源中重复 URL 的不同图片位置不能合并成一次回看。

`ForumHtmlImageViewportCoordinator.visibilityObserver` 可注入公开的 `ForumHtmlImageVisibilityObserver`。关闭时不增加观测 paint 节点或额外滚动监听。开启后使用 Host 的首帧就绪回调、当前绑定的实际 paint 和帧末几何共同确认：正面积视口交集才算可见，祖先裁剪／`paintsChild` 与横向表格滚动均参与复核。下载、磁盘命中和预解码成功均不能单独算作首帧显示。采样描述 Flutter 绘制／合成层就绪，不是 GPU 实际呈现时间，也不检测任意覆盖层遮挡；Host 须通过 `setActive` 提供页面前台／路由资格。Host 的首帧回调须在图片内容可参与当前绘制时报告。

`ForumHtmlImageVisibilityMetrics` 按会话保管访问与有界成功历史；相同 sourceId、DOM 图片位置与不可变显示身份在回收重挂后仍能识别。一次访问从首次可见采样开始，在离屏、隐藏、卸载或绑定退役时结束。回看分母为历史中曾成功绘制过的图片再次可见的访问，失败、离屏放弃与仍等待的回看也包含在内；仅进入的首个采样帧已有图才记命中和零等待。成功、失败、放弃与 pending 分开汇总，重试不改写本次访问的首个结局。历史被驱逐后按未知首次访问处理，不算有证据的回看。

默认最多记忆 512 个成功图片身份、128 个活跃访问；驱逐和超限观察次数单独导出。成功等待、成功回看等待、失败等待与放弃等待各保留最近 256 个时长，以 nearest-rank 导出 P50/P95/P99，空样本为 null，不能把这些分位数解释成全会话全部样本。快照只导出数字，不包含图片身份、URL、路径或正文；记录不持有 Context、Widget、像素或传输对象。`close` 永久拒绝迟到观察并释放身份。宿主负责更换 owner／来源时关闭旧记录器，异常 observer 不得影响图片显示或清理。

Y300 原生帖子 Host 在 debug 默认接入此端口，profile/release 可通过 `--dart-define=Y300_RENDER_METRICS=true` 显式启用；暂停／退出输出 `[ThreadImageVisibility]` 汇总。换帖、翻页、来源筛选／排序及图片服务换绑开启新的统计会话；不合并 reader 既有磁盘／预加载命中口径。

在包目录执行 `flutter pub get`、`flutter analyze --no-pub`、`flutter test --no-pub`。`example/` 是独立 Flutter 工程，显式组装准备与渲染；在该目录执行相同命令可验证公开入口及折叠交互。当前与 App 统一固定 HTML 库 0.17.4；后续升级仍须核对真实段距、列表与字号几何，并同步 App 分页布局修订号，避免复用旧布局页码。尚不对外发布。
