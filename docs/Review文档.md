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
