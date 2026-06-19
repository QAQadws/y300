# Yamibo 论坛网络网关 N-3 公共会话数据仓库实施计划

## 范围

N-3 新增公共会话数据仓库，让 API 与 HTML 成功响应中暴露的 `formhash`、登录态、UID、用户名可以统一提取、缓存和复用。目标是把 `formhash/profile` 从页面渲染链路和高频动作链路中逐步解耦，同时保持现有 API 行为兼容。

本阶段不删除 `profile`、`forumindex` 或现有 `ProfileRepository`；它们仍是 session 刷新 fallback 和后续 `YamiboApiClient` 迁移资产。

## 非目标

- 不把 `ApiClient` 传输层完整迁到 `YamiboHttpGateway`，N-4 再处理。
- 不迁移搜索、回复、发帖、收藏等直接 `Dio` HTML/form 请求，N-5 再处理。
- 不改变小说 API `version=1` 约束。
- 不把 session store 持久化到磁盘；N-3 先做内存快照，避免把用户标识类数据长期写入本地。

## 设计

### Core 类型

新增 `lib/core/network/yamibo/`：

- `YamiboSessionSnapshot`：记录 `isLoggedIn`、`uid`、`username`、`formhash`、`updatedAt`、`source`。
- `YamiboSessionStore`：内存保存当前 snapshot，提供 `readCurrent()`、`saveExtracted()`、`readFreshFormhash()`、`clear()`。
- `YamiboSessionExtractor`：从 Discuz API variables 和 HTML 文本中提取 session 线索。

默认 formhash freshness 为 30 分钟。空 `formhash` 不覆盖旧有效值；登录态和用户名为空时也尽量保留旧值，避免 HTML 页面缺字段导致 session 倒退。

### 网关接入

- `YamiboHttpGateway` 在 `getText` 成功后调用 HTML extractor，来源使用 `html:<operation>`。
- `ApiClient` 在 Discuz API 成功解析后调用 API extractor，来源使用 `api:<module>`。
- `network_providers.dart` 新增 `yamiboSessionStoreProvider`、`yamiboSessionExtractorProvider`，并注入到 `ApiClient` 与 `YamiboHttpGateway`。

### formhash 读取

`ApiFormhashProvider` 改为依赖 `YamiboSessionStore`：

1. 优先读取未过期 formhash。
2. 如果缺失或过期，再按原有策略请求 `forumindex/profile`。
3. fallback 请求成功后，`ApiClient` 会提取并写入 store；provider 仍从 response 中读取 formhash 返回，保持旧语义。

### 登出清理

`ApiAuthRepository.logout()` 在远端登出成功后同时清空 `CookieStore` 与 `YamiboSessionStore`。为减少耦合，`ApiAuthRepository` 构造参数新增可选 `YamiboSessionStore`，provider 注入默认 store。

## 测试计划

- 新增 `yamibo_session_extractor_test.dart`：
  - API variables 提取 formhash、uid、username、登录态。
  - HTML hidden input 提取 formhash。
  - HTML script 中 `discuz_uid` 提取登录态。
- 新增 `yamibo_session_store_test.dart`：
  - 保存有效 snapshot。
  - 空 formhash 不覆盖旧有效 formhash。
  - fresh formhash 在 30 分钟内返回，过期后返回 null。
  - `clear()` 清空状态。
- 补充 `yamibo_http_gateway_test.dart` 或新增测试，覆盖 HTML 成功后写入 session store。
- 补充 `auth_repository_test.dart`，覆盖 formhash provider 优先使用 store、登出清空 store。

## 验收点

- 首页 HTML 响应如果包含 session 线索，会更新公共 session snapshot。
- API 响应中的 `formhash/member_uid/member_username/auth` 会更新公共 session snapshot。
- 登录、登出、收藏、回复等现有行为保持兼容。
- 缓存命中时获取 formhash 不再额外请求 `forumindex/profile`。
- API 可以暂时不被页面调用，但不能删除；后续继续迁移进 `YamiboApiClient` / Dart 网络库。
