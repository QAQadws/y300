# Android 基于 Gitee Release 的应用内更新 Phase 0 基线与 ADR

> 状态：采用 `upgrader` 的简化方案基线（2026-07-19）
> 适用范围：Y300 Android arm64-v8a 自分发版本
> 更新源：公开 Gitee Release API，由维护者手工发布 Release
> 运行时方案：`upgrader 13.5.0` + 自定义 `UpgraderStore`
> 非目标：CI 自动发布到 Gitee、App 内下载进度、自建 DownloadManager/MethodChannel、静默安装
> 配套方案：[Android基于Gitee Release的应用内更新分阶段实施方案.md](./Android基于Gitee%20Release的应用内更新分阶段实施方案.md)

## 1. 决策摘要

Y300 不再建设一套完整的自定义更新状态机。版本读取、SemVer 比较、更新提示、稍后提醒、忽略版本和提示间隔交给 `upgrader 13.5.0`；Y300 只实现 Gitee 数据源适配和 APK 外部打开能力。

```text
维护者手工构建并签名 APK
  -> 手工创建 Gitee 正式 Release
  -> 手工上传 arm64 APK 与对应 .apk.sha256
  -> Upgrader 初始化或刷新版本信息
  -> GiteeUpgraderStore 请求公开 latest Release API
  -> Gitee 防腐 parser 验证 Tag 和附件协议
  -> 映射为 UpgraderVersionInfo
  -> Upgrader 判断版本并展示提示
  -> 用户点击“立即更新”
  -> Y300 用外部浏览器/系统应用打开 APK HTTPS URL
  -> Android/浏览器显示下载进度
  -> 用户从系统下载通知或下载列表发起安装
  -> Android 系统安装器校验签名并要求用户确认
```

该方案主动接受以下边界：

- Y300 内部不展示 APK 下载进度，也不恢复下载任务。
- Y300 不在下载后自行计算 SHA-256，不自行解析 APK Manifest 或证书。
- 下载和安装由外部浏览器、系统下载组件与系统安装器承接。
- `.apk.sha256` 是手工发布验收和公开复核制品，不是 App 内运行时信任根。
- 普通 Android App 不能静默安装，最终安装始终需要用户和系统确认。

## 2. 已验证环境与依赖基线

### 2.1 本地工具链

2026-07-19 实测：

```text
Flutter 3.44.4 stable
Dart 3.12.2
```

`upgrader 13.5.0` 的最低约束为 Dart `>=3.5.0 <4.0.0`、Flutter `>=3.27.0`，当前工具链满足要求。

### 2.2 依赖决策

首轮实现固定使用：

```yaml
dependencies:
  upgrader: 13.5.0
```

自定义 `UpgraderStore` 的接口直接使用 `package:version/version.dart` 中的 `Version`。如果 Y300 代码直接导入该类型，应同时把 `version: ^3.0.2` 声明为直接依赖，不能依赖 `upgrader` 的传递依赖。

`upgrader 13.5.0` 内部使用 `package_info_plus` 读取当前安装包版本，允许范围为 `>=4.0.1 <11.0.0`。当前项目执行真实依赖求解时，会选择 `package_info_plus 9.0.1`。

不得在当前依赖图中直接升级到 `package_info_plus 10.2.1`：

```text
package_info_plus 10.2.1 -> win32 ^6.0.1
file_picker 11.0.2      -> win32 ^5.9.0
```

两者当前无法同时求解。处理原则如下：

- 仅由 `upgrader` 读取安装版本时，不额外声明 `package_info_plus`。
- 如果 Y300 自己需要在“更多”页显示当前版本，则声明兼容的直接依赖 `package_info_plus: ^9.0.1`。
- 不为更新功能单独升级 `file_picker` 或强行覆盖 `win32`。
- 未来只有在稳定版 `file_picker` 支持 `win32 6.x` 且文件选择回归测试通过后，才单独升级 `package_info_plus 10.2.1`。

旧 Phase 0 使用的 `pub_semver`、`AppUpdatePolicy`、`AppUpdateDecision` 和 `InstalledAppVersion` 与 `upgrader` 的版本模型重复。接入完成且无其它引用后应删除；Tag 的 canonical 格式校验仍保留在 Gitee parser 中，数值版本比较统一交给 `upgrader` 的 `version` 模型。

## 3. 自托管发布源基线

Y300 使用以下公开 Gitee 仓库：

```text
Repository: QAQadws/y300-releases
Latest API: https://gitee.com/api/v5/repos/QAQadws/y300-releases/releases/latest
Release page: https://gitee.com/QAQadws/y300-releases/releases
```

2026-07-18 实测 latest API 无需 `access_token` 即可返回 `200`。真实响应包含：

- `tag_name`
- `prerelease`
- `name`
- `body`
- `created_at`
- `assets[].name`
- `assets[].browser_download_url`

真实响应不包含根级 `draft`、`published_at`、`html_url` 和附件大小。客户端不得照搬 GitHub Release 模型，也不得按 assets 数组位置选择附件。

脱敏 fixture 位于：

```text
test/features/app_update/fixtures/phase0/gitee_latest_release_v0_0_1.json
```

fixture 不进入 Flutter release assets，不包含凭据，只保存协议相关字段和未知字段样例。

## 4. 手工 Release 协议

### 4.1 版本与 Tag

正式 Tag 严格为：

```text
v{major}.{minor}.{patch}
```

第一版仅接受稳定三段版本，例如 `v0.0.1`。以下形式均拒绝：

```text
0.0.1
v0.0
v00.0.1
v0.0.1-beta
v0.0.1+4
```

Gitee Tag 只承载 `versionName`。Android `versionCode` 保留在 APK Manifest 中，每次正式发布必须同时满足：

```text
new versionName > previous versionName
new versionCode > previous versionCode
```

禁止仅提升 `versionCode` 后复用相同 Tag。错误版只能通过更高 patch 版本和更高 `versionCode` 修复。

### 4.2 附件命名

APK 严格命名为：

```text
y300-v{versionName}-android-arm64-v8a-release.apk
```

同一 Release 手工上传对应 checksum：

```text
y300-v{versionName}-android-arm64-v8a-release.apk.sha256
```

checksum 内容使用 canonical `sha256sum` 单行格式：

```text
{64位小写SHA-256}  {完整APK文件名}
```

摘要与文件名之间固定两个 ASCII 空格，允许文件末尾一个 `LF/CRLF`。源码 `.zip/.tar.gz` 和其它附件不参与更新选择。

`GiteeReleaseParser` 应要求同一正式 Release 中恰好存在一个精确 APK 和一个对应 checksum，以避免用户在手工附件尚未上传完毕时收到提示。但简化客户端不会继续请求 checksum 内容，也不会在下载后比较摘要。checksum 的作用是发布者上传前自检、公开复核和识别未完成 Release，不能代替 APK 签名。

### 4.3 已验证制品

| 项目 | Phase 0 基线 |
| --- | --- |
| APK | `y300-v0.0.1-android-arm64-v8a-release.apk` |
| APK SHA-256 | `fbf38c93718f0709363c2eb26d613030b87d78f984329a87b24a05e79f547077` |
| applicationId | `com.adws.y300` |
| versionName | `0.0.1` |
| versionCode | `4` |
| native ABI | `arm64-v8a` |
| signer certificate SHA-256 | `6c3f720b52f587142c156543b20208de775372928201b590758bb4be6f7c8d68` |
| APK signature | v2 verified，single signer |

后续 Release 必须继续使用同一份 JKS。即使 Y300 不再自行校验证书，Android 覆盖安装仍要求新旧 APK 使用兼容签名。

## 5. 运行时架构

### 5.1 为什么使用自定义 UpgraderStore

`UpgraderAppcastStore` 可以支持自托管，但需要一个地址稳定的 Appcast XML。Y300 已经有 Gitee latest JSON；再手工维护 Appcast 会形成第二份版本元数据，容易出现 Release 与 XML 不一致。

因此采用：

```text
Gitee latest JSON
  -> GiteeReleaseDto
  -> GiteeReleaseParser
  -> GiteeReleaseCandidate
  -> GiteeUpgraderStore
  -> UpgraderVersionInfo
  -> Upgrader / UpgradeAlert
```

建议边界：

```text
lib/features/app_update/data/gitee
  gitee_release_dto.dart
  gitee_release_parser.dart
  gitee_latest_release_repository.dart
  gitee_upgrader_store.dart

lib/features/app_update/domain
  gitee_release_candidate.dart
  app_update_launch_failure.dart

lib/features/app_update/presentation
  app_update_prompt_coordinator.dart
  widgets/app_update_alert_host.dart
```

职责固定为：

- `GiteeReleaseDto` 只表达供应商 JSON 字段。
- `GiteeReleaseParser` 校验 Tag、Prerelease、精确附件和 HTTPS URL。
- `GiteeLatestReleaseRepository` 执行公开 HTTP 请求、超时和失败分类。
- `GiteeUpgraderStore` 只把有效候选映射成 `UpgraderVersionInfo`。
- `Upgrader` 负责读取已安装版本、版本比较和提示状态。
- `AppUpdatePromptCoordinator` 只管理一个长生命周期 `Upgrader` 实例和手动刷新入口，不重新实现版本策略。
- 页面只挂载 `UpgradeAlert` 或触发 coordinator，不直接请求 Gitee。

### 5.2 Store 接口方向

实现方向：

```dart
final class GiteeUpgraderStore extends UpgraderStore {
  GiteeUpgraderStore(this._repository);

  final GiteeLatestReleaseRepository _repository;

  @override
  Future<UpgraderVersionInfo> getVersionInfo({
    required UpgraderState state,
    required Version installedVersion,
    required String? country,
    required String? language,
  }) async {
    // 获取并严格解析 Gitee latest Release，再映射为 UpgraderVersionInfo。
  }
}
```

映射规则：

```text
tag_name 去掉 v 后的版本 -> appStoreVersion
精确 APK browser_download_url -> appStoreListingURL
Release body -> releaseNotes
方法参数 installedVersion -> installedVersion
isCriticalUpdate -> null/false
minAppVersion -> null
```

第一版不从 Release body 解析强制更新、最低版本、渠道、脚本或其它配置。更新说明按纯文本处理并设置合理长度上限。

### 5.3 生命周期与请求频率

`Upgrader` 必须由 provider/coordinator 创建一次并在应用壳生命周期内复用，不能在 Widget `build` 中反复实例化。`UpgradeAlert` 只负责展示。

`upgrader` 的 `durationUntilAlertAgain` 只限制再次弹窗，不限制 Gitee HTTP 请求；它还会在 App 恢复前台时调用 `updateVersionInfo()`。为避免频繁访问 Gitee：

- `GiteeUpgraderStore` 使用同一个长生命周期实例。
- repository/store 对成功响应做进程内 TTL 缓存，建议 6 小时。
- 网络失败采用短退避，建议 5 分钟，不循环重试。
- “手动检查更新”可以显式绕过 TTL，但重复点击必须合并为同一个 Future。
- 启动检查异步执行，不阻塞启动页、论坛、书架或阅读器。

第一版不为 Release metadata 增加 SQLite 表，也不复制 `upgrader` 已持久化的忽略版本和上次提示状态。

### 5.4 失败边界

`Upgrader.updateVersionInfo()` 不负责捕获自定义 Store 抛出的所有异常。`GiteeUpgraderStore` 必须把预期的网络、超时、HTTP、JSON 和协议错误收敛为“没有可用远端版本”，不能让启动时检查更新导致未捕获异常。

自动检查失败时静默结束并记录稳定诊断 code。手动检查失败时使用 Y300 现有 Snackbar 显示简短可操作信息。日志不得包含 Cookie、Token 或完整异常页面。

## 6. 更新提示与下载跳转

### 6.1 Upgrader 负责的状态

直接使用 `upgrader` 的：

- 已安装版本读取。
- SemVer 数值比较。
- `UpgradeAlert`。
- Release notes 展示。
- “稍后”与“忽略此版本”。
- `durationUntilAlertAgain`。
- 新版本出现后解除旧版本提示间隔的行为。
- 多语言基础文案。

Y300 不再建立平行的 `available/latest/ignored/later` 持久化状态机。`upgrader` 使用的 SharedPreferences 项属于第三方技术状态，不纳入个性化设置，也不复制到 SQLite。

第一版建议保留 `upgrader` 默认 3 天再次提醒间隔。手动检查不清空忽略记录，也不调用 `Upgrader.clearSavedSettings()`；如未来需要“取消忽略”，应增加明确入口，而不是在每次检查时偷偷重置用户选择。

### 6.2 必须覆盖默认 onUpdate

`upgrader 13.5.0` 在 Android 默认使用 `LaunchMode.externalNonBrowserApplication` 打开商店地址。Y300 提供的是 Gitee APK HTTPS URL，不是 Play Store URI，因此必须覆盖 `UpgradeAlert.onUpdate`：

```dart
UpgradeAlert(
  upgrader: upgrader,
  onUpdate: () {
    unawaited(updateLauncher.openInExternalApplication());
    return false;
  },
  child: appContent,
)
```

`return false` 阻止 `upgrader` 执行默认商店跳转。`updateLauncher` 从当前 `UpgraderVersionInfo.appStoreListingURL` 读取已验证的 HTTPS URL，并通过 `url_launcher` 的 `LaunchMode.externalApplication` 或经真机验证的系统默认模式打开。

`return false` 不会阻止普通 `UpgradeAlert` 在按钮点击后关闭，它只阻止默认 URL 启动。若没有有效 URL、系统没有可处理应用或异步启动失败，应在弹窗关闭后显示 Snackbar，并允许用户从“检查更新”入口重试；不得假定异步失败时还能保留原弹窗，也不得把异常抛到 Widget 树。

### 6.3 明确删除的复杂度

简化方案不再实现：

- Kotlin `DownloadManager` gateway。
- MethodChannel 下载与安装协议。
- App 内下载进度、暂停、取消和恢复。
- 下载任务 ID 与 APK 文件状态持久化。
- APK SHA-256 运行时计算。
- PackageManager archive package/version/signature 预校验。
- `REQUEST_INSTALL_PACKAGES` 与 Y300 自身的未知来源设置跳转。
- FileProvider/content URI 安装桥接。
- 下载完成应用通知。

用户看到的下载进度来自浏览器或 Android 系统下载通知。安装权限如果需要，由实际发起安装的浏览器、文件管理器或系统下载组件引导。

## 7. 手工发布流程

Gitee Release 由维护者手工发布，不建设“CI 自动发布到 Gitee”。客户端和仓库中不需要 `GITEE_TOKEN`。

每次发布依次执行：

1. 在 `pubspec.yaml` 同时提升 `versionName` 和 `versionCode`。
2. 运行发布所需 analyze、tests 和 arm64 release 构建。
3. 确认 APK 文件名严格符合协议。
4. 本地核对 applicationId、versionName、versionCode、ABI 和签名证书。
5. 计算 APK SHA-256，生成 canonical `.apk.sha256` 文本并本地回读验证。
6. 在 Gitee 手工创建 `v{versionName}` 正式 Release，`prerelease=false`。
7. 填写纯文本更新说明。
8. 上传唯一 APK 和唯一对应 checksum；不上传第二个同名/同 ABI APK。
9. 匿名请求 latest API，确认 Tag、Release notes 和两个附件名称。
10. 匿名打开 APK URL 与 checksum URL，确认可下载且摘要一致。
11. 用旧版真机检查更新，确认提示、外部下载和 Android 覆盖安装完整链路。

现有 GitHub workflow 可以继续作为构建和测试工具，但不得自动创建、修改或上传 Gitee Release，也不新增 Gitee 发布 Token。最终发布动作和 Release 内容由维护者人工确认。

发布过程中 latest Release 短暂缺少附件时，parser 返回“不完整 Release”，客户端不提示。两个附件上传完成后，下次检查自然恢复。不得为了绕过短暂窗口而模糊匹配附件。

## 8. 安全与隐私边界

### 8.1 信任链

简化方案的信任链为：

```text
维护者保管的 JKS
  -> 签名 APK
  -> Gitee HTTPS 分发
  -> 浏览器/系统下载
  -> Android 系统安装器验证签名兼容性
  -> 用户确认安装
```

JKS 仍是最重要资产：

- 不提交仓库。
- 至少保留两份离线备份。
- 文件与密码分离保存。
- 后续 Release 不随意更换签名证书。

APK 与 checksum 位于同一 Gitee Release，因此 checksum 可以发现传输损坏和误上传，但不能抵抗 Gitee 账户同时替换两项附件。真实性最终依赖 Android APK 签名和系统安装器。

### 8.2 网络与数据

- App 仅匿名读取公开 Gitee API，不携带发布 Token。
- API 与 APK URL 必须是 HTTPS。
- 只接受预期 Gitee host 和精确附件名。
- Release body 只作为文本显示，不执行 HTML、脚本或远端配置。
- 自动检查失败不影响登录、论坛、收藏、漫画、小说和启动流程。
- 小说网络请求继续固定使用 `version=1`，更新模块不得触碰该链路。

## 9. ADR 决策

### ADR-1：用 Upgrader 替代自建更新状态机

选择 `upgrader 13.5.0` 负责版本读取、比较、弹窗、忽略和提醒间隔。Y300 只保留供应商适配、请求节流和外部 URL 启动，不重复实现库已提供的能力。

### ADR-2：使用自定义 Gitee Store，不维护 Appcast

Gitee latest API 是唯一在线版本来源。Appcast 会形成第二份必须手工同步的版本清单，不符合简化目标。

### ADR-3：Release 完全手工发布

不实现 CI 自动创建或上传 Gitee Release，不在 CI 或客户端增加 Gitee Token。CI 可以构建和测试，但发布者人工检查版本、签名、附件和 Release notes 后再发布。

### ADR-4：系统负责下载与安装

“立即更新”打开精确 APK URL。Y300 不拥有下载任务、不申请安装 APK 权限、不实现 Kotlin 更新桥接。系统无法打开或下载时，向用户报告失败并允许重试。

### ADR-5：保留严格 Gitee 防腐层

`tag_name`、`browser_download_url` 等字段停留在 data 层。自定义 Store 不能取第一个 asset，也不能把任意 Gitee JSON 直接传给 Widget。

### ADR-6：版本比较只有一个所有者

parser 负责拒绝非 canonical Tag；实际远端与本地版本大小比较由 `upgrader` 完成。迁移后删除自定义 `pub_semver` 更新策略，避免两套 SemVer 类型和结论漂移。

### ADR-7：package_info_plus 10.2.1 暂不接入

当前项目与 `file_picker 11.0.2` 存在 `win32` 约束冲突。优先保持现有文件选择功能稳定，由 `upgrader` 使用依赖求解得到的 `package_info_plus 9.0.1`；未来在独立依赖升级任务中处理 10.x。

### ADR-8：checksum 不进入运行时下载状态机

继续手工上传 checksum 并用它验收 Release 完整性，但 App 不下载、持久化或比较摘要。若未来恢复 App 内下载，再另立 ADR 评估校验、任务恢复和安装边界，不能把旧复杂方案悄悄塞回本阶段。

## 10. Phase 0 测试基线

### 10.1 纯解析测试

- 真实脱敏 latest fixture 成功解析。
- 自动源码附件被忽略。
- 精确 APK/checksum 唯一匹配。
- Prerelease、缺 APK、重复 APK、错误 ABI 和 HTTP URL 被拒绝。
- `v1.0.10` 与 `v1.0.9` 映射为正确 `Version`。
- `v1.0`、前导零、Prerelease 和 build metadata Tag 被拒绝。
- 未知 Gitee 字段忽略，Release body 为空时仍可更新。
- 时间字段错误降级为未知，不影响版本发现。

### 10.2 Store 测试

- 有效候选正确映射 `appStoreVersion/listingURL/releaseNotes`。
- `installedVersion` 原样传入 `UpgraderVersionInfo`。
- 网络、超时、HTTP、JSON 和协议错误不会逃逸到 Upgrader 初始化流程。
- 并发检查合并，TTL 内不重复请求。
- 手动检查可以绕过 TTL，失败后不会无限重试。

### 10.3 Upgrader 集成测试

- 远端高于本地时 `isUpdateAvailable()` 为真。
- 远端等于或低于本地时不提示。
- 忽略当前版本后自动提示不再出现，更高版本仍可提示。
- 提示间隔遵循 `durationUntilAlertAgain`。
- `onUpdate` 返回 `false`，不会执行默认商店启动逻辑。
- 点击更新只打开 parser 已验证的 APK HTTPS URL。
- 无 URL 或外部启动失败时显示失败，并可从手动检查入口重试。

### 10.4 回归测试

- 更新检查不阻塞 App 启动。
- “更多”页挂载与卸载不会重复创建 Upgrader。
- App 恢复前台不会突破 Store TTL 高频请求 Gitee。
- 不新增 Android Manifest 安装权限。
- 不新增 Kotlin updater、MethodChannel、FileProvider 或下载状态 key。
- 论坛、书架、阅读器和其它下载功能不受影响。

## 11. 旧 Phase 0 代码迁移边界

接入 `upgrader` 时按以下方式收口现有 Phase 0 产物：

保留并调整：

- Gitee latest 真实脱敏 fixture。
- `GiteeReleaseDto`。
- 严格 Tag、Prerelease 和附件 parser 测试。
- APK/checksum 命名协议和签名基线。
- Gradle release APK 标准命名。

替换或删除：

- `AppUpdatePolicy`，改由 `Upgrader.isUpdateAvailable()` 负责。
- `AppUpdateDecision`，不再维护平行结论模型。
- `InstalledAppVersion`，由 Upgrader 的 `PackageInfo/Version` 状态负责。
- `AppReleaseChecksumParser`，因为客户端不再下载 checksum 内容。
- 仅服务于旧策略的 `pub_semver` 直接依赖。

新增最小能力：

- `GiteeLatestReleaseRepository`。
- `GiteeUpgraderStore`。
- 单例生命周期的 `AppUpdatePromptCoordinator`。
- 使用外部浏览器/系统应用的 `AppUpdateLauncher`。
- `UpgradeAlert` 宿主与必要测试。

## 12. Phase 0/1 验收与下一阶段准入

当前公开 `v0.0.1` Release、APK/checksum 命名、匿名访问、ABI、Manifest 和签名基线继续有效，无需重建 Release。

Phase 0 重基线已确认：

1. 本文件与配套分阶段实施方案共同取代旧的 DownloadManager/自建安装状态机方向。
2. `upgrader 13.5.0` 在当前 Flutter/Dart 环境可解析。
3. `package_info_plus 10.2.1` 的依赖冲突已有明确记录，Phase 1 不强行升级。
4. Gitee latest、APK 和 checksum 仍可匿名访问。
5. 手工 Release 是唯一发布方式，不设计 Gitee CI Token 或自动发布步骤。
6. 后续阶段不恢复旧 Phase 2/3 的 Kotlin 下载和安装管线。

Phase 1 已于 2026-07-19 完成：

- 引入 `upgrader 13.5.0` 和直接依赖 `version 3.x`；依赖求解使用 `package_info_plus 9.0.1`，没有覆盖 `win32`。
- `GiteeReleaseCandidate`、公开 latest repository 和 `GiteeUpgraderStore` 已建立。
- repository 已覆盖 6 小时成功 TTL、5 分钟失败退避、并发合并、强制刷新、超时和稳定失败分类。
- parser 继续要求 canonical Tag、唯一 APK/checksum、HTTPS、`gitee.com` host 和 URL 文件名一致，并将更新说明限制为 8192 个 Unicode 字符。
- 旧 `AppUpdatePolicy/AppUpdateDecision/InstalledAppVersion/AppReleaseChecksumParser` 和 `pub_semver` 直接依赖已移除。
- 33 项 `test/features/app_update` 测试通过，`flutter analyze` 无问题。
- 未增加 provider、Widget、Android 权限、Kotlin 文件或生产网络入口。

Phase 2 已于 2026-07-19 完成：

- 单一 Riverpod coordinator/provider 生命周期已接入应用根节点；`UpgradeAlert` 异步初始化且保留 Upgrader 的忽略、稍后和 3 天再次提醒状态。
- 更新网络使用独立、无论坛 Cookie/Authorization 的 Dio client；Store 缓存失败不重复记录，自动检查失败和受抑制状态保持静默。
- `UpgradeAlert.onUpdate` 返回 `false`，由独立 launcher 使用 `LaunchMode.externalApplication` 打开经过二次策略校验的 Gitee HTTPS arm64 APK URL；无 URL、无法启动和异步异常通过稳定失败与公共 Snackbar 收敛。
- 46 项更新模块测试和 12 项应用根主题测试通过；全仓 analyzer 结果记录在配套实施方案。Android 真机浏览器下载与覆盖安装仍需 Phase 4 使用正式签名 APK 验收。
- Phase 2 没有承担下载任务、安装权限、FileProvider 或更新专用 Kotlin/MethodChannel。Phase 3 可在同一 coordinator 上增加“更多”页手动检查，不得创建第二个 Upgrader 或版本状态机。

Phase 3 已于 2026-07-19 完成：

- “更多”页新增更新模块自有的检查 tile；当前版本仅从 coordinator 的 Upgrader 状态读取，页面没有直接依赖 `package_info_plus`、Gitee repository 或版本比较类型。
- coordinator 使用 typed result 编排一次强制刷新与一次缓存读取，重复点击和自动初始化共享在途请求；是否存在新版仍由 `Upgrader.isUpdateAvailable()` 唯一判断。
- 未受抑制的新版继续使用根节点唯一 `UpgradeAlert`。已忽略或仍在提醒间隔内时，仅通过带“立即下载”的 Snackbar 允许本次显式下载；不调用 `clearSavedSettings()`，不重置忽略版本和提醒时间。
- 53 项更新模块测试、11 项“更多”页测试和 12 项应用根主题测试通过，`flutter analyze` 无问题。
- Phase 3 没有新增下载状态、APK 文件管理、安装权限或第二套持久化。Phase 4 只负责手工 Release 与真机发布演练，不应重新引入客户端更新内核。
