# Yamibo 论坛网络网关 N-7 内部库稳定与外部 Package 预留实施计划

## 范围

N-7 收束 N-1 到 N-6 已落地的内部 Yamibo 网络库边界，让后续维护者能清楚地区分“可复用网络能力”和“Y300 app 组合/业务能力”。本阶段不拆独立 package，只在仓库内部稳定 public export、provider 边界和抽包说明。

## 非目标

- 不创建新的 Dart package。
- 不改业务 repository 的运行时语义。
- 不迁移新的网络调用链路。
- 不删除 `ApiClient`、旧 repository、provider、模型或测试资产。
- 不把 Riverpod provider、页面 controller、UI 或书架业务模型放进可抽包核心边界。

## 设计

### Public Export

新增 `lib/core/network/yamibo/yamibo.dart` 作为内部 Yamibo 网络库的统一导出入口，导出：

- `YamiboApiClient`
- `YamiboHtmlClient`
- `YamiboHttpGateway`
- `YamiboHttpResponse`
- `YamiboRequestContext`
- `YamiboResourceClient`
- `YamiboSessionExtractor`
- `YamiboSessionSnapshot`
- `YamiboSessionStore`

不导出 `YamiboRequestLogger`，它是网关内部日志实现细节。

### Provider 边界

- Riverpod provider 继续留在 `lib/core/network/network_providers.dart`。
- `core/network/yamibo` 核心类型不依赖 Flutter Widget，也不依赖 Riverpod。
- app 侧依赖组合仍通过 provider 完成，未来抽包时可替换为 package 外部装配。

### Package 预留文档

新增 `docs/网关/Yamibo论坛网络网关内部库边界与抽包预留说明.md`，记录：

- 当前可抽包候选。
- 明确不应抽进 package 的 Y300 app 资产。
- 后续抽包前必须满足的测试和迁移条件。
- API 可以暂时不被页面调用，但不能删除；后续应迁移/沉淀进 `YamiboApiClient` 或独立 Dart 网络库。

## 修改清单

- 新增 `lib/core/network/yamibo/yamibo.dart` barrel export。
- 适度更新 app 层 import，优先让 provider 和兼容 facade 使用统一入口，避免后续新增代码继续散落导入。
- 新增 public export smoke test，确认核心类型可从统一入口导入。
- 更新 `docs/开发文档.md` 顶部，说明 N-7 边界稳定和抽包预留。

## 测试计划

- `flutter analyze`
- `flutter test test\core\network\yamibo\yamibo_public_api_test.dart`
- 视改动范围补跑已有核心网关测试。

## 验收点

- `core/network/yamibo` 有统一 public export。
- provider 仍在 app 装配层，不进入纯核心类型。
- 文档明确 package 候选和非候选边界。
- API 资产保留原则再次写清楚。
- N-1 到 N-7 主方案的阶段性任务全部有计划文档、代码提交和验证记录。
