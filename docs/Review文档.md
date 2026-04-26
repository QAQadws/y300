# 接口封装 Review 文档

## 1. 目标与使用方式

这份文档用于审查“登录态与鉴权（关键）”本次落地实现，重点关注：

1. 是否完成真实网页登录，而不是仅调用移动接口探活
2. Cookie 会话是否可持久化并自动注入后续请求
3. 登录成功后是否进行了二次会话校验（profile）
4. 错误模型是否可被 UI 稳定消费
5. 测试是否覆盖关键成功/失败路径

建议审查顺序：

1. 先看核心网络层（ApiClient）
2. 再看鉴权仓库（AuthRepository）
3. 最后看单元测试（auth_repository_test.dart）

---

## 2. 审查范围（文件索引）

### 核心网络层

1. [lib/core/config/app_config.dart](../lib/core/config/app_config.dart)
2. [lib/core/utils/parse_utils.dart](../lib/core/utils/parse_utils.dart)
3. [lib/core/network/api_result.dart](../lib/core/network/api_result.dart)
4. [lib/core/network/discuz_response.dart](../lib/core/network/discuz_response.dart)
5. [lib/core/network/cookie_store.dart](../lib/core/network/cookie_store.dart)
6. [lib/core/network/api_client.dart](../lib/core/network/api_client.dart)
7. [lib/core/network/network_providers.dart](../lib/core/network/network_providers.dart)

### 仓库与模型层

1. [lib/features/forum/data/forum_repository.dart](../lib/features/forum/data/forum_repository.dart)
2. [lib/features/forum/data/models/forum_index_models.dart](../lib/features/forum/data/models/forum_index_models.dart)
3. [lib/features/profile/data/profile_repository.dart](../lib/features/profile/data/profile_repository.dart)
4. [lib/features/profile/data/models/profile_models.dart](../lib/features/profile/data/models/profile_models.dart)
5. [lib/features/favorites/data/favorite_repository.dart](../lib/features/favorites/data/favorite_repository.dart)
6. [lib/features/favorites/data/models/favorite_models.dart](../lib/features/favorites/data/models/favorite_models.dart)
7. [lib/features/thread/data/thread_repository.dart](../lib/features/thread/data/thread_repository.dart)
8. [lib/features/thread/data/models/thread_detail_models.dart](../lib/features/thread/data/models/thread_detail_models.dart)
9. [lib/features/auth/data/auth_repository.dart](../lib/features/auth/data/auth_repository.dart)

### 相关文档

1. [docs/解析.md](解析.md)
2. [docs/开发文档.md](开发文档.md)

---

## 3. 审查清单（Checklist）

## 3.1 架构与分层

1. UI 层是否可以完全通过 Repository 使用接口，而无需依赖 Dio
### 2.1 核心网络层
3. 各 feature 的模型是否仅描述本 feature 需要的数据
4. Provider 注入是否统一且无循环依赖
2. [lib/core/network/cookie_store.dart](../lib/core/network/cookie_store.dart)
3. [lib/core/network/api_result.dart](../lib/core/network/api_result.dart)
4. [lib/core/network/api_client.dart](../lib/core/network/api_client.dart)
## 3.2 请求规范与通用参数
### 2.2 仓库层
1. 是否统一注入 module 与 version 参数
1. [lib/features/auth/data/auth_repository.dart](../lib/features/auth/data/auth_repository.dart)

### 2.3 测试与文档
2. 响应后是否自动保存 set-cookie
1. [test/features/auth/auth_repository_test.dart](../test/features/auth/auth_repository_test.dart)
2. [docs/开发文档.md](开发文档.md)
3. [docs/Discuz-X3.5移动端App实现方案.md](Discuz-X3.5移动端App实现方案.md)

判定标准：

1. Cookie 丢失导致登录态无法维持，判定为 P0
2. 本地会话残留但不影响主流程，判定为 P1
## 3.1 网页登录链路
## 3.4 错误模型与异常映射
1. 是否存在 GET 登录页请求：`member.php?mod=logging&action=login&mobile=2`
2. 是否从登录页提取 `formhash/loginhash`
3. 是否存在 POST 登录提交并携带 `loginsubmit=yes`
4. 登录成功判定是否基于响应体而非仅 HTTP 200
4. 解析错误是否能定位到具体上下文

判定标准：
1. 缺少任一关键步骤导致无法建立真实会话，判定为 P0
2. 参数提取脆弱导致频繁误判登录失败，判定为 P1
2. 发生异常直接崩溃，判定为 P0
## 3.2 Cookie 与会话维持
## 3.5 模型解析鲁棒性
1. GET 登录页返回的 `set-cookie` 是否被持久化
2. POST 登录返回的 `set-cookie` 是否被持久化
3. 后续 `profile` 请求是否自动携带 Cookie
4. `logout()` 是否清理本地 Cookie
3. list 与 map 的非预期类型是否被安全处理
4. 仅保留必要字段，避免过度耦合后端完整结构

1. 登录后请求未带 Cookie，判定为 P0
2. 退出后 Cookie 残留，判定为 P1
1. 常见字段缺失即可崩溃，判定为 P0
## 3.3 登录后会话校验

1. `AuthRepository.login` 是否在网页登录成功后调用 `refreshSession()`
2. `SessionInfo.isLoggedIn` 判定是否依赖 `member_uid != 0`
3. 网页登录成功但会话未生效时，是否返回 `ApiErrorType.unauthorized`
3. 空列表、count=0、perPage 缺失时行为是否合理

判定标准：
1. 登录流程不做二次校验，判定为 P1
2. 二次校验失败仍返回成功，判定为 P0
2. 仅展示文案不准确，判定为 P2
## 3.4 错误模型与可观测性
## 3.7 可测试性与可维护性
1. 所有登录路径是否统一返回 `ApiResult`
2. 参数提取失败是否映射为 `ApiErrorType.parse`
3. 用户名/密码错误是否映射为 `ApiErrorType.business`
4. 网络异常是否保留原始上下文便于排查
4. 新增接口是否可按同一模式快速扩展

判定标准：
1. 错误类型不准确导致 UI 无法提示，判定为 P1
2. 发生异常向上抛出导致崩溃，判定为 P0
2. 结构清晰但缺少测试用例，判定为 P2
## 3.5 测试完整性
---
1. 是否包含“登录成功”用例
2. 是否包含“登录失败”用例
3. 是否包含“网页登录成功但会话未生效”用例
4. 是否包含“logout 清 Cookie”用例
2. 针对 5 个核心接口准备固定 JSON 样例（成功/失败各一份）
3. 对每个 Repository 至少验证三类输入：
   1. 正常数据
1. 缺任意一个关键场景，判定为 P1
2. 测试无法稳定复现行为，判定为 P1
4. 验证登录态流程：首次请求、重启后请求、logout 后请求
---

## 4. 你可以直接执行的 Review 步骤

1. 代码审查（静态）：
   - 按第 2 节文件顺序，逐项对照第 3 节清单打勾。
2. 本地自动化验证：

```bash
flutter test test/features/auth/auth_repository_test.dart
flutter analyze
```

3. 预期结果：
   - 测试输出包含 `All tests passed!`
   - 分析输出 `No issues found!`

4. 手工冒烟（可选，真机/模拟器）：
   - 输入正确账号密码，确认可登录并拉取个人信息。
   - 退出后再次请求 `profile`，应进入未登录态。

---

## 5. 测试说明（供 Review 时对照）

测试文件：

1. [test/features/auth/auth_repository_test.dart](../test/features/auth/auth_repository_test.dart)

覆盖说明：

1. `login success`: 验证登录成功、会话成功、Cookie 注入
2. `login failed on web form`: 验证业务错误透传
3. `web login success but profile uid is 0`: 验证二次校验拦截
4. `logout should clear persisted cookies`: 验证登出清理会话

若你要扩展测试，建议优先加：

1. 登录页缺失 `formhash/loginhash`
2. 登录返回非预期 HTML 结构
3. 网络超时和 5xx 场景

---

## 6. 问题分级标准
---
1. P0：登录不可用、登录后无会话、崩溃
2. P1：可登录但状态判定错误、错误类型不准确、关键测试缺失
3. P2：文档与可维护性问题，不影响当前主流程
1. P0：会导致崩溃、核心流程不可用、登录态不可用
---
3. P2：可维护性、可读性、扩展性问题，不影响当前主流程
## 7. Review 结论模板（可直接填写）

结论摘要：

1. 总体评价：通过 / 有条件通过 / 不通过
2. 主要风险：
3. 建议修复优先级：

发现列表：

| 编号 | 等级 | 文件 | 问题描述 | 复现步骤 | 建议修复 |
|---|---|---|---|---|---|
| 1 | P0/P1/P2 | 路径 | 描述 | 步骤 | 建议 |
| 2 | P0/P1/P2 | 路径 | 描述 | 步骤 | 建议 |

回归验证记录：

1. 已验证项：
2. 未验证项：
3. 阻塞项：
