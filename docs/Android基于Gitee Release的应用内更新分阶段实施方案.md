# Y300 Android 基于 Gitee Release 的应用内更新分阶段实施方案

> 文档日期：2026-07-18
> 适用范围：Y300 Android arm64-v8a 自分发版本
> 更新源：公开 Gitee Release API
> 下载内核：Android `DownloadManager`
> 安装方式：Android 系统安装器，用户显式确认

## 1. 结论与关键决策

Y300 的第一版应用内更新不增加稳定 JSON，也不把 Gitee Token 放入客户端。App 直接读取公开仓库的 Gitee 最新 Release，按固定 Tag 和附件命名协议解析版本与 APK，再交给 Android `DownloadManager` 后台下载。

完整链路如下：

```text
CI 构建并签名 arm64 APK
  -> 创建 Gitee 正式 Release
  -> 上传唯一匹配的 arm64 APK 与对应 .apk.sha256
  -> App 请求 latest Release API
  -> 用 Tag 中的严格 SemVer versionName 判断是否有更新
  -> 用户确认下载
  -> 获取并严格解析最多 1 KiB 的 checksum 文本
  -> Android DownloadManager 后台下载并显示系统通知进度
  -> App 前台查询同一任务并展示进度
  -> 流式计算 APK SHA-256 并与 Release checksum 比较
  -> 下载完成后校验包名、versionName、versionCode 和签名证书
  -> 用户点击安装
  -> Android 系统安装器再次校验并请求用户确认
```

本方案确定以下原则：

1. 更新发现比较 Tag 与本地 `PackageInfo.version` 的严格 SemVer `versionName`，禁止普通字符串或小数比较。
2. 每次正式发布都必须同时提升 `versionName` 和 Android `versionCode`；`versionCode` 不进入 Gitee Tag，只在 APK 内部参与安装前校验和 Android 覆盖安装。
3. App 只访问公开 Gitee API 和公开 Release 附件，不包含发布 Token。
4. 后台下载使用系统 `DownloadManager`，不自行维持 Flutter 后台 isolate。
5. 通知栏下载进度由系统下载服务负责，Flutter 页面只观察任务状态。
6. 下载完成后不在后台强行弹出安装页，由用户点击“安装”或完成通知。
7. 第一版不支持强制更新、灰度发布、多渠道和多 ABI。
8. 第一版要求每个 APK 同时发布唯一精确的 `.apk.sha256` 文本附件；checksum 用于发现传输损坏或错误附件，不替代 APK 签名、证书匹配和 Android 安装器校验，也不提供“缺失时跳过”的兜底。
9. 更新功能不得阻塞 App 启动，不得影响论坛、收藏、漫画、小说及现有下载模块。
10. Gitee API、下载与安装分别通过小型接口隔离，不把所有逻辑塞进页面或单个 service。

## 2. 目标与非目标

### 2.1 本轮目标

- 在“更多”页面提供“检查更新”入口并展示当前版本。
- App 启动后按频率限制静默检查 Gitee 最新正式 Release。
- 展示版本名称、更新说明、发布时间；APK 大小仅在服务端或下载任务能够提供时展示，未知时不显示占位值。
- 支持用户确认后在后台下载 APK。
- App 前台显示下载进度，App 退出后系统通知继续显示进度。
- App 被系统杀死或重启后能够恢复并查询原下载任务。
- 下载完成后检查 APK 包名、版本号和签名证书。
- 正确引导 Android 8 及以上授予“安装未知应用”权限。
- 调起 Android 系统安装器，由用户最终确认覆盖安装。
- CI 自动构建、签名、创建 Gitee Release 并上传 APK。

### 2.2 明确不做

- 不实现静默安装、Root 安装或设备管理器安装。
- 不实现 Android 之外的平台更新。
- 不接入 Google Play、应用商店或 Play In-App Updates。
- 不支持 x86、armeabi-v7a 或通用 APK。
- 不在 App 中存储 Gitee 私人访问令牌。
- 不从 Release 正文解析任意脚本或可执行配置。
- 不在第一版实现强制更新或最低可用版本。
- 不让自动更新复用漫画下载、图片缓存或小说水合的业务状态。

## 3. 当前项目基线

当前 `pubspec.yaml` 使用 Flutter 标准版本格式：

```yaml
version: 0.0.1+4
```

含义为：

```text
versionName = 0.0.1
versionCode = 4
```

现有 `.github/workflows/android-arm64-release.yml` 已具备：

- Java 17 和 Flutter stable 环境；
- `flutter analyze`；
- 从 CI Secrets 恢复 Android JKS；
- `--target-platform android-arm64` 构建 arm64-only APK；
- Android Components variant API 仅在 Release 打包阶段通过 `packaging.jniLibs.excludes` 移除插件附带的 `armeabi-v7a/x86/x86_64` 原生库，不影响 Debug 模拟器；
- `--build-name` 与 `--build-number` 覆盖版本；
- Gradle 按 `y300-v{versionName}-android-arm64-v8a-release.apk` 输出正式 APK；
- 从 `build/app/outputs/apk/release` 精确上传 GitHub Artifact。

现有不足：

- GitHub Artifact 只有临时保留期，不能作为客户端更新源；
- workflow 没有创建 Gitee Release；
- 版本输入、`pubspec.yaml`、Tag、APK 文件名之间没有一致性校验；
- App 没有 Gitee Release DTO、版本策略、下载任务和安装能力；
- `pubspec.yaml` 尚未引入 `package_info_plus`；
- Android Manifest 尚未为应用内 APK 安装建立明确合同。

## 4. 总体架构

新增独立 `app_update` feature，避免更新逻辑进入 `more`、`storage` 或通用网络模块内部。

```text
lib/features/app_update
  domain
    models
      app_release.dart
      app_update_decision.dart
      app_update_download.dart
    repositories
      app_release_repository.dart
      installed_app_version_repository.dart
      update_check_preferences_repository.dart
    services
      app_update_policy.dart
      update_download_service.dart
      update_installer.dart
  data
    gitee
      gitee_release_api.dart
      gitee_release_dto.dart
      gitee_release_parser.dart
      gitee_app_release_repository.dart
    package_info
      package_info_installed_version_repository.dart
    preferences
      shared_preferences_update_check_repository.dart
    platform
      method_channel_update_download_service.dart
      method_channel_android_update_installer.dart
    providers
      app_update_providers.dart
  presentation
    controllers
      app_update_controller.dart
    widgets
      app_update_sheet.dart
      app_update_progress.dart
```

Android 原生侧建议新增：

```text
android/app/src/main/kotlin/.../update
  AppUpdateChannel.kt
  AndroidDownloadManagerGateway.kt
  ApkInstallValidator.kt
  ApkInstaller.kt
  UpdateDownloadModels.kt
```

### 4.1 模块边界

- `app_update` 可以依赖 `core/network` 的 Dio 基础设施，但不得依赖漫画、小说或收藏 repository。
- `more` 页面只负责打开检查入口和更新面板，不执行 Gitee 请求或文件下载。
- Flutter domain 不直接依赖 MethodChannel、Android URI 或 `DownloadManager` 常量。
- Kotlin 层不解析 Gitee Release，也不决定是否存在新版本。
- CI 发布逻辑不进入 App 运行时代码。
- 更新 APK 不计入漫画下载或普通图片缓存统计，使用独立生命周期。

## 5. Gitee Release 发布协议

### 5.1 仓库与访问控制

用于 App 检查更新的 Gitee 仓库必须公开。客户端调用类似以下接口：

```http
GET https://gitee.com/api/v5/repos/{owner}/{repo}/releases/latest
```

已于 2026-07-18 使用公开仓库完成匿名请求验证：

```http
GET https://gitee.com/api/v5/repos/QAQadws/y300-releases/releases/latest
```

真实响应确认可直接获得 `tag_name`、`prerelease`、`name`、`body`、`created_at`，以及附件的 `name/browser_download_url`。当前 Release 同时包含唯一 APK、唯一 `.apk.sha256` 和 Gitee 自动生成的源码 `.zip/.tar.gz`；客户端必须按两个精确文件名筛选，不能取前两个 asset 或按数组位置猜测。

真实响应没有 `draft`、`published_at`、`html_url` 和附件大小字段，因此客户端不得把这些 GitHub 风格字段设为 Gitee 协议必填项。当前手工 Release `v0.0.1` 的 APK 与 checksum 附件已符合下述公开发布协议，可作为 Phase 0 的真实基线 fixture。

Phase 0 已把真实响应和 checksum 文本脱敏后保存为 fixture，并实际验证 APK/checksum URL 均可匿名获取。若后续发现不可接受的匿名限流，禁止把 CI Token 写入 APK；届时再评估公开代理或静态清单，不能偷偷降级为客户端携带私钥。

### 5.2 Tag 规范

正式 Release Tag 固定为：

```text
v{versionName}
```

示例：

```text
v1.0.4
```

客户端使用严格正则解析：

```text
^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$
```

解析结果：

```text
versionName = 1.0.4
```

不满足协议的 Tag 视为无效 Release，不尝试猜测或宽松修复。第一版不接受 `v1.0`、前导零、`v1.0.0-beta`、`v1.0.0+5` 或其它预发布/构建元数据形式。

客户端使用直接依赖的 `pub_semver` 解析并比较去掉 `v` 后的版本，不能使用字符串比较、浮点数比较或自行拼接权重。Tag、Release 标题和更新 UI 均只展示 `versionName`；内部 `versionCode` 仍由 `pubspec.yaml` 写入 APK，但不属于 Gitee Release 发现协议。

### 5.3 APK 与 checksum 附件命名

APK 文件名只包含用户版本和 ABI，不显示内部 `versionCode`：

```text
y300-v{versionName}-android-arm64-v8a-release.apk
```

示例：

```text
y300-v1.0.4-android-arm64-v8a-release.apk
```

同一 Release 必须额外提供：

```text
y300-v{versionName}-android-arm64-v8a-release.apk.sha256
```

checksum 使用 UTF-8/ASCII 兼容的 canonical `sha256sum` 单行格式，允许文件末尾最多一个换行：

```text
{64位小写十六进制摘要}  {完整APK文件名}
```

摘要与文件名之间固定两个 ASCII 空格。checksum 响应最多 1 KiB，不接受大写摘要、单空格、额外行、额外字段或错误文件名。

客户端根据已解析的 `versionName` 生成 APK 和 checksum 两个期望文件名，并要求 assets 中各自恰好存在一个完全同名附件。发布协议禁止用相同 `versionName` 仅提升 `versionCode` 后重新发版，因为客户端不会把相同 Tag 识别为更新；修复版必须同时提升 patch 版本和 `versionCode`。以下情况均判为 Release 配置错误：

- 找不到匹配附件；
- 存在多个同名附件；
- checksum 缺失、重复或 URL 不是 HTTPS；
- 只有 32 位或通用 APK；
- 附件 URL 不是 HTTPS；
- 下载地址为空；
- Release 是 Prerelease。

远端 SemVer 不大于已安装 SemVer 不是协议错误，而由 `AppUpdatePolicy` 分别解释为“已是最新”或“本地开发版更高”，不得提示降级。

### 5.4 Release 正文

`body` 仅作为纯文本或受限 Markdown 更新说明展示，不作为配置协议。客户端不得从正文解析：

- 强制更新标志；
- 下载 URL；
- versionCode；
- 任意命令或 HTML 脚本。

Gitee API 没有返回 Release 页面 URL。data repository 使用已配置的公开仓库 Releases 页面作为“在浏览器中查看”的故障回退入口，不从不可信正文中读取或拼接跳转地址。

### 5.5 Gitee DTO 防腐层

Gitee API 响应只存在于 data 层 DTO，presentation 和 domain 不得引用 `tag_name`、`browser_download_url` 等供应商字段。

```dart
class GiteeReleaseDto {
  const GiteeReleaseDto({
    required this.tagName,
    required this.name,
    required this.body,
    required this.prerelease,
    required this.createdAt,
    required this.assets,
  });
}
```

附件 DTO 只读取真实存在的 `name` 与 `browser_download_url`。parser 将唯一 APK 与唯一 checksum URL 映射为同一个 `AppReleaseAsset`；checksum 文本内容不在 latest JSON 中，留给下载阶段的小型 repository 获取。`id`、`target_commitish`、`author` 和自动生成的源码附件属于供应商附加信息，不进入 domain。

DTO parser 必须对缺字段、错误类型、空数组、未知额外字段和时间格式错误做显式处理。未知额外字段忽略；`body` 可为空，`created_at` 解析失败可降级为未知时间，其余协议必需字段错误则返回可分类失败，不抛到页面。Gitee 不返回附件大小，repository 初始映射为 `sizeBytes=null`，不得为了显示大小而阻塞版本检查；Phase 2 可使用 `DownloadManager` 的 `totalBytes` 补齐下载进度。

## 6. 领域模型

### 6.1 已安装版本

```dart
class InstalledAppVersion {
  const InstalledAppVersion({
    required this.packageName,
    required this.versionName,
    required this.semanticVersion,
    required this.versionCode,
  });

  final String packageName;
  final String versionName;
  final Version semanticVersion;
  final int versionCode;
}
```

`Version` 来自直接依赖的 `pub_semver`。`package_info_plus` 的 `version` 必须解析为三段稳定 SemVer，`buildNumber` 必须严格转换为正整数；任一字段非法都属于本地版本读取错误，不能通过字符串比较或把 buildNumber 默认为 0 后继续更新。

### 6.2 Release 与附件

```dart
class AppReleaseAsset {
  const AppReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.abi,
    required this.checksum,
  });

  final String name;
  final Uri downloadUrl;
  final int? sizeBytes;
  final String abi;
  final AppReleaseChecksumAsset checksum;
}

class AppReleaseChecksumAsset {
  const AppReleaseChecksumAsset({
    required this.name,
    required this.downloadUrl,
  });

  final String name;
  final Uri downloadUrl;
}

class AppReleaseChecksum {
  const AppReleaseChecksum({
    required this.sha256Hex,
    required this.fileName,
  });

  final String sha256Hex;
  final String fileName;
}

class AppRelease {
  const AppRelease({
    required this.tag,
    required this.versionName,
    required this.semanticVersion,
    required this.title,
    required this.releaseNotes,
    required this.releasedAt,
    required this.releasePageUrl,
    required this.apk,
  });

  final String tag;
  final String versionName;
  final Version semanticVersion;
  final String title;
  final String releaseNotes;
  final DateTime? releasedAt;
  final Uri releasePageUrl;
  final AppReleaseAsset apk;
}
```

`releasedAt` 映射自 Gitee `created_at`；`releasePageUrl` 来自 repository 的公开仓库配置，而不是 Gitee DTO。`AppReleaseAsset.sizeBytes` 对 Gitee latest 响应通常为 `null`，UI 必须允许省略大小。

### 6.3 更新决策

```dart
sealed class AppUpdateDecision {
  const AppUpdateDecision();
}

class AppUpToDate extends AppUpdateDecision {}

class AppUpdateAvailable extends AppUpdateDecision {
  const AppUpdateAvailable(this.release);
  final AppRelease release;
}

class AppUpdateCheckFailed extends AppUpdateDecision {
  const AppUpdateCheckFailed(this.failure);
  final AppUpdateFailure failure;
}
```

`AppUpdatePolicy` 只做纯函数判断：

```dart
abstract interface class AppUpdatePolicy {
  AppUpdateDecision evaluate({
    required InstalledAppVersion installed,
    required AppRelease latest,
  });
}
```

规则固定为：

```text
latest.semanticVersion > installed.semanticVersion -> 有更新
latest.semanticVersion == installed.semanticVersion -> 已是最新
latest.semanticVersion < installed.semanticVersion -> 本地为更高开发版，不提示降级
```

更新发现阶段不使用远端 `versionCode`，因为 Gitee latest API 与协议 Tag 都不提供它。Android `versionCode` 只在 APK 下载完成后从归档 Manifest 读取，并验证其严格大于当前安装包；这两层规则分别负责“发现新版本”和“允许覆盖安装”。

### 6.4 下载任务

```dart
enum UpdateDownloadStatus {
  idle,
  pending,
  running,
  paused,
  successful,
  failed,
  canceled,
  missing,
}

class UpdateDownloadSnapshot {
  const UpdateDownloadSnapshot({
    required this.taskId,
    required this.targetTag,
    required this.targetVersionName,
    required this.status,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.localUri,
    required this.failureReason,
  });

  final int taskId;
  final String targetTag;
  final String targetVersionName;
  final UpdateDownloadStatus status;
  final int downloadedBytes;
  final int? totalBytes;
  final Uri? localUri;
  final String? failureReason;
}
```

当 `totalBytes` 缺失或为 0 时，UI 使用不确定进度，不伪造百分比。

## 7. 接口设计

```dart
abstract interface class AppReleaseRepository {
  Future<AppRelease> getLatestStableRelease();
}

abstract interface class InstalledAppVersionRepository {
  Future<InstalledAppVersion> getInstalledVersion();
}

abstract interface class AppReleaseChecksumRepository {
  Future<AppReleaseChecksum> getChecksum(AppReleaseAsset asset);
}

abstract interface class UpdateDownloadService {
  Future<int> enqueue(AppRelease release);

  Future<UpdateDownloadSnapshot> query(int taskId);

  Stream<UpdateDownloadSnapshot> watch(int taskId);

  Future<void> cancel(int taskId);
}

abstract interface class UpdateInstaller {
  Future<ApkValidationResult> validate(int taskId);

  Future<InstallPermissionState> getPermissionState();

  Future<void> openInstallPermissionSettings();

  Future<void> launchInstaller(int taskId);
}

abstract interface class UpdateCheckPreferencesRepository {
  Future<AppUpdateRuntimeState> load();

  Future<void> save(AppUpdateRuntimeState state);
}
```

repository、policy、download service 和 installer 必须可独立替换为 fake，controller 测试不得启动真实 Gitee 请求或 Android 下载任务。

## 8. 更新状态机

页面状态应由一个不可变模型表达，不能靠多个互相矛盾的 bool 拼接。

```text
idle
  -> checking
      -> upToDate
      -> available
      -> checkFailed

available
  -> preparingDownload
      -> checksumInvalid
      -> downloadFailed
      -> enqueueing
          -> downloading

downloading
  -> paused
  -> downloaded
  -> downloadFailed
  -> canceled

downloaded
  -> verifyingChecksum
      -> checksumInvalid
      -> validating
          -> readyToInstall
          -> invalidPackage

readyToInstall
  -> permissionRequired
  -> launchingInstaller
```

状态转换必须满足：

- 同一 canonical Tag 最多只有一个活跃下载任务；
- checksum 缺失、格式错误或无法获取时不得 enqueue APK 下载；
- 重复点击“下载”返回当前任务，不重复 enqueue；
- 新 Release 出现时，不自动取消正在下载的旧 Release；
- 已安装 SemVer 不低于任务目标 SemVer 时，清理任务引用并回到 idle；
- 页面销毁只停止 UI 观察，不取消系统下载；
- controller dispose 后任何轮询结果不得更新状态；
- 失败状态保留可理解原因和重试入口。

## 9. 检查更新策略

### 9.1 手动检查

“更多”页面提供明确入口：

```text
检查更新
当前版本 1.0.3
```

手动检查行为：

- 总是发起请求，不受自动检查 24 小时窗口限制；
- 检查中禁用重复点击；
- 最新版本时显示短暂反馈；
- 网络失败时显示可重试错误；
- 发现更新时打开更新 BottomSheet。

### 9.2 自动检查

自动检查在主壳首帧完成后异步启动，不放在 `main()` 阻塞 `runApp()`：

- 默认每 24 小时最多成功检查一次；
- 失败后至少间隔 1 小时再自动重试；
- 静默检查发现已是最新时不显示消息；
- 静默检查失败时不显示 Snackbar；
- 发现更新时才展示更新入口；
- 用户本次忽略某个 canonical Tag 后，该版本不再自动弹出，但手动检查仍展示；
- 新的更高 SemVer Tag 可以再次自动提示。

### 9.3 网络要求

- 请求超时建议 5 到 8 秒；
- 只允许 HTTPS；
- Gitee API 错误、超时、限流和 JSON 错误分别分类；
- 不重试 4xx 协议错误；
- 网络错误只做少量带抖动重试；
- 日志只记录状态码、Tag 和错误类别，不记录 Token 或完整敏感 URL；
- Gitee API 改变字段时，App 保持可用，只将检查结果视为失败。

## 10. Android DownloadManager 方案

### 10.1 为什么不照搬 2022 教程

教程中的 `flutter_downloader + WorkManager + isolate + app_installer` 可以表达基本概念，但不应直接复制：

- 下载任务 ID 只保存在 Widget 内，重启后会失联；
- 手工修改 WorkManager initializer 容易与新插件和 AndroidX Startup 冲突；
- 回调入口在新 Flutter 下还涉及 tree shaking 和 `@pragma('vm:entry-point')`；
- 旧存储权限不适用于 Scoped Storage；
- Widget 直接持有并修改 State，不符合当前 Riverpod 架构；
- 下载完成后自动弹安装页不符合后台 Activity 限制；
- URL 截取文件名无法可靠处理 Gitee 重定向。

Y300 当前只做 Android，直接通过小型 Kotlin bridge 使用系统 `DownloadManager` 更简单、稳定，也更容易恢复进程外任务。

### 10.2 MethodChannel 合同

建议使用独立 channel：

```text
com.y300/app_update
```

方法：

```text
enqueueDownload
queryDownload
cancelDownload
computeDownloadedSha256
validateDownloadedApk
getInstallPermissionState
openInstallPermissionSettings
launchInstaller
```

`enqueueDownload` 输入：

```json
{
  "url": "https://...",
  "fileName": "y300-v1.0.4-android-arm64-v8a-release.apk",
  "title": "Y300 1.0.4",
  "targetTag": "v1.0.4",
  "targetVersionName": "1.0.4"
}
```

输出为 Android `DownloadManager` 的 `long` task ID。Flutter 转换为 Dart `int`，不得截断为 32 位。

`queryDownload` 输出：

```json
{
  "taskId": 123,
  "status": "running",
  "downloadedBytes": 10485760,
  "totalBytes": 31457280,
  "localUri": null,
  "failureReason": null
}
```

Kotlin 内部将 Android 常量转换为稳定字符串，Flutter 不依赖平台整数常量。

`computeDownloadedSha256(taskId)` 必须通过 DownloadManager 返回的 content URI 流式读取文件并返回 64 位小写十六进制摘要，不把 APK 字节跨 MethodChannel 传给 Dart，也不一次性读入内存。Dart 使用 Phase 0 的 `AppReleaseChecksum` 做精确比较；不匹配时删除错误 APK、保留可诊断失败并禁止进入 PackageManager 校验。

### 10.3 下载请求配置

推荐：

- enqueue 前通过独立 checksum repository 获取 `.apk.sha256`，响应上限 1 KiB、短超时、只允许 HTTPS，并使用 Phase 0 纯 parser 验证单行格式与 APK 文件名；
- 使用 Gitee asset 明确文件名；
- 允许系统处理 HTTPS 重定向；
- 目标目录使用 App 专属外部文件目录的 updates 子目录；
- 使用 `VISIBILITY_VISIBLE_NOTIFY_COMPLETED`；
- 标题包含目标版本；
- 描述只写“正在下载更新”；
- 是否允许移动网络遵循普通系统下载行为，不默认强制 Wi-Fi；
- 不申请旧 `READ_EXTERNAL_STORAGE` 或 `WRITE_EXTERNAL_STORAGE`；
- enqueue 前检查已有相同目标任务，避免重复文件。

### 10.4 App 内进度

Flutter 页面只在以下条件下观察任务：

- 更新面板可见；
- “更多”页更新区域可见；
- App 从后台恢复且存在活跃任务。

观察方式以 `queryDownload(taskId)` 为权威来源，每 500 到 1000 ms 查询一次即可。可增加 EventChannel 优化前台即时性，但不能把 EventChannel 当唯一事实来源，因为 App 被杀死时事件会丢失。

进度计算：

```text
totalBytes > 0 -> downloadedBytes / totalBytes
totalBytes <= 0 -> 不确定进度
```

不要每个网络数据块都触发 Flutter rebuild，也不要自行高频刷新通知栏。

### 10.5 通知栏进度

下载期间优先使用 DownloadManager 自带通知，不用 `flutter_local_notifications` 重复创建第二条进度通知。这样即使 Flutter 进程退出，系统仍能继续下载和更新通知。

下载完成后的安装入口有两种展示位置，但安装动作始终由用户触发：

- App 回到前台后显示“下载完成，安装”；
- 后续阶段可增加一条“点击安装”的应用通知，点击后进入 App 更新页。

如果使用应用自己的完成通知，需要遵循 Android 13 通知权限；不应因为用户拒绝通知权限而影响下载任务本身。

### 10.6 下载任务恢复

SharedPreferences 保存固定规模运行状态：

```json
{
  "schemaVersion": 1,
  "taskId": 123,
  "targetTag": "v1.0.4",
  "targetVersionName": "1.0.4",
  "assetName": "y300-v1.0.4-android-arm64-v8a-release.apk",
  "expectedSha256": "64位小写十六进制摘要",
  "startedAt": "2026-07-18T12:00:00Z"
}
```

这些 key 属于技术运行状态，放入 `TechnicalStorageKeys`，不进入普通个性化重置域。不得存储 Gitee Token。

App 启动恢复规则：

1. 没有 task ID，保持 idle。
2. task ID 存在，向 DownloadManager 查询。
3. `pending/running/paused`，恢复下载 UI。
4. `successful`，先流式计算 APK SHA-256 并与持久化期望摘要比较，通过后才进入 APK 校验。
5. `failed`，保留失败信息并允许重新创建任务。
6. `missing`，清除陈旧运行状态。
7. 当前已安装 SemVer 不低于 `targetVersionName`，说明更新已经完成或本地版本更高，清理任务和旧 APK 引用。

## 11. APK 校验与安装

### 11.1 安装前校验

DownloadManager 成功不等于可安装。进入 Kotlin `ApkInstallValidator` 前必须已经完成 APK SHA-256 比较；随后使用 `PackageManager` 读取归档信息并检查：

1. APK 可以被 PackageManager 解析；
2. archive package name 等于当前 `applicationId`；
3. archive versionName 可解析为稳定 SemVer，且与 Release Tag 的目标 `versionName` 完全一致；
4. archive versionCode 是正整数且严格大于当前安装值；
5. archive signing certificate digest 等于当前已安装 App 的证书摘要；
6. 下载任务状态确实为 successful；
7. DownloadManager 返回可读取的 content URI。

Android 系统安装器最终还会再次验证签名。提前校验的价值是把“下载了错误 APK”“CI 用错 JKS”等问题转换成 App 内可理解错误，而不是把用户直接送进失败安装页。

`.sha256` 与 APK 来自同一 Release，因此它能发现传输损坏、CDN 错误和误上传，但不能单独对抗同时替换两项附件的仓库入侵。真实性仍由当前安装证书、archive 证书和 Android 系统安装器保证；checksum 校验不得替代或跳过签名校验。

### 11.2 安装权限

Manifest 需要：

```xml
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
```

Android 8 及以上通过：

```text
PackageManager.canRequestPackageInstalls()
```

判断当前 App 是否获准安装未知应用。未授权时：

```text
ACTION_MANAGE_UNKNOWN_APP_SOURCES
package:{applicationId}
```

打开系统设置。用户返回 App 后重新检查，不假定权限已授予。

这不是普通运行时权限，不能把它当作存储权限弹窗处理。

### 11.3 调起系统安装器

采用单一策略：从 `DownloadManager.getUriForDownloadedFile(taskId)` 获取 content URI，再启动：

```text
Intent.ACTION_VIEW
MIME application/vnd.android.package-archive
FLAG_GRANT_READ_URI_PERMISSION
FLAG_ACTIVITY_NEW_TASK（仅在非 Activity context 需要）
```

不传 `file://` 路径，不复制教程中的重复 FileProvider，不在后台直接启动安装 Activity。

### 11.4 无法静默安装

普通 Android App 不能静默覆盖安装。最终流程必须包含系统确认：

```text
用户点击安装
  -> 系统安装器展示包信息
  -> 用户确认
  -> Android 验证包名、版本和签名
  -> 安装完成
```

## 12. UI 与交互

### 12.1 更新面板

推荐使用底部抽屉，与当前“外观与文字”等页面交互保持一致，不复制教程中的自管理 `UpgradeCard`。

可用状态：

```text
有更新：版本、更新说明、大小、下载按钮、稍后提醒
下载中：线性/不确定进度、字节数、后台继续提示、取消按钮
暂停：系统原因、继续等待或取消
失败：错误说明、重试、浏览器打开 Release
下载完成：安装按钮
需要权限：前往系统设置按钮
包无效：明确说明签名/包名/版本错误，禁止安装
```

### 12.2 进度显示

- 进度条由 controller state 驱动，不从 Widget 外部持有 State；
- 更新 state 使用 Riverpod，不直接修改 Widget 字段；
- 页面关闭后系统下载继续；
- 重新打开时从持久化 task ID 恢复；
- 进度未知时显示循环进度，不显示 `0%`；
- 下载完成后不自动关闭面板；
- 下载失败不自动无限重试。

### 12.3 忽略更新

第一版只支持普通更新：

- “稍后提醒”只记录当前 canonical Tag；
- 手动检查仍可看到该版本；
- 更高版本自动解除忽略；
- 不提供永久忽略所有未来版本；
- 不使用不可退出的强制弹窗。

## 13. CI/CD 发布全流程

### 13.1 版本单一来源

推荐以提交中的 `pubspec.yaml version` 为单一事实来源，并由 Git Tag确认：

```text
pubspec.yaml: 1.0.4+5
Git Tag:      v1.0.4
Release Tag:  v1.0.4
APK:          y300-v1.0.4-android-arm64-v8a-release.apk
```

workflow 不应允许四处独立填写版本。推荐改为 Tag 触发：

```yaml
on:
  push:
    tags:
      - 'v*'
```

CI 首先解析 `pubspec.yaml`，并断言：

```text
git tag == v${pubspec versionName}
```

CI 还必须从 `pubspec.yaml` 独立读取正整数 `versionCode`。当前 source Tag 相比上一个正式 source Tag，必须同时满足 SemVer `versionName` 更高且 `versionCode` 更高；Tag 虽然不展示 build number，但不能失去 Android 安装序列的单调性。若继续保留 `workflow_dispatch` 输入，也必须断言输入与 `pubspec.yaml` 一致，不能只覆盖构建参数而留下源文件版本漂移。

### 13.2 CI Secrets 与 Variables

继续保留 Android 签名 Secrets：

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

新增：

```text
GITEE_TOKEN
GITEE_OWNER
GITEE_RELEASE_REPO
```

其中：

- `GITEE_TOKEN` 使用最小可用权限；
- Token 只存在 CI Secrets；
- owner/repo 可使用 repository variables；
- 日志不得输出 Token；
- curl 失败输出需避免打印带 `access_token` 的完整 URL；
- 定期轮换 Token；
- App 代码、Release 正文和 APK 均不得包含 Token。

### 13.3 构建步骤

```text
1. Checkout Tag 对应 commit
2. 验证 Tag 与 pubspec versionName，并验证 versionName/versionCode 均高于上一个正式 source Tag
3. 设置 Java 17
4. 设置 Flutter stable
5. flutter pub get
6. flutter analyze
7. 运行发布门禁测试
8. 恢复 JKS 与 key.properties
9. flutter build apk --release --target-platform android-arm64
10. 断言 Gradle 正式产物文件名与协议完全一致
11. 生成 canonical `${APK}.sha256` 并本地回读验证
12. 用 apkanalyzer/aapt 验证 APK package、versionName、versionCode
13. 验证 APK 签名证书摘要与发布基线一致
14. 创建 Gitee Release
15. 上传唯一 APK 与唯一 checksum asset
16. 匿名回读 latest API、APK 和 checksum，重新计算远端 APK SHA-256 并与 checksum 比较
17. 清理 runner 中的 JKS 和临时配置
```

### 13.4 发布原子性

若 Gitee 发布 API 支持更新 Prerelease 状态，理想流程是：

```text
创建 Prerelease
  -> 上传并验证 APK + checksum
  -> 切换为正式 Release
```

真实 latest 响应没有 `draft` 字段，客户端不能依赖 Draft 语义。Phase 5 实现 CI 时需确认 Gitee API 是否支持“Prerelease 上传后转正式”。若不支持，则先创建正式 Release 再立即上传附件；客户端通过 `prerelease=false + 严格 Tag + 唯一 APK + 唯一 checksum`共同验收 Release，在短暂的不完整窗口返回 `assetMissing/checksumAssetMissing` 并静默忽略，两项上传完成后下一次检查自然恢复。

发布 API 的具体 endpoint、请求字段和返回字段必须以实现时的 Gitee 官方文档及真实响应 fixture 为准。CI 脚本应把供应商细节封装在单独步骤或脚本中，不散落在多个 YAML step。

### 13.5 幂等与冲突

- 同一 Tag 已有正式 Release 时默认失败，不覆盖；
- 同一 versionName 或同一 versionCode 都不允许重新上传不同 APK；
- 不复用已发布 Tag；
- 上传失败的 Prerelease 可以人工删除后重试；正式 Release 不覆盖、不复用 Tag；
- CI 根据 source Tag 对应提交中的 `pubspec.yaml` 检查上一正式版本，要求新 `versionName` 与 `versionCode` 都更大；Gitee latest 本身不提供 versionCode，不能从 Release 正文猜测；
- 两项附件上传后验证文件名、大小，并匿名回读比较 APK 与 checksum；
- API latest 返回的 Tag 必须等于本次发布 Tag 才算成功。

### 13.6 回滚策略

Android 不允许正常降级。错误版本的修复方式是同时发布更高 patch 版本和更高 versionCode：

```text
错误版 1.0.4+5
修复版 1.0.5+6
```

不能发布 `1.0.4+6`，因为只看 Tag `v1.0.4` 的客户端无法发现它；也不能删除错误 Release 后复用 `v1.0.4` 上传另一份 APK。保留至少最近几个正式 APK，方便定位问题，但 App 永远只检查最新正式版本。

## 14. 安全模型

### 14.1 信任链

```text
CI Secrets 中的 JKS
  -> 签名 APK
  -> Gitee HTTPS 分发
  -> App 安装前证书摘要检查
  -> Android 系统安装器签名检查
```

最重要资产是 JKS：

- JKS 不能提交到仓库；
- 至少保留两份离线备份；
- 备份密码与文件分离；
- 发布后不能随意更换签名证书；
- CI 应锁定期望证书指纹，避免错误密钥产出不可更新 APK。

### 14.2 Gitee Token

Gitee 发布 Token 只用于 CI 创建 Release 和上传附件。公开客户端只读匿名 API。若匿名 latest API 不可用，必须调整服务端分发方式，不能把 Token 混淆、加密后放进 App，因为 APK 中的任何静态秘密都可被提取。

### 14.3 下载内容

- 限制为 HTTPS；
- 只接受协议文件名；
- 检查下载状态和可读取 URI；
- 使用 PackageManager 解析 APK；
- 校验 packageName、versionName、versionCode 和签名证书；
- 不执行 Release 正文；
- 不安装低版本或同版本 APK；
- 不把下载文件当作普通压缩包解压；
- 安装失败时保留可诊断错误，但不记录凭据。

## 15. 持久化边界

更新运行状态是固定规模技术状态，适合 SharedPreferences，但不属于个性化设置：

```text
app_update.last_successful_check_at_ms
app_update.last_failed_check_at_ms
app_update.dismissed_release_tag
app_update.active_download.v1
```

应放入 `TechnicalStorageKeys` 或更新模块自己的技术 key 注册表，并满足：

- “恢复默认设置”不删除活跃下载；
- 清理普通图片缓存不删除正在下载的 APK；
- 用户取消下载时删除对应 APK 与 active task；
- 更新安装完成后清理旧任务引用和过期 APK；
- 登出论坛账号不影响应用更新任务；
- 不把 Gitee Token、JKS 密码或 Cookie 写入更新状态。

## 16. 错误模型

禁止只返回一个“更新失败”。至少区分：

```text
networkUnavailable
requestTimeout
giteeRateLimited
giteeUnauthorized
releaseNotFound
invalidPayload
missingRequiredField
invalidFieldType
invalidTag
prerelease
assetMissing
assetAmbiguous
invalidAssetUrl
checksumAssetMissing
checksumAssetAmbiguous
invalidChecksumAssetUrl
checksumMalformed
checksumFileNameMismatch
checksumMismatch
invalidLocalVersion
downloadEnqueueFailed
downloadPaused
downloadFailed
downloadTaskMissing
insufficientStorage
apkUnreadable
packageNameMismatch
versionNameMismatch
versionCodeNotNewer
signatureMismatch
installPermissionDenied
installerUnavailable
```

用户文案与诊断日志分离。页面显示可行动信息，例如“下载失败，请重试”；Debug 日志记录稳定错误 code 和平台 reason，不把原始异常堆栈直接展示给用户。

## 17. 测试计划

### 17.1 Domain 单元测试

- SemVer `versionName` 大于、等于、小于本地版本；
- 相同 `versionName` 即使测试数据声称内部 build 更高也不得误报更新；正式发布必须提升版本名；
- 本地 buildNumber 非法时失败；
- 严格 Tag 成功和失败样例；
- 数字语义比较 `1.0.10 > 1.0.9`，拒绝字符串字典序和浮点数比较；
- 拒绝 `v1.0`、`v01.0.0`、`v1.0.0-beta` 和 `v1.0.0+5`；
- Prerelease 被拒绝；latest 响应缺少 `draft` 时仍可按真实 Gitee 协议解析；
- 缺 APK、重复 APK、错误 ABI、错误文件名；
- 缺 checksum、重复 checksum、非 HTTPS checksum URL；
- checksum canonical 单行格式、1 KiB 上限、错误文件名和摘要不匹配；
- HTTPS 和非法 URL；
- Release 正文为空仍可更新；
- 本地开发版高于 latest 时不降级。

### 17.2 Gitee data 测试

- 使用真实响应脱敏 fixture；
- 覆盖真实响应没有 `draft/published_at/html_url/asset size` 的情况；
- 缺字段、null、错误类型和未知字段；
- 403、404、429、500；
- 超时与连接中断；
- API 返回 Release 但附件尚未上传；
- `browser_download_url` 重定向；
- checksum 以 `application/octet-stream` 字节响应时按 UTF-8/ASCII 兼容文本解析；
- repository 不泄漏 Gitee DTO 到 domain。

### 17.3 Controller 测试

- 手动检查最新、发现更新和失败；
- 自动检查频率限制；
- 忽略当前版本；
- 重复点击不重复请求；
- 重复下载不重复 enqueue；
- 页面关闭后不取消下载；
- task ID 恢复；
- running、paused、successful、failed、missing 映射；
- controller dispose 后忽略迟到结果；
- 安装权限拒绝后可再次检查；
- 新版本已安装后清理旧任务。

### 17.4 MethodChannel 合同测试

- Dart 参数与 Kotlin 类型一致；
- Android `long` task ID 不截断；
- 未知 status 映射为安全失败；
- total bytes 未知时不除零；
- content URI 正确序列化；
- Kotlin exception 转换为稳定平台错误 code；
- cancel/query 不存在任务时幂等。

### 17.5 Android 集成测试

- packageName 校验；
- versionCode 校验；
- archive versionName 与 Release Tag 一致；
- 当前签名证书与 archive 证书匹配；
- 错误签名 APK 被提前拒绝；
- `canRequestPackageInstalls` 两种状态；
- 设置页返回后重新检查；
- content URI 获得临时读取权限；
- 系统安装 Intent 可解析；
- App 后台和进程重启后任务仍可查询。

### 17.6 手工设备矩阵

至少覆盖：

```text
Android 8/9：未知应用权限基础行为
Android 10/11：Scoped Storage
Android 12：exported 与后台启动限制
Android 13：通知权限
Android 14/15：后台和安装限制
```

场景：

- 干净安装后检查；
- 从旧版覆盖到新版；
- 下载中切后台；
- 下载中杀进程并重启；
- 断网、切换网络、空间不足；
- 拒绝安装未知应用；
- 下载错误签名 APK；
- Gitee Release 无附件；
- Gitee API 限流；
- 同版本重复检查；
- 发布更高 SemVer 且内部 versionCode 同步递增后重新检查。

## 18. 分阶段实施

### Phase 0：协议、基线与 ADR

任务：

- 创建或确定公开 Gitee Release 仓库。
- 手工发布一个仅用于测试的正式 Release。
- 验证 latest API 匿名访问、响应字段、限流和 asset 下载重定向。
- 保存脱敏 Gitee fixture。
- 保存真实 checksum 文本 fixture，并固定 canonical `sha256sum` 格式。
- 将 `pub_semver` 声明为直接依赖，建立唯一 SemVer codec，禁止各层各自解析版本。
- 固定 Tag、APK/checksum 文件名、ABI 和正式/预发布规则。
- 记录当前 packageName、versionName、versionCode 和发布证书 SHA-256 指纹。
- 建立 domain 模型、Gitee Release parser、checksum 文本 parser 和纯更新策略，不接 UI 和真实下载。
- 在 ADR 中确定不用稳定 JSON、不在 App 内放 Token、采用 DownloadManager。

验收：

- fixture parser 全部通过；
- APK 与 checksum 必须同时唯一存在；checksum 缺失时没有 fallback；
- SemVer 更新决策有完整测试，安装校验另行锁定 versionCode 严格递增；
- Release 配置错误不会误报更新；
- 没有任何真实下载安装行为。

Phase 0 已于 2026-07-18 按必需 checksum 协议修正：公开仓库、`v0.0.1` 手工正式 Release、latest API 匿名访问、APK/checksum 匿名获取、真实字段观察、脱敏 fixture、Manifest/ABI/摘要/签名基线、domain/parser/policy、错误模型、ADR 和测试均已落实。当前 Release 的两项附件符合协议，无需删除或重建。

Phase 1 准入门槛（必须全部满足）：

- latest API 匿名返回的正式 Tag 符合 `v{major}.{minor}.{patch}`，当前基线 `v0.0.1` 已满足；
- Release 中恰好存在一个 `y300-v0.0.1-android-arm64-v8a-release.apk` 和一个同名 `.apk.sha256`，自动源码压缩包不会被识别为更新附件；
- 在不携带 Token 时，APK/checksum URL 均能读取；checksum 为 107 字节 canonical 单行文本且与 APK 实际 SHA-256 一致；
- 已把真实响应保存为脱敏 fixture，并覆盖缺少 `draft/published_at/html_url/asset size` 的实际字段模型；
- 已固定 `applicationId=com.adws.y300`、当前 `versionName/versionCode` 与正式发布证书 SHA-256 指纹，测试 APK 确认使用未来持续保管的同一份 Release JKS；
- Phase 0 的 domain 模型、严格 Tag/asset parser、checksum parser、基于 `pub_semver` 的纯更新策略、错误模型和 ADR 已完成并通过测试；
- 客户端代码和 fixture 均不包含 Gitee Token，CI Token 与 Android JKS 仍只存在于 Secrets 或本地安全存储。

准入结论：以上条件已全部满足；28 项 `test/features/app_update` 测试通过，`flutter analyze` 无问题，可以进入 Phase 1。当前 `v0.0.1` 与已安装 `0.0.1+4` 用于验证“已是最新”；Phase 1 收尾再按下文发布 `v0.0.2` 验证真实“发现更新”。

### Phase 1：版本检查与手动 UI

任务：

- 引入 `package_info_plus`。
- 实现 Gitee HTTP API 与 repository，把 latest 响应交给 Phase 0 已测试的 DTO/parser 防腐层；Phase 1 只验证 checksum asset 元数据存在，不提前下载 APK。
- 实现“更多 -> 检查更新”。
- 实现更新 BottomSheet，但下载按钮暂时可打开 Release 页面或显示未接入状态。
- 增加手动检查的加载、最新、错误和更新可用状态。
- 加入请求超时和错误分类。

验收：

- 真机可以通过公开 Gitee API发现更新；
- 本地版本较高时不提示降级；
- Prerelease 不被识别为稳定更新；Gitee 未提供 `draft` 字段时不会误判为协议损坏；
- 页面没有 Gitee Token；
- 网络失败不影响其它功能。

“发现更新”的真机验收应在 Phase 1 收尾时进行：保留安装中的 `0.0.1+4`，再发布由同一 Release JKS 签名的 `0.0.2+5`，Tag 使用 `v0.0.2`，同时上传 `y300-v0.0.2-android-arm64-v8a-release.apk` 与对应 `.apk.sha256`。这不是进入 Phase 1 的前置条件；Phase 0 可用当前 `v0.0.1` fixture 和 fake release 完成全部协议测试。

### Phase 2：DownloadManager 与进度恢复

任务：

- 实现 Kotlin DownloadManager gateway 和 MethodChannel。
- 实现受 1 KiB 限制的 checksum repository、canonical 文本解析和期望摘要持久化。
- 下载完成后通过 content URI 流式计算 SHA-256，不把 APK 载入 Dart 内存；摘要不匹配时删除文件并阻止后续校验。
- 定义稳定 status 映射。
- 使用 App 专属 updates 目录。
- 保存 active task snapshot。
- 实现前台轮询、系统通知和 App 内进度。
- 实现取消、失败和重试为新任务。
- App 重启后恢复任务。

验收：

- App 退到后台后下载继续；
- Flutter 进程被杀后系统任务继续；
- 重启 App 可恢复进度或完成状态；
- 同一 canonical Tag 不会重复创建任务；
- 无 total bytes 时 UI 不显示错误百分比。
- checksum 缺失、格式错误或摘要不匹配时均失败且不降级；进程重启后仍可使用持久化期望摘要完成校验。

### Phase 3：APK 校验与安装

任务：

- 增加 `REQUEST_INSTALL_PACKAGES`。
- 实现 install permission 查询和设置页跳转。
- 实现 PackageManager archive 校验。
- 比对 packageName、versionName、versionCode 和签名证书。
- 使用 DownloadManager content URI 调起系统安装器。
- 下载完成后由用户点击安装，不在后台强弹。

验收：

- 正确签名的新版本可以覆盖安装；
- 错包名、versionName 与 Tag 不符、同/低 versionCode、错误签名均在安装前被拒绝；
- 拒绝未知应用权限不会死循环；
- 不使用 `file://`；
- Android 系统保留最终确认权。

### Phase 4：自动检查与完成通知

任务：

- 主壳首帧后异步检查。
- 增加 24 小时成功检查窗口和失败退避。
- 实现忽略当前 canonical Tag。
- 恢复活跃下载状态。
- 根据产品需要增加“下载完成，点击安装”的应用通知。
- 处理前后台切换和通知权限拒绝。

验收：

- 启动不被 Gitee 网络阻塞；
- 最新版本和检查失败不产生启动噪音；
- 发现新版本才提示；
- 忽略只影响当前版本；
- 通知权限被拒绝时下载和 App 内安装入口仍可用。

### Phase 5：CI 自动发布到 Gitee

任务：

- 将版本改为 Tag 与 `pubspec.yaml` 单一来源。
- 增加版本一致性和递增校验。
- 构建并检查 Gradle 已按协议命名的 arm64 APK，不做第二次手工重命名。
- 生成 canonical `.apk.sha256`，并在上传前重新计算 APK 摘要自检。
- 校验 package、version 和签名证书。
- 优先用 Gitee API 创建 Prerelease、上传 APK/checksum 后转为正式 Release；若平台不支持，则采用严格双附件协议容忍短暂不完整窗口。
- 匿名验证 latest API、两项下载 URL，并回读比较 APK 与 checksum。
- 发布失败时不留下可被客户端识别的不完整正式版本。
- 保留 GitHub Artifact 作为 CI 调试产物，但 App 不使用它。

验收：

- 一个 Tag 可以全自动生成对应 Gitee Release；
- Tag、APK Manifest、Release、APK/checksum 文件名与摘要一致；
- CI 日志不泄漏 Token 和签名密码；
- App 能发现并下载该发布；
- 重跑不会覆盖既有正式版本。

### Phase 6：硬化、回归与发布演练

任务：

- 完成 Android 版本和 OEM 手工矩阵。
- 演练错误签名、错误附件、Gitee 限流和断网。
- 演练下载中杀进程、重启和安装权限拒绝。
- 演练坏版本后同时提升 patch versionName 和 versionCode 的修复发布。
- 检查更新日志隐私和技术状态清理。
- 更新用户可见版本信息和开发文档。

验收：

- 所有 Definition of Done 项满足；
- 不影响论坛、书架、阅读器、缓存和业务下载；
- 可以完成一次旧版到新版的真实覆盖安装演练。

## 19. 预计文件变更方向

```text
pubspec.yaml
  + package_info_plus
  + pub_semver（直接依赖，不依赖传递依赖）

lib/core/config/technical_storage_keys.dart
  + 更新检查与活跃任务技术 key

lib/features/app_update/**
  + 完整更新 feature

lib/features/more/presentation/**
  + 检查更新入口和版本展示

lib/features/startup/**
  + 非阻塞自动检查编排

android/app/src/main/AndroidManifest.xml
  + REQUEST_INSTALL_PACKAGES

android/app/src/main/kotlin/**/update/**
  + DownloadManager、校验与安装 bridge

.github/workflows/android-arm64-release.yml
  + Tag 校验、Gitee Release 创建与上传

test/features/app_update/**
  + parser、policy、controller、UI 和 channel contract 测试
```

不应修改：

- 小说 `version=1` 请求策略；
- 漫画章节下载；
- 图片缓存目录和淘汰策略；
- 收藏同步；
- 论坛 Cookie；
- 作品详情和阅读进度。

## 20. Review 检查清单

- App 是否完全不包含 `GITEE_TOKEN`？
- Gitee 仓库是否允许匿名读取 latest Release？
- Tag 是否严格为 `v{major}.{minor}.{patch}` 且只包含 versionName？
- APK 是否只有一个 arm64 协议附件，并且只有一个精确对应的 `.apk.sha256`？
- checksum 是否使用 64 位小写摘要、两个空格、完整 APK 文件名和最多一个末尾换行？
- checksum 是否必需且无缺失跳过策略？
- 更新发现是否使用 `pub_semver` 比较 versionName，而不是字符串、浮点数或远端不存在的 versionCode？
- package_info 是否每次读取真实安装包，而不是保存陈旧版本副本？
- 下载 task ID 是否持久化并能在重启后恢复？
- 期望 SHA-256 是否随活跃任务持久化，APK 是否通过 content URI 流式计算而非整体载入内存？
- 是否使用 DownloadManager，而不是页面生命周期承载下载？
- 页面关闭是否不会取消下载？
- 是否没有旧存储权限？
- 是否没有重复 FileProvider 和 WorkManager initializer？
- 是否校验 packageName、versionName、versionCode 和签名证书？
- 是否使用 content URI？
- 是否由用户点击后调起安装器？
- 是否处理未知应用权限被拒绝？
- 自动检查是否不阻塞启动？
- 检查失败是否不影响主业务？
- 普通个性化重置是否不删除更新任务？
- CI 是否验证 APK Manifest versionName 与 Tag 一致，并独立验证 versionCode 单调递增？
- CI 是否验证发布证书指纹？
- CI 是否生成、上传并匿名回读 checksum，确认远端 APK 摘要一致？
- 发布失败是否不会产生可被客户端误识别的正式更新？
- 坏版本是否通过同时提升 patch versionName 和 versionCode 修复，而不是复用 Tag？

## 21. Definition of Done

只有同时满足以下条件，Android 应用内更新才算完成：

1. 可从公开 Gitee latest Release API稳定获取并解析正式版本。
2. 更新发现使用严格稳定 SemVer versionName；下载后要求 APK versionName 与 Tag 一致，并要求正整数 versionCode 严格大于当前安装包。
3. App 和 CI 都遵守同一 Tag、APK 与 checksum 命名协议。
4. checksum 缺失、格式错误、文件名错误或摘要不匹配时必须失败；APK 通过 content URI 流式计算 SHA-256。
5. 用户可以在 App 内看到系统下载任务的真实进度。
6. App 退出或进程被杀后下载不依赖 Flutter 存活。
7. App 重启后能恢复下载、期望摘要或完成状态。
8. APK 安装前完成 checksum、包名、版本和签名证书校验。
9. 用户拒绝安装权限时可以安全返回并稍后重试。
10. 安装必须经过 Android 系统确认，不能静默执行。
11. CI 能用英文 Release 流程自动上传 APK/checksum，不泄漏任何 Secret。
12. 错误 Release、无附件、错误 checksum、错误 ABI、错误签名和断网均有测试或演练。
13. 更新功能不影响 Y300 其它模块，小说网络继续固定使用 `version=1`。
