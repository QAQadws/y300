# forum_content_renderer

本地 Flutter HTML 准备与渲染包，负责 prepared document、DOM 规范化、主题与文字样式、正文布局、折叠和图片 viewport 调度。

Core renderer 必须显式接收 `preparedDocument`、`options`、`labels` 和 `theme`。图片 `Host` 可选；宿主通过中立的准备、显示、尺寸和预取端口提供图片能力。准备资源与显示资源分别保持身份，迟到回调和取消仍受当前绑定与显示代次约束。

宿主可提供已解析、未缩放的 `textStyle` 和根 `textAlign`。提供 style 时不再应用 options.fontScale；系统缩放仍由 renderer 环境决定，作者 CSS 和段距策略继续生效。缺省参数保留默认样式及 start 对齐；仅改变对齐也会使缓存正文和根属性失效，不重挂图片/折叠状态。

应用偏好及其持久化、文字转换、本地化、默认 URL/缓存装配、provider、Cookie 和会话继续由宿主负责。包不依赖应用源码或 provider，不装配 Host 传输或会话，也不调用论坛客户端的网络请求 API。

首版通过同仓路径依赖 `yamibo_forum_client`，仅复用公开的图片来源纯策略，保留 DOM 属性优先级、来源规范化和附件判定的唯一实现。

`DiscuzFontSizePolicy`、颜色对比度/色调策略和 `ForumCollapseChrome` 的唯一实现也归本包。HTML、编辑器及其测试统一通过公开入口 `forum_content_renderer.dart` 使用；应用不保留同名副本或旧路径转发。应用共享的 `RichTextTypography` 和文字转换仍由宿主持有。

`ForumHtmlPreparationPipeline` 使用显式 URL resolver 和同步 image policy。prepared 资源实现须为不可变纯值，可随后台准备结果传递；它不持有服务、Widget、Ref 或闭包。renderer 不重做 Host 转换或图片准备，也不替代小说分页。

缓存命中时 callbacks 与 labels 可更新，图片点击启用/禁用不会替换图片状态或拦截无图片回调的链接。options、完整 theme signature 与布局值变化会使正文样式失效。ready 可重复报告，宿主应保持幂等。

宿主可传入可写的 `collapseExpansion` Map 观察正文的有效折叠状态。renderer 为当前渲染的折叠补齐实际默认值，已有用户选择优先，嵌套折叠沿用同一状态容器；`onCollapseExpansionChanged` 继续报告真实切换。容器反映已渲染折叠，不是完整文档的预扫描结果，正文身份变化时由宿主管理其生命周期。宿主可据此判断正文是否完整展开，不把关闭的折叠当作已读完；未提供容器的消费者保持原行为。该能力不写入阅读记录或持久偏好。

`ForumHtmlRenderer.imageAnchorController` 可注入正文级 `ForumHtmlImageAnchorController`，嵌套折叠共享根正文的 readable sequence。`revealImage` 按 index、cacheKey 与 URL 校验当前已挂载图片，使用宿主提供的 ScrollController 在至多三帧内对齐真实上沿。关闭折叠、缺失锚点、正文换绑、取消或销毁不猜测目标；不下载图片、不保存阅读进度，也不持有卸载后的正文树。宿主负责在覆盖正文的阅读器退出前调用、校验来源代次并在会话结束时 dispose；未提供 controller 的消费者保持原行为。

`ForumHtmlImageViewportCoordinator` 默认保留磁盘预取。传入 `ForumHtmlImagePredecodePolicy` 可启用方向性邻图准备；宿主通过可选 `ForumHtmlImagePredecodeHost` 实现有界首帧预解码，返回 decoded／diskOnly／failed／cancelled，不暴露 App 缓存类型。成功预解码的邻图在进入视口前挂载显示组件。普通可见加载的成功帧也可保留：Host 通过同步 `canRetainDisplayedImage` 使用原始尺寸、显示宽度与 DPR 核对相同字节预算，不发起额外下载或解码；尺寸提示晚于首帧时可补充准入。失败只释放可见等待名额，不作为解码成功或自动重试。

`retained` 与 `display` 共用同一元素和有效回调代次，越过可见边缘不重新查询磁盘或插回占位。仅当前解码窗口内、张数限制内且通过预算准入的成功图片可保留组件；远离窗口／隐藏／绑定或解码宽度失效即释放。diskOnly／failed 不提前挂载。屏外保留组件通过 `TickerMode` 暂停动图，进入视口恢复。块图工作身份包含 Host、资源身份、显示宽度和 DPR；真实高度回填只更新布局，不退役宽度解码任务或重挂已经显示的图片。

可选任务完成后释放名额继续推进；两个可见首帧等待占满时暂停新任务，快速滚动推迟新增解码并在滚动停止后恢复。取消立即阻止迟到结果，但在途操作完成前仍占执行名额。预加载失败不自动循环重试，图片显示保留自身重试行为。Host 应复用实际显示的 provider key、限定解码像素预算并在首帧后释放临时监听；不持有长期 Context 或全帖 bitmap。设备档位、内存预算与启用范围由 App 注入，本包不读取 provider 或持久化偏好。

在包目录执行 `flutter pub get`、`flutter analyze --no-pub`、`flutter test --no-pub`。`example/` 是独立 Flutter 工程，显式组装准备与渲染；在该目录执行相同命令可验证公开入口及折叠交互。首版固定既有 HTML 库 0.17.2，升级另做验证；尚不对外发布。
