# Y300 Android 基于 Gitee Release 的应用内更新分阶段实施方案

> 文档日期：2026-07-19
> 适用范围：Y300 Android arm64-v8a 自分发版本
> 更新源：公开 Gitee Release API
> 发布方式：维护者手工创建和上传 Gitee Release
> 更新组件：`upgrader 13.5.0` + 自定义 `UpgraderStore`
> 下载与安装：外部浏览器/Android 系统组件
> 架构基线：[Android基于Gitee Release的应用内更新Phase0基线与ADR.md](./Android基于Gitee%20Release的应用内更新Phase0基线与ADR.md)

## 1. 方案结论

Y300 采用轻量自托管更新方案，不再自行实现 APK 下载和安装内核：

```text
维护者手工发布 Gitee Release
  -> App 匿名请求 latest Release API
  -> Gitee 防腐层选择严格版本和精确 arm64 APK
  -> GiteeUpgraderStore 映射 UpgraderVersionInfo
  -> Upgrader 读取本地版本并判断是否更新
  -> UpgradeAlert 展示更新说明和用户选择
  -> 用户点击“立即更新”
  -> Y300 覆盖默认 onUpdate，外部打开 APK HTTPS URL
  -> 浏览器/Android 系统显示下载进度
  -> 用户从通知或下载列表安装
  -> Android 系统安装器完成签名校验和最终确认
```

职责只保留三层：

1. Y300 负责把 Gitee latest JSON 转成可信的更新候选。
2. `upgrader` 负责版本读取、版本比较、提示、稍后和忽略状态。
3. 浏览器与 Android 系统负责下载、下载通知和安装。

本方案不再包含：

- CI 自动发布到 Gitee。
- Gitee 发布 Token。
- Kotlin `DownloadManager` gateway。
- MethodChannel 下载/安装协议。
- App 内下载进度、暂停、取消和进程恢复。
- APK SHA-256 运行时计算。
- Y300 自己的 APK 包名、版本和证书预校验。
- `REQUEST_INSTALL_PACKAGES`、FileProvider 或 content URI 安装桥接。
- 与 `upgrader` 平行的版本判断、忽略版本和提醒时间状态机。

## 2. 目标与非目标

### 2.1 目标

- 使用公开 Gitee latest Release API 作为唯一在线更新源。
- 不在 APK、源码、日志或配置中保存 Gitee Token。
- 使用 `upgrader 13.5.0` 统一版本读取、比较和提示行为。
- 保留严格的 Gitee DTO/parser 防腐层，不让供应商 JSON 进入 UI。
- 支持启动后的非阻塞自动检查。
- 支持“更多 -> 检查更新”的主动检查。
- 展示目标版本和 Gitee Release body 更新说明。
- 允许用户“稍后”和“忽略当前版本”。
- 点击更新后交给外部浏览器/Android 系统下载。
- 保持 Gitee 请求可控，不因 App 多次恢复前台而频繁访问 API。
- 更新功能失败时不影响论坛、收藏、漫画、小说、书架和启动流程。

### 2.2 明确不做

- 不实现静默安装、Root 安装或设备管理器安装。
- 不接入 Google Play In-App Updates。
- 不为 Gitee 增加 Appcast XML 或稳定 JSON 镜像。
- 不支持 Prerelease、灰度发布、强制更新、最低可用版本或多渠道。
- 不支持 x86、x86_64、armeabi-v7a 或通用 APK。
- 不把 Gitee Release body 当作远端配置或脚本。
- 不在 App 内展示浏览器下载任务的百分比。
- 不在 Y300 内持久化下载任务、APK 路径或安装状态。
- 不自动创建、修改或上传 Gitee Release。
- 不为了使用 `package_info_plus 10.2.1` 强行覆盖现有依赖约束。

## 3. 当前基线

### 3.1 工具链

2026-07-19 实测：

```text
Flutter 3.44.4 stable
Dart 3.12.2
```

满足 `upgrader 13.5.0` 的 Dart `>=3.5.0 <4.0.0` 和 Flutter `>=3.27.0` 要求。

### 3.2 应用版本

当前 `pubspec.yaml`：

```yaml
version: 0.0.1+4
```

对应：

```text
versionName = 0.0.1
versionCode = 4
```

更新发现只比较稳定三段 `versionName`。`versionCode` 不写入 Gitee Tag，但每次正式发布仍必须严格递增，否则 Android 不允许正常覆盖安装。

### 3.3 已完成的旧 Phase 0 产物

当前仓库已经具备：

- Gitee latest Release 脱敏 fixture。
- Gitee DTO 和严格 parser。
- `v{major}.{minor}.{patch}` Tag 协议。
- arm64 APK 与 checksum 精确命名协议。
- 当前 APK、ABI、Manifest、摘要和签名证书基线。
- Gradle release APK 标准命名。
- 基于 `pub_semver` 的旧版纯更新策略。

其中 DTO、fixture、严格协议和制品基线继续复用；旧 `AppUpdatePolicy/AppUpdateDecision/InstalledAppVersion/AppReleaseChecksumParser` 将在 Phase 1 被 `upgrader` 方案替换。

## 4. 依赖方案

### 4.1 必需依赖

Phase 1 首先加入：

```yaml
dependencies:
  upgrader: 13.5.0
```

`upgrader` 内部已经通过 `package_info_plus` 读取安装包版本。仅为使用 Upgrader 时，不需要再把 `package_info_plus` 声明为 Y300 的直接依赖。

自定义 `UpgraderStore` 的方法签名和返回模型使用 `package:version/version.dart`。如果 Y300 源码直接导入 `Version`，则必须声明：

```yaml
dependencies:
  version: ^3.0.2
```

不能依赖传递依赖碰巧存在。

### 4.2 package_info_plus 版本决策

`upgrader 13.5.0` 接受：

```text
package_info_plus >=4.0.1 <11.0.0
```

当前项目真实依赖求解结果为 `package_info_plus 9.0.1`。直接指定 `package_info_plus 10.2.1` 会失败：

```text
package_info_plus 10.2.1 -> win32 ^6.0.1
file_picker 11.0.2      -> win32 ^5.9.0
```

本方案决定：

- Phase 1 不直接添加 `package_info_plus 10.2.1`。
- 如果“更多”页仅通过 coordinator 读取 `Upgrader.state.packageInfo`，不添加直接依赖。
- 如果 Y300 独立代码确实需要导入 `PackageInfo`，声明 `package_info_plus: ^9.0.1`。
- 不使用 `dependency_overrides` 强行统一 `win32`。
- 未来把 `file_picker` 与 `package_info_plus 10.x` 作为独立依赖升级任务，不混入应用更新功能。

### 4.3 旧依赖收口

`upgrader` 使用 `package:version` 完成比较。旧 `pub_semver` 仅服务于旧更新策略时，在 Phase 1 删除相关代码后同步移除直接依赖。

最终版本语义只有一个所有者：

```text
parser：验证 Tag 是否严格 canonical
upgrader/version：比较 installedVersion 与 appStoreVersion
Android：根据 APK 内 versionCode 决定能否覆盖安装
```

## 5. Gitee 手工发布协议

### 5.1 仓库

```text
Repository: QAQadws/y300-releases
Latest API: https://gitee.com/api/v5/repos/QAQadws/y300-releases/releases/latest
Release page: https://gitee.com/QAQadws/y300-releases/releases
```

客户端匿名访问，不携带 `access_token`。

### 5.2 Tag

只接受：

```text
v{major}.{minor}.{patch}
```

例如：

```text
v0.0.1
v1.0.10
```

拒绝：

```text
0.0.1
v1.0
v01.0.0
v1.0.0-beta
v1.0.0+5
```

Tag 与 APK 的 `versionName` 必须一致。Tag 不携带 `versionCode`，但维护者发布前必须确认新 APK 的 `versionCode` 更高。

### 5.3 附件

唯一 APK：

```text
y300-v{versionName}-android-arm64-v8a-release.apk
```

唯一 checksum：

```text
y300-v{versionName}-android-arm64-v8a-release.apk.sha256
```

checksum 内容：

```text
{64位小写SHA-256}  {完整APK文件名}
```

两个 ASCII 空格分隔，文件末尾允许一个换行。Gitee 自动生成的源码 zip/tar.gz 必须忽略。

客户端 parser 仍要求 APK/checksum 对完整且唯一，避免手工上传过程中的不完整 Release 被提示给用户。简化客户端不请求 checksum 正文，也不在本地下载后比较摘要。

### 5.4 Release body

`body` 只映射为 `UpgraderVersionInfo.releaseNotes`：

- 允许为空。
- 作为普通文本展示。
- 设置长度上限，建议 8 KiB。
- 不解析强制更新、最低版本、下载地址或脚本。
- 不执行 HTML 或 JavaScript。

## 6. 总体架构

### 6.1 模块结构

```text
lib/features/app_update
  domain
    models
      gitee_release_candidate.dart
      app_update_lookup_failure.dart
      app_update_launch_failure.dart
    repositories
      gitee_latest_release_repository.dart
    services
      app_update_launcher.dart
  data
    gitee
      gitee_release_dto.dart
      gitee_release_parser.dart
      dio_gitee_latest_release_repository.dart
      gitee_upgrader_store.dart
    platform
      url_launcher_app_update_launcher.dart
    providers
      app_update_providers.dart
  presentation
    controllers
      app_update_prompt_coordinator.dart
    widgets
      app_update_alert_host.dart
```

### 6.2 依赖方向

```text
presentation
  -> coordinator / domain interfaces
  -> Upgrader public API

GiteeUpgraderStore
  -> GiteeLatestReleaseRepository
  -> GiteeReleaseParser

URL launcher adapter
  -> AppUpdateLauncher interface
  -> url_launcher
```

禁止：

- 页面直接使用 Dio 请求 Gitee。
- DTO 进入 presentation。
- Gitee parser 决定是否展示弹窗。
- coordinator 自己再次比较版本字符串。
- repository 依赖 Widget、BuildContext 或 Riverpod。
- 更新模块依赖漫画、小说、收藏或论坛 repository。

### 6.3 领域候选模型

建议最小模型：

```dart
final class GiteeReleaseCandidate {
  const GiteeReleaseCandidate({
    required this.tag,
    required this.version,
    required this.apkUri,
    required this.checksumUri,
    required this.releaseNotes,
  });

  final String tag;
  final Version version;
  final Uri apkUri;
  final Uri checksumUri;
  final String? releaseNotes;
}
```

不加入下载 task ID、文件路径、进度、APK size 或安装权限状态，因为简化方案不拥有这些数据。

### 6.4 GiteeUpgraderStore

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
    // Repository 读取并解析候选，Store 只做 Upgrader 映射。
  }
}
```

映射：

```text
candidate.version      -> appStoreVersion
candidate.apkUri       -> appStoreListingURL
candidate.releaseNotes -> releaseNotes
installedVersion       -> installedVersion
isCriticalUpdate       -> null
minAppVersion          -> null
```

Store 不根据 `country/language` 切换 Release；参数只为满足 Upgrader 合同。

### 6.5 StoreController

使用 Android 自托管 Store：

```dart
final store = GiteeUpgraderStore(repository);

final upgrader = Upgrader(
  storeController: UpgraderStoreController(
    onAndroid: () => store,
  ),
  durationUntilAlertAgain: const Duration(days: 3),
);
```

`store` 和 `upgrader` 都必须由 provider/coordinator 长生命周期持有。`onAndroid` 返回同一个 Store 实例，以保留进程内 TTL 和并发请求合并能力。

Android 之外的平台在本方案中不提供 Store，不展示 Android APK 更新提示。

## 7. 请求、缓存与失败模型

### 7.1 请求策略

- 使用项目现有 Dio 基础能力或独立、无 Cookie 的 Dio client。
- 只请求公开 latest API。
- 设置连接和响应超时，建议 10 秒。
- 不携带论坛 Cookie、Authorization 或 Gitee Token。
- 只接受 JSON object。
- HTTP 3xx 由客户端按受控策略处理；最终 API 和 APK URL 必须为 HTTPS。
- HTTP 403/429 视为限流/访问失败，不重试风暴。
- HTTP 404 视为 Release 不存在。
- HTTP 5xx 视为远端暂时失败。

### 7.2 为什么需要轻量 TTL

`Upgrader.durationUntilAlertAgain` 只限制弹窗，不限制网络请求；`Upgrader` 会在初始化和 App 恢复前台时刷新版本信息。

因此 repository/store 必须实现：

```text
成功缓存 TTL：6 小时
失败退避：5 分钟
并发合并：同一时刻只有一个 latest 请求
手动检查：可强制刷新并绕过 TTL
```

第一版仅使用进程内缓存，不写 SQLite，不持久化整份 Release。App 重启后允许重新请求一次。

### 7.3 失败类型

最小稳定错误分类：

```text
networkUnavailable
requestTimeout
rateLimited
releaseNotFound
invalidPayload
invalidTag
prerelease
apkMissing
apkAmbiguous
checksumMissing
checksumAmbiguous
invalidAssetUrl
externalLaunchUnavailable
externalLaunchFailed
```

自动检查失败：

- 不显示启动错误弹窗。
- Store 返回不含远端版本的 `UpgraderVersionInfo`。
- 记录稳定 code，避免打印整页响应和敏感 header。

手动检查失败：

- 使用现有 Snackbar 显示简短文案。
- 允许用户稍后重试。
- 不自动无限重试。

自定义 Store 必须捕获预期异常，因为 `Upgrader.updateVersionInfo()` 不会替 Store 兜住所有异常。

## 8. Upgrader 生命周期与提示

### 8.1 单一实例

`AppUpdatePromptCoordinator` 负责：

- 创建并持有唯一 `Upgrader`。
- 创建并持有唯一 `GiteeUpgraderStore`。
- 初始化一次。
- 向 UI 暴露只读版本信息。
- 触发手动强制刷新。
- dispose 时释放 Upgrader observer。

不得在 Widget `build()` 中 `Upgrader()`，也不得在多个页面各自创建实例，否则会重复请求、重复监听生命周期和重复弹窗。

### 8.2 自动提示

在 MaterialApp 以下、主壳页面以上挂载一个 `AppUpdateAlertHost`：

```text
MaterialApp
  -> AppUpdateAlertHost / UpgradeAlert
  -> MainShellPage
```

要求：

- 不阻塞应用启动。
- 首次检查异步进行。
- 无更新或检查失败时保持安静。
- 新版本出现后按 Upgrader 规则提示。
- 保留“稍后”和“忽略此版本”。
- 默认再次提醒间隔为 3 天。
- 不实现强制更新。

### 8.3 Upgrader 持久化所有权

直接使用 Upgrader 的 SharedPreferences 状态：

- 上次提示时间。
- 上次提示版本。
- 用户忽略版本。

Y300 不复制这些状态，不新增 SQLite 表，也不在个性化设置 repository 中再保存一份。

“恢复默认设置”不应无意清除 Upgrader 技术状态。手动检查也不能调用 `Upgrader.clearSavedSettings()` 偷偷取消用户忽略。

## 9. 点击更新与外部下载

### 9.1 为什么不能使用默认跳转

`upgrader 13.5.0` 在 Android 的默认 `sendUserToAppStore()` 使用：

```text
LaunchMode.externalNonBrowserApplication
```

该模式面向 Play Store 等商店应用。Y300 的 `appStoreListingURL` 是 Gitee APK HTTPS URL，可能只能由浏览器处理，因此必须覆盖 `UpgradeAlert.onUpdate`。

### 9.2 AppUpdateLauncher

定义小型接口：

```dart
abstract interface class AppUpdateLauncher {
  Future<void> openApk(Uri apkUri);
}
```

实现使用 `url_launcher`：

- 首选经真机验证的 `LaunchMode.externalApplication`。
- 不在内嵌 WebView 下载 APK。
- URL 必须来自已通过 parser 的 `UpgraderVersionInfo`。
- 启动前再次验证 HTTPS、host 和精确 APK 文件名。
- 无处理应用或启动失败时返回稳定失败。

### 9.3 UpgradeAlert 回调

```dart
UpgradeAlert(
  upgrader: upgrader,
  onUpdate: () {
    unawaited(updateLauncher.openApk(currentApkUri));
    return false;
  },
  child: child,
)
```

返回 `false` 阻止 Upgrader 继续执行默认商店跳转。异步失败由 launcher/coordinator 通过现有 Snackbar 报告。

### 9.4 用户体验边界

点击更新后：

- 普通 UpgradeAlert 会关闭；`onUpdate` 返回 `false` 只阻止默认商店跳转，不阻止弹窗关闭。
- 异步打开外部应用失败时使用 Snackbar 报错，并允许用户从“检查更新”入口重试。
- 下载进度显示在浏览器或系统通知，不在 Y300 内伪造进度。
- 下载完成后由用户点击通知/文件开始安装。
- Android 可能要求用户为浏览器或文件管理器授权“安装未知应用”；该权限不由 Y300 申请。
- 安装失败由 Android 系统说明，Y300 不猜测下载任务状态。

## 10. 手动检查更新

“更多”页保留一个清晰的“检查更新”命令，并显示当前版本文本。页面本身不请求 Gitee。

### 10.1 检查流程

```text
用户点击检查更新
  -> coordinator 合并重复点击
  -> repository.forceRefresh() 绕过 TTL 并缓存本次 typed result
  -> Upgrader.updateVersionInfo() 通过 Store 读取同一缓存结果
  -> Upgrader.isUpdateAvailable()
```

该顺序保证一次手动检查只有一个 HTTP 请求，同时让 coordinator 能区分 repository 失败与“远端版本不高于本地”。不得通过 Store 的可变 `lastError` 侧通道猜测结果。

结果：

```text
失败       -> Snackbar：检查更新失败，请稍后重试
已是最新   -> Snackbar：当前已是最新版本
发现更新且允许提示 -> 由现有 UpgradeAlert 展示
发现更新但被忽略/仍在提示间隔 -> 带“下载”操作的 Snackbar
```

手动检查不增加第二个更新 BottomSheet。coordinator 在刷新完成后使用 Upgrader 的 `isUpdateAvailable()`、`alreadyIgnoredThisVersion()` 和 `isTooSoon()` 判断由谁呈现结果：正常更新交给已经挂载的 `UpgradeAlert`；被用户选择抑制的版本只通过 Snackbar 提供显式下载动作。版本大小比较仍由 Upgrader 完成。

### 10.2 忽略语义

自动提示遵循 Upgrader 的“忽略当前版本”。主动检查属于用户明确操作，可以告诉用户存在已忽略版本，但不能静默清除忽略状态。

主动检查时允许用户通过 Snackbar 的“下载”操作打开已忽略版本；这只绕过本次 UI 提示抑制，不改变持久化的忽略选择。更高版本仍由 Upgrader 自动恢复提示。

## 11. 手工发布 SOP

### 11.1 发布前

1. 修改 `pubspec.yaml`，同时提升 `versionName` 和 `versionCode`。
2. 确认 Tag 将使用 `v{versionName}`，不包含 `+versionCode`。
3. 运行必要的 `flutter analyze` 和发布门禁测试。
4. 使用正式 JKS 构建 arm64 release APK。
5. 确认输出名为 `y300-v{versionName}-android-arm64-v8a-release.apk`。
6. 核对 packageName、versionName、versionCode 和 ABI。
7. 核对签名证书与基线一致。
8. 计算 SHA-256，生成同名 `.apk.sha256` 并本地回读。

### 11.2 Gitee 手工发布

1. 打开 `QAQadws/y300-releases`。
2. 手工创建 Tag `v{versionName}` 的正式 Release。
3. `prerelease=false`。
4. 填写纯文本更新说明。
5. 上传唯一 APK。
6. 上传唯一 checksum。
7. 不上传另一个同 ABI 或通用 APK。

不配置：

- `GITEE_TOKEN`。
- CI 自动创建 Release。
- CI 自动上传附件。
- CI 自动修改现有 Release。

现有 CI 可以继续运行构建和测试，但最终 Release 创建、说明确认和附件上传由维护者完成。

### 11.3 发布后验收

1. 匿名请求 latest API，确认返回本次 Tag。
2. 确认 `prerelease=false`。
3. 确认 APK/checksum 名称唯一且精确。
4. 匿名打开两个附件 URL。
5. 重新计算远端 APK 摘要并与 checksum 比较。
6. 使用旧版真机检查更新。
7. 确认 UpgradeAlert 展示正确版本和说明。
8. 点击更新，确认外部浏览器开始下载。
9. 确认系统通知/下载列表可见。
10. 完成一次旧版到新版的覆盖安装。

### 11.4 错误版本处理

Android 不支持正常降级。坏版本必须发布更高版本：

```text
错误版：1.0.4+5 / Tag v1.0.4
修复版：1.0.5+6 / Tag v1.0.5
```

禁止删除后复用 `v1.0.4` 上传不同 APK，也禁止只发布 `1.0.4+6`。

## 12. 安全模型

### 12.1 信任链

```text
维护者 JKS
  -> 签名 APK
  -> Gitee HTTPS
  -> 外部浏览器/系统下载
  -> Android 系统安装器签名验证
  -> 用户确认
```

维护要求：

- JKS 不进入仓库。
- 至少两份离线备份。
- 密码与文件分开保存。
- 发布前核对证书指纹。
- 后续版本继续使用相同签名身份。

### 12.2 checksum 边界

checksum 用于：

- 发布者确认构建产物没有拿错。
- 用户或维护者公开复核下载内容。
- parser 判断手工 Release 是否已上传完整附件。

checksum 不用于：

- App 内下载后校验。
- 代替 APK 签名。
- 抵抗 Gitee 账户同时替换 APK 和 checksum。

### 12.3 网络隔离

- 更新请求不携带论坛 Cookie。
- 不携带 Gitee Token。
- 不把 Release body 写入日志。
- 不允许 HTTP APK URL。
- 不从 Release body提取跳转地址。
- 不让更新失败影响业务网络网关。

## 13. 测试策略

### 13.1 Parser 测试

- 真实脱敏 Gitee fixture。
- 严格稳定三段 Tag。
- 数字版本 `1.0.10`。
- 非法 Tag、Prerelease 和 build metadata。
- 缺 APK/checksum。
- 重复 APK/checksum。
- 错误 ABI、文件名和 HTTP URL。
- 自动源码附件忽略。
- Release body 缺失和过长截断。
- 未知 Gitee 字段忽略。

### 13.2 Repository 测试

- 200 正常 JSON。
- 403、404、429、500。
- 超时和断网。
- 非 object JSON 和错误字段类型。
- 6 小时成功 TTL。
- 5 分钟失败退避。
- 并发请求合并。
- 手动强制刷新绕过 TTL。
- repository 不泄漏 Gitee DTO。

### 13.3 Store 测试

- Candidate 到 `UpgraderVersionInfo` 映射。
- installedVersion 原样返回。
- country/language 不改变 Release。
- 预期错误不会逃逸到 Upgrader。
- 无有效远端版本时返回安全空信息。

### 13.4 Coordinator 与 Upgrader 测试

- 单一实例初始化。
- 远端高于、等于、低于本地版本。
- 忽略当前版本。
- 更高版本解除旧提示抑制。
- 3 天再次提醒间隔。
- 多次页面 rebuild 不重复初始化。
- App 恢复前台受 Store TTL 限制。
- 手动检查重复点击合并。
- dispose 后不继续触发 UI。

### 13.5 UI 与 launcher 测试

- UpgradeAlert 使用自定义 Store。
- `onUpdate` 返回 `false`。
- 不调用 Upgrader 默认商店跳转。
- 只打开已验证 HTTPS APK URL。
- 外部应用不可用和启动失败提示。
- “更多”页显示当前版本。
- 最新、失败和发现更新三种手动结果。
- UpgradeAlert 中更新说明过长时布局可滚动且按钮可见。

### 13.6 Android 真机矩阵

至少覆盖：

```text
Android 8/9
Android 10/11
Android 12/13
Android 14/15
```

验证：

- Chrome 或默认浏览器打开 APK URL。
- 浏览器下载通知。
- 下载列表找到 APK。
- 未知来源权限由实际安装来源引导。
- 正确签名 APK 覆盖安装。
- 错误签名 APK 被 Android 拒绝。
- 断网和 Gitee 限流不影响 App 主流程。

## 14. 分阶段实施

### Phase 0：方案重基线与 ADR

实施状态：已于 2026-07-19 完成文档与依赖可行性重基线；运行时代码迁移从 Phase 1 开始。

任务：

- 固定自托管 Gitee latest API 和手工发布方式。
- 确认不增加 Appcast 或稳定 JSON。
- 核对 `upgrader 13.5.0` 的 Store、提示和回调边界。
- 验证当前 Flutter/Dart 工具链满足 Upgrader 要求。
- 实际求解 `upgrader 13.5.0` 依赖。
- 记录 `package_info_plus 10.2.1` 与 `file_picker 11.0.2` 的 `win32` 冲突。
- 决定第一版不建设 DownloadManager/Kotlin/MethodChannel。
- 决定覆盖 Android 默认 `onUpdate`，外部打开 Gitee APK。
- 固定旧 Phase 0 代码的保留、替换和删除清单。
- 重构本方案与 Phase 0 ADR，使二者一致。

验收：

- 两份文档不再包含 CI 自动发布到 Gitee 的实施任务。
- 两份文档不再把 App 内下载进度和安装桥接作为完成条件。
- `upgrader`、Gitee Store、手工 Release 和系统下载边界明确。
- 依赖版本和冲突有真实求解结果支持。
- 后续 Phase 不会并行维护两套版本状态机。

### Phase 1：Gitee Store 与版本模型收口

实施状态：已于 2026-07-19 完成。Phase 1 只提供 data/domain 内核，尚未创建 provider、Widget 或生产检查入口。

任务：

- 添加 `upgrader: 13.5.0`。
- 根据直接 import 需要添加 `version: ^3.0.2`。
- 不直接添加 `package_info_plus 10.2.1`。
- 将旧 Gitee parser 的版本类型迁移到 `package:version`，保留 canonical Tag 校验。
- 建立 `GiteeReleaseCandidate`。
- 实现公开 Gitee latest repository、超时和失败分类。
- 实现 6 小时成功 TTL、5 分钟失败退避和并发请求合并。
- 实现 `GiteeUpgraderStore`。
- 删除旧 `AppUpdatePolicy/AppUpdateDecision/InstalledAppVersion/AppReleaseChecksumParser`。
- 删除不再使用的 `pub_semver` 直接依赖。
- 保留 checksum asset 完整性检查，但不请求 checksum 内容。
- 更新 `docs/开发文档.md`。

验收：

- Gitee fixture 可以映射为 `UpgraderVersionInfo`。
- 非法 Release 不产生更新候选。
- 网络/解析失败不抛出到 Upgrader 初始化。
- 同一进程内恢复前台不会频繁请求 Gitee。
- 代码中只有 Upgrader/version 执行版本大小比较。
- Phase 1 不增加任何 Widget、Android 权限或 Kotlin 文件。

### Phase 2：自动提示与外部 APK 打开

实施状态：已于 2026-07-19 完成代码接入与自动化验证。Android 真机的浏览器下载和系统安装链路保留到 Phase 4 发布演练验收。

任务：

- 建立 Riverpod providers 和单例生命周期 coordinator。
- 在主壳挂载 `AppUpdateAlertHost/UpgradeAlert`。
- 自动检查异步启动，不阻塞首页。
- 使用默认 3 天再次提醒间隔。
- 保留“稍后”和“忽略此版本”。
- 实现 `AppUpdateLauncher` 和 `url_launcher` adapter。
- 覆盖 `UpgradeAlert.onUpdate` 并返回 `false`。
- 使用外部应用模式打开精确 Gitee APK URL。
- 处理无 URL、无法启动和异步失败 Snackbar。
- 确认不新增 `REQUEST_INSTALL_PACKAGES`、FileProvider 或 Kotlin bridge。
- 更新 `docs/开发文档.md`。

实现记录：

- `AppUpdatePromptCoordinator`、更新专用 providers 和独立无认证 Dio client 已接入；同一 ProviderScope 内只创建一个 coordinator、Upgrader 和 Store，销毁时释放 Upgrader 与 Dio。
- `Y300App` 在 MaterialApp 首页根部挂载唯一 `AppUpdateAlertHost`；测试/预览可显式关闭宿主，生产默认启用。
- `UpgradeAlert` 保留 release notes、忽略、稍后和 3 天提醒间隔；无更新或受 Upgrader 规则抑制时保持静默。
- `onUpdate` 返回 `false`，并由 `UrlLauncherAppUpdateLauncher` 使用 `LaunchMode.externalApplication` 打开 URL，确保不会回落到 Upgrader 的默认商店启动器。
- parser 与 launcher 复用 `AppUpdateApkUriPolicy`，在外部启动前再次要求 HTTPS、`gitee.com`、无 userinfo/fragment 和 canonical arm64 APK 文件名。
- 无 URL、无可用外部应用和启动异常均返回稳定失败并通过公共 Snackbar 呈现；重复点击外部启动会合并为一个在途 Future。
- Store 的缓存失败不会在每次前台刷新时重复上报；真实网络失败和意外异常仍保留稳定诊断码。
- 未增加更新专用 Android 权限、FileProvider、Kotlin bridge、MethodChannel 或 App 内下载状态。

验收：

- fake 高版本可触发 UpgradeAlert。
- latest/失败状态不打扰启动。
- 点击更新不会走 Upgrader 默认商店启动。
- Android 真机能进入浏览器下载 APK。
- 页面 rebuild 不重复创建 Upgrader 或重复弹窗。
- 自动检查不影响其它功能。

自动化结果：

- `flutter test test/features/app_update`：46 项通过。
- `flutter test test/app/app_theme_test.dart`：12 项通过。
- `flutter analyze`：通过，`No issues found`。
- 真机浏览器下载、通知进度和覆盖安装不由 Widget 测试模拟，必须在 Phase 4 使用正式签名 APK 验收。

### Phase 3：“更多”页手动检查与单一提示入口

实施状态：已于 2026-07-19 完成代码接入与自动化验证。正式 Gitee Release 的真机交互仍随 Phase 4 发布演练验收。

任务：

- 增加“检查更新”入口和当前版本展示。
- 当前版本优先从 coordinator 的 Upgrader 状态读取，不让页面直接依赖 PackageInfo。
- 手动检查绕过 TTL 并合并重复点击。
- 失败和“已是最新”使用现有 Snackbar。
- 发现更新且未受抑制时复用现有 UpgradeAlert，不增加第二个更新面板。
- 主动检查不清除 Upgrader 的忽略状态。
- 已忽略或仍在提醒间隔内的版本通过带操作的 Snackbar 明确说明，并允许用户显式下载。
- 更新 `docs/开发文档.md`。

实现记录：

- “更多”页只挂载更新模块提供的 `AppUpdateCheckTile`；当前版本来自 coordinator 持有的 Upgrader 状态，页面不直接导入 `package_info_plus`、repository 或版本类型。
- coordinator 新增 typed `AppUpdateCheckResult`：稳定区分检查失败、已是最新和发现新版，并保留 Upgrader 给出的 ignored/reminder interval 抑制原因。
- `checkNow()` 先执行一次 `forceRefresh`，再让同一个 Upgrader 调用 `updateVersionInfo()` 读取刚写入的 repository cache；自动初始化与重复点击均受 repository/coordinator 两层 in-flight 合并保护，不产生第二次 HTTP 请求。
- 版本是否可更新只调用 `Upgrader.isUpdateAvailable()`；检查过程不实现第二套 SemVer 比较，不读取或修改 Upgrader 私有 SharedPreferences。
- 未受抑制的新版由根节点已经挂载的唯一 `UpgradeAlert` 响应；手动入口不创建 dialog、sheet 或第二个 Upgrader。
- 已忽略或仍在提醒间隔内时显示带“立即下载”的 Snackbar。该一次性操作直接复用当前 launcher，不调用 `clearSavedSettings()`，因此不会取消用户忽略或改变后续自动提醒时间。
- 检查按钮在请求期间禁用并显示紧凑进度；失败、已是最新以及外部启动失败均使用公共 transient Snackbar。

验收：

- 三种手动结果明确且不会重复请求。
- 主动检查不会创建第二个 Upgrader 实例。
- 手动检查不增加第二个弹窗状态机，不重新实现 SemVer 比较或持久化。
- 不出现下载进度、安装权限和任务恢复 UI。

自动化结果：

- `flutter test test/features/app_update`：53 项通过。
- `flutter test test/features/more/presentation/more_page_test.dart`：11 项通过。
- `flutter test test/app/app_theme_test.dart`：12 项通过。
- `flutter analyze`：通过，`No issues found`。
- 真机上的 Gitee 高版本提示、忽略/稍后状态和外部浏览器打开仍需 Phase 4 使用正式签名 APK 验收。

### Phase 4：手工发布演练与发布硬化

任务：

- 用更高 `versionName/versionCode` 构建正式 arm64 APK。
- 本地核对包名、ABI、版本、签名和 checksum。
- 维护者手工创建 Gitee 正式 Release。
- 手工上传唯一 APK/checksum。
- 匿名验收 latest API 和两个附件。
- 使用旧版真机完成发现、提示、浏览器下载和覆盖安装。
- 覆盖 Android 版本矩阵。
- 演练断网、Gitee 429、缺附件、错误附件和错误签名。
- 演练坏版本通过更高 patch/versionCode 修复。
- 完成日志隐私和跨模块回归检查。
- 更新发布 SOP 和 `docs/开发文档.md`。

验收：

- 不使用 Gitee CI Token。
- Release 全程由维护者手工确认。
- 旧版可以发现并安装新版。
- 下载进度由浏览器/系统正常显示。
- Android 系统拒绝错误签名 APK。
- 检查失败不影响业务模块。
- Definition of Done 全部满足。

## 15. 预计文件变更

```text
pubspec.yaml
  + upgrader 13.5.0
  + version ^3.0.2（仅在直接 import 时）
  - pub_semver（无其它引用后）

lib/features/app_update/data/gitee/**
  ~ 保留 DTO/parser
  + latest repository
  + GiteeUpgraderStore

lib/features/app_update/domain/**
  + release candidate / failure / launcher contracts
  - 自定义更新 decision/policy/checksum content parser

lib/features/app_update/presentation/**
  + coordinator
  + UpgradeAlert host

lib/features/more/presentation/**
  + 检查更新入口和当前版本

lib/features/startup 或 app shell
  + 非阻塞 UpgradeAlert 宿主

test/features/app_update/**
  + repository/store/coordinator/launcher/UI 测试
  ~ 复用 Gitee fixture
```

不应新增：

```text
android/**/update/*.kt
REQUEST_INSTALL_PACKAGES
FileProvider
下载 MethodChannel
Gitee 发布 Token
Gitee 自动发布 workflow
下载任务 SharedPreferences key
```

不应修改：

- 小说 `version=1` 请求策略。
- 漫画章节下载。
- 图片缓存与阅读器预加载。
- 收藏同步。
- 论坛 Cookie。
- 作品详情和阅读进度。

## 16. Review 检查清单

- 是否固定使用 `upgrader 13.5.0`？
- 是否没有强行引入 `package_info_plus 10.2.1`？
- 如果直接 import `Version/PackageInfo`，是否声明了直接依赖？
- 是否只有 parser 校验格式、Upgrader 比较版本？
- 是否删除了旧的平行更新策略和持久化？
- 是否使用自定义 Gitee Store，而不是再维护 Appcast？
- 是否只匿名访问 Gitee latest API？
- 是否完全没有 Gitee Token？
- 是否精确匹配 APK/checksum，而不是取第一个 asset？
- 是否限制 HTTPS 和预期 host？
- 是否限制 Release notes 长度并按文本展示？
- Store 是否捕获预期异常，不让自动检查破坏启动？
- 是否有进程内 TTL、失败退避和并发合并？
- Upgrader 和 Store 是否都是单实例？
- 是否没有在 Widget build 中创建 Upgrader？
- 是否覆盖 `onUpdate` 并返回 `false`？
- 是否使用外部应用打开 APK，而不是 Upgrader 默认商店模式？
- 是否没有 App 内下载进度和任务恢复？
- 是否没有 Kotlin updater、MethodChannel、FileProvider 和安装权限？
- 手动检查是否不清空忽略状态？
- Gitee Release 是否由维护者手工发布？
- 是否同时提升 versionName 和 versionCode？
- 是否继续使用同一 JKS？
- 是否完成旧版到新版真机覆盖安装？
- 是否没有影响论坛、收藏、漫画、小说和阅读器？

## 17. Definition of Done

只有同时满足以下条件，简化更新功能才算完成：

1. App 能匿名读取公开 Gitee latest Release。
2. 自定义 Store 能把严格有效的 Release 映射给 Upgrader。
3. 非 canonical Tag、Prerelease、错误附件和 HTTP URL 不会产生提示。
4. Upgrader 是安装版本读取、版本比较、忽略和提醒间隔的唯一所有者。
5. App 启动和恢复前台不会高频请求 Gitee。
6. 自动检查失败不影响启动和其它业务。
7. 新版本能展示 UpgradeAlert 和 Release notes。
8. 点击更新覆盖默认商店行为，并能用外部浏览器打开精确 APK URL。
9. 下载进度由浏览器/Android 系统展示。
10. 安装由用户主动发起并由 Android 系统确认。
11. Y300 不包含 DownloadManager 更新桥接、下载任务状态或安装权限。
12. Gitee Release 由维护者手工发布，客户端和 CI 均无 Gitee Token。
13. APK/checksum 命名、版本递增和签名纪律得到遵守。
14. `package_info_plus 10.2.1` 依赖冲突没有被 override 掩盖。
15. 完成一次旧版到新版的真实覆盖安装演练。
16. 小说网络继续固定使用 `version=1`，其它模块无行为回归。
