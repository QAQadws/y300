# 接口封装 Review 文档

## 1. 目标与使用方式

这份文档用于审查本次网络层与接口仓库实现，重点关注：

1. 架构是否解耦、可维护
2. 行为是否符合 Discuz 接口特性
3. 错误处理与 Cookie 会话是否可靠
4. 分页与解析是否有边界问题

建议审查顺序：

1. 先看核心网络层
2. 再看 feature 仓库
3. 最后看模型解析与分页逻辑

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
2. ApiClient 是否只负责网络通用能力，不包含业务字段映射
3. 各 feature 的模型是否仅描述本 feature 需要的数据
4. Provider 注入是否统一且无循环依赖

判定标准：

1. 若业务解析逻辑散落在 UI 层，判定为 P1
2. 若网络层与业务层耦合导致难以替换实现，判定为 P1

## 3.2 请求规范与通用参数

1. 是否统一注入 module 与 version 参数
2. Base URL、超时等是否集中在配置层
3. 日志输出是否可控，且不影响线上稳定性

判定标准：

1. 参数注入缺失或覆盖异常导致请求错误，判定为 P0
2. 配置散落多处难维护，判定为 P2

## 3.3 Cookie 与会话

1. 请求前是否自动读取并注入 Cookie
2. 响应后是否自动保存 set-cookie
3. Cookie 读写失败时是否有安全降级，不会导致崩溃
4. 退出登录是否可清理会话

判定标准：

1. Cookie 丢失导致登录态无法维持，判定为 P0
2. 本地会话残留但不影响主流程，判定为 P1

## 3.4 错误模型与异常映射

1. 是否统一返回 ApiResult，不向上抛裸异常
2. 超时、网络错误、服务端错误、业务错误是否能区分
3. Discuz Message 业务错误是否正确识别
4. 解析错误是否能定位到具体上下文

判定标准：

1. 错误无法分类导致 UI 无法正确提示，判定为 P1
2. 发生异常直接崩溃，判定为 P0

## 3.5 模型解析鲁棒性

1. 字段缺失、空值、类型变化时是否有兜底
2. 数值字符串转 int 是否可控
3. list 与 map 的非预期类型是否被安全处理
4. 仅保留必要字段，避免过度耦合后端完整结构

判定标准：

1. 常见字段缺失即可崩溃，判定为 P0
2. 解析不崩溃但值不准确，判定为 P1

## 3.6 分页与边界

1. 收藏分页与帖子分页是否从 page=1 开始
2. hasMore 计算逻辑在最后一页是否准确
3. 空列表、count=0、perPage 缺失时行为是否合理

判定标准：

1. 分页死循环或提前停止，判定为 P1
2. 仅展示文案不准确，判定为 P2

## 3.7 可测试性与可维护性

1. Repository 是否便于 Mock ApiClient 进行单测
2. 关键逻辑是否可在无 UI 环境下验证
3. 文件命名、目录职责是否清晰
4. 新增接口是否可按同一模式快速扩展

判定标准：

1. 无法隔离测试关键逻辑，判定为 P1
2. 结构清晰但缺少测试用例，判定为 P2

---

## 4. 建议执行的验证步骤

1. 运行静态检查：flutter analyze
2. 针对 5 个核心接口准备固定 JSON 样例（成功/失败各一份）
3. 对每个 Repository 至少验证三类输入：
   1. 正常数据
   2. 缺字段数据
   3. 异常类型数据
4. 验证登录态流程：首次请求、重启后请求、logout 后请求

---

## 5. 问题分级标准

1. P0：会导致崩溃、核心流程不可用、登录态不可用
2. P1：功能可用但行为不正确，或边界情况明显异常
3. P2：可维护性、可读性、扩展性问题，不影响当前主流程

---

## 6. Review 结论模板（可直接填写）

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

---

## 7. 本次实现重点关注项（建议优先看）

1. ApiClient 请求拦截与错误映射
2. CookieStore 的持久化与读取策略
3. ThreadDetailData 与 FavoriteThreadsPage 的 hasMore 逻辑
4. ParseUtils 在字段漂移场景的兜底能力
