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

## 4. forumdisplay 页面检查

- [ ] 未登录时首页仅展示 forumindex 分组
- [ ] 已登录时首页优先展示“我收藏的版块”
- [ ] “我收藏的版块”使用与普通分组一致的 `_ForumCard` 组件
- [ ] myfavforum 失败时首页可降级展示 forumindex，不阻塞主流程
- [ ] 收藏区为空时首页展示空态提示，不出现崩溃

判定说明：

1. 首页登录态顺序错误（收藏区未置顶），判定为 P1。
2. myfavforum 失败导致首页不可用，判定为 P0。

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
- [ ] 首页聚合已使用 `module=myfavforum` 拉取收藏版块
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
- [ ] 登录后首页可见“我收藏的版块”并位于普通分组前
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
- [ ] “更多”页包含：登录、缓存目录、阅读设置占位、关于占位
- [ ] 登录入口仅在“更多”页可见，论坛页不再提供登录按钮

### 二、缓存目录设置页
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
