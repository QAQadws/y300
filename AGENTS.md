# AGENTS.md

全部编写工作请用UTF-8，你全部的读取代码的工作也是UTF-8编码

## 项目背景

本仓库是面向 Yamibo 论坛内容的 Y300 Flutter/Dart 客户端。主壳包含论坛、收藏、漫画、小说、记录和更多六个入口，覆盖登录与会话、论坛原生解析/WebView 浏览、HTML-first 帖子详情、发帖/回复/帖子编辑、Quill/BBCode 富文本、搜索与标签、收藏同步、漫画/小说书架与阅读器、漫画离线下载队列、应用更新、缓存与数据管理等完整流程。

应用同时使用 SQLite、SharedPreferences 和文件系统保存业务数据、阅读状态、偏好、下载及可再生缓存。全部 Yamibo 论坛远端协议（读取、写命令、认证、受保护图片资源）封装在纯 Dart 包 `packages/yamibo_forum_client` 中，应用统一经 `yamiboForumClientProvider` 提供的 `YamiboForumClient` facade 访问；Host 侧由 `YamiboHttpGateway` 承担唯一共享传输（Cookie、`YamiboSessionStore`、Discuz formhash、WAF 单次重放），并通过 host adapter 桥接 document/snapshot 缓存与表情目录存储。阅读和同步流程普遍包含缓存、取消、single-flight、generation/owner 隔离及失败恢复。进入仓库工作时，必须先理解目标 feature、共享契约和持久化边界的既有写法，并让改动贴合当前架构与兼容策略。

## `lib` 架构地图

应用按功能模块组织代码：通用基础设施放在 `core`，应用级装配放在 `app`，业务能力放在 `features`，无单一业务归属的 UI 放在 `shared`，论坛远端协议客户端放在 `packages`。Riverpod provider 是主要依赖组合和生命周期管理方式。

- `lib/main.dart`：Flutter 入口、全局初始化和启动前兼容维护。
- `lib/app`：应用顶层装配；`navigation` 负责跨 feature 路由，`settings` 负责外观设置，`theme` 负责主题 token、语义色和组件主题，`localization` 负责语言解析；`Y300App` 还装配更新提示和后台 WAF 恢复宿主。
- `lib/core/config`：应用配置、稳定存储 key 和技术性存储 key。
- `lib/core/media`：封面裁剪/焦点、图片降采样、显示 provider 和 Flutter 图片内存缓存调优。
- `lib/core/network`：共享网络基础设施与 forum client Host 边界。包括 `ApiResult`、`YamiboHttpGateway`（唯一 Host 传输：Cookie、会话与 formhash 存储、WAF 挑战检测/恢复协调、敏感 URI 日志脱敏）、WebView Cookie 同步、图片请求头和 URL 解析；`yamibo_forum_client_provider.dart`、`yamibo_forum_transport_providers.dart`、`yamibo_forum_client_host_adapters.dart` 负责把 Host 传输、Cookie、会话、document/snapshot 缓存和表情目录存储注入 `YamiboForumClient`。
- `lib/core/preferences`：类型化偏好 key、SharedPreferences 访问、provider 和旧偏好迁移。
- `lib/core/utils`：跨模块使用的小型解析工具和通用工具。
- `lib/features`：按业务能力拆分的 feature；跨漫画/小说/收藏的书架能力位于 `library_shared`，跨图片阅读器能力位于 `reader_shared`，发帖/回复/帖子编辑共用编辑器能力位于 `composer_shared`。
- `lib/shared/widgets`：不属于单一 feature 的轻量可复用 UI，包括论坛原生 surface、头像、瞬时反馈、书架视觉组件和帖子正文/编辑器共享的折叠视觉壳。
- `packages/yamibo_forum_client`：纯 Dart 论坛协议客户端包，不依赖 Flutter 与应用状态。包含 source-neutral 的读取/命令/资源/会话认证契约、Discuz adapter、来源装配计划（source plan）、document/snapshot 缓存端口和 WAF 边界；全部 Yamibo 请求构造、协议解析、成功证据与失败分类都在这里，feature 只消费契约结果。

大多数 feature 模块采用轻量 Clean Architecture 分层：

- `data`：本地持久化、codec、平台集成服务、Riverpod provider 装配，以及对 forum client 契约的消费；远端协议解析与请求构造不再位于 feature 数据层，统一在 `packages/yamibo_forum_client`。
- `domain`：稳定模型、repository/服务契约、业务策略、分类器和解析器；原则上不依赖 Flutter Widget。
- `presentation`：页面、controller、adapter、视图状态、Widget，以及必须依赖 Flutter 布局/渲染的阅读与 HTML 展示服务。

依赖方向优先保持 `presentation -> domain <- data`，由 provider 在边界处装配实现。跨 feature 调用应优先经过公开 contract、service、adapter、bus 或 use case，不直接穿透另一个模块的私有数据库/页面状态。

### 功能模块职责

- `app_update`：Gitee Release 更新检查、版本/校验和解析、APK 下载与校验、后台下载事件、安装权限、安装/外部打开和更新弹窗协调。
- `auth`：API 与 WebView 登录、登录进度和认证状态 controller。会话恢复/校验、密码登录与登出经 forum client 的 `session`/`passwordLogin`/`logout` 契约；formhash 由包内 provider 统一提供，不再由本模块自持。
- `cache`：统一可再生磁盘缓存。负责图片、原始 HTML、解析快照、受保护封面、retention 分类、统一容量预算/LRU 裁剪、写入通知、静态容量统计/手动导出和论坛图片预加载；受保护图片字节经包 `ForumResourceClient` 流式获取，本模块只做落盘、索引与预算。
- `comic`：漫画数据、书架、详情和阅读器。章节目录、帖子发现与标签目录经 forum client 读取契约消费业务投影；负责标题分析、章节发现与 TID 顺序、刷新/搜索 fallback 工作流、重复合并、封面与阅读进度、评论页、持久化下载队列、单章 CBZ 产物和下载图片限速。
- `composer_shared`：发帖、回复与帖子编辑共用编辑器基础设施。负责 source/Quill surface、BBCode 转换与预览、`collapse=0` grammar/原子 embed/编辑流程、附件语义与预览解析、编辑偏好、通用 controller 基类和错误呈现；表情目录、图片上传权限/上传、未使用附件目录与删除经 forum client 契约执行。草稿能力由调用方决定，帖子编辑明确关闭持久化草稿。
- `favorites`：论坛收藏同步与收藏书架。收藏目录读取与收藏/取消收藏命令经 forum client 契约（提交后目录回读确认在包内）；负责同步限流、本地持久化、详情上下文加载、内容 ingest 注册表，以及把收藏帖子导入漫画或小说。
- `forum`：论坛壳、解析模式首页/版块列表和 WebView 模式。首页/版块列表读取经 forum client HTML-first 契约（document/snapshot fallback 在包内）；负责模式偏好、SWR 与轮播聚合、WebView driver/runtime、Cookie bootstrap、网络/视觉策略、链接路由、论坛收藏入口，以及应用前台内不可见的普通 WebView WAF 挑战宿主。
- `history`：浏览记录数据库、记录/查询/分组/清理/保留策略、Debug 日志和记录页；记录类型覆盖论坛、帖子、漫画与小说。
- `image_loading`：通用应用图片 source/provider/cache manager、预取接口和 `AppImage` 展示封装；不要与业务化的 `cache` 所有权/retention 规则混为一层。
- `library_shared`：漫画、小说、收藏共用的书架/详情/选择模式抽象。包含模块 adapter、统一 controller/page、排序筛选、视图偏好、书架状态、刷新总线、任务进度/通知、批量阅读状态、封面预热和作品清理契约。
- `more`：更多页、关于页、外观入口、数据与存储页、统一缓存上限设置、清理/统计/手动导出和 Debug 原型工具。
- `novel`：小说数据、书架、详情和阅读器。作者帖正文经 forum client `threadAuthorPosts` 契约以 `version=1` 读取；负责来源元数据与章节同步/恢复、帖子章节网关、正文解析、HTML-first 纵向渲染、全新混合分页、分页缓存/取消/性能策略、唯一阅读进度、书签/搜索和显示偏好。
- `posting`：新主题发布流程。发帖准备与提交经 forum client preparation/command 契约；负责版块/类型/标签/特殊主题与投票建模、提交结果映射，并在 `composer_shared` 之上提供发帖 controller/page。
- `profile`：当前用户与指定用户资料、消息中心、日志列表/详情。当前用户资料、公开资料/日志、提醒/私信读取经 forum client 契约；同时承接需要认证资料的页面入口。资料修改、私信发送等写能力尚未实现，不得凭空补造请求。
- `reader_shared`：漫画与帖子图片阅读共用引擎。负责连续/横向分页阅读、owner 会话隔离、真实可见位置、预加载窗口、图片 preparation、长图切片、缩放/手势、阅读偏好、简繁转换、性能诊断和图片导出。
- `reply`：帖子回复与楼层回复。回复准备与提交经 forum client preparation/command 契约（楼层回复动态字段封装在包内 opaque token）；负责草稿校验，并在 `composer_shared` 之上提供回复 controller/page。
- `search`：搜索读取经 forum client `forumSearch` 契约（formhash、POST、redirect 校验与结果页解析在包内）；负责搜索调度器、限流、查询 generation 隔离、自动分页搜索页和漫画 fallback 编排。
- `startup`：六栏懒加载主壳、跨书架选择操作，以及启动后的 best-effort 任务编排，包括缓存预算维护、漫画刷新/下载队列恢复、系统通知初始化、草稿附件维护和 Yamibo 会话预热（经 client 当前用户资料契约）。
- `storage`：下载根目录选择、目录/文件名规范化、原子 JSON 写入、漫画 CBZ 定位和下载存储模型；不负责具体业务下载队列。
- `tags`：论坛标签索引与查询、标签主题页；标签主题列表读取经 forum client 桌面 HTML 契约。为帖子内容分类和漫画/小说识别提供元数据。
- `thread`：帖子详情核心。详情、回复分页、只看楼主、评分/点评的准备与提交、投票、收藏动作、楼层定位经 forum client 契约；负责内容分类、HTML-first 正文准备/主题适配/缓存图片、原生帖子页、历史记录和帖子图片阅读器桥接。帖子编辑的表单准备、提交与图片附件删除契约已在包内，本模块负责编辑 composer 工作流、提交回读验证、capability gate、原生编辑页及 WebView fallback。

### 跨模块流转说明

- 所有 Yamibo 业务请求经 `yamiboForumClientProvider` 的 `YamiboForumClient` 发起，协议构造、解析与成功/失败语义在 `packages/yamibo_forum_client` 内；Host 传输统一由 `core/network` 的 `YamiboHttpGateway` 承担，共享 Cookie、`YamiboSessionStore` 与 formhash。feature 不得绕过 client 自建第二套请求/会话路径；唯一例外是 App-bound 的 `ForumWebViewRedirectResolver`，只用于跟随 WebView 受管站内跳转并返回最终 URI。WebView 登录/浏览产生的 Cookie 通过同步服务回写；feature 不应各自维护第二套会话。检测到 WAF 挑战（同站 HTTP 405）时，由共享 coordinator 在应用处于 `resumed` 时挂载不可见普通 WebView，Cookie 回灌后仍须通过原生探针确认，只允许原业务请求重放一次；页面加载完成或出现 Cookie 不能单独视为成功。
- 写命令结果统一区分 applied / rejected / notSent / outcomeUnknown / unsupported：只有 applied 才允许更新本地数据、刷新页面或同步书架；结果不确定（outcomeUnknown）不得自动重发；失败呈现使用本地化固定文案，不展示服务器原始消息、JSON、XML/CDATA 或 HTML。
- 论坛壳根据持久化模式进入解析模式或 WebView。受管站内链接由 forum router 分流到原生帖子、发帖、回复、用户资料等页面；无法原生承接的流程保留 WebView 边界。
- 帖子详情通过 `ThreadContentClassifier` 使用 fid/typeid/tag 判断内容类型，tag 数据来自 `tags`。正文进入 `thread` 的 HTML-first pipeline，统一处理 DOM、主题颜色、图片来源、折叠块和渲染缓存；漫画评论与小说正文优先复用该渲染能力，不另建低质量 HTML 子集。
- 收藏同步由 `favorites` 保存远端条目，再通过 ingest registry 调用 `comic`/`novel` 的导入服务。成功导入、刷新、删除或阅读状态变化后，通过 `LibraryShelfRefreshBus` 和共享状态 repository 通知对应书架，而不是直接操作页面 controller。
- 漫画刷新先做当前帖/目录发现与增量合并，直接发现不足时再进入搜索 fallback 或持久化搜索刷新队列。漫画下载入口只向 `ComicDownloadQueue` 入队，worker 串行调用下载服务并写入 CBZ；队列和搜索刷新队列均由 `startup` 恢复。
- 统一书架和统一详情页依赖 `library_shared` 的 `ShelfModuleAdapter`、`DetailModuleAdapter`、选择动作和 purge 契约，不直接依赖漫画/小说/收藏的私有 repository。跨模块长任务通过 `LibraryTaskProgressHub` 与通知桥接发布进度。
- 漫画与帖子图片阅读通过 capability/adapter 接入 `reader_shared` 的 `ImageReaderEngine`；图片缓存与预加载通过 `cache` 服务完成。owner/session generation 是章节或帖子切换的异步边界，旧回调不得污染新内容。
- 小说纵向正文复用 HTML-first 渲染准备，分页模式由 `novel` 自己的文档模型、分类器和混合分页器负责；复杂 HTML 测量属于 presentation 布局能力。小说作者帖读取固定经 forum client `threadAuthorPosts` 契约使用 `version=1`，不得改成 `version=4`。
- `posting` 与 `reply` 只保留各自表单建模与提交结果映射，preparation/command 协议在 forum client 内；编辑器、草稿、附件上传、表情与 BBCode 由 `composer_shared` 统一维护。`thread` 的帖子编辑复用该 surface，编辑表单准备、提交与图片附件删除契约已在包内，但每次进入必须重新 GET 编辑表单且不保存/恢复编辑草稿。帖子编辑只对 capability allowlist 内的普通表单开放原生提交，未知、复杂或结果无法确认的状态必须 fail closed 到 WebView 或停留当前页保留内容，提交后由 app 回读编辑表单证明最终状态。
- `collapse=0` 的语法、递归解析与序列化归 `composer_shared`，视觉 chrome 归 `shared/widgets`；collapse 在 Quill 中是不可被外层格式包裹的原子块，内部仍可包含已支持的 BBCode、表情、附件和嵌套折叠。非法、行内、交叉或超深结构必须保留原始源码，不得猜测修复或丢失内容。
- 页面访问由 `history` 的 mapper/recorder 统一落库，`app/navigation` 的 `HistoryEntryRouter` 再按记录类型打开论坛、帖子、漫画或小说目标。
- 图片、HTML 文档和解析快照写入后通过 `CacheMutationBus` 通知统一预算调度器；“更多/数据与存储”只通过缓存维护与容量契约统计或清理，不扫描并误删下载和用户数据。
- 搜索请求默认经过搜索调度器和限流器，协议层（formhash、POST、redirect、结果页解析）由 forum client 承担；旧搜索 raw service 已删除，不得重建旁路。应用更新使用独立的 Gitee release/checksum/download 边界，不复用论坛搜索或漫画下载队列。

## 强制约束
Flutter 系列命令和dart系列指令是无法在Codex沙箱内跑的，
请你用 require_escalated 发起权限请求，然后自己审批，或者我允许你在沙箱外执行，适合 flutter analyze、flutter test 这类需要访问 SDK/cache 的命令

对你的写的代码要用flutter analyze和flutter test检验（不一定跑完全部的测试，只需要跑必要的测试即可）

## 新增界面文字与国际化

- 所有新增用户可见文字，包括页面标题、按钮、菜单、tooltip、Semantics、SnackBar、错误提示、确认框和空状态，必须加入所有支持语言的 ARB 文件。
- Presentation 层通过 `AppLocalizations` 获取显示文字；domain、data、repository、controller 和业务模型不得硬编码 UI 文案。
- 修改 ARB 后必须执行 `flutter gen-l10n`，检查生成文件和未翻译报告，并在测试中优先使用 `AppLocalizations` 获取期望文字，避免固定语言字符串断言。
- 服务器正文、用户名、URL、协议字段和 parser 判断字符串属于业务原文或协议语义，不是应用 UI 文案，不得误写入 ARB 或进行 UI 文案替换。

## 工程实现要求

实现代码改动时：

- 优先考虑工程化、现代化、可维护的实现。
- 考虑设计模式、设计原则和现有模块边界。
- 不要把所有逻辑耦合到一个地方。
- 优先使用职责清晰的小型 service、adapter 或 interface，避免庞大纠缠的流程。
- 保持代码解耦，方便 review。
- 引入新抽象前，先遵循项目已有约定。
- 只格式化本次实际修改的 Dart 文件；不得无目的地对整个 `lib`、`test` 或仓库执行 formatter，避免产生大量无关 diff。
- 在非显而易见的决策或复杂逻辑处添加简洁注释，方便 review。
- 不要添加只是复述代码表面含义的噪音注释。

## 文档要求

当代码行为、架构、工作流或 review 重点发生变化时：

- 更新 `docs/开发文档.md`。（在文档开头追加新内容即可）（如果仅微调代码时不需要更新docs/开发文档.md）
- 已经不需要更新 `docs/Review文档.md`了。
- 文档应聚焦“改了什么、为什么改、需要用户 review 或测试什么”。

## 协作说明

- 如果用户提供测试或 analyzer 输出，根据输出修复问题，但不要自行运行这些命令。
- 如果遇到已有未提交改动，保留用户改动，并基于当前状态继续工作，不要回退无关改动。
- 优先做范围明确、能解决问题且不破坏整体一致性的最小改动。


## 方案创建
- 对于方案的规划要优先考虑工程化、现代化、可维护的实现。
- 考虑设计模式、设计原则和现有模块边界。
- 不要把所有逻辑耦合到一个地方。


## 重要决策
小说的解析要version=1，而不是version=4，要不然可能会发生格式错误，目前已经实现了，但是我希望你记住而不要乱改

## 笔记
当要增加comic测试标题时需要加到`test\features\comic\domain\services\comic_title_parser_cases.dart`
当要增加novel测试标题时需要加到`test\features\novel\test_support\novel_title_fixtures.dart`
