# 收藏自动刷新与搜索等待队列：阶段 3 Review 补充

## 文件范围

- [ ] `lib/features/search/data/forum_search_service.dart`
- [ ] `lib/features/search/data/forum_search_scheduler.dart`
- [ ] `lib/features/search/data/discuz_search_service.dart`
- [ ] `lib/features/search/data/search_rate_limiter.dart`
- [ ] `lib/features/comic/data/local/comic_local_db.dart`
- [ ] `lib/features/comic/data/comic_search_refresh_queue_repository.dart`
- [ ] `lib/features/comic/data/local_comic_search_refresh_queue_repository.dart`
- [ ] `lib/features/comic/data/comic_search_refresh_queue_providers.dart`
- [ ] `lib/features/comic/domain/services/comic_search_refresh_queue_models.dart`
- [ ] `lib/features/comic/domain/services/comic_search_refresh_queue_service.dart`
- [ ] `lib/features/library_shared/domain/services/library_shelf_refresh_bus.dart`
- [ ] `lib/features/startup/presentation/main_shell_page.dart`
- [ ] `test/features/search/data/forum_search_scheduler_test.dart`
- [ ] `test/features/comic/data/comic_search_refresh_queue_repository_test.dart`
- [ ] `test/features/comic/domain/services/comic_search_refresh_queue_service_test.dart`
- [ ] `test/features/startup/presentation/main_shell_page_test.dart`
- [ ] `test/features/startup/presentation/startup_page_test.dart`

## Review 重点

- [ ] `discuzSearchServiceProvider` 仍兼容旧调用方，但真实搜索请求会经过 `ForumSearchScheduler`。
- [ ] 调度器连续两次 `searchForum(enforceRateLimit: true)` 至少间隔 10.5 秒。
- [ ] `rawDiscuzSearchServiceProvider` 只用于真实网络搜索，不承载队列状态。
- [ ] `comic_search_refresh_queue` 表存在，并包含 active 查询与 comic 去重索引。
- [ ] 同一漫画重复入队时 active 任务只有一条。
- [ ] `start()` 会把 running 任务恢复为 pending。
- [ ] worker 成功后调用 `fetchSearchAndCurrentOnly()`、合并章节、提升首集封面，并发出书架刷新信号。
- [ ] worker 异常会写入 `last_error`，增加 `attempts`，并按 retry policy 延后。
- [ ] `MainShellPage` 启动后台任务的 provider 可被测试覆盖，不应强迫 widget 测试打开真实数据库或网络依赖。
- [ ] 本轮未接入收藏同步、详情页手动更新提示、搜索页队列提示和书架 UI 自动订阅，这些属于后续阶段。
- [ ] 本轮未执行测试、分析或格式化，需由 reviewer 本地执行。

---

# 收藏自动刷新与搜索等待队列：阶段 1/2 Review 补充

## 文件范围

- [ ] `lib/features/comic/domain/services/comic_services_impl.dart`
- [ ] `lib/features/comic/domain/services/comic_episode_discovery_service.dart`
- [ ] `lib/features/comic/domain/services/comic_first_episode_cover_service.dart`
- [ ] `lib/features/comic/data/comic_repository.dart`
- [ ] `lib/features/comic/data/local_comic_repository.dart`
- [ ] `lib/features/comic/presentation/adapters/comic_detail_adapter.dart`
- [ ] `lib/features/comic/presentation/comic_detail_page.dart`
- [ ] `test/features/comic/domain/services/network_comic_episode_refresh_service_test.dart`
- [ ] `test/features/comic/domain/services/comic_first_episode_cover_service_test.dart`

## Review 重点

- [ ] `fetchCatalogOnly()` 不触发 `ForumSearchService.searchForum()`。
- [ ] `fetchSearchAndCurrentOnly()` 能跳过当前帖 catalog fallback，并保留搜索候选回探能力。
- [ ] 旧 `fetchEpisodeLinks()` 调用方仍保持兼容。
- [ ] 自动封面提升只写普通封面，不覆盖 `custom_cover_*`。
- [ ] 封面提升服务不依赖 SQLite 细节，写回能力由 `ComicFirstEpisodeCoverWriter` 承担。
- [ ] 本轮未实现搜索等待队列，后续阶段需要继续接入收藏同步和队列 worker。
- [ ] 本轮未执行测试、分析或格式化，需由 reviewer 本地执行。

---

# MVP 页面实现 Review 打勾版模板

> 用途：审查“第 1 批（MVP）”中新实现的 `forumdisplay`、`viewthread`、`登录页`。
> 使用方式：逐项打勾，最后填写结论。每一项都带判定说明，便于统一标准。

---

## 1. 基本信息

- [ ] Review 日期：
- [ ] Reviewer：
- [ ] 分支/提交：
- [ ] 运行环境（设备/模拟器）：

---

## 2. 文件范围确认

### 2.1 应用入口与共享组件

- [ ] 已审查 `lib/main.dart`
- [ ] 已审查 `lib/app/y300_app.dart`
- [ ] 已审查 `lib/shared/widgets/app_skeleton.dart`

### 2.2 forumdisplay 页面

- [ ] 已审查 `lib/features/forum/data/forum_home_repository.dart`
- [ ] 已审查 `lib/features/forum/presentation/forum_home_state.dart`
- [ ] 已审查 `lib/features/forum/presentation/forum_home_controller.dart`
- [ ] 已审查 `lib/features/forum/presentation/forum_home_page.dart`
- [ ] 已审查 `lib/features/forum/data/forum_display_repository.dart`
- [ ] 已审查 `lib/features/forum/data/models/forum_display_models.dart`
- [ ] 已审查 `lib/features/forum/presentation/forum_display_state.dart`
- [ ] 已审查 `lib/features/forum/presentation/forum_display_controller.dart`
- [ ] 已审查 `lib/features/forum/presentation/forum_display_page.dart`

### 2.3 viewthread 页面

- [ ] 已审查 `lib/features/thread/data/thread_repository.dart`
- [ ] 已审查 `lib/features/thread/data/models/thread_detail_models.dart`
- [ ] 已审查 `lib/features/thread/presentation/thread_detail_state.dart`
- [ ] 已审查 `lib/features/thread/presentation/thread_detail_controller.dart`
- [ ] 已审查 `lib/features/thread/presentation/thread_detail_page.dart`

### 2.4 登录页

- [ ] 已审查 `lib/features/auth/data/auth_repository.dart`
- [ ] 已审查 `lib/features/auth/presentation/login_state.dart`
- [ ] 已审查 `lib/features/auth/presentation/login_controller.dart`
- [ ] 已审查 `lib/features/auth/presentation/login_page.dart`

### 2.5 测试与文档

- [ ] 已审查 `test/features/forum/presentation/forum_display_page_test.dart`
- [ ] 已审查 `test/features/thread/presentation/thread_detail_page_test.dart`
- [ ] 已审查 `test/features/thread/data/models/thread_detail_models_test.dart`
- [ ] 已审查 `test/features/auth/presentation/login_page_test.dart`
- [ ] 已审查 `test/features/auth/auth_repository_test.dart`
- [ ] 已审查 `docs/开发文档.md`

判定说明：

1. 缺少任一核心文件审查记录，判定为 P2。
2. 关键文件未提交或未纳入审查，判定为 P1。

---

## 3. 架构与解耦检查

- [ ] 页面层未直接依赖 Dio 或网络细节
- [ ] 控制器负责状态与映射，页面只负责渲染
- [ ] 分页逻辑集中在控制器，不散落在 Widget 内
- [ ] 仓库已抽象为接口，便于测试替身注入
- [ ] Provider 注入路径清晰，无循环依赖
- [ ] 关键流程已写明注释，便于后续维护

判定说明：

1. 页面直接依赖网络实现，判定为 P1。
2. 状态逻辑散落页面导致难维护，判定为 P1。
3. 结构清晰但命名/职责仍可优化，判定为 P2。

---

## 4. 论坛首页收藏版块入口检查

- [ ] 未登录时首页仅展示 forumindex 分组
- [ ] 已登录且有版块收藏时首页展示“我收藏的版块”
- [ ] 首页请求 `myfavforum` 失败时降级为空，不影响 forumindex
- [ ] 线程收藏统一通过主 Tab“收藏”处理

判定说明：

1. 登录态有版块收藏但首页不展示，判定为 P1。
2. `myfavforum` 失败导致 forumindex 主流程不可用，判定为 P0。

---

## 5. forumdisplay 页面检查

- [ ] 首屏可加载帖子列表
- [ ] 加载态显示骨架
- [ ] 下拉刷新可重新拉取数据
- [ ] 加载更多可获取下一页帖子
- [ ] 点击帖子可进入 viewthread 页
- [ ] 失败态可展示错误并支持重试
- [ ] 分页参数 `fid/page` 传递正确

判定说明：

1. 主流程不可用（无法加载/无法渲染），判定为 P0。
2. 分页/跳转/错误态异常，判定为 P1。
3. 仅展示文案或样式细节问题，判定为 P2。

---

## 6. viewthread 页面检查

- [ ] 首屏可展示楼层内容
- [ ] 加载态显示骨架
- [ ] 加载更多可获取下一页回复
- [ ] `[attach]aid[/attach]` 占位能替换为图片，未命中的图片追加到末尾
- [ ] 失败态可展示错误并支持重试
- [ ] `tid/page` 参数传递正确

判定说明：

1. 帖子详情主流程不可用，判定为 P0。
2. 分页或错误态异常，判定为 P1。
3. 仅文本清洗或样式细节问题，判定为 P2。

---

## 7. 登录页检查

- [ ] 表单输入与提交状态正确
- [ ] 空用户名或密码时可阻止提交
- [ ] 登录成功显示成功反馈
- [ ] 登录失败显示错误文案
- [ ] 成功后实际走 `AuthRepository.login`
- [ ] 登录逻辑包含网页登录 + profile 二次校验

判定说明：

1. 登录不可用或成功态不可验证，判定为 P0。
2. 只显示 UI 但不走真实登录链路，判定为 P1。
3. 仅提示文案或按钮样式问题，判定为 P2。

---

## 8. 接口映射检查

- [ ] 首页聚合已使用 `module=forumindex`
- [ ] 首页聚合已使用 `module=profile` 判定登录态
- [ ] 首页聚合不再使用 `module=myfavforum`
- [ ] `forumdisplay` 使用 `module=forumdisplay`
- [ ] `forumdisplay` 列表字段兼容 `forum_threadlist/threadlist`
- [ ] `forumdisplay` 分页字段兼容 `tpp/perpage`
- [ ] `viewthread` 使用 `module=viewthread`
- [ ] 登录页复用网页登录桥接流程（member.php 登录 + profile 校验）

判定说明：

1. 页面使用了错误接口模块，判定为 P0。
2. 接口参数不完整导致行为异常，判定为 P1。

---

## 9. 自动化测试检查

### 8.1 执行记录

- [ ] 已执行 `flutter test test/features/forum/data/models/forum_display_models_test.dart`
- [ ] 已执行 `flutter test test/features/forum/data/forum_home_repository_test.dart`
- [ ] 已执行 `flutter test test/features/forum/presentation/forum_home_page_test.dart`
- [ ] 已执行 `flutter test test/features/forum/presentation/forum_display_page_test.dart`
- [ ] 已执行 `flutter test test/features/thread/presentation/thread_detail_page_test.dart`
- [ ] 已执行 `flutter test test/features/thread/data/models/thread_detail_models_test.dart`
- [ ] 已执行 `flutter test test/features/auth/presentation/login_page_test.dart`
- [ ] 已执行 `flutter test`
- [ ] 已执行 `flutter analyze`

### 8.2 结果记录

- [ ] `forumdisplay` 页面测试通过
- [ ] 论坛首页（登录态 + 收藏区排序）测试通过
- [ ] 首页聚合仓库（降级策略）测试通过
- [ ] `viewthread` 页面测试通过
- [ ] 登录页测试通过
- [ ] 全量测试通过
- [ ] 静态检查无错误

判定说明：

1. 关键测试缺失或无法运行，判定为 P1。
2. 编译或分析报错，判定为 P0。

---

## 10. 手工验证（可选）

- [ ] forumdisplay 页面可进入 viewthread 页面
- [ ] 登录后有版块收藏时首页出现“我收藏的版块”
- [ ] 登录成功后可回到已登录使用路径
- [ ] 弱网下可看到加载态，不会崩溃
- [ ] 异常情况下可触发重试恢复

判定说明：

1. 手工冒烟发现崩溃，判定为 P0。
2. 功能可用但交互不稳定，判定为 P1。

---

## 11. 问题分级标准

- P0：崩溃、核心流程不可用、测试或分析无法通过
- P1：功能可用但行为不正确、关键路径缺测试
- P2：可维护性或可读性问题，不影响当前主流程

---

## 12. 发现记录（填写）

| 编号 | 等级 | 文件 | 问题描述 | 复现步骤 | 建议修复 |
|---|---|---|---|---|---|
| 1 | P0/P1/P2 | 路径 | 描述 | 步骤 | 建议 |
| 2 | P0/P1/P2 | 路径 | 描述 | 步骤 | 建议 |
| 3 | P0/P1/P2 | 路径 | 描述 | 步骤 | 建议 |

---

## 13. 最终结论（填写）

- [ ] 通过
- [ ] 有条件通过
- [ ] 不通过

结论摘要：

1. 主要风险：
2. 必改项：
3. 建议优化项：
4. 回归验证人/时间：

---

## 漫画模块阶段0/1 Review 补充清单

### 一、架构与解耦

- [ ] 漫画能力集中在 `features/comic`，未侵入论坛数据层实现细节。
- [ ] `thread_detail` 仅通过状态扩展接入漫画识别结果，无跨层直接耦合。
- [ ] 识别(`ComicDetector`)与解析(`ComicParserService`)为可替换抽象。

### 二、功能检查（阶段0）

- [ ] 新增漫画域骨架后，非漫画路径页面行为保持不变。
- [ ] 漫画入口未在非候选帖首楼显示。

### 三、功能检查（阶段1）

- [ ] `fid=30` 且图文/章节信号充分时，首楼显示“加入书架”按钮。
- [ ] 点击“加入书架”后按钮状态变为“已在书架”。
- [ ] 非漫画帖不应误展示入口。
- [ ] HTML 异常或解析失败不应影响帖子正文渲染。

### 四、解析质量

- [ ] `img[src]` 提取可去重并过滤表情类资源。
- [ ] 章节链接 `thread-xxx-1-1.html` 可被提取并规范化。
- [ ] 目录链接与摘要文本能被正确输出（允许部分缺失）。

### 五、测试覆盖检查

- [ ] `comic_detector_test.dart` 覆盖候选与非候选判定。
- [ ] `comic_parser_service_test.dart` 覆盖图片去重、链接提取、目录识别。
- [ ] `thread_detail_page_test.dart` 覆盖漫画入口显隐与加入书架状态切换。

### 六、本轮已知限制（非缺陷）

1. 书架存储为内存仓库，仅用于阶段1联调。
2. 尚未接入本地数据库持久化（属于阶段2范围）。
3. “已在书架”按钮暂未跳转漫画书架页。

---

## 漫画模块阶段2 Review 清单补充

### 一、存储层检查

- [ ] 已引入本地数据库并完成建表：`comics/episodes/episode_images/categories/shelf_items`
- [ ] 默认分类 `default` 初始化成功
- [ ] `shelf_items` 唯一约束生效（重复加入不产生脏数据）
- [ ] 关键查询已建立索引（章节、图片、书架）

### 二、仓库实现检查

- [ ] `ComicRepository` 接口维持稳定，业务层不直接依赖 SQL
- [ ] `LocalComicRepository.addToShelf` 使用事务，失败可回滚
- [ ] `isInShelf/getShelfItems` 查询结果正确
- [ ] `addToShelf` 具备幂等性

### 三、功能闭环检查

- [ ] 帖子详情点击“加入书架”后，漫画 Tab 书架可见
- [ ] 重启 App 后书架数据仍保留
- [ ] 非漫画帖不会污染书架数据

### 四、导航与页面检查

- [ ] 启动后进入 `MainShellPage`
- [ ] 可在“论坛/漫画”Tab间切换
- [ ] 漫画书架空态、错误态与基础网格显示正常

### 五、测试检查（阶段2新增）

- [ ] `local_comic_repository_test.dart` 通过
- [ ] `comic_shelf_models_test.dart` 通过
- [ ] `main_shell_page_test.dart` 通过
- [ ] `comic_shelf_page_test.dart` 通过
- [ ] `startup_page_test.dart` 新增断言通过

### 六、已知限制（阶段边界）

1. 阶段2书架仅最小可用，分类管理 UI 未实现（属于阶段3）。
2. 漫画详情/阅读页未实现（属于阶段4/5）。
3. 书架封面渲染暂为基础网络图加载，缓存策略后续增强。

---

## 漫画规则增强 Review 清单补充

### 一、楼主一二楼聚合规则

- [ ] 首楼始终纳入漫画判定输入
- [ ] 二楼为楼主且图片主导时，二楼内容并入判定与解析输入
- [ ] 二楼非楼主时，不应并入
- [ ] 聚合策略已独立成服务，控制器无硬编码规则膨胀

### 二、封面与标题展示

- [ ] 书架标题显示在封面图片底部（覆盖层）
- [ ] 标题最多两行
- [ ] 超出时第二行末尾显示“···”
- [ ] 在无封面图/加载失败时，叠字样式仍保持稳定

### 三、测试覆盖

- [ ] `comic_post_aggregation_service_test.dart` 通过
- [ ] `comic_shelf_page_test.dart` 新增叠字截断断言通过
- [ ] `thread_detail_page_test.dart` 新增二楼补图场景通过

### 四、风险提醒

1. “多数图片”规则当前采用通用启发式（图片>=2且图片数>=链接数），后续可按真实帖子样本继续调参。
2. 中文“···”截断为自定义实现，建议在不同屏幕宽度下补充更多快照或 Widget 回归用例。

---

## 登录链路增强 Review 补充清单

### 一、登录态校验

- [ ] 登录流程包含 forumindex(auth) 校验
- [ ] `auth != null && auth 非空` 才判定登录态有效
- [ ] forumindex 通过后再读取 profile 组装会话

### 二、稳定性与体验

- [ ] 登录按钮重复点击时不会并发触发多次提交
- [ ] 登录链路存在超时兜底并返回可读错误
- [ ] 登录成功后会触发论坛首页数据刷新
- [ ] 登录成功后页面可回退并带成功结果

### 三、测试覆盖

- [ ] `auth_repository_test.dart` 覆盖 auth 成功/失败场景
- [ ] 覆盖“网页登录成功但 forumindex.auth 为空”的失败分支
- [ ] `login_page_test.dart` 覆盖登录成功/失败 UI 路径

### 四、潜在风险与后续优化

1. 如后端出现“forumindex.auth 延迟生效”，可考虑短轮询重试 1-2 次再判失败。
2. 登录超时阈值目前固定 18 秒，后续可通过配置化按网络环境调优。

---

## 漫画模块阶段3 Review 补充清单（书架完整 UI 与分类系统）

### 一、数据层与迁移
- [ ] `ComicRepository` 阶段3接口完整：分类管理、封面替换、网格设置、分类迁移。
- [ ] `ComicLocalDb` 版本升级到 `v2`，包含 `settings` 表迁移逻辑。
- [ ] 老数据库升级后默认写入 `grid_column_count=3`。

### 二、分类系统行为
- [ ] 可创建自定义分类。
- [ ] 可重命名自定义分类。
- [ ] 可删除自定义分类。
- [ ] 删除分类后漫画自动回落默认分类。
- [ ] 默认分类不可重命名、不可删除。

### 三、书架 UI 行为
- [ ] AppBar 包含：标题、搜索按钮、菜单按钮。
- [ ] 分类横向条可切换分类并刷新网格。
- [ ] 网格支持 2/3/4 列切换并稳定渲染。
- [ ] 漫画卡片长按可打开操作面板。

### 四、封面与移动
- [ ] 支持输入封面 URL 替换封面。
- [ ] 支持恢复默认封面。
- [ ] 支持将漫画移动到其他分类。

### 五、解耦与可维护性
- [ ] UI 页面未直接访问 SQL。
- [ ] 控制器仅负责编排状态，不承载数据库细节。
- [ ] 仓储实现保持幂等与事务一致性。

### 六、测试清单（阶段3新增/更新）
- [ ] `test/features/comic/data/local_comic_repository_test.dart`
- [ ] `test/features/comic/presentation/comic_shelf_page_test.dart`
- [ ] `test/features/comic/domain/comic_shelf_models_test.dart`
- [ ] `test/features/startup/presentation/main_shell_page_test.dart`
- [ ] `test/features/thread/presentation/thread_detail_page_test.dart`

### 七、执行说明
本轮未执行自动化命令，请本地执行并回传结果：
1. `flutter test`
2. `flutter analyze`

---

## 漫画书架分类分页化 Review 补充清单

### 一、分类栏视觉与结构
- [ ] 分类栏仅保留文字标签，无边框、无内联删除图标。
- [ ] 分类栏底部存在圆角小长条指示器。
- [ ] 分类栏与内容区之间存在分隔线。

### 二、分页交互
- [ ] 点击分类文字可平滑切换到对应页。
- [ ] 左右滑动内容区可切换分类。
- [ ] 滑动过程中指示器位置连续变化，无跳变。
- [ ] 切换时可感知左右相邻页（非硬切）。

### 三、分类管理入口
- [ ] 分类新建/重命名/删除均从 AppBar 菜单触发。
- [ ] 默认分类不可重命名、不可删除。
- [ ] 删除自定义分类后漫画回落默认分类。

### 四、工程化与可维护性
- [ ] 状态层提供 `itemsByCategory`，UI 不直接调仓库读取分类内容。
- [ ] 页面拆分为分类头、分页页、网格卡片等独立组件。
- [ ] `PageController` 与业务状态同步逻辑清晰且可追踪。

### 五、测试项
- [ ] `comic_shelf_page_test.dart` 覆盖分类头/指示器/分页滑动。
- [ ] 现有主流程测试（thread/startup）可继续通过。

### 六、执行说明
本轮未执行自动化命令，请本地执行并回传：
1. `flutter test`
2. `flutter analyze`

### 增量补充：固定4槽位分类栏检查项

- [ ] 分类标签宽度固定为分类栏宽度的 `1/4`（与分类数量无关）。
- [ ] 分类数量 < 4 时不拉伸单个标签宽度。
- [ ] 分类数量 > 4 时可横向滚动查看更多分类。
- [ ] 指示器基于固定槽位计算并随滑动连续联动。
- [ ] 相关测试已覆盖固定宽度与超4滚动场景。

---

## 漫画模块阶段4 Review 补充清单（详情与章节管理）

### 一、页面与导航
- [ ] 书架卡片点击可进入 `ComicDetailPage`。
- [ ] 详情页展示封面、标题、作者、章节统计信息。
- [ ] 章节项点击可进入阅读占位页（阶段5待接入正式阅读器）。

### 二、章节列表与排序
- [ ] 章节列表默认倒序展示（最新章节在前）。
- [ ] 章节空态提示文案清晰。

### 三、刷新章节流程
- [ ] 右上角“刷新章节”可触发。
- [ ] 刷新流程为：拉帖首楼 -> 解析章节链接 -> 合并本地章节。
- [ ] 合并逻辑具备幂等性（同章节重复刷新不产生重复记录）。
- [ ] 刷新后页面可提示新增/更新统计结果。

### 四、解耦与可维护性
- [ ] `ComicEpisodeRefreshService` 负责网络拉取与解析。
- [ ] `LocalComicRepository` 仅负责本地持久化与合并。
- [ ] `ComicDetailController` 仅负责编排状态，不承担底层细节。

### 五、测试检查
- [ ] `comic_detail_page_test.dart` 覆盖详情渲染与刷新动作。
- [ ] `local_comic_repository_test.dart` 覆盖详情读取与章节合并。
- [ ] 受接口扩展影响的旧测试已全部适配。

### 六、执行说明
本轮未执行自动化命令，请本地执行并回传：
1. `flutter test`
2. `flutter analyze`

---

## 漫画模块阶段5 Review 补充清单（阅读器与缓存优化）

### 一、阅读器主流程
- [ ] 章节点击进入 `ComicReaderPage`（不再是占位页）
- [ ] 长图纵向滚动阅读稳定
- [ ] 图片加载中有占位提示
- [ ] 图片加载失败可点击“重试”

### 二、缓存能力
- [ ] 右上角存在“缓存本话”操作
- [ ] 右上角存在“缓存全部未读”操作
- [ ] 缓存结果可回写缓存状态（done/failed）

### 三、阅读进度
- [ ] 滚动阅读后可持久化最后阅读位置（章节+图片索引+偏移）
- [ ] 重新进入阅读器可恢复上次滚动位置
- [ ] `comics.last_read_episode_id` 与 `reading_progress` 数据一致

### 四、数据层与解耦
- [ ] `ComicRepository` 已扩展阅读器接口，页面未直接依赖存储实现
- [ ] 阅读抓图与缓存逻辑集中在 `ComicReaderService`
- [ ] 控制器仅做状态编排，不混入 SQL 细节

### 五、回归关注点
- [ ] 漫画详情页刷新章节能力不受影响
- [ ] 书架页加载与分类切换不受影响
- [ ] 线程详情“加入书架”链路不受影响

### 六、测试清单（阶段5新增/更新）
- [ ] `test/features/comic/presentation/comic_reader_page_test.dart`
- [ ] `test/features/comic/data/local_comic_repository_test.dart`（阅读进度与缓存状态）
- [ ] 受 `ComicRepository` 接口变更影响的页面测试全部通过

### 七、执行说明
本轮改动未执行自动化命令，请本地执行并回传结果：
1. `flutter test`
2. `flutter analyze`

---

## 漫画阅读迁移阶段0 Review补充清单

### 一、阶段目标对齐
- [ ] 已新增阅读器偏好模型：`ReaderPreferences`
- [ ] 已新增阅读器偏好持久化抽象：`ReaderPreferencesRepository`
- [ ] 已新增 shared_preferences 落地实现且未向上层泄漏存储细节
- [ ] 阅读页已拆分为三层容器（内容/顶部/底部）
- [ ] 阅读控制器已补充 `jumpToImageIndex` / `goToPreviousEpisode` / `goToNextEpisode`

### 二、解耦与可维护性
- [ ] 模型、存储、状态、页面层职责边界清晰
- [ ] 页面不直接读写 shared_preferences
- [ ] 控制器通用接口可复用于后续进度条/章节切换
- [ ] 关键预埋点具备注释说明，便于后续阶段扩展

### 三、回归约束（阶段0必须不破坏现有行为）
- [ ] 阅读页图片流渲染行为与改造前一致
- [ ] 缓存按钮行为与改造前一致
- [ ] 上一话/下一话返回约定（`previous`/`next`）保持不变

### 四、阶段0新增测试检查
- [ ] `test/features/comic/presentation/models/reader_preferences_test.dart`
- [ ] `test/features/comic/presentation/providers/reader_preferences_provider_test.dart`
- [ ] `test/features/comic/presentation/controllers/comic_reader_controller_test.dart`
- [ ] `test/features/comic/presentation/comic_reader_page_test.dart`（新增三层容器断言）

### 五、执行说明
本轮按约定未执行：
1. `flutter test`
2. `flutter analyze`

请在本地执行后回传结果，再进行下一轮修复或进入阶段1。

### 阶段0修订 Review补充（生命周期与菜单交互）

- [ ] `ComicReaderController` 依赖不再通过异步续体直接 `ref.read`，而是在 `build()` 缓存后使用
- [ ] 控制器关键异步路径在 `await` 后有 `ref.mounted` 防护
- [ ] 阅读页菜单默认隐藏
- [ ] 仅点击中部区域触发菜单显隐
- [ ] 菜单显隐存在上下滑入动效
- [ ] `上一话/下一话` 仅在菜单显示时出现（非固定常驻）
- [ ] `comic_reader_page_test.dart` 已覆盖中部点击触发菜单出现断言

执行说明：
本轮仍未执行：
1. `flutter test`
2. `flutter analyze`

---

## 漫画阅读迁移阶段1续做 Review 补充（2026-05-01）

### 一、更多页信息架构
- [ ] “更多”页包含：登录、数据与存储、阅读设置占位、关于占位
- [ ] 登录入口仅在“更多”页可见，论坛页不再提供登录按钮

### 二、数据与存储设置页
- [ ] 默认目录与当前生效目录可见
- [ ] 选择自定义目录后，自定义目录与生效目录同步更新
- [ ] 恢复默认后，自定义目录清空，生效目录回到默认目录
- [ ] 操作后提示文案清晰（已更新/已恢复等）

### 三、工程化与解耦
- [ ] `MorePage` 仅负责入口与导航，不承载缓存存储逻辑
- [ ] `CacheSettingsPage` 仅消费状态并触发动作
- [ ] `CacheSettingsController` 负责编排流程
- [ ] `MoreSettingsRepository` 负责平台/插件调用（目录与持久化）

### 四、测试覆盖补充
- [ ] `test/features/more/presentation/cache_settings_page_test.dart` 已覆盖三条主链路
- [ ] `test/features/forum/presentation/forum_home_login_entry_migration_test.dart` 已覆盖登录入口迁移回归
- [ ] `test/features/more/presentation/more_page_test.dart` 包含入口与文案断言

### 五、执行说明
本轮未执行自动化命令，请本地执行并回传结果：
1. `flutter test`
2. `flutter analyze`

---

## 漫画阅读迁移阶段2 Review补充清单（菜单动效与中心点击）

### 一、交互主链路
- [ ] 阅读页菜单默认隐藏
- [ ] 点击中部区域可切换菜单显示/隐藏
- [ ] 菜单显示/隐藏存在上下滑入滑出动效
- [ ] 菜单隐藏时不可点击（`IgnorePointer` 生效）

### 二、顶部菜单
- [ ] 包含返回按钮
- [ ] 可展示当前话标题（超长省略）
- [ ] 包含“缓存本话”“缓存全部未读”入口

### 三、底部菜单
- [ ] 包含“上一话”“下一话”按钮
- [ ] 无上一话/下一话时按钮禁用状态正确
- [ ] 章节跳转行为保持既有约定（`Navigator.pop('previous'/'next')`）

### 四、工程化解耦
- [ ] 点击分区组件已拆分为 `ReaderTapZones`
- [ ] 顶部菜单组件已拆分为 `ReaderTopBar`
- [ ] 底部菜单组件已拆分为 `ReaderBottomPanel`
- [ ] `ComicReaderPage` 仅负责状态编排与组装，不混入大量UI细节

### 五、测试覆盖
- [ ] `comic_reader_page_test.dart` 回归通过
- [ ] `reader_tap_zones_test.dart`（中心点击触发）通过

### 六、执行说明
本轮按约定未执行自动化命令，请本地运行并回传结果：
1. `flutter test`
2. `flutter analyze`

---

## 漫画阅读迁移阶段3 Review补充清单（阅读模式切换）

### 一、阅读模式主链路
- [ ] 底部菜单存在阅读模式切换控件（垂直/左到右/右到左）
- [ ] 三种模式切换可即时生效
- [ ] `vertical` 使用 `ListView` 轨道
- [ ] `ltr/rtl` 使用 `PageView` 轨道

### 二、模式映射正确性
- [ ] `ltr` 对应 `PageView(reverse: false)`
- [ ] `rtl` 对应 `PageView(reverse: true)`
- [ ] 分页模式左右点击分区翻页方向符合模式语义

### 三、进度对齐与持久化
- [ ] 模式切换以逻辑 index 对齐，不丢页
- [ ] 切换后调用偏好持久化，重进阅读页可恢复上次模式
- [ ] 页面初始化时按 `reader_preferences` 选择渲染轨道

### 四、工程化解耦检查
- [ ] `ReaderBottomPanel` 仅负责 UI 与回调，不包含业务状态编排
- [ ] `ComicReaderPage` 负责流程编排与状态同步
- [ ] 内容渲染按垂直/分页拆分独立方法，避免单函数过度膨胀

### 五、测试覆盖
- [ ] `comic_reader_page_test.dart` 覆盖三模式核心路径（默认、持久化恢复、切换生效）
- [ ] `reader_bottom_panel_test.dart` 覆盖模式切换回调

### 六、执行说明
本轮按约定未执行自动化命令，请本地运行并回传结果：
1. `flutter test`
2. `flutter analyze`

### 阶段3回归修复检查项（分页模式溢出）

- [ ] `ltr` 模式下阅读页无 `RenderFlex overflow` 报错
- [ ] `rtl` 模式下阅读页无 `RenderFlex overflow` 报错
- [ ] 分页模式单页图片在视口内完整显示（`BoxFit.contain`）
- [ ] 分页模式图片加载失败态不触发溢出
- [ ] 纵向模式渲染行为未回退（仍为宽度铺满连续流）

回归命令（由你本地执行）：
1. `flutter test`
2. `flutter analyze`

---

## 漫画阅读迁移阶段4 Review补充清单（进度条 + 页码 + 章节按钮）

### 一、结构与交互
- [ ] 底部菜单存在进度条区块（左右章节按钮 + 中间胶囊）
- [ ] 左内显示当前页，右内显示总页数
- [ ] 拖动中页码可即时反馈
- [ ] 释放滑块后触发实际跳页

### 二、模式一致性
- [ ] 垂直模式释放后按目标索引滚动到对应位置
- [ ] 分页模式释放后跳转到目标页（PageView）
- [ ] 跳页后进度持久化状态一致（逻辑 index 同步）

### 三、边界与健壮性
- [ ] 单页场景不报 `divisions` 错误
- [ ] 无上一话/下一话时按钮禁用状态正确
- [ ] 无图片场景仍走上游空章节提示，不出现进度条异常

### 四、解耦性
- [ ] `ReaderProgressBar` 仅负责 UI + 交互回调
- [ ] `ReaderBottomPanel` 仅组合与透传回调
- [ ] `ComicReaderPage` 仅负责模式分发与跳页业务编排

### 五、测试覆盖
- [ ] `comic_reader_page_test.dart` 覆盖进度条存在与交互主链路
- [ ] `reader_bottom_panel_test.dart` 兼容新参数并保持模式切换断言
- [ ] `reader_progress_bar_test.dart` 覆盖页码渲染与回调触发

### 六、执行说明
本轮按约定未执行自动化命令，请本地运行并回传结果：
1. `flutter test`
2. `flutter analyze`

---

## 跳转性能优化 Review补充清单（进度条卡顿/偶发不跳）

### 一、跳转命中率
- [ ] 进度条快速拖动释放后能稳定跳转到目标页
- [ ] 连续多次短间隔释放不出现“偶发不跳”
- [ ] 垂直模式在图片尚未完全布局时仍可纠偏到目标区域

### 二、性能体验
- [ ] 高频滚动时无明显主线程卡顿
- [ ] 拖动进度条过程中 UI 反馈平滑
- [ ] 跳页后目标页及相邻页加载感知改善（近邻预加载生效）

### 三、数据一致性
- [ ] 进度落库最终值与最后停留页一致
- [ ] 防抖后无异常进度回退/跳动
- [ ] 模式切换后进度持久化逻辑不回归

### 四、工程化与解耦
- [ ] 预加载能力通过 `ComicReaderService.prefetchImages` 抽象，不侵入页面层
- [ ] 控制器负责防抖与预加载编排，页面仅触发行为
- [ ] 垂直跳转纠偏逻辑集中在 `_jumpVerticalToIndex`，便于后续调参

### 五、测试覆盖
- [ ] `comic_reader_controller_test.dart` 覆盖预加载窗口触发
- [ ] `comic_reader_controller_test.dart` 覆盖滚动进度防抖落库

### 六、执行说明
本轮按约定未执行自动化命令，请本地运行并回传结果：
1. `flutter test`
2. `flutter analyze`

### 编译修复检查项（prefetchImages 接口）

- [ ] `NetworkComicReaderService` 已显式实现 `prefetchImages`
- [ ] `ComicReaderPage` 相关 fake service 已显式实现 `prefetchImages`
- [ ] 不再出现 `non_abstract_class_inherits_abstract_member` 编译错误

回归命令（由你本地执行）：
1. `flutter test`
2. `flutter analyze`

### 测试生命周期检查项（autoDispose + debounce）

- [ ] `onScrollProgress persists with debounce` 用例中已保持 provider 订阅存活
- [ ] 定时器窗口内 provider 不被 autoDispose 回收
- [ ] 断言落库记录非空且最终值正确

---

## 进度条防抽搐 Review补充清单

### 一、交互稳定性
- [ ] 进度条首次点击/拖动释放可稳定触发跳转
- [ ] 不再出现“来回抽搐后回原位”现象
- [ ] 提交过程中滑块不会被旧状态反向拉回

### 二、状态机验证
- [ ] 拖动开始进入 session 态
- [ ] 提交后进入 commit-in-flight 态并锁定交互
- [ ] 到达目标页后自动解锁并清理 pending 状态

### 三、组件解耦
- [ ] `ReaderProgressBar` 仅处理输入与锁定渲染，不承载业务逻辑
- [ ] `ReaderBottomPanel` 仅透传进度回调与锁定参数
- [ ] `ComicReaderPage` 集中维护提交状态机与模式分发

### 四、测试覆盖
- [ ] `reader_progress_bar_test.dart` 覆盖锁定态不可交互
- [ ] `comic_reader_page_test.dart` 覆盖提交期间关键节点稳定性
- [ ] `reader_bottom_panel_test.dart` 适配新增参数

### 五、执行说明
请本地执行并回传：
1. `flutter test`
2. `flutter analyze`

### 回归补充检查项（pending timer + warning）

- [ ] 进度条稳定性测试不再出现 pending timer
- [ ] `comic_reader_page.dart` 无 `_isSliderSessionActive` 未使用告警
- [ ] `flutter analyze` 无新增 warning/error

1. `flutter test`
2. `flutter analyze`
## 搜索收藏联动 Phase 0 Review补充清单（2026-05-03）

### 一、可观测性基线
- [ ] `ParsedComicPost` 已增加 `parsingDebug` 可选字段，旧调用方不受影响
- [ ] 解析结果包含阶段信号（`image` / `anchor` / `rule`）
- [ ] 解析结果包含汇总统计（anchor 数、episode 数、catalog）
- [ ] 新增 `ComicSyncLogger`，可消费解析调试信息

### 二、解析回归样本
- [ ] 兼容 `thread-xxx-1-1.html` 链接
- [ ] 兼容 `forum.php?mod=viewthread&tid=xxx` 链接
- [ ] 兼容 `&amp;amp;` 多重转义链接
- [ ] 兼容残缺链接 `;tid=537155&...`
- [ ] 目录链接（文本含“目录”）可命中并记录 signal

### 三、工程化解耦
- [ ] 调试模型位于独立文件，不与 UI/存储耦合
- [ ] 日志组件与解析组件分离
- [ ] Phase 0 仅增强可观测性，不引入 UI 行为变更

### 四、测试文件检查
- [ ] `test/features/comic/data/comic_parser_service_test.dart` 已新增阶段0回归样本
- [ ] 包含 debug signal 相关断言
- [ ] 包含 `;tid=` 异常链接断言

### 五、执行说明
本轮按约定未执行自动化命令，请你本地执行并回传结果：
1. `flutter test`
2. `flutter analyze`
---

## 搜索收藏联动 Phase 1 Review 补充清单（2026-05-03）

### 一、解析引擎化与解耦
- [ ] 新增 `comic_post_parsing_models.dart`，解析上下文/锚点/候选模型职责清晰
- [ ] `ComicPostParsingEngine` 通过规则列表驱动，非单体 if/else 膨胀
- [ ] 规则拆分为 `CatalogRule` / `EpisodeStrongRule` / `EpisodeClusterRule` / `RejectRule`
- [ ] 引擎输出 `EpisodeExtractionResult`，包含 episodes/catalog/debug signals

### 二、链接解析能力
- [ ] 支持 `thread-xxx-1-1.html` 解析 tid
- [ ] 支持 `forum.php?mod=viewthread&tid=xxx` 解析 tid
- [ ] 支持残缺 `;tid=xxx` 链接修复
- [ ] 章节候选按 tid 去重，保留高置信度结果

### 三、连续楼主楼层解析
- [ ] 新增 `ComicConsecutiveOpPostParser`
- [ ] 从 1 楼开始合并连续楼主楼层
- [ ] 遇到首个非楼主楼层立即停止
- [ ] 合并结果保持 `ParsedComicPost` 向后兼容

### 四、兼容接入
- [ ] `HtmlComicParserService` 已通过适配层接入引擎
- [ ] `ComicParserService` 对外接口未变
- [ ] 既有调用方无需改动即可使用新能力

### 五、测试覆盖
- [ ] `comic_post_parsing_engine_test.dart` 覆盖 thread/viewthread/;tid= 三类链接
- [ ] `comic_post_parsing_engine_test.dart` 覆盖目录识别与连续簇识别
- [ ] `comic_consecutive_op_post_parser_test.dart` 覆盖连续楼主合并与停止规则

### 六、执行说明
本轮按约定未执行自动化命令，请本地执行并回传结果：
1. `flutter test`
2. `flutter analyze`

---

## 搜索收藏联动 Phase 1 回归修复 Review 清单（2026-05-03，viewthread tid 与顺序）

### 一、01~07 漏解析修复
- [ ] `LocalComicRepository._extractTid` 已支持 `forum.php?mod=viewthread&tid=xxx`
- [ ] `LocalComicRepository._extractTid` 已支持 `;tid=xxx` 残缺链接
- [ ] `mergeEpisodesFromLinks` 不再把多个 viewthread 链接回退到同一 fallbackTid

### 二、章节顺序一致性
- [ ] `order_index` 仍按 message 中解析顺序写入
- [ ] `descending=true` 时详情页展示顺序为 message 顺序倒序
- [ ] 特典位置与 message 序列一致（不再意外置顶）

### 三、测试覆盖
- [ ] `local_comic_repository_test.dart` 覆盖 viewthread tid 提取回归
- [ ] `local_comic_repository_test.dart` 覆盖倒序展示顺序回归

### 四、执行说明
本轮按约定未执行自动化命令，请本地执行并回传结果：
1. `flutter test`
2. `flutter analyze`

---

## 搜索收藏联动 Phase 1 顺序修复 Review 清单（2026-05-03，特典穿插）

### 一、顺序真值定义
- [ ] 章节顺序以 message 中链接出现顺序为唯一真值
- [ ] 去重后不再引入 groupId 排序扰动

### 二、去重与排序行为
- [ ] 同 tid 冲突时保留最早出现位置
- [ ] 最终输出严格按 `position` 升序
- [ ] 详情页倒序时可得到“message顺序倒序”

### 三、特典穿插回归
- [ ] 第一卷/第二卷/第三卷特典在章节序列中保持原始穿插位置
- [ ] 不再出现特典集中到列表最上方的异常

### 四、测试覆盖
- [ ] `comic_post_parsing_engine_test.dart` 覆盖特典穿插顺序
- [ ] `local_comic_repository_test.dart` 覆盖详情页倒序穿插顺序

### 五、执行说明
本轮按约定未执行自动化命令，请本地执行并回传结果：
1. `flutter test`
2. `flutter analyze`

---

## 搜索收藏联动 Phase 2 Review 清单（2026-05-03，递归回溯与目录解析）

### 一、架构与解耦
- [ ] `ComicEpisodeDiscoveryService` 独立于 UI/Controller，职责仅为章节发现编排
- [ ] 线程详情依赖通过 `ThreadDetailFetcher` 注入，而非硬绑定具体仓储实现
- [ ] 目录抓取依赖通过 `CatalogHtmlFetcher` 抽象，便于替换和测试

### 二、策略行为验证
- [ ] `direct`：章节数达到阈值时直接返回，不触发递归/目录
- [ ] `recursive`：仅在章节不足且 subject 命中高话数信号时启用
- [ ] `recursive`：具备防环（visited）、深度上限、连续失败熔断
- [ ] `catalog`：仅在 direct/recursive 不足时启用
- [ ] `catalog`：支持 thread 链接提取、去重与“下一页”分页遍历

### 三、接入与兼容
- [ ] `ComicEpisodeRefreshService` 对外接口未变（`fetchEpisodeLinksFromTid`）
- [ ] `comic_services_impl.dart` 已通过 provider 接入发现服务
- [ ] 详情页刷新流程无需改动调用方即可使用新策略

### 四、测试覆盖
- [ ] `comic_episode_discovery_service_test.dart` 覆盖 direct 场景
- [ ] `comic_episode_discovery_service_test.dart` 覆盖 recursive 场景
- [ ] `comic_episode_discovery_service_test.dart` 覆盖 catalog 场景

### 五、执行说明
本轮按约定未执行自动化命令，请本地验证：
1. `flutter test`
2. `flutter analyze`

---

## 搜索收藏联动 Phase 2 Review 补充（2026-05-03，目录解析工程化）

### 一、目录解析抽象
- [ ] 目录 HTML 解析已抽离为独立组件：`CatalogThreadHtmlParser`
- [ ] 解析输出包含结构化字段：`tid`、`url`、`subject`、`nextPageUrl`
- [ ] 目录解析逻辑不再和发现编排强耦合

### 二、目录结果质量
- [ ] 同一 `tid` 多锚点时优先标题锚点（`th` 内链接）
- [ ] 目录条目可稳定提取 `thread-xxx-1-1.html` 对应 tid
- [ ] 可稳定提取章节标题（subject）用于后续展示/匹配
- [ ] 目录分页可识别并继续遍历下一页

### 三、发现链路行为
- [ ] direct 成功时不触发 catalog
- [ ] recursive 不足时可进入 catalog 兜底
- [ ] “仅上一话链接”场景递归链路不再因 strict rule 丢空

### 四、测试覆盖
- [ ] `catalog_thread_html_parser_test.dart` 覆盖目录行提取与去重
- [ ] `catalog_thread_html_parser_test.dart` 覆盖 next-page 解析
- [ ] `comic_episode_discovery_service_test.dart` 覆盖 direct/recursive/catalog 三策略

### 五、执行说明
本轮按约定未执行自动化命令，请本地验证：
1. `flutter test`
2. `flutter analyze`

---

## 漫画详情章节标题规范化 Review 清单（2026-05-03）

### 一、问题修复验证
- [ ] 目录来源长 subject 不再原样显示在详情页列表标题中
- [ ] `【...】... 第1.1话` 最终展示为 `第1.1话`
- [ ] 普通短标题（如 `01`、`第3话`、`特典`）不被误改

### 二、工程化与解耦
- [ ] 标题规范化逻辑集中在仓储层 `_resolveEpisodeTitle`，UI 层不增加特判
- [ ] 规则来源复用 `ComicSubjectParser`，不重复造正则
- [ ] `LocalComicRepository` 支持注入 parser，便于后续替换与测试

### 三、回归风险检查
- [ ] `mergeEpisodesFromLinks` 插入/更新计数逻辑不受影响
- [ ] 章节顺序策略（当前按 message/输入顺序）不受本次标题规范化影响
- [ ] 阅读器打开链路不受影响（依赖 tid 与 episodeId，不依赖原始标题）

### 四、测试覆盖
- [ ] `local_comic_repository_test.dart` 新增目录长标题规范化用例
- [ ] 既有 merge/order 相关测试保持通过

### 五、执行说明
本轮按约定未执行自动化命令，请本地验证：
1. `flutter test`
2. `flutter analyze`

---

## 搜索收藏联动 Phase 3 Review 清单（2026-05-03，搜索服务与限流）

### 一、搜索服务主流程
- [ ] `DiscuzSearchService` 已实现 `formhash -> POST -> 302 -> 结果页解析` 链路
- [ ] 搜索结果可稳定提取 `tid/fid/title/url`
- [ ] 结果过滤仅保留 `fid=30`
- [ ] `formhash` 为空时返回明确异常信息

### 二、限流能力
- [ ] 已实现 10 秒 1 次触发规则
- [ ] 命中限流时返回剩余冷却时间
- [ ] 最近触发时间已持久化（重启后仍生效）
- [ ] 限流命中时搜索请求短路，不发网络请求

### 三、刷新链路联动
- [ ] 漫画刷新在 `direct/recursive/catalog` 均无结果时触发搜索后备
- [ ] 关键词来源于 `ComicSubjectParser.normalizedTitle`
- [ ] 搜索结果使用标题相似度评分并按 Top-K 验证
- [ ] 搜索后备通过注入 `ThreadSeedFetcher` 获取标题种子，不与仓储硬耦合

### 四、页面入口与交互
- [ ] `ForumHomePage` AppBar 存在搜索入口
- [ ] 点击后可进入 `ForumSearchPage`
- [ ] 搜索页能展示“冷却剩余秒数”提示
- [ ] 搜索页能展示结果列表并可进入帖子详情

### 五、测试覆盖
- [ ] `test/features/search/data/search_rate_limiter_test.dart`
- [ ] `test/features/search/data/discuz_search_service_test.dart`
- [ ] `test/features/search/presentation/forum_search_page_test.dart`
- [ ] `test/features/comic/domain/services/network_comic_episode_refresh_service_test.dart`
- [ ] 现有 `discuz_search_html_parser_test.dart` 继续通过

### 六、执行说明
本轮按协作约定未执行自动化命令，请本地验证：
1. `flutter test`
2. `flutter analyze`

## 搜索分页与场景路由改造 Review（2026-05-03）

### 变更概览
1. 搜索结果增加分页游标（`nextPageUrl`）并提供下一页加载接口。
2. 搜索上下文从 `srhfid` 扁平参数升级为 `DiscuzSearchContext`（`forum/curForum`）。
3. 页面入口场景化：论坛首页走 `forum`，`fid=30` 版块/帖子与漫画更新走 `curForum(30)`。

### 重点代码落点
1. `lib/features/search/data/models/discuz_search_models.dart`
   - 新增 `DiscuzSearchContext` / `DiscuzSearchScope`
   - `DiscuzSearchResult` 新增 `nextPageUrl`
2. `lib/features/search/data/discuz_search_html_parser.dart`
   - 新增 `.pg a.nxt` 下一页解析
3. `lib/features/search/data/discuz_search_service.dart`
   - 新增 `fetchNextPage`
   - `searchForum` 按 context 构建 URL / referer
4. `lib/features/search/presentation/forum_search_page.dart`
   - 新增“查看更多”交互
5. `lib/features/forum/presentation/forum_home_page.dart`
   - 搜索入口调整为全站
6. `lib/features/forum/presentation/forum_display_page.dart`
   - `fid=30` 增加“搜索本版”入口
7. `lib/features/thread/presentation/thread_detail_page.dart`
   - `fid=30` 增加“搜索本版”入口
8. `lib/features/comic/domain/services/comic_services_impl.dart`
   - 漫画更新搜索切到 `curForum(30)`

### 设计审查结论
1. 解耦性：通过 `DiscuzSearchContext` 把“搜索场景决策”从 UI 与业务逻辑中抽离，符合可维护目标。
2. 可扩展性：后续支持其他版块只需传 `DiscuzSearchContext.curForum(srhfid: 'xx')`。
3. 风险点：依赖 Discuz `.pg a.nxt` 结构；若站点模板变更，需要补兜底 selector。
4. 回归范围：搜索数据层、搜索页面、forum/thread 顶栏入口、漫画刷新搜索后备路径。

### 测试审查
1. 已新增/更新单测覆盖上述关键路径。
2. 本轮未执行测试命令，待本地验证。

## 目录与章节排序改造 Review（2026-05-03）

### 变更结论
1. 目录抓取链路已覆盖 `mod=tag` 的标准化（`type=thread&page=1`），符合“目录应取 thread 列表页”的要求。
2. 目录分页识别能力从“仅 next 链接”增强为“next + 总页数推断补全”，对多页目录的末页命中率更高。
3. 漫画详情页章节排序从固定顺序升级为用户可切换升降序，且排序依据明确为 `sourceTid` 数值。

### 主要代码变更
1. `catalog_thread_html_parser.dart`
- `CatalogThreadParseResult` 新增 `currentPage/totalPages`
- 解析 `.pg` 分页信息

2. `comic_episode_discovery_service.dart`
- 目录入口 URL 规范化（补 `type=thread&page=1`）
- 目录抓取循环支持总页数推断并补齐后续页

3. `comic_detail_controller.dart`
- 状态新增 `sortDescending`
- 新增 `toggleSortOrder()`
- 统一按 `sourceTid` 数值排序（含 tie-breaker）

4. `comic_detail_page.dart`
- 新增排序切换按钮与提示
- 默认 Tid 降序

### 工程性评估
1. 解耦：目录规则在 discovery 层，HTML 细节在 parser 层；UI 仅调用控制器接口。
2. 可维护：分页信息结构化后便于扩展到“跳页抓取策略”或“最大页上限策略调优”。
3. 风险：个别 tag 页面若不存在 `共 N 页` 文案，仍依赖 `nextPageUrl`，当前逻辑已有兼容。

### 测试评估
1. 新增目录分页解析单测。
2. 新增目录多页抓取单测。
3. 新增详情页排序切换单测。
4. 本轮未执行测试，待本地回归验证。

## 回复功能 Phase 1 Review（仅 API 回复，2026-05-03）

### 变更结论
1. 已完成 `sendreply API` 的最小可用回复链路。
2. 本轮严格未引入 Web 回退实现，符合“仅 API 回复”的阶段要求。
3. 回复功能以独立 `features/reply` 模块落地，Thread 页面通过抽象仓储调用，耦合可控。

### 关键落点
1. `lib/features/reply/domain/models/reply_models.dart`
2. `lib/features/reply/data/reply_repository.dart`
3. `lib/features/reply/data/discuz_reply_api_repository.dart`
4. `lib/features/thread/presentation/thread_detail_state.dart`
5. `lib/features/thread/presentation/thread_detail_controller.dart`
6. `lib/features/thread/presentation/thread_detail_page.dart`

### 设计审查
1. 解耦性
- UI/Controller 不直接依赖 Dio 与接口细节。
- API 调用细节封装在 `DiscuzReplyApiRepository`，后续接入 Web 回退不破坏上层接口。

2. 可维护性
- 回复请求模型结构化（`ReplyDraft`），后续扩展引用回复/附件参数只需增模型与仓储映射。
- 状态字段按职责拆分，避免复用 `errorMessage` 承载回复提示。

3. 风险与后续
- 当前成功判定依赖 `Message.messageval/messagestr` 关键字，仍建议后续通过真实抓包样本补强断言规则。
- 发送成功后刷新策略为“重载第一页”，逻辑正确但性能可继续优化（可改增量插入）。

### 测试审查
1. 已新增 API 层单测与页面交互测试。
2. 本轮未执行测试命令，待本地回归验证结果。

---

## 小说模块 Phase 0 Review 补充清单（2026-05-03）

### 一、基础设施与解耦
- [ ] 已新增 `features/novel` 分层骨架（data/domain/presentation）。
- [ ] `NovelRepository` 仅定义抽象，UI 不直接依赖底层存储。
- [ ] `NovelSyncLogger` 与解析模型分离，日志与业务逻辑解耦。

### 二、数据库迁移
- [ ] `ComicLocalDb` 版本已升级到 `v5`。
- [ ] 已创建 `works/work_episodes/novel_episode_content/reader_preferences`。
- [ ] 已创建小说阶段0索引：`idx_work_type_updated`、`idx_episode_work_order`、`idx_episode_tid_pid`。
- [ ] 最新版 schema 已包含小说阶段0表和索引；开发阶段旧库升级会重建数据库，不再维护 `oldVersion < 5` 增量迁移链。

### 三、主壳导航
- [ ] `MainShellPage` 已新增 `小说` Tab。
- [ ] 四栏顺序为：`论坛 / 漫画 / 小说 / 更多`。
- [ ] `NovelTabPage` 可正常渲染基础占位内容。

### 四、测试覆盖（已编写，未执行）
- [ ] `test/features/novel/data/novel_phase0_db_migration_test.dart`
- [ ] `test/features/novel/domain/services/novel_episode_discovery_service_test.dart`
- [ ] `test/features/startup/presentation/main_shell_page_test.dart`（新增小说Tab断言）

### 五、执行说明
本轮按约定未执行自动化命令，请本地执行并回传：
1. `flutter test`
2. `flutter analyze`

---

## 小说模块 Phase 1 Review 补充清单（2026-05-03）

### 一、分层与解耦
- [ ] `NovelRepository` 已作为唯一小说数据门面，页面不直接依赖 SQL。
- [ ] 线程拉取通过 `NovelThreadGateway` 抽象，仓储不硬耦合 `ThreadRepository`。
- [ ] 章节发现逻辑集中在 `NovelEpisodeDiscoveryService`，控制器仅做编排。

### 二、最小闭环能力
- [ ] 小说 Tab 可进入书架页并展示网格卡片。
- [ ] 支持手动输入 `fid + tid` 入库，并自动触发首轮章节刷新。
- [ ] 小说详情页可展示章节列表，支持刷新与排序切换。
- [ ] 阅读器可正常渲染文本段落并切换章节。

### 三、阅读体验与持久化
- [ ] 阅读器支持字号、行距、段距、主题调整。
- [ ] 阅读样式设置可持久化恢复。
- [ ] 阅读滚动进度可持久化并恢复。
- [ ] 已新增 `novel_reading_progress` 专用表，未污染章节内容表。

### 四、规则与数据质量（Phase 1）
- [ ] 章节发现仅保留楼主楼层。
- [ ] 标题优先提取“第x章/话/节”，未命中时有兜底标题。
- [ ] 章节结构包含 `pid/page/tid`，便于 Phase 2/3 继续增强。

### 五、测试覆盖（已编写，未执行）
- [ ] `test/features/novel/data/local_novel_repository_test.dart`
- [ ] `test/features/novel/domain/services/novel_episode_discovery_service_test.dart`
- [ ] `test/features/novel/presentation/novel_shelf_page_test.dart`
- [ ] `test/features/novel/presentation/novel_detail_page_test.dart`
- [ ] `test/features/novel/presentation/novel_reader_page_test.dart`
- [ ] `test/features/novel/data/novel_phase0_db_migration_test.dart`（含进度表断言）

### 六、执行说明
本轮按约定未执行自动化命令，请本地执行并回传：
1. `flutter test`
2. `flutter analyze`

---

## 小说模块 Phase 1.1 Review 补充清单（2026-05-03）

### 一、稳定性修复
- [ ] `ComicLocalDb.open` 支持测试隔离库名，避免并发锁库。
- [ ] 小说数据层测试使用独立 test db，不再争用 `comic_shelf.db`。
- [ ] `MainShellPage` 测试已覆盖小说 provider fake，避免落到真实依赖。

### 二、与漫画入口策略对齐
- [ ] `ThreadDetailPage` 在 `fid=49/55` 首楼显示“小说候选”入口。
- [ ] 小说入口交互复用 `AddToShelfButton`，视觉与漫画入口一致。
- [ ] 点击入口后执行 `upsertNovelBySeed + refreshEpisodes` 闭环。
- [ ] 入库成功后按钮状态切为“已在书架”。

### 三、状态与解耦
- [ ] 小说候选状态收敛在 `ThreadDetailState`，UI 不包含业务判定逻辑。
- [ ] `ThreadDetailController` 负责流程编排，仓储细节不泄露给页面。
- [ ] 候选判定规则函数独立（`_isNovelCandidateFid`），便于后续策略演进。

### 四、测试覆盖（已编写，未执行）
- [ ] `test/features/startup/presentation/main_shell_page_test.dart`
- [ ] `test/features/thread/presentation/thread_detail_page_test.dart`（新增小说入口场景）
- [ ] `test/features/novel/data/novel_phase0_db_migration_test.dart`
- [ ] `test/features/novel/data/local_novel_repository_test.dart`

### 五、执行说明
本轮按约定未执行自动化命令，请本地执行并回传：
1. `flutter test`
2. `flutter analyze`

---

## 书架框架抽象 Review 补充清单（2026-05-03）

### 一、抽象组件设计
- [ ] `ShelfCoverCard` 已落在 `shared/widgets/shelf`，不绑定漫画/小说模型。
- [ ] `ShelfCoverCard` 支持可插拔：封面、兜底、角标、标题策略、交互回调。
- [ ] `CandidateShelfActionRow` 已独立为通用候选入架行组件。

### 二、模块接入一致性
- [ ] 漫画书架网格卡片已使用 `ShelfCoverCard`。
- [ ] 小说书架卡片已使用 `ShelfCoverCard`。
- [ ] 帖子详情中漫画/小说候选入口均复用 `CandidateShelfActionRow`。

### 三、可维护性检查
- [ ] 共用组件位于 `shared`，业务模块仅保留差异化配置。
- [ ] 视觉骨架不再重复定义在 comic/novel 各模块内。
- [ ] long-press 等业务行为仍在模块层注入，未反向耦合 shared。

### 四、测试覆盖（已编写，未执行）
- [ ] `test/shared/widgets/shelf/shelf_cover_card_test.dart`
- [ ] `test/shared/widgets/shelf/candidate_shelf_action_row_test.dart`
- [ ] `test/features/novel/presentation/novel_shelf_page_test.dart`（共用组件断言）

### 五、执行说明
本轮按约定未执行自动化命令，请本地执行并回传：
1. `flutter test`
2. `flutter analyze`
---

## 小说入书架状态修复 + 书架分页策略共享化 Review（2026-05-03）

### 一、线程详情入架状态稳定性
- [ ] `ThreadDetailController.addNovelToShelf` 不再依赖异步后的 `state.value ?? current` 回退写法  
- [ ] `ThreadDetailController.addToShelf` 同步采用快照写回模式，避免竞态覆盖  
- [ ] 异步回写前已增加 `ref.mounted` 守卫  
- [ ] 入架成功/失败均可回写明确状态（loading 关闭 + 成功标记或错误提示）  

### 二、shared 分页策略抽象
- [ ] 已新增 `lib/shared/widgets/shelf/shelf_pager_strategy.dart`  
- [ ] `ShelfPagerStrategy.buildTabs()` 可复用分类到头部 tab 的映射逻辑  
- [ ] `ShelfPagerStrategy.resolveSelectedIndex()` 具备安全兜底策略  

### 三、漫画/小说接入一致性
- [ ] `ComicShelfPage` 分类头通过 shared 策略生成 tab  
- [ ] `NovelShelfPage` 筛选头通过 shared 策略生成 tab  
- [ ] comic tab key 保持稳定且包含分类 id（`comic-category-tab-$id`）  
- [ ] 两端仍基于 `FixedSlotPagerHeader + PageView` 统一分页交互  

### 四、测试覆盖（仅编写，未执行）
- [ ] `test/shared/widgets/shelf/shelf_pager_strategy_test.dart` 已覆盖映射与索引兜底  
- [ ] 相关页面既有测试可继续验证回归（comic/novel/thread）  

### 五、执行说明
本轮按约定未执行自动化命令，请本地验证：  
1. `flutter test`  
2. `flutter analyze`

---

## 书架框架进一步统一 Review（2026-05-03）

### 一、AppBar 共享化
- [ ] `ShelfAppBar` 已抽象到 `shared/widgets/shelf`。
- [ ] `ComicShelfPage` 已接入 `ShelfAppBar`。
- [ ] `NovelShelfPage` 已接入 `ShelfAppBar`。
- [ ] 搜索与菜单行为通过回调注入，未反向耦合业务层。

### 二、小说入口策略对齐
- [ ] 小说书架页已移除“手动添加小说”入口。
- [ ] 搜索提示引导为“去论坛帖子加入书架”。
- [ ] 小说书架数据入口仍由帖子详情 `addNovelToShelf` 驱动。

### 三、小说分类体系对齐漫画
- [ ] 数据库版本已升级，新增 `novel_categories / novel_shelf_items`。
- [ ] 小说默认分类 `default` 自动创建。
- [ ] NovelRepository 已提供分类管理接口（增删改/移动）。
- [ ] 默认分类不可重命名、不可删除。

### 四、分类分页稳定性
- [ ] 小说书架分页头使用分类 ID 驱动（非 fid 过滤态）。
- [ ] 刷新后保持当前分类（分类仍存在时）。
- [ ] 分类被删除时才回退默认分类。
- [ ] 不应再出现“切到目标分类后自动回全部”的回跳。

### 五、测试覆盖（仅编写，未执行）
- [ ] `test/shared/widgets/shelf/shelf_app_bar_test.dart`
- [ ] `test/features/novel/presentation/novel_shelf_page_test.dart`
- [ ] NovelRepository 新接口 fake 适配已覆盖 startup/thread/novel 测试文件

### 六、执行说明
本轮按约定未执行自动化命令，请本地验证：  
1. `flutter test`  
2. `flutter analyze`

---

## 书架/详情统一抽象 Phase 0 Review 清单（2026-05-04）

### 一、抽象边界与解耦
- [ ] 通用模型仅包含跨模块稳定字段，未混入模块私有渲染细节。
- [ ] 统一层通过合同接口访问能力，不直接依赖 comic/novel 页面实现。
- [ ] 适配器承担映射职责，控制器/页面后续可无感替换。

### 二、合同完整性
- [ ] `ShelfModuleAdapter` 已覆盖：分类/数据查询/搜索/分类管理/显示偏好/随机打开。
- [ ] `DetailModuleAdapter` 已覆盖：头部数据/章节加载/章节动作/下载动作/原帖与阅读器路由。
- [ ] 合同命名与返回类型可支撑 Phase 1~Phase 3 的功能扩展。

### 三、适配器骨架可维护性
- [ ] 漫画适配器完成现有仓储字段到通用模型映射。
- [ ] 小说适配器完成现有仓储字段到通用模型映射。
- [ ] 标注了 Phase 0 空实现位置（后续状态表能力接入点清晰）。

### 四、测试覆盖（本轮仅编写）
- [ ] 通用模型单测覆盖默认值与 copyWith 行为。
- [ ] 合同可实现性测试可验证接口约束稳定。
- [ ] 测试目录结构与现有项目组织一致，便于持续扩展。

### 五、执行说明
本轮按约定未执行自动化命令，请本地验证：
1. `flutter test`
2. `flutter analyze`

---

## 书架/详情统一抽象 Phase 1 Review 清单（2026-05-04）

### 一、数据库迁移正确性
- [ ] `ComicLocalDb` 版本已升级到 `8`。
- [ ] 五张统一状态表均已创建成功。
- [ ] 三个状态查询索引均已创建成功。
- [ ] 旧版本升级路径（<8）可增量执行，不破坏既有漫画/小说表结构。

### 二、仓储分层与解耦
- [ ] `LibraryStateRepository` 作为独立抽象存在，未与 UI 直接耦合。
- [ ] `LocalLibraryStateRepository` 仅依赖数据库，不反向依赖 comic/novel 页面层。
- [ ] 状态仓储职责清晰：作品状态、章节状态、标签、显示偏好。

### 三、适配器接入质量
- [ ] `ComicShelfAdapter` 已接入统一状态统计（未读/已读/已下载/标签）。
- [ ] `NovelShelfAdapter` 已接入统一状态统计（未读/已读/已下载/标签）。
- [ ] `ComicDetailAdapter` 章节状态写入路径可用。
- [ ] `NovelDetailAdapter` 章节状态写入路径可用。

### 四、可维护性检查
- [ ] 关键逻辑处有注释说明“Phase 0/1 临时实现与后续扩展点”。
- [ ] 空实现仅保留在后续阶段能力范围内，避免误导。
- [ ] 通用状态与业务仓储边界明确，可支持后续 Phase 2 控制器统一。

### 五、测试覆盖（本轮仅编写）
- [ ] 迁移测试覆盖新增表和索引创建。
- [ ] 状态仓储测试覆盖：
  - 作品状态 upsert/query
  - 章节状态 upsert/count
  - 显示设置持久化
  - 标签绑定与解绑

### 六、执行说明
本轮按约定未执行自动化命令，请本地验证：
1. `flutter test`
2. `flutter analyze`

---

## 书架/详情统一抽象 Phase 2 Review 清单（2026-05-04）

### 一、控制器边界与解耦
- [ ] `UnifiedShelfController` 仅依赖 `ShelfModuleAdapter`，不直接依赖 comic/novel 仓储实现。
- [ ] 状态模型集中在 shared 层，便于后续 UI 统一接入。
- [ ] 控制器未引入具体 Widget 逻辑，保持可测试性。

### 二、状态机能力完整性
- [ ] 初始化、刷新、搜索模式切换流程可闭环。
- [ ] 关键词变化会触发 query 并更新分类匹配计数。
- [ ] 筛选、排序、显示模式更新流程均由控制器统一编排。
- [ ] 显示偏好写入通过 adapter 下沉，不反向耦合存储实现。

### 三、默认分类规则
- [ ] default 空且其他分类有内容时隐藏 default。
- [ ] default 有内容时保持展示。
- [ ] 缺失 default 但存在未分类数据时，自动补 default 到最左侧。

### 四、容错与一致性
- [ ] reload 失败后 `isLoading` 可正确恢复。
- [ ] 错误信息通过 `errorMessage` 暴露，不打断后续恢复流程。
- [ ] 分类选中在重载后有稳定兜底（命中优先，否则回落首分类）。

### 五、测试覆盖（本轮仅编写）
- [ ] 控制器单测覆盖初始化与基础加载。
- [ ] 控制器单测覆盖 default 分类显隐规则。
- [ ] 控制器单测覆盖搜索与匹配计数。
- [ ] 控制器单测覆盖显示设置写入调用。

### 六、执行说明
本轮按约定未执行自动化命令，请本地验证：
1. `flutter test`
2. `flutter analyze`

---

## 书架/详情统一抽象 Phase 3 Review 清单（2026-05-04）
### 一、统一书架页面能力
- [ ] `UnifiedShelfPage` 已提供搜索模式切换（普通态/搜索态）。
- [ ] 搜索态下显示返回箭头 + 搜索输入框（提示词：`搜索···`）。
- [ ] 分类头使用 `FixedSlotPagerHeader + PageView`，支持横向切换。
- [ ] 页面支持 `RefreshIndicator` 下拉刷新。
- [ ] 空状态/错误提示渲染正确。

### 二、筛选/排序/显示面板
- [ ] `filter_list` 可打开底部弹窗。
- [ ] 弹窗包含三个横向分栏：`筛选`、`排序`、`显示`。
- [ ] 筛选分栏支持三态切换（不筛选/包含/排除）。
- [ ] 排序分栏支持字段切换与升降方向切换。
- [ ] 显示分栏支持网格/列表切换，网格支持每行个数（1~3）。

### 三、更多菜单动作
- [ ] `more_vert` 菜单包含：新建分类、重命名当前分类、删除当前分类、更新书架、随机打开作品。
- [ ] 默认分类不允许重命名与删除。
- [ ] 删除普通分类时有二次确认弹窗。

### 四、漫画/小说接入解耦
- [ ] `ComicShelfPage` 仅作为统一页薄壳，负责 adapter 注入和详情跳转。
- [ ] `NovelShelfPage` 仅作为统一页薄壳，负责 adapter 注入和详情跳转。
- [ ] 共享交互逻辑全部沉淀到 `library_shared`，避免 comic/novel 重复实现。

### 五、测试覆盖（本轮编写）
- [ ] `test/features/library_shared/presentation/pages/unified_shelf_page_test.dart`
- [ ] `test/features/comic/presentation/comic_shelf_page_test.dart`
- [ ] `test/features/novel/presentation/novel_shelf_page_test.dart`

### 六、执行声明
本轮按约定未执行自动化命令，请本地验证：
1. `flutter test`
2. `flutter analyze`

---

## 书架/详情统一抽象 Phase 4 Review 清单（2026-05-04）
### 一、统一详情页骨架
- [ ] 页面已使用 `SliverAppBar` 实现透明扩展态与实体固定态过渡。
- [ ] 头图存在时有模糊背景与向下渐隐过渡。
- [ ] 标题在折叠态可显示且超长省略。
- [ ] 无封面时有稳定兜底样式。

### 二、信息区与通用操作
- [ ] 头部信息区包含封面、标题、作者/汉化组。
- [ ] 操作区包含：在书架/更新/原帖。
- [ ] 简介区域支持展开/收起。
- [ ] 标签区域保留后续扩展接口（阶段4可占位）。

### 三、章节列表基础能力
- [ ] 章节列表展示名称与辅助信息（发布时间 + tid）。
- [ ] 章节右侧展示下载状态图标占位。
- [ ] 点击章节可进入阅读器（通过 adapter 路由目标）。
- [ ] FAB（继续）可进入阅读器继续逻辑。

### 四、菜单与解耦
- [ ] AppBar 右侧包含下载菜单、筛选入口、更多菜单。
- [ ] 下载菜单包含“未读/全部”。
- [ ] 刷新动作可触发统一控制器刷新流程。
- [ ] 页面不直接依赖 comic/novel 仓储，依赖 `DetailModuleAdapter`。

### 五、漫画/小说接入方式
- [ ] `ComicDetailPage` 已变为统一详情页薄壳接入。
- [ ] `NovelDetailPage` 已变为统一详情页薄壳接入。
- [ ] reader/thread 跳转差异仅保留在模块薄壳，未污染共享页。

### 六、测试覆盖（本轮编写）
- [ ] `test/features/library_shared/presentation/controllers/unified_detail_controller_test.dart`
- [ ] `test/features/library_shared/presentation/pages/unified_detail_page_test.dart`
- [ ] `test/features/comic/presentation/comic_detail_page_test.dart`
- [ ] `test/features/novel/presentation/novel_detail_page_test.dart`

### 七、执行声明
本轮按约定未执行自动化命令，请本地验证：
1. `flutter test`
2. `flutter analyze`

## Phase 4 修复补丁 Review 记录（2026-05-04）
### 目标
- 修复 Unified Detail/Shelf/Main Shell 在测试中的不稳定断言与异步上下文问题。

### 检查项
- [x] UnifiedDetailPage 异步后不再直接使用易失的 build context。
- [x] Unified Shelf 网格/列表模式提供稳定 key 以支持可维护测试。
- [x] 详情页章节断言改为滚动后断言，避免 Sliver 首屏可见性差异导致误报。
- [x] MainShell 小说 Tab 断言替换为结构锚点，降低图标耦合风险。

### 风险评估
1. 当前修复不改变业务语义，仅增强上下文安全与测试稳定性，低风险。
2. 由于未执行自动化命令，仍需本地完整回归确认。

### 待回归
1. `flutter test`
2. `flutter analyze`

## Phase 4 详情页视觉修复 Review 记录（2026-05-04）
### Review 范围
- `lib/features/library_shared/presentation/pages/unified_detail_page.dart`
- `test/features/library_shared/presentation/pages/unified_detail_page_test.dart`

### 结论
1. 顶部视觉层已统一，背景模糊图与封面/元信息在同一 Hero 区中渲染，满足“从封面底部往上是同一背景模糊图”的体验要求。
2. AppBar 标题显隐已改为滚动阈值驱动，展开态不显示，折叠后显示，符合交互预期。
3. 元信息布局已包含 `person_outlined + 作者` 行，并保留 `group_outlined + 汉化组` 行，信息层次清晰。
4. 代码拆分为多个私有组件，页面与业务适配器边界保持清晰，可维护性良好。

### 测试覆盖检查（已编写，未执行）
- [x] 作者行与 person 图标存在
- [x] 折叠标题初始隐藏
- [x] 滚动后折叠标题显示

### 待你本地回归
1. `flutter test`
2. `flutter analyze`

## Phase 5 Review 记录（章节列表交互与下载/书签状态，2026-05-04）
### Review 范围
- `lib/features/library_shared/presentation/controllers/unified_detail_controller.dart`
- `lib/features/library_shared/presentation/pages/unified_detail_page.dart`
- `lib/features/comic/presentation/adapters/comic_detail_adapter.dart`
- `lib/features/novel/presentation/adapters/novel_detail_adapter.dart`
- `test/features/library_shared/presentation/controllers/unified_detail_controller_test.dart`
- `test/features/library_shared/presentation/pages/unified_detail_page_test.dart`

### 核对结论
1. 章节筛选/排序：已接入统一详情页 `filter_list` 面板并写回控制器。
2. 章节长按动作：已提供加书签/取消全部已读/删除下载三项操作并回写状态。
3. 状态一致性：漫画与小说 adapter 均已接入 `LibraryStateRepository`，章节状态可在统一模型中回填。
4. 控制器职责：仍保持“编排层”定位，具体数据读写在 adapter，边界清晰。

### 风险与后续
1. 当前下载动作主要写统一状态标记，未与真实媒体缓存下载任务深度联动（属于后续增强点）。
2. 章节筛选排序由 adapter 实现，后续若字段增长建议抽成共享策略以减少重复。

### 待你本地回归（本轮未执行）
1. `flutter test`
2. `flutter analyze`

---

## 书架/详情统一抽象 Phase 6 Review 记录（2026-05-04）
### Review 范围
- `lib/features/library_shared/domain/contracts/detail_module_adapter.dart`
- `lib/features/library_shared/presentation/pages/unified_detail_page.dart`
- `lib/features/comic/presentation/adapters/comic_detail_adapter.dart`
- `lib/features/novel/presentation/adapters/novel_detail_adapter.dart`
- `test/features/library_shared/domain/contracts/detail_module_adapter_contract_test.dart`
- `test/features/library_shared/presentation/controllers/unified_detail_controller_test.dart`
- `test/features/library_shared/presentation/pages/unified_detail_page_test.dart`

### 核对结论
1. 合同层：`DetailModuleAdapter` 已覆盖 Phase 6 需要的分类与标签动作，且保持 shared 层解耦。
2. 详情页菜单：`more_vert` 已扩展到“修改分类/编辑简介/添加标签/移除标签”，动作均经 adapter 下沉。
3. 模块差异：
- 漫画：封面为空时可回退“首话首图”策略。
- 小说：无封面时有独立兜底视觉（`小说无封面`）。
4. 线程联动：原帖跳转链路继续通过 `getThreadRouteTarget` + 外部注入 `onOpenThread`，保持统一接入。
5. 测试可维护性：合同扩展后的 fake adapter 已同步补齐，避免接口升级造成测试编译断裂。

### 风险与后续
1. 当前“修改分类”基于 adapter 查找当前分类后迁移，后续可在 detail header 中补充当前分类字段以减少遍历成本。
2. 标签操作完成后未在页面显式展示标签区域（阶段4占位逻辑仍在），后续可在详情页增加标签可视列表与即时刷新反馈。

### 执行说明
本轮按约定未执行：
1. `flutter test`
2. `flutter analyze`

---

## 漫画阅读器优化 Phase 10 Review 记录（2026-05-13）
### Review 范围
- `lib/features/comic/domain/services/comic_reader_feature_flags.dart`
- `lib/features/comic/data/comic_providers.dart`
- `lib/features/comic/domain/services/comic_services_impl.dart`
- `lib/features/comic/presentation/controllers/comic_reader_controller.dart`
- `lib/features/comic/presentation/controllers/comic_detail_controller.dart`
- `lib/features/comic/presentation/adapters/comic_detail_adapter.dart`
- `lib/features/comic/presentation/adapters/comic_shelf_adapter.dart`
- `lib/features/comic/presentation/comic_detail_page.dart`
- `lib/features/comic/presentation/comic_shelf_page.dart`
- Phase 10 新增/更新的测试文件

### 架构检查
- [x] 灰度开关以独立值对象实现，不把 Riverpod、SharedPreferences 或 UI 细节写入 domain。
- [x] Reader controller 只读取开关并保持原有职责：状态、进度、预加载编排。
- [x] 自定义元数据开关同时覆盖详情页、书架、刷新请求，不出现展示与更新策略不一致。
- [x] 自定义元数据关闭时书架绕开合成字段 snapshot，避免 source/custom 字段被仓储快照提前合并后无法回退。
- [x] 刷新服务仍依赖 `ComicEpisodeDiscoveryService`、`ForumSearchService`、`ComicSubjectParser` 抽象，未耦合仓储或页面。

### 行为检查
- [x] 严格已读：最后页需要进入视口并完成解码，失败页不会自动已读。
- [x] 单页章节：首图显示成功后可完成已读。
- [x] 未读聚合：无状态章节计未读，新增章节默认进入未读角标。
- [x] 合并更新：同 tid 更新标题不重复插入且不清阅读状态。
- [x] 搜索兜底：低分候选被过滤，当前 tid 不作为搜索候选重复合并。
- [x] 多关键词刷新：默认关闭，开启后按优先级尝试后续关键词；当前关键词只有当前 tid/空候选时继续降级尝试。
- [x] 预加载队列：支持去重、retry 优先、dispose 后取消。

### 测试覆盖（仅编写，未执行）
- [ ] `comic_reader_feature_flags_test.dart` 覆盖默认开关和 copyWith。
- [ ] `comic_reader_controller_test.dart` 覆盖严格已读降级、预加载队列禁用、下一章预加载禁用。
- [ ] `comic_reader_preload_queue_test.dart` 覆盖 dispose 取消 pending/running 任务。
- [ ] `network_comic_episode_refresh_service_test.dart` 覆盖低分过滤、多关键词开关、单关键词不重试、当前 tid 排除。
- [ ] `local_comic_repository_test.dart` 覆盖同 tid 标题更新不丢状态。
- [ ] `comic_detail_adapter_test.dart` 与 `comic_shelf_adapter_test.dart` 覆盖自定义元数据开关回退。
- [ ] `comic_detail_page_test.dart` 覆盖读完后详情章节变淡。
- [ ] `unified_shelf_page_test.dart` 覆盖未读角标。
- [ ] `reader_bottom_panel_test.dart` 与 `reader_top_bar_test.dart` 覆盖窄屏与长标题。

### 风险与后续
1. `readerRefreshMultiKeywordEnabled` 默认关闭，避免宽关键词误合并；打开前应观察刷新日志中的 `refreshKeywordMode`、keyword source 与候选 top 分数。
2. 自定义元数据开关当前为运行时注入值，后续若接入设置页，需要补持久化与 UI 文案测试。
3. Phase 10 的完整结论依赖你本地执行 `flutter test` / `flutter analyze` 后的结果。

### 执行声明
本轮按约定未执行：
1. `flutter test`
2. `flutter analyze`
3. `dart format`

---

## 漫画电梯目录解析修复 Review 记录（2026-05-13）
### Review 范围
- `lib/features/comic/domain/services/comic_post_parsing_engine.dart`
- `test/features/comic/domain/services/comic_post_parsing_engine_test.dart`
- `test/features/comic/domain/services/comic_episode_discovery_service_test.dart`
- `test/features/thread/domain/services/forum_post_dom_extractor_test.dart`

### 一、目录入口规则
- [ ] `目录/目錄` 仍可识别为 catalog。
- [ ] `电梯/電梯` 可识别为 catalog。
- [ ] `catalog/contents` 可识别为 catalog。
- [ ] `misc.php?mod=tag&id=...` 即使文案不标准，也会作为 Yamibo tag catalog 候选。
- [ ] 普通外链不会因为本次扩展被误识别为章节链接。

### 二、刷新链路
- [ ] `tid=476059` 风格的首楼 `電梯` 链接会进入 `ComicEpisodeDiscoveryService` 的 catalog 策略。
- [ ] catalog URL 会标准化为 `type=thread&page=1` 后再抓取。
- [ ] 搜索 fallback 命中的同系列候选帖若使用 `電梯`，也能产出章节列表。

### 三、图片提取确认
- [ ] `<div class="img"><img src="...data/attachment..." attach="..."></div>` 可被提取为漫画图片。
- [ ] 表情、头像等 forum chrome 图片过滤规则不受影响。

### 四、测试覆盖（仅编写，未执行）
- [ ] `comic_post_parsing_engine_test.dart` 覆盖电梯目录入口。
- [ ] `comic_episode_discovery_service_test.dart` 覆盖电梯入口走 catalog 策略。
- [ ] `forum_post_dom_extractor_test.dart` 覆盖 Yamibo 附件图片结构。

### 执行声明
本轮按约定未执行：
1. `flutter test`
2. `flutter analyze`
3. `dart format`

---

## 漫画搜索兜底章节化 Review 记录（2026-05-13）
### Review 范围
- `lib/features/comic/domain/services/comic_services_impl.dart`
- `lib/features/comic/domain/services/comic_subject_parser.dart`
- `test/features/comic/domain/services/network_comic_episode_refresh_service_test.dart`
- `test/features/comic/domain/services/comic_subject_parser_test.dart`

### 一、搜索兜底行为
- [ ] 搜索 fallback 命中同系列帖子后，不再只把候选当作二次解析入口。
- [ ] 候选详情解析为空时，搜索结果本身会转换为 `ComicEpisodeLink`。
- [ ] 候选详情解析只产出部分章节时，会与搜索候选按 tid 去重合并。
- [ ] 目录/递归解析结果仍优先于搜索候选，避免降低高置信目录结果质量。

### 二、章节排序与标题
- [ ] 搜索候选可按 `第81话 -> 第82话上 -> 第82话下` 排序。
- [ ] 支持繁体 `話` 与 `上/中/下/前/后/後` 后缀。
- [ ] `RuleBasedComicSubjectParser` 保留 `第82話下` 作为完整 episode label。
- [ ] 重复 tid 时保留搜索候选侧较完整标题。

### 三、测试覆盖（仅编写，未执行）
- [ ] `network_comic_episode_refresh_service_test.dart` 覆盖搜索结果章节化兜底。
- [ ] `comic_subject_parser_test.dart` 覆盖上下篇后缀不丢失。

### 执行声明
本轮按约定未执行：
1. `flutter test`
2. `flutter analyze`
3. `dart format`

---

## 漫画阅读器 Phase 9 Review 清单（2026-05-13）
### 一、图片尺寸与布局稳定
- [ ] `LibraryCachedImage` 的 `onImageResolved/onImageFailed` 为可选回调，不影响书架封面等既有调用方。
- [ ] 成功解码后上报真实图片宽高，回调在 post-frame 执行，不在 build 同步更新父级状态。
- [ ] 本地图片和远程图片都能触发尺寸上报；解码失败能触发失败回调。
- [ ] `_ReaderImageSlot` 在存在 `width/height` 时按真实比例预留高度，未知尺寸时继续使用 `width * 4 / 3` fallback。
- [ ] 长图使用 `fitWidth` 自然撑开，不强制固定高度裁切。

### 二、数据库与仓储边界
- [ ] `ComicLocalDb.dbVersion` 已升级到 `15`。
- [ ] `episode_images` 最新 schema 包含 `width`、`height`。
- [ ] `ComicEpisodeImageItem` 和 `EpisodeImageRecord` 均透出宽高字段。
- [ ] `ComicEpisodeImageCacheMetadataWriter` 继续作为窄接口使用，reader 不依赖本地仓储具体类型。
- [ ] 本地仓储仅写入大于 0 的宽高，避免无效尺寸污染 metadata。

### 三、失败恢复与已读完成
- [ ] 图片显示失败会写入 `episode_images.cache_status = failed`。
- [ ] 失败图片会清理当前 state 的本地路径，避免继续展示坏缓存。
- [ ] 最后一页必须本次会话解码成功后才允许自动完成章节。
- [ ] 持久化宽高只参与布局，不参与本次成功显示判定。
- [ ] 普通预加载窗口不会静默覆盖显示失败页；只有 retry 任务可恢复失败状态。
- [ ] 失败页重新解码成功后会清除 failed 状态并允许完成章节。

### 四、可观测性与内存边界
- [ ] `page_visible` 日志包含进度落库耗时。
- [ ] 首图可见、图片显示失败、缓存命中/未命中、预加载成功/失败、跳页窗口取消均有 reader event。
- [ ] 预加载队列仍只负责磁盘缓存调度，不主动扩大整章图片解码。
- [ ] 快速跳页会取消旧窗口任务并记录取消日志。

### 五、测试覆盖（仅编写，未执行）
- [ ] `library_cached_image_test.dart` 覆盖本地图片尺寸上报。
- [ ] `image_cache_phase4_db_migration_test.dart` 覆盖 `episode_images.width/height`。
- [ ] `local_comic_repository_test.dart` 覆盖宽高 metadata 持久化。
- [ ] `comic_reader_controller_test.dart` 覆盖解码成功前不完成、持久化宽高不完成、失败阻止完成、恢复成功后完成。
- [ ] `comic_reader_page_test.dart` 覆盖垂直 slot 按图片真实比例预留高度。

### 六、待你本地回归
1. `flutter test`
2. `flutter analyze`

说明：本轮按要求未执行 `flutter test`、`flutter analyze`、`dart format`。

---

## 漫画阅读器 Phase 7 自定义作品信息 Review 记录（2026-05-12）
### Review 范围
- `lib/features/comic/data/comic_repository.dart`
- `lib/features/comic/data/local/comic_local_db.dart`
- `lib/features/comic/data/local/comic_local_models.dart`
- `lib/features/comic/data/local_comic_repository.dart`
- `lib/features/comic/domain/models/comic_detail_models.dart`
- `lib/features/comic/domain/models/comic_shelf_models.dart`
- `lib/features/comic/domain/services/comic_services_impl.dart`
- `lib/features/comic/presentation/adapters/comic_detail_adapter.dart`
- `lib/features/comic/presentation/adapters/comic_shelf_adapter.dart`
- `lib/features/comic/presentation/controllers/comic_detail_controller.dart`
- `lib/features/comic/presentation/controllers/comic_reader_controller.dart`
- `lib/features/library_shared/domain/contracts/detail_module_adapter.dart`
- `lib/features/library_shared/domain/models/library_models.dart`
- `lib/features/library_shared/presentation/pages/unified_detail_page.dart`

### 核对结论
1. 数据分层
- [ ] `comics` 表包含 `source_title/custom_title/custom_search_title`。
- [ ] `comics` 表包含 `source_author/custom_author`。
- [ ] `comics` 表包含 `source_translation_group/custom_translation_group`。
- [ ] `title/author/translation_group` 是展示值，按自定义优先合成。
- [ ] 来源刷新不会覆盖用户自定义字段。

2. 自定义封面
- [ ] 阅读器“将当前页设为封面”先复制到受保护封面缓存。
- [ ] `custom_cover_local_path` 指向受保护本地文件，不直接指向普通页面缓存。
- [ ] 写入来源章节、页码和图片 URL 追踪字段。
- [ ] 清理普通页面缓存不影响 `custom_cover_local_path`。
- [ ] 首话首图纠正不会覆盖已有自定义封面。

3. 详情编辑
- [ ] 只有实现 `DetailMetadataEditor` 的模块显示“编辑作品信息”。
- [ ] Sheet 包含标题、作者、汉化组、更新搜索关键词。
- [ ] 空白自定义字段保存后恢复来源值。
- [ ] Sheet 显示来源值辅助文本。
- [ ] 保存后只 reload 本地详情，不触发网络刷新。

4. 书架/详情展示
- [ ] 详情页展示自定义标题。
- [ ] 详情页展示自定义作者和汉化组。
- [ ] 书架展示自定义标题。
- [ ] 书架副标题展示“作者 / 汉化组”，字段缺失时回退单项。

5. 刷新关键词
- [ ] 刷新请求携带 `comicId/sourceTid/displayTitle/sourceTitle/customTitle/customSearchTitle`。
- [ ] 搜索关键词优先级：自定义搜索关键词 -> 自定义标题 -> 展示标题 -> 来源标题 -> 当前帖解析标题。
- [ ] Debug/Profile 日志输出关键词来源、候选数量和合并数量。
- [ ] 旧 `fetchEpisodeLinksFromTid` 仍保留兼容路径。

### 测试覆盖（仅编写，未执行）
- [ ] `local_comic_repository_test.dart` 覆盖自定义元数据写入、清空、来源刷新不覆盖自定义字段。
- [ ] `network_comic_episode_refresh_service_test.dart` 覆盖自定义搜索关键词优先级。
- [ ] `unified_detail_page_test.dart` 覆盖编辑作品信息 sheet 保存。
- [ ] `image_cache_phase4_db_migration_test.dart` 覆盖 Phase 7 schema 字段。
- [ ] 旧 fake repository 已补齐新增仓储/刷新接口。

### 风险与后续
1. `unified_detail_page.dart` 继续增长，后续建议拆出作品信息编辑 sheet 与 more action coordinator。
2. 本轮保留 `title/author/translation_group` 作为展示值以降低改造面；若后续做严格领域建模，可再把 display 字段改为查询时计算。
3. 刷新候选评分仍沿用现有阈值，Phase 8 可继续做多关键词评分与误匹配保护。

### 执行声明
本轮按约定未执行：
1. `flutter test`
2. `flutter analyze`
3. `dart format`

---

## 分阶段优化漫画阅读器 Phase 2 Review 清单（2026-05-12）

### 一、未读聚合语义
- [ ] `LocalComicRepository.queryShelfSnapshot()` 以 `episodes` 为主表统计章节总数。
- [ ] `library_episode_state` 仅作为状态覆盖，左联条件包含 `content_type = 'comic'` 与 `episode_id`。
- [ ] 无状态章节通过 `COALESCE(is_read, 0)` 视为未读。
- [ ] `total_count/read_count/unread_count/downloaded_count` 来自同一套 `chapter_stats` 聚合。
- [ ] 手动标记已读后，书架未读数减少。
- [ ] 手动取消已读后，书架未读数增加。

### 二、Fallback 与架构边界
- [ ] `ComicShelfWorkStats` / `ComicShelfStatsRepository` 作为窄接口存在，未把统计方法塞进 `ComicRepository` 主合同。
- [ ] `ComicShelfAdapter.loadCategoryItems()` 在仓储支持时使用 `ComicShelfStatsRepository`。
- [ ] 仓储不支持窄接口时仍保留旧 `LibraryStateRepository.count*` fallback。
- [ ] shared 层不直接依赖漫画 SQL 或漫画仓储实现。

### 三、继续阅读与刷新闭环
- [ ] `ComicDetailAdapter.getReaderRouteTarget(preferContinue: true)` 优先使用 `reading_progress.episode_id`。
- [ ] 无阅读进度时回退 `library_work_state.last_read_episode_id`。
- [ ] 无历史进度时打开第一章未读章节；无状态章节视为未读。
- [ ] 右下角“继续”打开 reader 返回后详情页执行本地 reload。
- [ ] 书架打开详情返回后执行 refresh，让未读角标读取最新 snapshot。

### 四、测试覆盖（仅编写，未执行）
- [ ] `local_comic_repository_test.dart` 覆盖无状态章节默认未读。
- [ ] `local_comic_repository_test.dart` 覆盖未读筛选包含无状态章节。
- [ ] `comic_detail_adapter_test.dart` 覆盖继续阅读优先级：reading progress -> work state -> first unread。
- [ ] `comic_shelf_adapter_test.dart` 覆盖非 snapshot fallback 使用仓储统计。

### 五、待你本地回归
1. `flutter test`
2. `flutter analyze`

说明：本轮按要求未执行 `flutter test`、`flutter analyze`、`dart format`。

---

## 漫画阅读器 Phase 0/1 Review 记录（2026-05-12）
### Review 范围
- `lib/features/comic/domain/services/comic_reader_events.dart`
- `lib/features/comic/domain/services/comic_reading_state_writer.dart`
- `lib/features/comic/domain/models/comic_reader_exit_result.dart`
- `lib/features/comic/data/comic_providers.dart`
- `lib/features/comic/presentation/controllers/comic_reader_controller.dart`
- `lib/features/comic/presentation/comic_reader_page.dart`
- `lib/features/library_shared/presentation/pages/unified_detail_page.dart`
- `test/features/comic/presentation/controllers/comic_reader_controller_test.dart`
- `test/features/comic/presentation/comic_reader_page_test.dart`
- `test/features/library_shared/presentation/pages/unified_detail_page_test.dart`

### 核对清单
- [ ] 详情页章节 `onTap` 不再调用 `markChapterRead(isRead: true)`。
- [ ] 手动标记已读/未读入口仍保留在章节操作中。
- [ ] 阅读进度保存统一通过 `ComicReadingStateWriter.saveProgress()`。
- [ ] 最后一页完成统一通过 `ComicReadingStateWriter.markEpisodeCompleted()`。
- [ ] `markEpisodeCompleted()` 同时写阅读进度、章节已读状态和作品最近阅读状态。
- [ ] 单页章节不会在 `_loadState` 阶段直接标记已读。
- [ ] 最后一页必须进入视口后才自动已读。
- [ ] 失败页不会触发自动已读。
- [ ] 自动已读具备防重复写入保护。
- [ ] reader 退出时会 flush 最新进度。
- [ ] reader 返回后详情页会 reload 本地章节状态。
- [ ] Phase 0 日志覆盖 open、page visible、chapter completed、exit。
- [ ] 手动取消已读时 `read_at` 会被清空。

### 测试检查（仅编写，未执行）
- [ ] controller 测试覆盖“倒数第二页不已读，最后一页已读”。
- [ ] controller 测试覆盖“单页章节可见后已读”。
- [ ] 页面测试覆盖 reader provider 依赖隔离。
- [ ] 统一详情页测试覆盖“点击章节不提前已读”。
- [ ] 状态仓储测试覆盖“取消已读清空 readAt”。

### 待你本地回归
1. `flutter test test/features/comic/presentation/controllers/comic_reader_controller_test.dart`
2. `flutter test test/features/comic/presentation/comic_reader_page_test.dart`
3. `flutter test test/features/library_shared/presentation/pages/unified_detail_page_test.dart`
4. `flutter test test/features/library_shared/data/local_library_state_repository_test.dart`
5. `flutter test`
6. `flutter analyze`

说明：按本轮要求，我未执行测试、分析或 `dart format`。

---

## Shelf 性能优化 Milestone D Review 记录（2026-05-10）
### Review 范围
- `lib/features/library_shared/domain/services/shelf_feature_flags.dart`
- `lib/features/library_shared/domain/services/library_shelf_snapshot_diff.dart`
- `lib/features/library_shared/domain/services/shelf_cover_resolver.dart`
- `lib/features/library_shared/presentation/controllers/unified_shelf_controller.dart`
- `lib/features/cache/domain/protected_cover_cache_maintenance.dart`
- `lib/features/cache/data/protected_cover_file_store.dart`
- `lib/features/cache/data/image_cache_repository.dart`
- `lib/features/cache/data/image_cache_providers.dart`
- Milestone D 新增/更新的测试文件

### 核对结论
1. 状态增量与 SWR
- Controller 新增 `stateListenable`，保留现有 `state` 读取方式，降低页面迁移风险。
- `UnifiedShelfPage` 分类内容区域已接入 `ValueListenableBuilder`，封面 warmup patch 不再触发整页 `setState()`。
- 封面 warmup 结果只 patch 相关 `workId` 的 local path，不重新查询 metadata。
- 默认 stale-while-revalidate 保持旧列表可见；关闭 flag 后可回退阻塞 loading。

2. 灰度开关
- `ShelfFeatureFlags` 覆盖 snapshot、cover queue、cover image、SWR 四条优化路径。
- Snapshot、cover queue、cover image 和 SWR 已接入页面/controller，可逐项回滚。
- `useShelfCoverImage=false` 时，书架 grid/list 封面回退 `LibraryCachedImage`；`ShelfCoverCard` 通过 builder 注入避免 shared 层反向依赖 cache feature。

3. 缓存一致性
- `ShelfCoverResolver.resolveFast()` 明确了 custom local > normal local > cache metadata > stale/remote 的读取顺序。
- `ImageCacheRepository.listProtectedCovers()` 只列出 protected cover/custom cover，不混入阅读页普通图片。
- `ProtectedCoverCacheMaintenance` 通过 metadata/file 两个小 store 合同清理 orphan/stale protected cover，避免 domain 依赖 SQLite 和 `dart:io` 细节。
- `protectedCoverCacheMaintenanceProvider` 已提供统一装配入口，后续 UI 或后台任务只需提供 owner 判定逻辑。

4. 可观测性
- `LibraryShelfSnapshotDiffer` 为 reload 输出新增、删除、变更和顺序变化计数。
- `UnifiedShelfController._reload()` 将 diff 计数写入 `ShelfPerfTrace`，后续可作为性能 dashboard 的基础。

### 风险与后续
1. `stateListenable` 当前已覆盖分类内容区域；AppBar、筛选弹层和全局 loading 仍沿用页面 `setState`，后续可继续细分。
2. `ShelfCoverResolver` 当前只做 fast resolve，不直接接管 adapter warmup；后续可把 resolver 输出接到 tile 级状态 store。
3. Protected cover orphan 清理由调用方传入 `ownerExists`，后续可分别为漫画/小说仓库提供批量 owner 判定。
4. `useShelfCoverImage` 当前通过构造参数接入，后续如需运行时开关可接设置页或实验配置。

### 测试覆盖（仅编写，未执行）
- [ ] `shelf_feature_flags_test.dart` 覆盖灰度开关。
- [ ] `library_shelf_snapshot_diff_test.dart` 覆盖 snapshot diff。
- [ ] `shelf_cover_resolver_test.dart` 覆盖 fast resolver 优先级与 stale 状态。
- [ ] `protected_cover_cache_maintenance_test.dart` 覆盖 protected cover 清理。
- [ ] `unified_shelf_controller_test.dart` 覆盖 flags、SWR、stateListenable 增量 patch。
- [ ] `unified_shelf_page_test.dart` 覆盖 cover image flag 回退路径。
- [ ] `image_cache_repository_test.dart` 覆盖 protected cover 查询。

### 待你本地回归
1. `flutter test`
2. `flutter analyze`

说明：本轮按你的要求未执行 `flutter test`、`flutter analyze`、`dart format`。

---

## Shelf 性能优化 Milestone C Review 记录（2026-05-10）
### Review 范围
- `lib/features/library_shared/domain/services/shelf_cover_warmup_service.dart`
- `lib/features/library_shared/presentation/controllers/unified_shelf_controller.dart`
- `lib/features/library_shared/presentation/pages/unified_shelf_page.dart`
- `lib/shared/widgets/shelf/shelf_cover_image.dart`
- `lib/shared/widgets/shelf/shelf_cover_card.dart`
- `test/features/library_shared/domain/services/shelf_cover_warmup_service_test.dart`
- `test/features/library_shared/presentation/controllers/unified_shelf_controller_test.dart`
- `test/features/library_shared/presentation/pages/unified_shelf_page_test.dart`
- `test/shared/widgets/shelf/shelf_cover_image_test.dart`

### 核对结论
1. 封面队列边界
- Shared 层现在负责优先级、取消 token、去重和失败冷却。
- 漫画/小说/收藏 adapter 仍只负责构造 request 与模块写回，未把模块细节扩散到页面层。

2. 视口优先级
- 页面只上报分类可见 index 范围。
- Controller 根据当前分类、可见范围、显示模式和相邻分类计算 warmup 优先级。
- 新 tab 选中后会重新发起 warmup，新分类首屏能优先补图。

3. 分类页稳定性
- 分类页拆出 `_ShelfCategoryPage`，使用 `AutomaticKeepAliveClientMixin`。
- 每个分类页、grid/list 和 item 都有稳定 key，便于保留滚动位置并减少无意义重建。
- 页面刷新时旧内容不会因为 background warmup 结果而整页重建。

4. 图片组件现代化范围
- 新增 `ShelfCoverImage` 仅用于 shelf 场景。
- Shelf 封面不再在 build 中执行同步文件存在检查。
- Shelf 封面不直接 fallback 到 `NetworkImage`，网络加载统一回到 warmup pipeline。
- `gaplessPlayback` 已开启，local path 增量更新时降低闪烁。

### 风险与后续
1. 当前可见范围使用网格/list 的估算值，已经足够支撑 P0/P1 排队；后续可结合真实 viewport layout 做更精确计算。
2. `imageHeaderBuilder` 在 shelf 参数中仍保留但暂不参与 `ShelfCoverImage`，后续若统一移除需要同步外部调用和测试。
3. 失败冷却存在于 `ShelfCoverWarmupService` 实例生命周期内，App 重启后会清空；Milestone D 可再做持久化或 stale-while-revalidate。
4. 分类 keep-alive 当前依赖 PageView 生命周期和 PageStorage，若分类数量特别多，后续可加最近访问分类数量限制。

### 测试覆盖（仅编写，未执行）
- [ ] `shelf_cover_warmup_service_test.dart` 覆盖优先级、失败冷却、视口/相邻分类标记。
- [ ] `unified_shelf_controller_test.dart` 覆盖视口范围提升 warmup 优先级。
- [ ] `unified_shelf_page_test.dart` 覆盖分类页稳定 PageStorageKey。
- [ ] `shelf_cover_image_test.dart` 覆盖 placeholder 与本地 FileImage/gapless 行为。

### 待你本地回归
1. `flutter test`
2. `flutter analyze`

说明：本轮按你的要求未执行 `flutter test`、`flutter analyze`、`dart format`。

---

## Shelf 性能优化 Milestone B Review 记录（2026-05-10）
### Review 范围
- `lib/features/library_shared/domain/models/library_models.dart`
- `lib/features/library_shared/domain/contracts/shelf_module_adapter.dart`
- `lib/features/library_shared/domain/services/library_shelf_query_utils.dart`
- `lib/features/library_shared/presentation/controllers/unified_shelf_controller.dart`
- `lib/features/comic/data/comic_repository.dart`
- `lib/features/comic/data/local_comic_repository.dart`
- `lib/features/comic/presentation/adapters/comic_shelf_adapter.dart`
- `lib/features/novel/data/novel_repository.dart`
- `lib/features/novel/data/local_novel_repository.dart`
- `lib/features/novel/presentation/adapters/novel_shelf_adapter.dart`
- `lib/features/favorites/data/local_favorite_repository.dart`
- `lib/features/favorites/presentation/adapters/favorite_shelf_adapter.dart`
- `lib/features/comic/data/local/comic_local_db.dart`
- 新增/更新的 snapshot 相关测试文件

### 核对结论
1. Snapshot 边界达成
- Shared 层新增 `LibraryShelfSnapshot` 与可选 `ShelfSnapshotAdapter`。
- Controller 优先走 snapshot，不支持时回退旧查询，降低一次性改造风险。

2. per-item 查询收敛
- 漫画/小说 snapshot 使用 SQL 聚合 unread/read/download/tag/章节数，不再需要 adapter 对每个作品调用状态仓库。
- 收藏 snapshot 批量 join 分类、标签和模块封面，避免每个收藏条目单独查 tag/封面。

3. 封面链路仍保持非阻塞
- Snapshot 只返回当前 DB 中已有的封面 URL/local path。
- 后台 `ShelfCoverWarmupService` 仍由 controller 在 metadata ready 后触发，不回退到查询阶段下载封面。

4. 可维护性
- keyword/filter/sort 统一收敛到 `LibraryShelfQueryUtils`。
- 三模块 repository 只负责批量取字段，adapter 只负责桥接 snapshot/fallback。
- 新增 repository snapshot 接口为可选接口，避免已有 fake 和其它调用方被强制改造。

### 风险与后续
1. 聚合 SQL 和旧 per-item 逻辑的统计口径需要通过你本地测试进一步对齐，尤其是“未读”是否只统计已有状态行。
2. 当前筛选排序仍在 Dart 层执行，后续大数据量可继续把部分排序下推 SQL。
3. 收藏 snapshot 的系统分类只在有原始内容时出现；搜索后空分类由 controller 可见性规则继续处理。
4. DB 版本已提升到 `13`，开发期仍沿用重建最新版 schema 策略。
5. 收藏表索引需要在 `_createFavoriteTables()` 中创建，不能放在早于收藏表创建的通用索引方法里。

### 测试覆盖（仅编写，未执行）
- [ ] `unified_shelf_controller_test.dart` 覆盖 snapshot adapter 优先路径。
- [ ] `local_comic_repository_test.dart` 覆盖漫画聚合状态/标签。
- [ ] `local_novel_repository_test.dart` 覆盖小说聚合状态/标签。
- [ ] `local_favorite_repository_test.dart` 覆盖收藏聚合分类/标签/封面。
- [ ] `library_state_phase1_db_migration_test.dart` 覆盖 snapshot 新索引。

### 待你本地回归
1. `flutter test`
2. `flutter analyze`

说明：本轮按你的要求未执行 `flutter test`、`flutter analyze`、`dart format`。

---

## 问题汇总补充修复 Review 记录（2026-05-10）
### Review 范围
- `lib/features/comic/data/local_comic_repository.dart`
- `lib/features/comic/presentation/adapters/comic_detail_adapter.dart`
- `lib/features/comic/presentation/adapters/comic_shelf_adapter.dart`
- `lib/features/favorites/data/local_favorite_repository.dart`
- `lib/features/favorites/presentation/adapters/favorite_shelf_adapter.dart`
- `lib/features/library_shared/domain/models/library_models.dart`
- 对应新增/调整测试文件

### 核对结论
1. 自定义封面与普通封面已分流
- 自定义封面使用 `customCoverImageUrl/customCoverLocalPath` 数据链路。
- 缓存使用 `cover/custom/...` key 与 `ImageCacheRole.customCover`，不再写入普通封面本地路径。

2. 本地存储写回边界更清晰
- `updateCustomCover()` 会清空旧 `custom_cover_local_path`，防止远程封面变化后继续命中旧文件。
- 详情页、漫画书架、收藏书架写回时只更新对应字段。

3. 收藏页复用模块封面更安全
- 收藏仓库透传漫画模块的自定义远程封面。
- 收藏适配器区分普通/自定义封面缓存目标，避免把自定义封面写成普通封面。

### 风险与后续
1. 小说模块当前只有 `custom_cover_local_path`，若后续增加自定义远程封面字段，可复用 shared 层 `customCoverImageUrl` 和收藏适配器的 custom cover 分流策略。
2. 本轮未执行格式化，可能存在需要 `dart format` 调整的长行。

### 执行声明
本轮按约定未执行：
1. `flutter test`
2. `flutter analyze`

---

## 漫画阅读器 Phase 3 Review 清单（2026-05-12）
### 一、上下菜单
- [ ] 顶栏展示作品标题和章节标题，长标题省略不溢出。
- [ ] 点击顶栏标题返回详情页并触发 reader 退出进度保存。
- [ ] 顶栏书签按钮调用 `ComicReadingStateWriter.setEpisodeBookmarked()`。
- [ ] 顶栏打开原帖按钮使用当前章节 `sourceTid` 进入 `ThreadDetailPage`。
- [ ] 更多菜单包含标记已读/未读、设当前页为封面、缓存本章、缓存未读、清除本章缓存、重试失败图片。

### 二、底部面板
- [ ] 第一行保留上一章、当前页、Slider、总页、下一章。
- [ ] 阅读模式改为图标入口 + bottom sheet，不再使用占高的大号分段控件作为主面板。
- [ ] 章节列表入口可打开章节 sheet，当前章节有选中态。
- [ ] 显示设置入口可打开设置 sheet。
- [ ] 缓存入口可触发当前章节缓存。

### 三、页码浮层与交互
- [ ] 菜单隐藏且偏好开启时显示 `current / total` 页码浮层。
- [ ] 翻页/滚动时页码浮层短暂高亮。
- [ ] 内容滚动或翻页自动隐藏菜单。
- [ ] Slider 拖动/提交期间不触发自动隐藏。
- [ ] 图片缩放状态下 tap zone 不误触菜单或翻页。

### 四、当前页设为封面
- [ ] 操作入口在阅读器顶部更多菜单。
- [ ] 使用当前 `currentImageIndex` 对应图片，不使用详情封面 URL 或章节首图替代。
- [ ] 当前页已有本地路径时直接复制该文件到受保护封面缓存。
- [ ] 当前页只有远程 URL 时先通过 reader cache 缓存，再复制受保护封面。
- [ ] 写入 `customCoverLocalPath` 后，详情页和书架优先展示该本地文件。
- [ ] 清除本章缓存不会清理受保护自定义封面。

### 五、设置偏好
- [ ] `ReaderPreferences` 持久化阅读模式、页面适配、背景色、页间距、页码浮层。
- [ ] 已删除 Phase 6 裁边入口和未接入图片处理管线的预留偏好接口。
- [ ] 页面适配和页间距能影响 reader 图片布局。

### 六、架构边界
- [ ] Reader 页面只编排 UI 与导航，不直接写统一状态表。
- [ ] 书签/已读/完成状态通过 `ComicReadingStateWriter` 统一写入。
- [ ] 封面文件复制通过 `ImageCacheService.copyProtectedLocalFile()`。
- [ ] 章节图片缓存元数据清理通过 `ComicRepository.clearEpisodeImageCache()`。

### 七、测试覆盖（仅编写，未执行）
- [ ] `comic_reader_controller_test.dart` 覆盖书签、已读、清缓存、设封面。
- [ ] `comic_reader_page_test.dart` 覆盖菜单/sheet/设封面入口。
- [ ] `reader_top_bar_test.dart` 覆盖顶栏双行标题与更多菜单。
- [ ] `reader_bottom_panel_test.dart` 覆盖底部工具入口。
- [ ] `reader_page_indicator_overlay_test.dart` 覆盖页码浮层。
- [ ] `local_comic_repository_test.dart` 覆盖章节缓存元数据清理。

### 八、待你本地回归
1. `flutter test`
2. `flutter analyze`

说明：`dart format` 按本轮要求未执行，也不作为本轮回归项。

---

## 漫画阅读器 Phase 4 Review 清单（2026-05-12）
### 一、预加载队列边界
- [ ] `ComicReaderPreloadQueue` 位于 domain service 层，不依赖 Riverpod、repository 或 UI。
- [ ] 队列只负责优先级、去重、并发上限、取消和 snapshot，不直接写数据库。
- [ ] 同一 `episodeId:imageIndex` 不重复入队。
- [ ] pending 任务允许被更高优先级任务升级。
- [ ] `maxConcurrent` 默认 2，并被约束在 1~4。

### 二、取消与跳页行为
- [ ] Slider/显式跳页会调用 `cancelExcept()` 清理旧窗口外任务。
- [ ] 已运行但被取消的旧任务结果不会触发 `onResult` 回写。
- [ ] 保留窗口内的运行任务结果仍可正常回写。
- [ ] provider dispose 会释放队列，避免页面销毁后继续调度。

### 三、缓存状态回写
- [ ] 入队成功写 `queued`。
- [ ] 任务开始写 `downloading`。
- [ ] 任务成功写 `done` 和本地路径/缓存元数据。
- [ ] 任务失败写 `failed`，且不打断阅读器状态流。
- [ ] `downloaded` 图片不会被预加载任务降级覆盖。
- [ ] `storageImageUrl` 用于定位数据库行，`imageUrl` 用于实际下载。

### 四、阅读器集成
- [ ] 打开章节后优先入队当前页和后续 4 页。
- [ ] 滚动/页可见时按方向入队后续 4 页、前序 2 页。
- [ ] 跳页时目标页使用 `jumpTarget` 优先级。
- [ ] 图片重试使用 `retry` 优先级。
- [ ] 靠近章节末尾时仅预取下一章前 3 页，不提前改变当前章节 UI。

### 五、日志与可观测性
- [ ] `ComicReaderEventLogger` 支持 `extra` 字段。
- [ ] 队列 snapshot 日志包含 pending/running/success/failed/cancelled。
- [ ] 日志仍保持轻量，不引入额外 telemetry 依赖。

### 六、测试覆盖（仅编写，未执行）
- [ ] `comic_reader_preload_queue_test.dart` 覆盖优先级顺序。
- [ ] `comic_reader_preload_queue_test.dart` 覆盖去重与优先级升级。
- [ ] `comic_reader_preload_queue_test.dart` 覆盖并发上限。
- [ ] `comic_reader_preload_queue_test.dart` 覆盖取消旧运行任务结果。
- [ ] `comic_reader_controller_test.dart` 覆盖跳页窗口预加载和 `queued/downloading/done` 回写。
- [ ] `comic_reader_controller_test.dart` 覆盖失败图片 retry 入队与状态回写。

### 七、待你本地回归
1. `flutter test`
2. `flutter analyze`

说明：`dart format` 按本轮要求未执行，也不作为本轮回归项。

---

## 漫画阅读器 Phase 5 Review 清单（2026-05-12）
### 一、章节预加载策略
- [ ] `ComicReaderChapterPreloadPolicy` 独立于 UI 和 Riverpod。
- [ ] 总页数 `<= 6` 时最后 2 页触发下一章预加载。
- [ ] 总页数 `> 6` 时最后 4 页触发下一章预加载。
- [ ] 下一章只预加载前 3 页，不自动拼接当前阅读流。

### 二、Controller 行为
- [ ] `ensureNextChapterPreloaded()` 可重复调用且复用进行中的 future。
- [ ] 下一章已 ready 时重复调用不重新入队。
- [ ] 下一章图片列表获取失败或为空不会影响当前章节阅读。
- [ ] 最后一章进入 unavailable 状态，不反复请求下一章。
- [ ] `goToEpisode()` 在当前 reader 内切换章节，并重置可见页、进度窗口和预加载状态。
- [ ] `goToEpisode()` 加载目标章节失败时恢复当前章节状态并给出提示。
- [ ] 章节切换后阅读进度、书签、已读状态属于目标章节。
- [ ] reader 正常退出时不会因为 `lastReadEpisodeId` 变化而触发详情页循环再次打开。

### 三、缓存与日志
- [ ] 下一章前 3 页任务使用 `ComicReaderPreloadPriority.nextChapter`。
- [ ] 下一章任务只回写仓储和下一章预加载状态，不污染当前章节图片状态。
- [ ] 日志包含 `next_chapter_preload_start`、`next_chapter_preload_ready`、`next_chapter_preload_failed` 或最后一章不可用事件。
- [ ] provider dispose 后队列仍由既有 dispose 流程释放。

### 四、转场 UI
- [ ] 垂直连续模式末尾显示“下一章：xxx”转场块。
- [ ] 已预加载时转场块显示已预加载页数。
- [ ] 点击转场块切换到下一章，不返回详情页重新打开。
- [ ] 垂直模式 tap zone 不覆盖转场块所在的底部安全区。
- [ ] tap zone 作为内容层父级 raw pointer 监听点击，滚动/拖动手势仍可传递给 `ListView/PageView`。
- [ ] tap zone 的单击延迟不会破坏图片双击缩放。
- [ ] 底部下一章按钮按 idle/loading/ready/failed 显示对应状态图标或 tooltip。

### 五、Phase 6 跳过范围
- [ ] `comic_reader_page.dart` 中不再出现“裁边”开关。
- [ ] `ReaderPreferences` 不再包含 `cropBorders`。
- [ ] `ReaderPreferencesController` 不再暴露 `setCropBorders()`。
- [ ] 未实际接入 UI 的 `fullscreenOnOpen/cacheDirectoryPath` 预留偏好接口已删除。
- [ ] 页面适配、背景色、页间距、页码浮层等已完成功能保留。

### 六、测试覆盖（仅编写，未执行）
- [ ] `comic_reader_chapter_preload_test.dart` 覆盖阈值策略。
- [ ] `comic_reader_controller_test.dart` 覆盖下一章预加载和当前 reader 内切换章节。
- [ ] `comic_reader_page_test.dart` 覆盖下一章转场块。
- [ ] `comic_detail_page_test.dart` 覆盖 reader 正常退出不触发详情页再次打开。
- [ ] `reader_tap_zones_test.dart` 覆盖底部安全区、拖动手势穿透和双击保护。
- [ ] 偏好相关测试删除裁边/预留接口断言。

### 七、本轮回归修复关注点（2026-05-12）
- [ ] `comic_reader_controller_test.dart` 中下一章预加载用例不再直接对短暂 loading 状态执行 `value!`。
- [ ] `comic_reader_controller_test.dart` 对 `autoDispose` reader provider 持有订阅，异步队列期间不会被释放重建。
- [ ] `comic_reader_page_test.dart` 对尾部下一章转场块先滚动到可见区域再断言。
- [ ] 菜单、章节列表、更多菜单、Slider 用例不再通过 `ensureVisible()` 滚动固定底部 overlay。
- [ ] 阅读器正文滚动后，底部控制层仍位于视口内且可点击。

### 八、待你本地回归
1. `flutter test`
2. `flutter analyze`

说明：`dart format` 按本轮要求未执行，也不作为本轮回归项。

---

## Shelf 性能优化 Milestone A Review 记录（2026-05-10）
### Review 范围
- `lib/features/library_shared/domain/services/shelf_cover_warmup_service.dart`
- `lib/features/library_shared/domain/services/shelf_perf_trace.dart`
- `lib/features/library_shared/domain/models/library_models.dart`
- `lib/features/library_shared/presentation/controllers/unified_shelf_controller.dart`
- `lib/features/library_shared/presentation/pages/unified_shelf_page.dart`
- `lib/features/comic/presentation/adapters/comic_shelf_adapter.dart`
- `lib/features/novel/presentation/adapters/novel_shelf_adapter.dart`
- `lib/features/favorites/presentation/adapters/favorite_shelf_adapter.dart`
- `test/features/library_shared/domain/services/shelf_cover_warmup_service_test.dart`
- `test/features/library_shared/presentation/controllers/unified_shelf_controller_test.dart`
- `test/features/favorites/presentation/favorite_shelf_adapter_test.dart`
- `test/features/comic/presentation/adapters/comic_shelf_adapter_test.dart`
- `test/features/novel/presentation/adapters/novel_shelf_adapter_test.dart`

### 核对结论
1. Milestone A 目标达成
- 漫画、小说、收藏 adapter 的元数据查询不再直接调用 `ensureCached/ensureProtectedCover`。
- 封面缓存与写回迁移到 `ShelfCoverWarmupAdapter.warmCover()`。
- `UnifiedShelfController` 在 metadata 可用后启动后台 warmup，不再把封面下载纳入首屏 loading。
- 收藏首次同步改为后台任务，不阻塞 `loadCategories()`。

2. 架构边界合理
- shared 层只定义 warmup 合同、并发/去重和 controller 编排。
- cache key、ownerType、role、模块仓储写回仍由各模块 adapter 自己负责。
- `LibraryWorkItem.copyWith()` 只补足视图模型增量更新能力，没有把缓存服务引入 model。

3. 状态一致性
- controller 使用 generation 和 dispose guard，避免旧 warmup 结果覆盖新 reload。
- warmup 结果只更新命中 workId 的封面路径，并通过 `onStateChanged` 通知 UI。
- 后台任务进度从 active 变为 inactive 后会触发一次 metadata reload，覆盖收藏首次同步完成后的快照刷新。

4. 异常处理
- `ShelfCoverWarmupService` 内部吞掉单个封面失败。
- controller 的 warmup request 构建和 warmup 调度也做 best-effort 保护，避免未等待 Future 异常进入 Flutter error handler。
- 收藏 `_syncIfNoSnapshot()` 捕获异常，错误由同步服务进度/状态链路负责，不破坏首屏 metadata 路径。

5. 测试覆盖
- 已补充服务层、controller 层、漫画/小说/收藏 adapter 层测试。
- 新测试重点覆盖 metadata-only、后台 warmup 写回、自定义封面优先级、收藏首次同步非阻塞和后台任务完成后自动刷新。

### Review Checklist
- [ ] `queryItems/loadCategoryItems/searchItemsByKeyword` 不应再下载封面或写回封面缓存。
- [ ] `buildCoverWarmupRequests()` 只根据当前 state 快照生成请求，不修改仓储。
- [ ] `warmCover()` 可以写缓存和仓储，但失败必须返回 `null` 或被上层吞掉，不影响页面。
- [ ] 同一 `cacheKey` 在 warmup service 中应去重，避免多分类重复下载同一作品封面。
- [ ] 自定义封面 pending 时，普通本地封面不应被当作首选封面展示。
- [ ] 收藏首次进入时，页面应能显示结构和进度 banner，不等待完整同步。
- [ ] 后台任务完成后，应有一次轻量 metadata reload，使新同步数据进入当前页面。
- [ ] controller dispose 后，旧 warmup/reload 不能再更新 state 或触发 UI 回调。

### 风险与后续
1. 当前 warmup 仍是“当前分类优先 + 后续分类顺序”的基础队列，尚未做到真正视口级优先级；该能力属于 Milestone C。
2. 漫画/小说仍有 per-item unread/read/download/tag 查询，数据量大时仍会拖慢 metadata query；该能力属于 Milestone B 的 snapshot 聚合查询。
3. `LibraryCachedImage` 仍在 build 中做同步文件存在检查，Milestone A 暂未处理；后续应进入现代化图片组件阶段。
4. 未做真实设备性能采样，本轮仅提供 debug/profile 日志入口。

### 执行声明
本轮按约定未执行：
1. `flutter test`
2. `flutter analyze`
3. `dart format`

---

## 问题汇总修复 Review 记录（2026-05-10）
### Review 范围
- 阅读器：`comic_reader_page.dart`、`library_cached_image.dart`
- 封面缓存：漫画/小说/收藏 shelf adapter、`LibraryCoverCacheService`、`DefaultImageCacheService`
- 本地封面：`local_comic_repository.dart`、`comic_detail_adapter.dart`
- 书架/详情：`unified_shelf_controller.dart`、`unified_detail_page.dart`
- 论坛首页：`forum_home_repository.dart`、`forum_home_controller.dart`、`forum_home_page.dart`、`forum_home_state.dart`
- 对应测试文件与本文档、开发文档

### 核对结论
1. 阅读器占位
- [ ] 纵向模式每张图片有稳定槽位，加载阶段不再把图片突然插入列表。
- [ ] 加载占位和错误占位分离，失败态仍保留重试按钮。

2. 封面缓存
- [ ] 漫画首图封面按最小 `sourceTid` 章节判定。
- [ ] 首楼封面可被真实首话首图纠正，但不会覆盖自定义封面。
- [ ] 漫画/小说/收藏书架远程封面会写入受保护缓存，并回写模块本地路径。
- [ ] 稳定 cache key 的来源 URL 变化会强制重拉，避免旧封面残留。

3. 书架加载体验
- [ ] 初始状态不再闪现“书架为空”。
- [ ] 已有内容的刷新不再阻塞式清空列表。

4. 详情页头部
- [ ] Hero 信息区和操作行处于同一个 header sliver，降低下拉刷新拉伸缝隙风险。

5. 论坛首页收藏版块
- [ ] 登录态可恢复展示“我收藏的版块”。
- [ ] `myfavforum` 加载失败不影响 forumindex 基础首页。
- [ ] 首页常规版块计数不被收藏快捷入口重复污染。

### 风险与后续
1. 阅读器槽位使用通用肖像比例作为最小高度，超长图加载后仍会扩展到真实高度；若后续需要绝对稳定滚动高度，可在图片 metadata 入库后按真实宽高比渲染。
2. 封面缓存现在在书架映射时惰性触发；首次打开大书架可能伴随少量封面缓存任务，后续可考虑批量限流队列。
3. 论坛首页恢复 `myfavforum` 后会多一个登录态接口请求；当前按失败降级处理，避免阻塞首页。

### 执行声明
本轮按约定未执行：
1. `flutter test`
2. `flutter analyze`
3. `dart format`

---

## 分阶段实现 05：下载存储结构 Review 清单（2026-05-10）
### 一、下载存储根目录
- [ ] 下载存储与图片缓存目录分离。
- [ ] 根目录包含 `.nomedia`、`favorites.json`、`comics/`、`novels/`。
- [ ] `comics/` 与 `novels/` 子目录均包含 `.nomedia`。
- [ ] 安全文件名会过滤 `\/:*?"<>|`，并处理过长名称与重名 hash。
- [ ] JSON 写入使用临时文件 + rename，避免写入中断留下半截 `meta.json`。

### 二、漫画下载结构
- [ ] 单章下载生成 `meta.json + cover.jpg + NNN-title.cbz`。
- [ ] CBZ 内部图片为扁平 `001.jpg / 002.png / 003.webp`。
- [ ] 图片扩展名优先根据 mime，其次根据本地路径或源 URL 推断。
- [ ] `meta.json.chapters` 是章节顺序来源，不依赖文件系统排序。
- [ ] 删除章节下载时会删除对应 CBZ，并从 `meta.json.chapters` 移除该章节。

### 三、小说下载结构
- [ ] 小说目录包含 `meta.json + cover.jpg + chapters/ + images/`。
- [ ] 章节 JSON 保存 `episodeId/sourceTid/sourcePid/sourcePage/title/orderIndex/rawHtml/plainText/paragraphs/images`。
- [ ] `meta.json.chapters[].file` 使用 posix 相对路径，例如 `chapters/001-序章.json`。
- [ ] 离线读取能从章节 JSON 恢复 `NovelChapterContent`。
- [ ] 当前插图 URL 未入正文缓存时，`images` 字段为空但结构保留。

### 四、读取优先级
- [ ] 漫画阅读器优先读取下载 CBZ，再回退 SQLite 图片索引/缓存，再请求网络。
- [ ] 已下载漫画图片不会被首屏预加载或跳页预取重新写入图片缓存。
- [ ] 小说阅读器优先读取下载章节 JSON，再回退 SQLite 正文缓存。
- [ ] 详情页下载按钮通过模块 adapter 调用下载服务，shared 层不直接依赖具体下载实现。

### 五、收藏快照
- [ ] 收藏同步成功后会写入下载根目录 `favorites.json`。
- [ ] 快照包含 `tid/favid/title/author/fid/typeid/tagName/contentKind/workId/removed/dateline`。
- [ ] SQLite 仍是 App 主索引，`favorites.json` 只作为可读快照和后续迁移输入。

### 六、测试覆盖（仅编写，未执行）
- [ ] `download_storage_service_test.dart` 覆盖存储根目录和 `.nomedia`。
- [ ] `comic_download_service_test.dart` 覆盖漫画 CBZ 与 `meta.json`。
- [ ] `novel_download_service_test.dart` 覆盖小说章节 JSON、`meta.json` 和离线读取。
- [ ] 漫画阅读器测试覆盖下载存储优先级。
- [ ] 小说阅读器测试覆盖下载 JSON 优先级。
- [ ] 收藏同步测试覆盖 `favorites.json` 快照写入。

### 七、待你本地回归
1. `flutter test`
2. `flutter analyze`

说明：`dart format` 按本轮要求未执行，也不作为本轮回归项。

---

## 分阶段实现 04：缓存机制重构测试反馈修复 Review 记录（2026-05-09）

### Review 范围
- `lib/features/comic/data/local/comic_local_db.dart`
- `lib/features/comic/presentation/adapters/comic_detail_adapter.dart`
- `lib/features/comic/presentation/controllers/comic_reader_controller.dart`
- `lib/features/novel/data/local_novel_repository.dart`
- `test/features/more/presentation/cache_settings_controller_test.dart`
- `test/features/more/presentation/cache_settings_page_test.dart`
- `test/features/more/presentation/more_page_test.dart`

### 核对结论
1. DB v12 开发期重建策略：
- [ ] `onUpgrade/onDowngrade` 统一调用 `_rebuildLatestSchema`。
- [ ] `_rebuildLatestSchema` 只删除本模块管理的表，再创建最新版 schema。
- [ ] 逐版本 `ALTER TABLE` 兼容链已移除，避免为开发期历史库持续膨胀迁移代码。
- [ ] 最新 schema 直接包含 source tag、本地封面路径、图片缓存 metadata、收藏表和统一状态表。
- [ ] `source_tag_db_migration_test.dart` 与 `image_cache_phase4_db_migration_test.dart` 已改为验证开发期重建策略。

2. 缓存写入接口边界：
- [ ] 漫画封面缓存写入通过 `ComicCoverCacheWriter` 窄接口显式转型。
- [ ] 漫画章节图片缓存 metadata 写入通过 `ComicEpisodeImageCacheMetadataWriter` 窄接口显式转型。
- [ ] `ComicRepository` 主接口未因图片缓存细节继续膨胀。
- [ ] `LocalNovelRepository.updateCoverCache` 不再错误标注 `@override`。

3. 更多页数据与存储测试：
- [ ] fake `MoreSettingsRepository` 已实现图片缓存上限读写。
- [ ] 设置页/controller 测试已覆盖 `imageCacheServiceProvider` fake 注入。
- [ ] More 页入口断言已从“缓存目录”改为“数据与存储”。
- [ ] 提示文案断言与当前实现一致：`存储位置已更新`、`已恢复默认存储位置`。

### 待你本地回归
1. `flutter test`
2. `flutter analyze`

说明：本轮按要求未执行自动化命令，也未执行 `dart format`。

---

## 分阶段实现 02：解析规则重构 Review 清单（2026-05-08）

### 一、DOM/URL 工具边界
- [ ] `ForumThreadUrlParser` 只负责链接规范化和 `tid` 提取，不承载漫画/小说业务语义。
- [ ] `ForumPostDomExtractor` 只提供 anchor、图片、纯文本、段落和标题候选等通用 DOM 提取能力。
- [ ] 图片提取支持 `src/data-src/data-original/file`。
- [ ] 表情、头像、论坛 UI 图片默认被过滤。
- [ ] 普通文本中的 `thread-xxx` 不会被当作递归候选。

### 二、漫画解析稳定性
- [ ] `ComicConsecutiveOpPostParser._extractImages` 不再正则扫描 `<img>`。
- [ ] `ComicEpisodeDiscoveryService._collectRecursiveTidCandidates` 不再对整段 raw HTML 做 `allMatches`。
- [ ] `ComicPostParsingEngine` 通过 DOM 工具获取 anchors，漫画规则仍只负责目录/章节/拒绝等语义判断。
- [ ] 既有章节顺序、目录识别、损坏链接兼容行为保持不变。

### 三、小说规则化架构
- [ ] `NovelEpisodeDiscoveryService` 只负责遍历和合并规则结果。
- [ ] 默认规则列表包含楼主过滤、有效内容、标题正则、DOM 标题、封面、简介、兜底标题。
- [ ] 新增规则时可以实现 `NovelParsingRule`，无需继续在 discovery service 内堆叠 if。
- [ ] `NovelRefreshPlan` 已携带 `intro/coverImageUrl/inlineImageUrls/debugInfo`。
- [ ] `NovelEpisodeDraft` 已携带章节内 `imageUrls`。
- [ ] 小说刷新发现封面候选时会更新本地 `cover_image_url`，未发现时保留旧值。

### 四、小说形式资料专项核对
- [ ] 小说作品保持一个主题帖 `tid`，章节列表使用同帖楼层 `pid` 定位。
- [ ] `NovelSameThreadCatalogExtractor` 只识别同帖 `mod=redirect&goto=findpost&ptid=<tid>&pid=<pid>` 目录。
- [ ] 目录中的“目录/contents/catalog”锚点不会生成章节。
- [ ] 同帖目录只扫描首屏前 5-10 个楼主楼层，避免把后续正文中的跳转误判为全书目录。
- [ ] 无目录时回退楼主楼层 `postlist.pid`，并能从 `<strong>001 xxx</strong><br>` 结构提取章节名。
- [ ] `ForumPostDomExtractor.extractPlainText` 保留 `<br>` 换行，避免标题和正文粘连。
- [ ] `LocalNovelRepository.refreshEpisodes` 在新解析结果非空时清理旧的错误章节行与正文缓存。
- [ ] 统一详情页章节行优先展示 `Pid`，仅缺失 pid 时回退 `Tid`。
- [ ] 统一详情页点击章节打开当前列表项 `episodeId`，不再误走第一章/续读目标。

### 五、测试覆盖（仅编写，未执行）
- [ ] `forum_post_dom_extractor_test.dart` 覆盖图片字段、过滤和 anchor tid。
- [ ] `comic_consecutive_op_post_parser_test.dart` 覆盖懒加载图片提取。
- [ ] `comic_episode_discovery_service_test.dart` 覆盖非 anchor 文本 URL 不入递归候选。
- [ ] `novel_episode_discovery_service_test.dart` 覆盖楼主过滤、标题识别、番外/特典、封面、简介、插图。
- [ ] `novel_episode_discovery_service_test.dart` 覆盖同帖 pid 目录与无目录 pid 回退。
- [ ] `novel_same_thread_catalog_extractor_test.dart` 覆盖同帖目录提取、跨帖/非楼主/过晚楼层过滤。
- [ ] `local_novel_repository_test.dart` 覆盖刷新后清理旧错误章节缓存。
- [ ] `unified_detail_page_test.dart` 覆盖列表展示 `Pid` 与章节点击打开当前 `episodeId`。

### 六、待你本地回归
1. `flutter test`
2. `flutter analyze`

说明：`dart format` 按本轮要求未执行，也不作为本轮回归项。

请本地回归后回传日志，我会继续修复。

---

## 统一详情页漫画刷新链路 Review 记录（2026-05-04）
### Review 范围
- `lib/features/comic/presentation/adapters/comic_detail_adapter.dart`
- `lib/features/comic/presentation/comic_detail_page.dart`
- `test/features/comic/presentation/adapters/comic_detail_adapter_test.dart`

### 结论
1. 统一刷新入口保持不变：
- 操作区“更新”按钮
- 下拉刷新
- more 菜单“刷新”
以上三者均通过 `UnifiedDetailController.refresh()` 汇总。

2. 漫画模块已接入域服务刷新策略：
- `ComicDetailAdapter.refreshWork` 不再是空实现；
- 通过 `ComicEpisodeRefreshService.fetchEpisodeLinksFromTid` 获取章节链接；
- 通过 `ComicRepository.mergeEpisodesFromLinks` 合并章节；
- 统一页随后 reload 即可在 `SliverList.builder` 看到新增章节。

3. 依赖注入边界清晰：
- `ComicDetailPage` 仅负责注入 refresh service；
- 统一详情页与控制器不感知漫画实现细节；
- 适配器承接模块差异，符合 shared 解耦目标。

4. 测试可维护性：
- 新增 adapter 单测覆盖刷新调用链关键断点。

### 风险与后续
1. 当前 `unified_detail_page.dart` 文件体量偏大，建议按“header/chapter/more-action 协调器”拆分组件与动作编排文件，降低 review 成本。

### 执行声明
本轮按约定未执行：
1. `flutter test`
2. `flutter analyze`

---

## 图片直链防盗链请求头修复 Review 记录（2026-05-10）
### Review 范围
- `lib/core/network/image_request_headers.dart`
- `lib/core/network/site_url_resolver.dart`
- `lib/core/network/network_providers.dart`
- `lib/features/cache/data/default_image_cache_service.dart`
- `lib/features/cache/presentation/widgets/library_cached_image.dart`
- `lib/features/comic/domain/services/comic_services_impl.dart`
- `lib/features/comic/presentation/comic_reader_page.dart`
- `lib/features/thread/domain/services/forum_post_dom_extractor.dart`
- `lib/features/thread/presentation/thread_detail_page.dart`
- `lib/features/thread/presentation/widgets/thread_post_html.dart`
- `lib/features/library_shared/presentation/pages/unified_shelf_page.dart`
- `lib/features/library_shared/presentation/pages/unified_detail_page.dart`
- `lib/shared/widgets/shelf/shelf_cover_card.dart`
- `test/core/network/image_request_headers_test.dart`
- `test/core/network/site_url_resolver_test.dart`
- `test/features/cache/data/default_image_cache_service_test.dart`
- `test/features/cache/presentation/widgets/library_cached_image_test.dart`
- `test/features/thread/domain/services/forum_post_dom_extractor_test.dart`
- `test/features/thread/presentation/widgets/thread_post_html_test.dart`

### 一、请求头策略
- [ ] 图片请求头逻辑集中在 `ImageRequestHeaderBuilder`，页面和服务不散写 Referer/Cookie。
- [ ] 默认 Referer 为 `https://bbs.yamibo.com/`。
- [ ] 默认带浏览器态 `User-Agent`。
- [ ] 默认带图片类 `Accept` 与 `Accept-Language`。
- [ ] Cookie 只按图片 URL 自身 host 读取，避免把站点 Cookie 泄露给第三方图床。
- [ ] `SiteUrlResolver` 统一归一化图片 URL，调用点不各自拼接站点地址。

### 二、下载与直显链路
- [ ] `DefaultImageCacheService.ensureCached` 下载图片时传入 `authHeaders`。
- [ ] `NetworkComicReaderService` legacy 下载兜底也传入同一套 headers。
- [ ] `LibraryCachedImage` 远程直显时通过 `Image.network(headers: ...)` 传入 headers。
- [ ] 原帖 `ThreadPostHtml` 的 `<img>` 也走 `LibraryCachedImage`，避免 `flutter_html` 默认图片绕过 headers。
- [ ] 本地缓存路径仍优先，不因 header builder 影响本地文件展示。
- [ ] shared widget 通过可选依赖接收 header builder，不反向依赖 Riverpod。

### 三、图片 URL 归一化
- [ ] `ForumPostDomExtractor.extractImageSources` 支持 `src` / `data-src` / `data-original` / `file`。
- [ ] 相对路径、根路径、协议相对路径会归一化为 Yamibo 绝对 URL。
- [ ] 表情、头像等站点装饰图仍会被过滤。
- [ ] 旧数据中残留的相对图片地址在 UI 展示和缓存下载前也会被归一化。

### 四、测试覆盖（仅编写，未执行）
- [ ] `image_request_headers_test.dart` 覆盖 Referer/User-Agent/Cookie 与第三方图床不泄露 Cookie。
- [ ] `site_url_resolver_test.dart` 覆盖绝对/相对/协议相对 URL。
- [ ] `default_image_cache_service_test.dart` 覆盖缓存下载 header 转发。
- [ ] `library_cached_image_test.dart` 覆盖 UI 直显 header 转发。
- [ ] `forum_post_dom_extractor_test.dart` 覆盖图片 URL 归一化。
- [ ] `thread_post_html_test.dart` 覆盖原帖 HTML 图片 header 转发。

### 风险与后续
1. 第三方图床如果同时要求它自己的登录 Cookie，当前不会携带 Yamibo Cookie；这是刻意的安全边界。
2. 如果某个图床要求更具体的 Referer（例如原帖 URL 而不是站点根），后续可在 `ImageRequestHeaderBuilder` 扩展上下文参数，而不改 UI/缓存调用点。

### 执行声明
本轮按约定未执行：
1. `flutter test`
2. `flutter analyze`
3. `dart format`

---

## 收藏与章节刷新体验修复 Review 记录（2026-05-09）
### Review 范围
- `lib/features/comic/domain/services/comic_services_impl.dart`
- `lib/features/favorites/data/local_favorite_repository.dart`
- `lib/features/favorites/data/favorite_sync_service.dart`
- `lib/features/favorites/presentation/adapters/favorite_shelf_adapter.dart`
- `lib/features/library_shared/domain/contracts/shelf_module_adapter.dart`
- `lib/features/library_shared/presentation/pages/unified_shelf_page.dart`
- `test/features/comic/domain/services/network_comic_episode_refresh_service_test.dart`
- `test/features/favorites/data/local_favorite_repository_test.dart`
- `test/features/favorites/data/favorite_sync_service_test.dart`
- `test/features/library_shared/presentation/pages/unified_shelf_page_test.dart`
- `test/features/favorites/presentation/favorite_shelf_page_test.dart`

### 一、漫画章节刷新
- [ ] 当前 tid 发现 direct/recursive 链接后不会直接停止。
- [ ] 目录解析成功且非空时优先使用目录结果。
- [ ] 无目录完整结果时会执行一次搜索 fallback 补全。
- [ ] 搜索 fallback 跳过当前 tid，避免搜索首项为当前帖时再次停在旧链路。
- [ ] 当前发现与搜索发现按 tid 去重合并。
- [ ] 重复 tid 时使用搜索/目录补全侧标题覆盖“上一话”等弱标题。
- [ ] 章节刷新逻辑仍集中在 `ComicEpisodeRefreshService`，详情页和 adapter 不感知搜索补全细节。

### 二、收藏页封面
- [ ] 收藏缓存不复制漫画/小说封面缓存策略。
- [ ] 收藏漫画条目可从 `comics` 表读取 `custom_cover_image_url / cover_image_url / cover_local_path / custom_cover_local_path`，并优先使用自定义网络封面。
- [ ] 收藏小说条目可从 `works` 表读取 `cover_image_url / cover_local_path / custom_cover_local_path`。
- [ ] `UnifiedShelfPage` 列表模式使用 `LibraryCachedImage`，本地封面优先，网络封面兜底。
- [ ] 无封面时仍显示稳定占位。

### 三、首次收藏同步进度
- [ ] `FavoriteSyncService.progress` 能描述读取列表、写入列表、解析详情、收尾等阶段。
- [ ] 首次无 sync state 进入收藏页时，同步进行中能显示进度条。
- [ ] 进度通过 `ShelfModuleAdapter.taskProgress` 可选能力进入 shared 层。
- [ ] `UnifiedShelfPage` 只依赖 `LibraryShelfTaskProgress`，不依赖 favorites 包。
- [ ] loading 阶段和普通列表阶段都能展示进度条。

### 四、测试覆盖（仅编写，未执行）
- [ ] `network_comic_episode_refresh_service_test.dart` 覆盖 direct 后搜索补全、跳过当前 tid 与去重。
- [ ] `local_favorite_repository_test.dart` 覆盖收藏条目复用漫画/小说封面。
- [ ] `favorite_sync_service_test.dart` 覆盖同步进度事件。
- [ ] `unified_shelf_page_test.dart` 覆盖通用任务进度条。
- [ ] `favorite_shelf_page_test.dart` 覆盖首次同步 loading 阶段进度显示。

### 风险与后续
1. 搜索 fallback 会增加一次网络搜索成本；当前限定为 direct/recursive 非目录结果后的补全，且 Top-K 验证仍在同步服务内控制。
2. 收藏页封面是列表渲染时轻量查询模块表，若后续收藏量极大且封面查询成为瓶颈，可在仓库层改为 SQL join 或批量预取。
3. 进度条当前展示同步阶段与页/条计数，若后续需要取消同步，可在 `FavoriteSyncService` 继续扩展取消令牌，不影响 shared 页面合同。

### 执行声明
本轮按约定未执行：
1. `flutter test`
2. `flutter analyze`
3. `dart format`

---

## 分阶段实现 01：标签与 typeid Review 清单（2026-05-08）

### 一、标签基础设施
- [ ] `pubspec.yaml` 已声明 `assets/tag.json`。
- [ ] `ForumTagLookup` 可通过 `fid + typeid` 查到标签名。
- [ ] 标签加载逻辑位于 `features/tags`，UI 不直接读取 asset。
- [ ] 标签加载失败不会阻断帖子详情正文展示。

### 二、帖子详情与分类规则
- [ ] `ThreadDetailData.fromVariables` 能解析 `typeid`。
- [ ] `ThreadDetailPageState` 携带 `typeid/sourceTagName/contentKind`。
- [ ] 漫画入口不再使用评分候选文案。
- [ ] 小说入口不再只靠页面层 fid 判断。
- [ ] 公告帖通过标签名或固定 typeid 被排除为普通论坛帖。

### 三、漫画/小说数据持久化
- [ ] `comics` 表包含 `source_typeid/source_tag_name`。
- [ ] `works` 表包含 `source_typeid/source_tag_name`。
- [ ] `ComicRepository.addToShelf` 写入来源标签字段。
- [ ] `NovelRefreshSeed` 可携带并保存来源标签字段。
- [ ] 老库升级到 DB v10 时新增列不破坏既有数据。

### 四、统一详情页标签展示
- [ ] `LibraryDetailHeader` 携带来源标签和自定义标签。
- [ ] 漫画/小说 detail adapter 会读取 `LibraryStateRepository.getWorkTags`。
- [ ] `UnifiedDetailPage` 在简介下方展示标签条。
- [ ] 标签顺序为：论坛来源标签在前，自定义标签在后。
- [ ] 无标签时不占用可见空间。
- [ ] 添加/移除自定义标签后使用轻量 `reload()` 刷新本地详情，不触发章节更新网络链路。

### 五、测试覆盖（仅编写，未执行）
- [ ] `thread_detail_models_test.dart` 覆盖 typeid 解析。
- [ ] `forum_tag_lookup_test.dart` 覆盖 `fid=30,typeid=65 => 公告`。
- [ ] `thread_content_classifier_test.dart` 覆盖漫画/小说/公告规则。
- [ ] `source_tag_db_migration_test.dart` 覆盖最新版 DB 新列，以及旧开发期库升级后重建为最新版结构。
- [ ] `unified_detail_controller_test.dart` 覆盖 `reload()` 不调用 `refreshWork`。
- [ ] `unified_detail_page_test.dart` 覆盖来源标签 + 自定义标签展示。

### 六、待你本地回归
1. `flutter test`
2. `flutter analyze`

说明：`dart format` 按本轮要求未执行，也不作为本轮回归项。

---

## 分阶段实现 03：收藏同步与收藏 Tab Review 清单（2026-05-08）

### 一、数据库与本地缓存
- [ ] `ComicLocalDb.dbVersion` 已升级到 `11`。
- [ ] 新建库包含 `favorite_sync_state/favorite_threads/favorite_categories/favorite_thread_category`。
- [ ] 老库升级到 v11 时可补齐收藏表，不破坏漫画/小说/统一状态表。
- [ ] `favorite_threads.content_kind` 支持 `unknown/comic/novel/forum`。
- [ ] detail 尚未补全的 `unknown` 记录暂归入默认分类。
- [ ] `removed_at IS NULL` 表示当前远程仍收藏。
- [ ] 收藏自定义分类只写入 `favorite_categories`，系统分类不入表。

### 二、同步策略
- [ ] `myfavthread` 请求显式携带 `version=4&page=N`。
- [ ] 首次同步读取 `myfavthread` 全部页。
- [ ] `remote_count < local_active_count` 时执行完整 diff 并标记 removed。
- [ ] `remote_count == local_active_count` 但 page 1 有未知 tid 时执行完整 diff。
- [ ] 增量同步会从 page 1 往后读取，直到遇到已知页。
- [ ] 同步失败会写入 sync state 的失败状态，不清空已有本地缓存。

### 三、进帖补全与分类规则
- [ ] 收藏补全使用 `ThreadRepository.getThreadDetail(tid,page:1)`。
- [ ] 来源标签使用 `ForumTagLookup(fid,typeid)`。
- [ ] 内容类型使用统一 `ThreadContentClassifier`。
- [ ] 漫画规则仍为 `fid=30 && 非公告`。
- [ ] 小说规则仍为 `fid=49/55 && 非公告`。
- [ ] 公告帖不会同步进入漫画/小说模块。

### 四、漫画/小说同步
- [ ] 漫画收藏写入 `workId=yamibo:<tid>`。
- [ ] 漫画 ingest 复用聚合、DOM 解析和标题元数据解析服务。
- [ ] 小说收藏写入 `workId=novel:<fid>:<tid>`。
- [ ] 小说 ingest 传入 `NovelRefreshSeed(fid/tid/typeid/tagName)` 并刷新章节。
- [ ] 取消收藏时从漫画/小说 shelf 表移除，但不静默删除作品数据、阅读进度、缓存或下载存储。

### 五、收藏页 UI
- [ ] 主 Tab 顺序为：论坛、收藏、漫画、小说、更多。
- [ ] 收藏页复用 `UnifiedShelfPage`。
- [ ] 收藏页默认列表显示。
- [ ] 收藏页首次进入且无 sync state 时自动同步一次。
- [ ] 收藏页系统分类为“漫画”“小说”“默认”。
- [ ] 默认分类不包含漫画/小说。
- [ ] 自定义分类可覆盖系统分类。
- [ ] 点击漫画收藏进入漫画详情页。
- [ ] 点击小说收藏进入小说详情页。
- [ ] 点击普通论坛收藏进入帖子详情页。

### 六、论坛版块收藏入口
- [ ] `ForumHomeRepository` 登录态请求 `myfavforum`。
- [ ] `ForumHomeController` 在有版块收藏时构造“我收藏的版块”分组。
- [ ] `ForumHomePage` 不展示“暂无收藏版块”旧空态。
- [ ] `myfavforum` 失败不影响论坛首页基础分组加载。

### 七、测试覆盖（仅编写，未执行）
- [ ] `favorite_models_test.dart` 覆盖 `FavoriteThreadsPage` 解析。
- [ ] `favorite_phase3_db_migration_test.dart` 覆盖 v11 表和索引。
- [ ] `local_favorite_repository_test.dart` 覆盖系统分类、默认排除漫画/小说、自定义分类覆盖、removed 标记。
- [ ] `favorite_sync_service_test.dart` 覆盖首次全量同步、漫画/小说 ingest、count 减少完整 diff、详情失败不阻塞后续记录。
- [ ] `favorite_shelf_adapter_test.dart` 覆盖默认模块、列表显示和首次同步。
- [ ] `favorite_shelf_page_test.dart` 覆盖收藏页薄壳构建。
- [ ] 论坛首页测试已更新为“有收藏时展示收藏版块”。
- [ ] 主壳测试已覆盖收藏 Tab。

### 八、待你本地回归
1. `flutter test`
2. `flutter analyze`

说明：`dart format` 按本轮要求未执行，也不作为本轮回归项。

---

## 分阶段实现 06：更多页数据与存储 Review 清单（2026-05-10）

### 一、更多页入口
- [ ] `MorePage` 不再出现 `more-cache-settings-entry`。
- [ ] `MorePage` 出现 `more-data-storage-entry`。
- [ ] 入口文案为“数据与存储 / 管理图片缓存与下载位置”。
- [ ] 点击入口进入 `DataStoragePage`。

### 二、图片缓存管理
- [ ] 页面展示当前图片缓存占用。
- [ ] `清除` 操作调用 `ImageCacheService.clearUnprotected()`。
- [ ] 清除图片缓存不删除封面、作品信息、标签、阅读状态和下载文件。
- [ ] 图片缓存上限写入 `AppStorageKeys.imageCacheMaxBytes`。
- [ ] 上限范围保持 128 MB 到 2048 MB，默认 512 MB。
- [ ] 调整上限后调用 `pruneToLimit()`。

### 三、下载存储位置
- [ ] 自定义下载目录写入 `AppStorageKeys.downloadStorageDirectory`。
- [ ] 旧 `comic_cache_dir` 不作为下载存储目录复用。
- [ ] 选择目录后调用 `DownloadStorageService.prepareRoot()`。
- [ ] 恢复默认后调用 `DownloadStorageService.prepareRoot()`。
- [ ] `prepareRoot()` 创建根目录 `.nomedia`、`comics/.nomedia`、`novels/.nomedia` 和 `favorites.json`。
- [ ] 恢复默认只清除自定义目录偏好，不删除旧自定义目录。

### 四、架构边界
- [ ] `DataStorageSettingsRepository` 不直接创建下载目录结构。
- [ ] More 页面不直接操作文件系统。
- [ ] 下载目录结构只由 `DownloadStorageService` 初始化。
- [ ] `cache_settings_*` 旧文件只作为 deprecated 兼容层，不保留旧缓存目录写入逻辑。

### 五、测试覆盖（仅编写，未执行）
- [ ] `more_page_test.dart` 覆盖入口替换。
- [ ] `cache_settings_controller_test.dart` 覆盖选择目录、恢复默认、清缓存、上限写入和真实目录结构初始化。
- [ ] `cache_settings_page_test.dart` 覆盖页面路径展示、提示文案和容量单位格式。

### 六、待你本地回归
1. `flutter test`
2. `flutter analyze`

说明：`dart format` 按本轮要求未执行，也不作为本轮回归项。

---

## UnifiedShelf 下拉刷新 Review 记录（2026-05-04）
### Review 范围
- `lib/features/library_shared/presentation/pages/unified_shelf_page.dart`
- `test/features/library_shared/presentation/pages/unified_shelf_page_test.dart`

### 核对结论
1. 问题定位正确：刷新手势未稳定进入内层网格/列表滚动通知链。
2. 修复方式合理：
- `RefreshIndicator.notificationPredicate` 放宽为垂直滚动通知；
- 内聚 `_handlePullToRefresh`，避免重复逻辑散落。
3. 可维护性：
- 刷新策略集中在统一页，不影响 adapter/controller 边界；
- 测试新增覆盖“下拉动作 -> refreshShelf 调用”链路。

### 风险与后续
1. 若后续引入新的垂直滚动子树（如嵌套弹层列表），可进一步按 key/上下文细化 predicate。

### 执行说明
本轮按约定未执行：
1. `flutter test`
2. `flutter analyze`

---

## 书架/详情统一抽象 Phase 7 Review 记录（2026-05-04）
### Review 范围
- `lib/features/library_shared/presentation/controllers/unified_shelf_controller.dart`
- `lib/features/library_shared/presentation/pages/unified_shelf_page.dart`
- `lib/features/library_shared/presentation/pages/unified_detail_page.dart`
- `lib/features/comic/data/local/comic_local_db.dart`
- `test/features/library_shared/presentation/controllers/unified_shelf_controller_test.dart`
- `test/features/library_shared/presentation/pages/unified_shelf_page_test.dart`
- `test/features/library_shared/presentation/pages/unified_detail_page_test.dart`
- `test/features/library_shared/data/library_state_phase1_db_migration_test.dart`

### 核对结论
1. 性能优化达成
- 搜索路径已加入防抖，避免每次输入字符都触发全量 reload。
- 网格/列表的虚拟化参数已显式设置，提升大数据量滚动稳定性。
- 章节列表的 keepAlive/semantic 参数做了轻量化处理。

2. 数据层索引增强达成
- 数据库版本升级并新增阶段7索引。
- 迁移测试已补充新索引断言，避免未来回归误删。

3. 测试覆盖增强
- 控制器新增防抖行为测试。
- 书架页面新增虚拟化参数测试。
- 详情页面补充章节长按动作入口测试。

### 风险与后续
1. 当前防抖阈值固定为 250ms，后续可按真实设备与书架规模调优。
2. `cacheExtent` 当前使用常量 900，后续可根据卡片尺寸和设备密度做自适应。

### 执行声明
本轮按约定未执行：
1. `flutter test`
2. `flutter analyze`
---

## 漫画解析与书架问题修复 Phase 1-3 Review 清单（2026-05-14）

### 一、URL 规范化
- [ ] `SiteUrlResolver.resolve()` 将 `http://data/attachment/...` 改写为站内附件 URL。
- [ ] `https://data/attachment/...` 同样被兼容。
- [ ] 正常第三方绝对 URL 不被改写。
- [ ] query 和 fragment 在改写后仍保留。

### 二、附件图片模型
- [ ] `ThreadPost` 保留 `attachmentImages`，默认空列表，不破坏旧构造。
- [ ] `ThreadPost.fromJson` 能解析 Discuz `attachments` map。
- [ ] 非图片附件不会进入 `attachmentImages`。
- [ ] `attachimg == '1'`、`ext` 白名单、附件路径扩展名三种图片判断路径均被覆盖。

### 三、图片来源服务
- [ ] `ForumAttachmentImageExtractor` 只负责附件 URL 拼接、规范化、去重。
- [ ] `ForumPostImageSourceCollector` 统一合并 DOM 图片和附件图片。
- [ ] 合并顺序保持 DOM 图片在前、附件图片在后。
- [ ] 重复 URL 只保留第一次出现。

### 四、漫画解析入口
- [ ] `ComicParserService.parseInput()` 是新的上下文解析入口。
- [ ] `parse(message:)` 保留兼容，并委托到 `parseInput()`。
- [ ] `HtmlComicParserService` debug signal 能区分 DOM 图片数、附件图片数、最终接受图片数。
- [ ] 详情页加入书架走 `parseInput()`。
- [ ] 收藏同步入库走 `parseInput()`。
- [ ] 阅读器缺图补拉走 `parseInput()`。
- [ ] 连续楼主楼层解析使用统一图片来源收集器。

### 五、附件主导楼层
- [ ] 楼主二楼只有附件图片时，也能被识别为图片主导楼层。
- [ ] 首楼 message 为空但附件图片存在时，漫画解析不会被短路为空。

### 六、测试覆盖（仅编写，未执行）
- [ ] `site_url_resolver_test.dart` 覆盖伪绝对附件 URL。
- [ ] `forum_post_dom_extractor_test.dart` 覆盖 sinaimg `<img>`。
- [ ] `thread_detail_models_test.dart` 覆盖 attachments 解析。
- [ ] `forum_attachment_image_extractor_test.dart` 覆盖附件图片提取。
- [ ] `forum_post_image_source_collector_test.dart` 覆盖图片来源合并。
- [ ] `comic_parser_service_test.dart` 覆盖 `parseInput()`。
- [ ] `comic_post_aggregation_service_test.dart` 覆盖附件楼层聚合。
- [ ] `comic_consecutive_op_post_parser_test.dart` 覆盖连续楼主附件图片。

### 七、待本地回归
1. `flutter test`
2. `flutter analyze`

说明：`dart format` 按本轮要求未执行。

---

## 漫画解析与书架问题修复 Phase 6 Review 清单（2026-05-14）

### 一、分类头背景
- [ ] `FixedSlotPagerHeader` 自身提供不透明 `Material` 背景。
- [ ] 背景色使用 `Theme.of(context).colorScheme.surface`。
- [ ] 空 tab 场景仍保持不透明 56 高度占位。
- [ ] 原有固定 4 槽位宽度、超过 4 项横向滚动和指示器逻辑不变。

### 二、列表模式无封面行为
- [ ] `_WorkList` 只在存在封面来源时构建 `leading`。
- [ ] 封面来源包含 `customCoverLocalPath`、`coverLocalPath`、`customCoverImageUrl`、`coverImageUrl`。
- [ ] 完全无封面来源时不显示 `Icons.image_not_supported_outlined`。
- [ ] 有封面来源但加载失败的场景仍可由图片组件显示错误兜底。
- [ ] 网格模式保持原有卡片封面兜底行为。

### 三、测试覆盖（仅编写，未执行）
- [ ] `fixed_slot_pager_header_test.dart` 覆盖 header surface 背景。
- [ ] `unified_shelf_page_test.dart` 覆盖列表无封面不渲染占位图标。
- [ ] `unified_shelf_page_test.dart` 覆盖列表有封面来源时仍渲染 leading 封面。

### 四、待本地回归
1. `flutter test`
2. `flutter analyze`

说明：`dart format` 按本轮要求未执行。
