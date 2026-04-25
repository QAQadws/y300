# Discuz! X3.5 论坛移动端 App 实施方案（Flutter）

> 目标：基于现有 Discuz! X3.5 论坛的移动接口（`/api/mobile/index.php`）开发 Android/iOS App，先实现可用 MVP，再迭代到稳定版本。

## 0. 项目总览

### 0.1 你当前已有条件
- 后端：Discuz! X3.5（已有移动 API）
- 前端框架：Flutter（当前仓库已是 Flutter 工程）
- 已知接口样例：
  - 论坛主页：`?module=forumindex&version=4`
  - 个人页面：`?module=profile&version=4`
  - 收藏板块：`?module=myfavforum&version=4`
  - 收藏帖子（分页）：`?module=myfavthread&version=4&page=1`
  - 帖子详情（分页）：`?module=viewthread&tid=570140&page=1`

### 0.2 推荐开发策略
采用 **3 阶段推进**：
1. **MVP（2~3 周）**：游客浏览 + 登录 + 首页/帖子详情 + 收藏列表只读。
2. **Beta（2~4 周）**：发帖/回帖、消息提醒、图片缓存、错误重试。
3. **Release（1~2 周）**：性能优化、埋点、崩溃监控、上架准备。

---

## 1. 先做技术验证（第 1-2 天）

先别急着写 UI，先验证接口可用性和登录态，否则后面会返工。

### 1.1 要验证的内容
1. 接口返回字段是否稳定（同一接口多次请求字段是否一致）。
2. 未登录/已登录时返回结构差异。
3. 分页字段规则：`page` 从 1 开始还是 0；是否有 `has_more` 类字段。
4. 编码与特殊字符：标题、用户名、表情符号是否正常。
5. 错误码格式：失败时是 `message`、`error` 还是别的结构。

### 1.2 产出物
- 一份接口对照表（建议写到 `docs/解析.md` 或新建 API 文档）。
- 固定示例 JSON（每个接口至少 1 份成功 + 1 份失败样例）。

---

## 2. 目标架构（Flutter）

建议采用 **分层 + 状态管理**，避免后期功能一多就混乱。

### 2.1 目录建议

```text
lib/
  core/
    network/
      api_client.dart
      api_result.dart
      cookie_store.dart
    config/
      app_config.dart
    utils/
      time_utils.dart
      html_utils.dart
  features/
    forum/
      data/
        models/
        forum_repository.dart
      presentation/
        forum_home_page.dart
        thread_detail_page.dart
    profile/
      data/
      presentation/
    favorites/
      data/
      presentation/
    auth/
      data/
      presentation/
  shared/
    widgets/
    theme/
  main.dart
```

### 2.2 推荐依赖
- 网络：`dio`
- JSON：`json_annotation`和`json_serializable`和`build_runner`
- 状态管理：`riverpod`
- 本地存储：`shared_preferences`（轻量）/ `hive`（结构化缓存）
- 图片缓存：`cached_network_image`
- 日志：`logger`

---

## 3. 接口设计与封装

统一 API 基础地址：
- `https://bbs.yamibo.com/api/mobile/index.php`

### 3.1 请求层统一规范

每个请求都通过一个 `ApiClient` 发出，统一处理：
1. 公共参数注入（如 `version=4`）。
2. Cookie 自动带上（登录态依赖）。
3. 超时、重试、错误码映射。
4. 原始响应日志（开发模式）。

### 3.2 响应统一封装

建议统一为：
- `ApiResult.success(data)`
- `ApiResult.failure(code, message, raw)`

不要在 UI 层直接解析 JSON。UI 只拿 ViewModel/State。

### 3.3 本项目首批接口映射

1. `ForumApi.getForumIndex()`
- `module=forumindex&version=4`
- 产出：板块列表、推荐帖子（若有）

2. `ProfileApi.getProfile()`
- `module=profile&version=4`
- 产出：用户信息、头像、积分、权限相关字段

3. `FavoriteApi.getFavForums()`
- `module=myfavforum&version=4`
- 产出：收藏板块列表

4. `FavoriteApi.getFavThreads(page)`
- `module=myfavthread&version=4&page={page}`
- 产出：收藏帖子列表 + 分页信息

5. `ThreadApi.getThreadDetail(tid, page)`
- `module=viewthread&tid={tid}&page={page}`
- 产出：主楼 + 回帖 + 分页

---

## 4. 登录态与鉴权（关键）

Discuz 移动接口通常依赖 Cookie / formhash / authkey 等机制之一。这里要先跑通。

### 4.1 登录阶段要做的事
1. 确定登录入口：
- 是否存在 `module=login`（常见）
- 或需走网页登录后拿 Cookie

2. 确定登录成功判定：
- 响应里用户字段变化
- `profile` 接口可访问且返回当前用户

3. 持久化会话：
- 保存 Cookie 到本地
- App 重启后自动恢复

### 4.2 安全建议
- 本地存储敏感信息时尽量用 `flutter_secure_storage`。
- 退出登录要清 Cookie + 本地用户缓存。

---

## 5. 页面拆分与迭代顺序

按“先核心浏览，再用户能力”的顺序：

### 第 1 批（MVP）
1. 启动页/骨架页
2. 论坛首页（板块 + 列表）
3. 帖子详情页（支持分页）
4. 登录页
5. 我的页面（调用 `profile`）
6. 我的收藏（板块 + 帖子）

### 第 2 批（增强）
1. 回帖
2. 发帖
3. 下拉刷新 + 上拉加载更多
4. 错误态空态页
5. 搜索（若接口支持）

### 第 3 批（体验优化）
1. 深色模式/主题切换
2. 图片预加载与弱网降级
3. 离线缓存（最近浏览帖子）

---

## 6. 分页、缓存、错误处理策略

### 6.1 分页策略
- `page` 从 1 开始。
- 维护状态：`currentPage`、`isLoading`、`hasMore`。
- 对重复请求做节流（防止连续触底触发多次）。

### 6.2 缓存策略
- 首页/帖子详情：内存 + 磁盘缓存（短 TTL，如 5~15 分钟）。
- 用户隐私数据：不做长期明文缓存。

### 6.3 错误处理
统一错误类型：
1. 网络错误（超时、断网）
2. 服务端错误（500/网关）
3. 业务错误（未登录、权限不足）
4. 数据解析错误（字段缺失/类型变化）

UI 层对应四类文案，且支持“点击重试”。

---

## 7. 详细开发任务分解（可直接当待办）

### 7.1 基础设施
1. 新建 `ApiClient`（Dio + 拦截器 + Cookie 管理）。
2. 建立 `ApiResult` 与统一异常模型。
3. 接入日志与全局错误捕获。

### 7.2 数据层
1. 为 5 个核心接口建立 Model（先手写，后续再自动生成）。
2. 建立 Repository，把 JSON 转成领域对象。
3. 为每个接口补 1~2 个单元测试（解析稳定性）。

### 7.3 UI 层
1. 首页：列表渲染 + 点击跳详情。
2. 帖子详情：主楼与回帖渲染 + 翻页。
3. 我的：显示 profile。
4. 收藏：板块/帖子双 Tab。

### 7.4 登录
1. 打通登录接口或网页登录桥接。
2. 启动时恢复会话。
3. 退出登录清理。

### 7.5 质量保障
1. API 失败场景手工测试。
2. 分页边界（最后一页、空页）测试。
3. Crash 收集（建议 Firebase Crashlytics）。

---

## 8. 里程碑与验收标准

### Milestone A（MVP）
验收条件：
1. 未登录可浏览首页与帖子详情。
2. 登录后可访问 `profile` 和收藏接口。
3. 收藏帖子分页可持续加载。
4. 崩溃率可控（核心路径无明显崩溃）。

### Milestone B（Beta）
验收条件：
1. 网络波动时可重试，状态提示明确。
2. 页面首屏性能可接受（常用机型 < 2s）。
3. 关键交互（翻页、返回、刷新）流畅。

### Milestone C（Release）
验收条件：
1. 隐私政策、用户协议、备案信息完善。
2. Android/iOS 打包签名与发布流程打通。
3. 上架素材齐备（截图、描述、关键词）。

---

## 9. 你现在可以立刻执行的下一步（建议顺序）

1. 先用 Postman/脚本把 5 个接口样例 JSON 固定下来。
2. 在 Flutter 中先写 `ApiClient` + `forumindex` 请求并渲染一个简单列表。
3. 打通 `viewthread`（含 `page` 翻页）后，再接入登录态。
4. 登录成功后接 `profile`、`myfavforum`、`myfavthread`。
5. 最后再做 UI 美化和缓存优化。

---

## 10. 风险清单（提前规避）

1. Discuz 字段不稳定：
- 解析时给可空字段和兜底值，避免强转崩溃。

2. 登录态复杂：
- 优先确认 Cookie 机制；必要时先实现“网页登录后同步 Cookie”的过渡方案。

3. HTML 内容渲染复杂：
- 帖子正文可能包含富文本，先用基础渲染，后续再增强（如图片点击预览、引用样式）。

4. 接口限流或防护：
- 控制请求频率，必要时加本地缓存与请求去重。

---

## 11. 推荐最小可用时间线（示例）

- 第 1 周：接口验证 + 网络层 + 首页/详情只读。
- 第 2 周：登录态 + 个人页 + 收藏页。
- 第 3 周：分页优化 + 缓存 + 错误态。
- 第 4 周：测试修复 + 打包发布准备。

如果你是单人开发，上述计划比较稳妥；如果多人并行，可以把“网络层/数据层”和“UI层”分开推进。

---

## 12. 附：接口清单（当前已知）

- 论坛主页：
  - `https://bbs.yamibo.com/api/mobile/index.php?module=forumindex&version=4`
- 个人页面：
  - `https://bbs.yamibo.com/api/mobile/index.php?module=profile&version=4`
- 收藏的板块：
  - `https://bbs.yamibo.com/api/mobile/index.php?module=myfavforum&version=4`
- 收藏帖子（分页）：
  - `https://bbs.yamibo.com/api/mobile/index.php?module=myfavthread&version=4&page=1`
- 帖子详情（分页）：
  - `https://bbs.yamibo.com/api/mobile/index.php?module=viewthread&tid=570140&page=1`

> 后续你可以把新增接口继续补到这份文档里，保持“接口 -> Model -> 页面 -> 测试”四项同步更新，项目会非常稳。
