# AGENTS.md

全部编写工作请用UTF-8，你全部的读取代码的工作也是UTF-8编码

## 项目背景

本仓库是面向 Yamibo 论坛内容的 Y300 Flutter/Dart 客户端。主壳包含论坛、收藏、漫画、小说、记录和更多六个入口，覆盖登录与会话、论坛原生解析/WebView 浏览、HTML-first 帖子详情、发帖/回复/帖子编辑、Quill/BBCode 富文本、搜索与标签、收藏同步、漫画/小说书架与阅读器、漫画离线下载队列、应用更新、缓存与数据管理等完整流程。

应用同时使用 SQLite、SharedPreferences 和文件系统保存业务数据、阅读状态、偏好、下载及可再生缓存。全部 Yamibo 论坛远端协议（读取、写命令、认证、受保护图片资源）封装在纯 Dart 包 `packages/yamibo_forum_client` 中，应用统一经 `yamiboForumClientProvider` 提供的 `YamiboForumClient` facade 访问；Host 侧由 `YamiboHttpGateway` 承担唯一共享传输（Cookie、`YamiboSessionStore`、Discuz formhash、WAF 单次重放），并通过 host adapter 桥接 document/snapshot 缓存与表情目录存储。阅读和同步流程普遍包含缓存、取消、single-flight、generation/owner 隔离及失败恢复。进入仓库工作时，必须先理解目标 feature、共享契约和持久化边界的既有写法，并让改动贴合当前架构与兼容策略。

## 架构约束与上下文入口

完整的 `lib` 目录、模块职责和跨模块流转说明位于 [`.codex/context/lib架构地图.md`](.codex/context/lib架构地图.md)。修改 `lib/` 前，必须阅读目标 feature 的职责；涉及跨 feature、论坛协议、持久化、缓存、阅读器或编辑器时，还必须阅读对应的跨模块流转说明。

以下高风险边界仍属于强制约束：

- 依赖方向优先保持 `presentation -> domain <- data`，跨 feature 调用经过公开 contract、service、adapter、bus 或 use case。
- 全部 Yamibo 远端协议位于纯 Dart 包 `packages/yamibo_forum_client`，feature 统一通过 `YamiboForumClient` facade 消费；不得重建旁路请求或第二套会话。
- `YamiboHttpGateway` 是唯一 Host 传输，负责 Cookie、Session/formhash 存储、WAF、取消、日志和单次重放；WebView 重定向 resolver 是明确的 App-bound 例外。
- 写命令只有 `applied` 才能更新本地状态；`outcomeUnknown` 不得自动重发，也不得展示服务器原始载荷。
- 异步阅读、同步与缓存流程必须保持 cancellation、single-flight 和 generation/owner 隔离，迟到结果不得污染新状态。
- 小说作者帖子正文固定通过 `threadAuthorPosts` 使用 `viewthread version=1`，不得改成 `version=4`。

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

- 日常功能调整、修复及验证结果通过提交信息记录；尚未提交时在交付说明中记录，不必逐次追加开发文档，也不因此自动提交。
- 仅在架构、公共契约、持久化规则或长期工作流发生变化时，更新 `docs/开发文档.md` 或对应的专项文档。
- 直接修订相关章节，保持文档描述当前有效的设计与约定；不在文档顶部持续追加逐次开发流水，避免新旧方案混杂。
- 重要技术决策可在专项文档中保留原因、取舍及兼容要求；普通改动无需单独创建设计文档。
- 不需要更新 `docs/Review文档.md`。

## 本地过程记录

- 分支尝试、备选方案、失败路径、待办、AI 交接上下文和原始验证输出默认是本地工作资料，不放入需要提交的 `docs/`，也不通过 `git add -f` 强制追踪。
- 统一保存在 `.local/agent-notes/<完整分支名>/`，保留分支名中的目录层级，例如 `.local/agent-notes/codex/blogs/`。该目录由 `.gitignore` 忽略；在尚未包含此规则的旧分支工作时，使用本仓库 `.git/info/exclude` 补充 `/.local/agent-notes/`，不要修改全局 Git 配置。
- 每条分支用简短的 `README.md` 作为索引：注明对应分支、最近核对的提交、当前结论、未决问题和必要的资料链接。较长的专题记录或运行输出另存文件；更新有效结论，不连续追加整段对话和重复日志。
- 接续任务时先核对当前分支和工作区，再按需读取该分支索引。笔记只提供线索，旧计划和旧测试结果不能代替当前代码、用户指令及实际运行结果；分支变基或重命名后同步修正索引中的提交或位置。
- 日常改动的最终行为、原因和验证结果仍写入提交信息或未提交交付说明。只有已经落地、面向维护者长期有效的架构、公共契约、持久化规则和工作流，才提炼进入正式文档；不把过程笔记原样改名后提交。正式文档不得依赖本地笔记链接才能读懂。
- 提交前用 `git status` 与 staged diff 核对范围，确保过程资料没有被追踪；仅新增忽略规则不能取消已有追踪。已经进入历史的记录须区分是否上传，未经用户授权不改写共享历史。
- 本地笔记不是远端备份，也不保存密码、Cookie 或真实私密正文。分支切换时保留；跨设备交接或删除工作树前，先按用户安排复制到仓库外的私有备份位置，不把临时目录作为唯一副本。

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
