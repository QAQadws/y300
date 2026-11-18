# AGENTS.md

所有文件的读取、编写和修改均使用 UTF-8。

## 项目与架构

Y300 是面向 Yamibo 论坛的 Flutter/Dart 客户端。主壳默认显示论坛、收藏、漫画、小说、记录和更多，博客与消息可在导航设置中启用。业务数据、阅读状态、偏好、下载和可再生缓存分别由 SQLite、SharedPreferences 和文件系统按现有职责管理。

修改 `lib/` 前，查阅 [lib 架构地图](.codex/context/lib架构地图.md) 中目标模块的职责。涉及跨 feature、论坛协议、持久化、缓存、阅读器或编辑器时，一并查阅相关的跨模块流转。涉及小说分页与恢复、HTML 或图片渲染、相关共享包及测试样本时，查阅 [阅读渲染与测试约束](.codex/context/阅读渲染与测试约束.md) 中适用的章节。

- 依赖方向优先保持 `presentation -> domain <- data`。跨 feature 调用使用公开 contract、service、adapter、bus 或 use case。
- Yamibo 远端协议集中在 `packages/yamibo_forum_client`。应用统一通过 `yamiboForumClientProvider` 提供的 `YamiboForumClient` 访问读取、写命令、认证及受保护图片资源。
- `YamiboHttpGateway` 是唯一共享 Host 传输，负责 Cookie、`YamiboSessionStore`、Discuz formhash、WAF、取消、日志及单次重放。WebView 重定向 resolver 是 App 侧例外。document/snapshot 缓存和表情目录存储使用现有 Host adapter。
- 写命令只有收到 `applied` 才能按成功更新已确认的业务数据或提示成功。草稿、待确认状态和失败反馈按各自的流程处理。`outcomeUnknown` 禁止自动重发和展示服务器原始载荷。
- 阅读、同步与缓存保持现有的取消、single-flight、generation/owner 隔离及失败恢复机制，防止迟到结果覆盖当前状态。
- 小说作者帖子正文固定通过 `threadAuthorPosts` 使用 `viewthread version=1`。

## 实现与 UI 迭代

- 检查当前分支和工作区，保留已有改动。沿用现有实现和模块边界，保留正常入口与兼容行为，做能解决任务的最小改动。
- 只格式化本次实际修改的 Dart 文件。在难以从代码看出原因的决策处补简洁注释。
- UI 方向未定时，先用局部样稿同当前页面对照，按目标屏幕比例检查排版、图标语义和状态。样式和状态确定后，再调过渡与交互反馈。
- 方向确定后，优先在实际页面用 App 热重载微调和验收。`@Preview` 适合独立对照组件或状态，也可以用静态样稿或 App 直接验证。
- 从已验证且反复出现的需求中提炼主题、组件、图标和动效规则。局部 UI 优化沿用现有交互、数据与缓存路径。

## 验证

- Flutter 应用及 Flutter 包的代码改动运行 `flutter analyze` 和相关 `flutter test`。纯 Dart 包在对应包目录运行 `dart analyze` 和相关 `dart test`。涉及 App 与包之间的契约时，在受影响的两侧验证。
- 需要访问沙箱外 Flutter/Dart SDK 或缓存时，按当前权限配置使用 `require_escalated` 申请执行。用户明确安排自行运行时，按其提供的结果处理，并在交付中区分验证来源。
- 纯文档或静态样稿按交付内容检查链接、格式或显示效果。交付时说明已验证的范围和未能完成的验证。

## 界面文字与国际化

- 应用新增用户可见文案时，标题、按钮、菜单、tooltip、Semantics、SnackBar、错误提示、确认框及空状态均补齐所有支持语言的 ARB。
- Presentation 层通过 `AppLocalizations` 获取显示文字。domain、data、repository、controller 和业务模型不得硬编码 UI 文案。
- 修改 ARB 后执行 `flutter gen-l10n`，核对生成文件和未翻译报告。测试期望文字优先从 `AppLocalizations` 获取。
- 服务器正文、用户名、URL、协议字段和 parser 判断字符串保留原有业务或协议语义。

## 文档与本地记录

- 普通功能和修复的行为、原因与验证结果写入提交信息或未提交的交付说明。按用户要求提交。
- Git 提交标题使用 `type(scope): description`，三项必填，分别表示改动类型、影响范围和改动摘要。
- 架构、公共契约、持久化规则或长期工作流发生变化时，直接修订受 Git 追踪的相关文档，记录必要的取舍和兼容要求。`docs/` 是 Git 忽略的本地文档目录，可用于用户指定的本地文档交付。
- 需要续作的分支试验、未决事项、交接内容和原始验证输出放在 `.local/agent-notes/<完整分支名>/`。需要索引时，用该目录的 `README.md` 记录分支、最近核对的提交、当前结论和资料链接。续作以当前代码、用户指令和验证结果为准，分支变基或改名后同步更新索引。
- 过程资料留在本地，避免写入密码、Cookie 或私密正文。跨设备交接或删除工作树前，按用户安排留存到仓库外的私有位置。正式文档应独立可读。
- 提交前用 `git status` 和 `git diff --cached` 核对范围，防止过程资料进入提交。对已追踪的资料先核对 Git 状态和共享历史，改写共享历史须经用户授权。
