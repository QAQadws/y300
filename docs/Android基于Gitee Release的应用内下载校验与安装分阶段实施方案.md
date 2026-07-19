# Android 基于 Gitee Release 的应用内下载、校验与安装分阶段实施方案

> 文档日期：2026-07-19
> 适用范围：Y300 Android arm64-v8a 自分发版本
> 文档状态：实施前架构方案，尚未开始本方案的代码阶段
> 在线来源：公开 Gitee Release latest API
> 发布方式：维护者手工创建和上传 Gitee Release
> 前置基线：Android 基于 Gitee Release 的应用内更新 Phase 0/1/2/3 已完成

## 0. 阅读说明与决策结论

当前 Y300 已完成以下更新能力：

1. Gitee latest Release 的 DTO、防腐解析、严格 Tag 和精确 APK/checksum 附件校验。
2. GiteeUpgraderStore 与 upgrader 13.5.0 集成。
3. 单例 Upgrader、自动提示、“稍后”和“忽略当前版本”。
4. “更多”页手动检查、TTL 绕过、重复检查合并和抑制状态 Snackbar。
5. 外部浏览器打开 APK URL 的现有降级方案。

当前方案存在三个用户体验问题：

1. Gitee 最终响应的 Content-Type 可能是 application/zip，部分 Android 下载器会把 APK 保存为 apk.zip。
2. 浏览器拥有下载文件，Y300 无法显示自己的下载状态，也无法在下载完成后自动校验。
3. Y300 不拥有已下载文件，因此用户需要手动重命名和手动计算 SHA-256。

本方案决定：

1. 保留现有 Gitee Release 发现、Upgrader 版本比较、弹窗、忽略和提醒间隔。
2. 第一阶段先将“立即更新”从外部浏览器下载改为 Y300 内部的前台下载流程。
3. 复用已有 Dio、path_provider 和 path；只为 Dart 侧流式 SHA-256 直接增加 crypto。
4. 使用独立安装器 adapter 把已验证 APK 交给 Android 系统安装器。
5. 将后台下载、通知栏进度、暂停/恢复和进程重启恢复定义为可选增强轨道，不在核心流程中强制引入 background_downloader。
6. Android 仍然必须由用户确认安装，Y300 不实现静默安装。
7. 不把下载、校验、安装和 UI 逻辑集中到一个 coordinator；应用服务只编排，各端口各司其职。

当前旧方案中的 Phase 4“手工发布演练”必须推迟到本方案至少完成核心应用内下载链路后。若选择后台增强轨道，则还必须完成后台轨道的真机验收；否则验证的只是浏览器下载链路，无法验证用户真正需要的 App 内进度、自动校验和安装体验。

## 1. 目标

### 1.1 产品目标

用户点击“立即更新”后，应看到以下体验：

~~~text
更新提示
  -> App 内开始前台下载
  -> 页面显示下载进度
  -> 下载完成后自动进入校验
  -> 校验通过后显示“准备安装”
  -> 用户点击打开 Android 安装器
  -> 用户确认安装
  -> Android 完成覆盖更新

可选后台增强轨道：

  -> 用户将 App 切到后台
  -> 后台任务和 Android 通知继续报告进度
  -> App 重启后恢复或明确终止任务
~~~

用户不应再需要：

- 手动删除 apk.zip 后缀。
- 手动寻找 checksum 文件。
- 手动计算 SHA-256。
- 手动判断下载文件是否完整。
- 从浏览器下载列表返回 App 后猜测更新状态。

### 1.2 工程目标

- 继续使用 Gitee latest JSON，不增加第二个版本元数据来源。
- 继续由 Upgrader 作为版本读取、版本比较、忽略和提醒间隔的唯一所有者。
- 下载服务通过端口和 adapter 接入，领域层不依赖具体插件。
- 文件验证在安装前强制执行，未经验证的文件不能进入安装器。
- 核心流程在 App 进程存活期间状态明确、可取消、可重试并可清理；跨进程恢复只属于可选后台轨道。
- 下载失败、校验失败和安装失败不影响论坛、收藏、漫画、小说、书架和阅读器。
- Android 平台配置集中在 app_update 的平台边界，不把平台细节扩散到页面。

## 2. 非目标与硬边界

本方案不实现：

- 静默安装、Root 安装或绕过 Android 系统确认。
- Google Play In-App Update。
- iOS 自托管 IPA 安装。
- CI 自动创建、修改或上传 Gitee Release。
- Gitee Token、GitHub Token 或其它发布凭据进入 App。
- APK 下载到用户可见的公共下载目录作为唯一来源。
- 把 APK 正文写入 SQLite 或 SharedPreferences。
- 通过 Gitee Release body 下发脚本、强制更新规则或远端配置。
- 预先解析 APK 内部证书作为 Android 安装器的替代品。
- 与漫画下载共用下载任务模型、目录或状态。
- 重新实现一个独立于 Upgrader 的 SemVer 比较器。
- 在没有验证真实需求前引入后台下载、任务恢复或通知栏进度。

Android 系统仍拥有最终安装决定权。Y300 的 SHA-256 校验用于发现损坏、截断和错误文件，不替代 APK 签名验证。

## 3. 当前基线

### 3.1 现有更新模块

~~~text
lib/features/app_update
  data/gitee
    dio_gitee_latest_release_repository.dart
    gitee_release_dto.dart
    gitee_release_parser.dart
    gitee_upgrader_store.dart
  data/platform
    url_launcher_app_update_launcher.dart
  data/providers
    app_update_providers.dart
  domain/models
    gitee_release_candidate.dart
    gitee_release_lookup_result.dart
    app_update_failure.dart
    app_update_check_result.dart
    app_update_launch_result.dart
  domain/services
    app_update_apk_uri_policy.dart
    app_update_launcher.dart
  presentation
    controllers/app_update_prompt_coordinator.dart
    widgets/app_update_alert_host.dart
    widgets/app_update_check_tile.dart
~~~

当前 GiteeReleaseCandidate 已经包含：

- canonical Tag。
- package:version 类型的稳定版本。
- 精确 APK URI。
- 精确 checksum URI。
- 纯文本 Release notes。

这些模型和解析边界继续复用。新的下载、校验和安装能力不能绕过 GiteeReleaseParser 直接使用原始 JSON。

### 3.2 当前发布协议

~~~text
Tag:
  v{major}.{minor}.{patch}

APK:
  y300-v{versionName}-android-arm64-v8a-release.apk

Checksum:
  y300-v{versionName}-android-arm64-v8a-release.apk.sha256
~~~

客户端仍只接受：

- HTTPS。
- 预期 Gitee host 和合法重定向链路。
- canonical 三段稳定版本。
- prerelease=false。
- 恰好一个精确 APK。
- 恰好一个精确 checksum。

### 3.3 当前 Android 边界

当前 Manifest 已有 INTERNET 和 Android 13+ 通知权限。当前没有：

- REQUEST_INSTALL_PACKAGES。
- 更新专用 FileProvider。
- 更新专用 DownloadManager Kotlin bridge。
- 更新专用 MethodChannel。

本方案会在安装阶段增加安装权限和文件分享配置。它们属于本方案明确拥有的 Android 平台边界，不是偷偷恢复旧的自建 Kotlin 下载管线。

## 4. 依赖决策

以下版本是 2026-07-19 对 pub.dev 的兼容性核查基线，正式加入前仍需执行 flutter pub get、flutter analyze 和 Android 构建验证：

| 依赖 | 版本基线 | 引入方式 | 职责 |
| --- | --- | --- | --- |
| upgrader | 13.5.0 | 已有 | 版本读取、比较、提示、忽略和提醒间隔 |
| dio | 5.9.2 | 已有 | Gitee API、checksum 文本和小型网络请求 |
| background_downloader | 9.5.6 | 可选新增 | 仅在选择后台增强轨道时负责后台 APK 下载、通知、暂停/恢复和任务持久化 |
| crypto | 3.0.7 | 新增 | 流式 SHA-256 |
| path_provider | 2.1.5 | 已有 | App support/cache 目录 |
| path | 1.9.1 | 已有 | 跨平台路径拼接和路径规范化 |
| open_filex | 4.7.0 | 新增候选 | 通过 Android Intent 打开 APK 安装器 |
| permission_handler | 12.0.2 | 已有 | 检查或引导未知来源安装权限 |
| shared_preferences | 2.5.5 | 已有 | Upgrader 的提醒/忽略状态；核心流程不用于保存下载任务 |

### 4.1 核心轨道不引入 background_downloader

前台核心使用已有 Dio 的流式响应下载 APK：

~~~text
Dio ResponseType.stream
  -> 写入 AppUpdateFileStore 管理的 .apk.part
  -> 回调 AppUpdateBinaryEvent
  -> 下载完成后进入 verifier
~~~

这已经可以解决自动文件名、App 内进度、自动校验和系统安装，不需要新增后台下载插件。下载器使用独立的 Dio 实例或明确的请求边界，不能携带论坛 Cookie、Authorization 或其它业务请求头。

### 4.2 可选 background_downloader

background_downloader 9.5.6 的公开包约束为 Dart 3.7 以上、Flutter 3.29 以上，当前 Y300 工具链满足该条件。

只有在产品确认需要“退到后台后继续下载、通知栏进度、App 被杀后恢复”时才引入。计划使用它的能力：

- DownloadTask 的明确 filename。
- applicationSupport 或 temporary 基础目录。
- statusAndProgress 更新。
- allowPause、retries 和后台任务。
- 中央任务事件监听。
- 持久任务数据库。
- Android 通知配置。
- App 重启后的任务查询和恢复。

下载插件只属于 data/platform adapter。领域层不能 import background_downloader 的 TaskStatus、DownloadTask 或插件 enum。插件自带的任务数据库是后台轨道的任务事实来源，Y300 不再额外建立一份完整的任务数据库。

### 4.3 crypto

crypto 只承担摘要计算。校验服务通过 File.openRead() 分块传入 SHA-256 sink，不把整个 APK 读入内存。

crypto 不负责：

- 判断 Release 是否可信。
- 解析 Gitee checksum 文本。
- 判断 APK versionName。
- 判断 Android 签名。

这些职责分别由 Gitee parser、checksum parser、Upgrader 和 Android 系统安装器承担。

### 4.4 open_filex 与安装权限

open_filex 4.7.0 支持 .apk 到 application/vnd.android.package-archive 的 MIME 映射，并可以通过 Android Intent 打开文件。

它的 README 明确说明自身移除了 REQUEST_INSTALL_PACKAGES，以兼容 Google Play 发布政策。Y300 是自分发 APK，因此不能把“插件不声明权限”误认为“应用不需要权限”。实施时由 Y300 自己在 Manifest 中声明：

~~~xml
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
~~~

FileProvider 的 authorities、paths 和其它插件冲突必须在真实 Android 设备上验证。若 open_filex 在目标 Android 矩阵上无法稳定打开安装器，只允许替换 AppUpdateInstaller adapter，不得把下载器、校验器和 UI 一起重写。

### 4.5 不重复使用 flutter_local_notifications

项目已有 flutter_local_notifications，但本方案不让它逐帧绘制更新进度。核心轨道不需要通知栏任务；选择后台轨道后，由 background_downloader 负责更新任务通知，避免两个通知系统同时维护相同 taskId、进度和点击行为。

flutter_local_notifications 只继续服务已有业务通知。若未来需要自定义“校验失败”或“准备安装”通知，应先定义通知所有权，再决定是否复用或扩展现有通知模块。

### 4.6 不直接增加 package_info_plus

Upgrader 已经通过其内部依赖读取安装版本。app_update 页面继续通过 coordinator 的 Upgrader 状态获取当前版本，不直接 import package_info_plus，也不强行升级到 10.2.1。

## 5. 总体架构

### 5.1 分层图

~~~text
Presentation
  AppUpdateAlertHost
  AppUpdateCheckTile
  AppUpdateDownloadSheet
  AppUpdateDownloadController
          |
          v
Application
  AppUpdatePromptCoordinator
  AppUpdateDownloadService
          |
          v
Domain ports
  GiteeLatestReleaseRepository
  AppUpdateChecksumRepository
  AppUpdateBinaryDownloader
  AppUpdateArtifactVerifier
  AppUpdateInstaller
  AppUpdateFileStore
          |
          v
Data/platform adapters
  DioGiteeLatestReleaseRepository
  DioGiteeChecksumRepository
  DioAppUpdateBinaryDownloader
  CryptoArtifactVerifier
  AppUpdateFileStoreImpl
  OpenFilexAppUpdateInstaller
  (optional) BackgroundDownloaderBinaryDownloader
~~~

### 5.2 依赖方向

允许：

~~~text
presentation -> application -> domain ports
data/platform -> domain ports
data/gitee -> domain models and domain repository contracts
providers -> concrete adapters and application services
~~~

禁止：

- MorePage 直接调用 Dio。
- Widget 直接构造 DownloadTask。
- Widget 直接读写 APK 文件。
- Gitee parser 调用 background_downloader。
- verifier 依赖 BuildContext。
- installer 修改 Upgrader 的忽略状态。
- downloader 直接打开安装器。
- 漫画下载服务复用 AppUpdateDownloadService。

### 5.3 建议目录结构

~~~text
lib/features/app_update
  domain
    models
      app_update_artifact.dart
      app_update_checksum.dart
      app_update_download_state.dart
      app_update_verification_result.dart
      app_update_install_result.dart
    repositories
      app_update_checksum_repository.dart
    services
      app_update_binary_downloader.dart
      app_update_artifact_verifier.dart
      app_update_file_store.dart
      app_update_installer.dart
      app_update_download_service.dart
  data
    gitee
      dio_gitee_checksum_repository.dart
      app_update_checksum_parser.dart
    local
      app_update_file_store_impl.dart
    platform
      dio_app_update_binary_downloader.dart
      open_filex_app_update_installer.dart
      app_update_install_permission.dart
      (optional) background_downloader_binary_downloader.dart
    providers
      app_update_download_providers.dart
  presentation
    controllers
      app_update_download_controller.dart
    widgets
      app_update_download_host.dart
      app_update_download_sheet.dart
      app_update_progress_tile.dart
~~~

实际命名应与仓库已有命名风格对齐，目录树表达的是 ownership，不要求一次性创建所有文件。Domain 目录不能出现 Flutter、Dio 或插件 import；data/platform 不能反向依赖具体页面。

### 5.4 设计模式

#### 防腐层

Gitee DTO 和 GiteeReleaseParser 继续隔离供应商 JSON。Release body、asset 数组和 redirect 细节不能进入 UI 或领域状态。

#### Ports and Adapters

下载器、文件存储、校验器和安装器均以 interface 定义。真实插件只出现在 data/platform，测试使用 fake adapter。

#### Application Service

AppUpdateDownloadService 编排一次更新，但不实现具体下载、哈希或安装细节。核心轨道负责顺序、状态迁移、取消和重试；后台轨道的任务恢复由 background_downloader adapter 提供。

#### State Machine

所有下载状态迁移必须通过一个受控 reducer 或 coordinator 方法完成，禁止 Widget 根据多个 bool 自行推断状态。

#### Repository

Gitee checksum 文本通过 repository 读取。核心轨道不建立下载任务 repository；若后台轨道启用，插件任务数据库由 adapter 管理，repository 不承担页面提示，也不直接打开系统 UI。

#### Single-flight

对同一 artifact identity 的检查、下载和安装请求合并，避免多个页面同时下载同一个 APK。核心轨道只需在内存中去重；后台轨道使用插件 task id 和 artifact identity 做去重。

#### Transactional Promotion

不完整文件停留在 staging 名称。只有下载完成且 SHA-256 校验成功后，才提升为可安装 artifact。

## 6. 领域模型

### 6.1 更新制品

建议新增或扩展以下领域模型：

~~~dart
final class AppUpdateArtifact {
  const AppUpdateArtifact({
    required this.tag,
    required this.version,
    required this.apkUri,
    required this.checksumUri,
    required this.fileName,
    required this.releaseNotes,
  });

  final String tag;
  final Version version;
  final Uri apkUri;
  final Uri checksumUri;
  final String fileName;
  final String? releaseNotes;
}
~~~

fileName 必须由 parser 根据 version 生成并和 asset name 比较，不能信任任意远端 filename。

### 6.2 Checksum

~~~dart
final class AppUpdateChecksum {
  const AppUpdateChecksum({
    required this.sha256,
    required this.fileName,
  });

  final String sha256;
  final String fileName;
}
~~~

Checksum parser 只接受 canonical sha256sum 单行格式：

~~~text
64位小写十六进制摘要 + 两个 ASCII 空格 + 精确 APK 文件名
~~~

正文最大长度继续限制为较小上限，例如 1 KiB。文件名必须和 AppUpdateArtifact.fileName 完全相等。

### 6.3 任务身份

~~~dart
final class AppUpdateArtifactIdentity {
  const AppUpdateArtifactIdentity({
    required this.tag,
    required this.version,
    required this.fileName,
  });

  final String tag;
  final Version version;
  final String fileName;

  String get stableKey => [tag, version.toString(), fileName].join('|');
}
~~~

stableKey 只用于 AppUpdateDownloadService 的内存去重，以及后台轨道和插件 task id 的关联，不展示给用户，不上传服务器。正式发布禁止复用同一 Tag 换包，因此第一版可以使用 tag、version 和 filename 组成稳定 identity。

### 6.4 下载状态

~~~dart
sealed class AppUpdateDownloadState {
  const AppUpdateDownloadState();
}

final class AppUpdateIdle extends AppUpdateDownloadState {
  const AppUpdateIdle();
}

final class AppUpdatePreparing extends AppUpdateDownloadState {
  const AppUpdatePreparing(this.artifact);
  final AppUpdateArtifact artifact;
}

final class AppUpdateDownloading extends AppUpdateDownloadState {
  const AppUpdateDownloading({
    required this.artifact,
    required this.progress,
    required this.receivedBytes,
    required this.totalBytes,
  });

  final AppUpdateArtifact artifact;
  final double progress;
  final int receivedBytes;
  final int? totalBytes;
}

final class AppUpdatePaused extends AppUpdateDownloadState {
  const AppUpdatePaused(this.artifact);
  final AppUpdateArtifact artifact;
}

final class AppUpdateVerifying extends AppUpdateDownloadState {
  const AppUpdateVerifying(this.artifact);
  final AppUpdateArtifact artifact;
}

final class AppUpdateReadyToInstall extends AppUpdateDownloadState {
  const AppUpdateReadyToInstall({
    required this.artifact,
    required this.apkPath,
  });

  final AppUpdateArtifact artifact;
  final String apkPath;
}

final class AppUpdateInstalling extends AppUpdateDownloadState {
  const AppUpdateInstalling(this.artifact);
  final AppUpdateArtifact artifact;
}

final class AppUpdateFailed extends AppUpdateDownloadState {
  const AppUpdateFailed({
    required this.artifact,
    required this.failure,
  });

  final AppUpdateArtifact artifact;
  final AppUpdateFailure failure;
}
~~~

不建议直接把插件的 TaskStatus 映射为业务状态。插件可能有 queued、enqueued、running、complete、failed 等平台状态，领域层应将它们映射为自己的稳定状态。

### 6.5 失败分类

建议增加以下稳定 code：

~~~text
checksumRequestFailed
checksumMalformed
checksumFileNameMismatch
apkDownloadStartFailed
apkDownloadFailed
apkDownloadCancelled
apkFileMissing
apkSizeExceeded
apkHashMismatch
apkPromotionFailed
installPermissionRequired
installerUnavailable
installerLaunchFailed
insufficientStorage
unsupportedPlatform
optionalTaskRecoveryFailed
~~~

日志和 UI 只使用 code 和安全的短描述。不能把完整下载 URL、redirect token、Cookie 或异常响应正文写入日志。

## 7. 领域端口与接口

### 7.1 Checksum repository

~~~dart
abstract interface class AppUpdateChecksumRepository {
  Future<AppUpdateChecksum> fetchChecksum(
    AppUpdateArtifact artifact,
  );
}
~~~

实现使用独立的 Dio 请求边界，不携带论坛 Cookie 或 Authorization。它必须复用 Gitee host、HTTPS 和 filename policy。

### 7.2 Binary downloader

~~~dart
abstract interface class AppUpdateBinaryDownloader {
  Stream<AppUpdateBinaryEvent> download(
    AppUpdateArtifact artifact, {
    required String stagingPath,
  });

  Future<void> cancel();
}
~~~

AppUpdateBinaryEvent 是 Y300 自己的模型，至少包含 artifact identity、receivedBytes、totalBytes、progress、运行状态和可安全展示的 failure code。核心实现使用 Dio 的 `ResponseType.stream` 写入指定 staging path。暂停、恢复和后台任务查询不是核心端口的一部分；若后台轨道启用，再由独立的可选 adapter 能力提供。

可选能力单独定义，避免核心服务被后台插件 API 污染：

~~~dart
abstract interface class AppUpdatePausableBinaryDownloader
    implements AppUpdateBinaryDownloader {
  Future<void> pause();
  Future<void> resume();
}
~~~

### 7.3 File store

~~~dart
abstract interface class AppUpdateFileStore {
  Future<String> stagingPath(AppUpdateArtifactIdentity identity);

  Future<String> verifiedPath(AppUpdateArtifactIdentity identity);

  Future<bool> exists(String path);

  Stream<List<int>> openRead(String path);

  Future<void> promote({
    required String stagingPath,
    required String verifiedPath,
  });

  Future<void> deleteArtifact(AppUpdateArtifactIdentity identity);

  Future<void> cleanupStaleArtifacts();
}
~~~

File store 负责路径安全和原子提升，不负责下载和哈希。

### 7.4 Verifier

~~~dart
abstract interface class AppUpdateArtifactVerifier {
  Future<AppUpdateVerificationResult> verify({
    required AppUpdateArtifact artifact,
    required AppUpdateChecksum checksum,
    required String apkPath,
  });
}
~~~

Verifier 必须：

1. 检查文件存在。
2. 检查文件大小不超过产品上限。
3. 流式计算 SHA-256。
4. 规范化大小写后比较 expected hash。
5. 比较 checksum 中的 filename 和 artifact filename。
6. 失败时不能返回可安装状态。

### 7.5 Installer

~~~dart
abstract interface class AppUpdateInstaller {
  Future<AppUpdateInstallResult> install({
    required String apkPath,
    required AppUpdateArtifact artifact,
  });
}
~~~

Installer 只接受 ReadyToInstall 状态产生的路径。它不能接收下载 URL，不能自行下载，不能绕过 verifier。

### 7.6 任务持久化边界

核心轨道不保存下载任务数据库。它只在应用进程内通过 `AppUpdateDownloadService` 暴露状态；App 进程终止后，未完成的 `.part` 文件会在下一次启动时被识别并清理或重新下载。

后台轨道启用后，background_downloader 的任务数据库作为底层任务事实来源。Y300 最多保存 artifact identity 与展示所需的最小关联信息，不能再建立一份包含完整状态的 `SharedPreferencesTaskStore`。不保存 APK 二进制，也不保存论坛账号信息。

## 8. 文件、持久化与生命周期

### 8.1 目录策略

更新 APK 不属于用户下载内容，也不应受漫画下载目录或用户选择的下载位置影响。

推荐目录：

~~~text
ApplicationSupport/
  y300/
    updates/
      staging/
        y300-v0.0.2-android-arm64-v8a-release.apk.part
      verified/
        y300-v0.0.2-android-arm64-v8a-release.apk
~~~

使用 `path_provider` 获取 application support directory，再用 `path` 拼接受保护的更新目录；不依赖 Android 绝对路径。只有后台轨道启用时，才把这个目录传给 background_downloader 的 BaseDirectory/directory/filename 配置。

### 8.2 staging 与 verified

- staging 文件永远不能交给安装器。
- 下载中断时 staging 文件只能由同一下载实现决定是否续传；核心轨道默认删除后重新下载，后台轨道才验证插件是否支持可靠续传。
- 下载完成后先进入 verifying。
- SHA-256 通过后再 promote 到 verified。
- verified 文件才允许调用 Installer。
- hash 不匹配时删除 staging，保留失败诊断，不保留可疑 APK。
- 新任务开始前清理不同版本的过期 staging 文件。

### 8.3 App 重启行为

核心轨道启动时只扫描受保护更新目录：

~~~text
发现 .part 文件
  -> 校验文件名是否属于当前 artifact
  -> 默认清理并回到可重试状态
发现 verified 文件
  -> 重新校验 checksum
  -> 成功才恢复 ReadyToInstall
  -> 失败则删除并重新下载
~~~

后台轨道启动时由 adapter 查询插件任务，再校验 staging 文件和 artifact identity。无论哪条轨道，恢复失败都必须回到可重试状态，不能让 UI 永久显示“下载中”。

### 8.4 清理策略

- 核心轨道只保留一个当前 active artifact。
- 后台轨道只允许一个当前更新 task，去重由插件 task id 与 artifact identity 共同保证。
- 完成安装并确认新版本启动后，清理旧 verified APK。
- 失败或取消后清理 staging。
- App 启动时清理超过保留时间的 orphan 文件。
- 不递归删除用户漫画、小说、图片缓存或下载目录。
- 清理失败只记录诊断，不阻塞 App 启动。

## 9. 应用服务与状态迁移

### 9.1 AppUpdateDownloadService

它是下载流程的应用服务，负责：

- 接收 artifact。
- 去重同一 artifact identity。
- 获取 checksum。
- 创建 staging 文件。
- 监听下载事件。
- 触发验证。
- promote 文件。
- 暴露 ReadyToInstall。
- 调用 installer。
- 处理取消、失败和重试；后台恢复由可选 adapter 接管。

它不负责：

- 构造 Gitee URL。
- 解析 checksum 文本。
- 计算 hash 的具体算法。
- 构造 Flutter Widget。
- 直接调用 Android Intent。

### 9.2 迁移现有 AppUpdatePromptCoordinator

现有 coordinator 保留：

- Upgrader 生命周期。
- checkNow。
- 版本提示逻辑。
- 当前 artifact 从 UpgraderVersionInfo 映射。

需要改变：

~~~text
现有：
  onUpdate -> AppUpdateLauncher.openApk(uri)

目标：
  onUpdate -> AppUpdateDownloadService.start(artifact)
~~~

openCurrentUpdate 可以改名为 startCurrentUpdateDownload，避免“打开 URL”语义残留。

AppUpdateLauncher 和 UrlLauncherAppUpdateLauncher 不应立即删除。它们可以在迁移阶段保留为明确的“外部下载降级” adapter，但不能作为默认路径。等真机矩阵通过后再删除或仅保留“打开 Release 页面”的诊断入口。

### 9.3 一次下载的事务顺序

~~~text
start(artifact)
  -> 如果已有相同 artifact identity，返回现有执行流
  -> 如果已有其它 artifact，按产品策略取消或拒绝
  -> fetchChecksum
  -> 创建 staging path
  -> foreground Dio download 或 optional background task
  -> 状态 Downloading
  -> 完成后状态 Verifying
  -> verify hash
  -> promote staging -> verified
  -> 状态 ReadyToInstall
  -> 用户确认或自动打开 installer
  -> 状态 Installing
  -> App 下次启动确认 versionName 已提升
  -> 清理旧 artifact
~~~

“下载完成”不能直接等价于“可以安装”。中间必须经过 verifier。

## 10. UI 设计

### 10.1 根宿主

MaterialApp 下、MainShellPage 上继续保留：

~~~text
AppUpdateAlertHost
  -> UpgradeAlert
  -> AppUpdateDownloadHost
  -> MainShellPage
~~~

AppUpdateDownloadHost 负责监听 application service 状态，不负责发起 Gitee 请求。

### 10.2 更新弹窗

UpgradeAlert 继续负责目标版本、Release notes、忽略和稍后。

点击“立即更新”后：

1. UpgradeAlert 关闭。
2. AppUpdateDownloadService 开始任务。
3. DownloadHost 显示进度 UI。
4. 若启用后台增强轨道，再由 background_downloader 显示系统通知进度。

不在 UpgradeAlert 内嵌入下载器，避免更新弹窗同时拥有版本和传输状态。

### 10.3 下载 UI

建议使用一个专用 AppUpdateDownloadSheet 或非阻塞底部进度区域，至少包含：

- 目标版本。
- 当前阶段：下载中、校验中、准备安装、失败。
- 百分比和已下载/总大小。
- 取消。
- 校验失败原因。
- “安装”按钮。
- “重试”按钮。

暂停/继续仅在后台增强轨道的 adapter 声明支持时显示，核心前台流程不伪造暂停语义。

校验阶段不能继续显示 100% 下载进度而不说明状态，应切换为“正在校验文件”。

### 10.4 更多页

现有 AppUpdateCheckTile 继续保留：

- 无任务：显示检查更新。
- 下载中：显示继续查看进度。
- 校验中：显示正在校验。
- ReadyToInstall：显示安装更新。
- 失败：显示重试和失败摘要。

更多页不直接渲染插件状态，只消费 AppUpdateDownloadState。

### 10.5 Snackbar

Snackbar 只用于短反馈：

- 已是最新。
- 检查失败。
- 下载已取消。
- SHA-256 校验失败。
- 无法打开安装器。

持续进度不能只放在 Snackbar 中。Snackbar 消失后，任务状态仍必须在下载页面、更多页和通知中可见。
## 11. Android 平台方案

### 11.1 权限

安装阶段新增：

~~~xml
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
~~~

Android 8.0 及以上，Y300 需要检查当前 App 是否被允许请求安装未知来源。permission_handler 12.0.2 已提供 requestInstallPackages 权限枚举，但必须在目标设备上验证：

- denied 时的返回值。
- permanentlyDenied 时是否能正确打开设置页。
- 从设置页返回后是否重新进入安装流程。

不能把请求权限失败当成 APK 下载失败。

### 11.2 FileProvider

Installer 必须使用 content URI，不得把 file URI 传给外部安装器。

需要确认：

- provider authority 唯一。
- paths 只覆盖 AppUpdate verified 目录。
- provider exported=false。
- grantUriPermissions=true。
- 不把整个根文件系统暴露给其它 App。

open_filex 文档中的 root-path 示例不能直接照抄到生产代码。Y300 应限制到实际更新目录，遵循最小权限原则。

### 11.3 可选后台通知

只有选择后台增强轨道时，background_downloader 才使用独立的更新通知组：

~~~text
channel id: app_update_downloads
group: app_update
~~~

通知至少支持：

- 下载中显示百分比。
- 暂停和继续。
- 失败后点击回到 App。
- 完成后点击进入校验/安装。

Android 13+ 通知授权被拒绝时，App 内进度仍然必须可见，不能把通知当作唯一状态来源。

### 11.4 安装器行为

Installer 的正常结果不是“安装成功”，而是：

~~~text
installerLaunched
installerUnavailable
installPermissionRequired
installerLaunchFailed
~~~

真正的安装结果在 App 下次启动时通过当前 versionName 判断：

~~~text
installedVersion >= task.targetVersion
  -> 标记完成并清理任务

installedVersion < task.targetVersion
  -> 保留可重试状态或清理过期 artifact
~~~

不能在打开 Intent 后直接把任务标记为 installed。

### 11.5 Android 版本矩阵

核心轨道至少验证：

| 版本 | 重点 |
| --- | --- |
| Android 8/9 | 未知来源权限和 FileProvider |
| Android 10/11 | Scoped Storage 和私有文件安装 |
| Android 12 | 安装器 Intent 和 URI grant |
| Android 13 | 通知权限、未知来源设置返回 |
| Android 14/15 | 安装确认和 URI grant |

若启用后台增强轨道，另外验证：

| 版本 | 重点 |
| --- | --- |
| Android 8/9 | 后台任务和未知来源权限 |
| Android 13 | 通知权限与任务恢复 |
| Android 14/15 | 后台下载限制、前台服务类型和通知 |

只有后台增强轨道启用时，才需要处理 background_downloader 的运行时间限制、allowPause、重试和前台服务配置，不能把这些平台问题带入核心前台流程。

## 12. 安全与完整性

### 12.1 网络

- Gitee API、APK 和 checksum 入口都使用 HTTPS。
- API 请求不带论坛 Cookie、Authorization 或 Gitee Token。
- DTO 不进入 UI。
- Release notes 按纯文本显示，不执行 HTML、JavaScript 或配置语法。
- 不把 Gitee redirect 中的 token 写入日志。

### 12.2 URL

parser 继续校验初始 APK 和 checksum URL：

- scheme=https。
- host=gitee.com。
- 无 userinfo。
- 无 fragment。
- filename 与 canonical filename 相等。

下载器允许 Gitee 正常的受控重定向，但不能让用户输入任意 URL 成为下载目标。所有下载任务必须从 GiteeReleaseCandidate 创建。

### 12.3 Checksum

checksum 是同一 Release 的公开附件，因此主要用于：

- 传输完整性。
- 发现错误上传。
- 发现 HTML/WAF 页面。
- 发现中途截断。

checksum 不能替代 Android APK 签名。系统安装器仍负责判断新 APK 是否与现有 App 使用兼容签名。

### 12.4 文件安全

- filename 只能来自 canonical artifact。
- 禁止把 URL path 直接拼接成本地路径。
- 路径必须位于 AppUpdateFileStore 管理目录。
- 下载前检查剩余空间，必要时设置最大 APK 大小。
- 校验失败立即删除 staging。
- 未验证文件不能显示“安装”按钮。
- 不允许 APK 下载到用户选定的漫画/小说下载目录。

### 12.5 日志

可以记录：

~~~text
tag=v0.0.2
version=0.0.2
artifact identity hash prefix
state transition
receivedBytes
totalBytes
failure code
~~~

不能记录：

- Cookie。
- Gitee Token。
- 完整带 query token 的 redirect URL。
- Release body 全文。
- 用户文件路径。
- APK 二进制或不必要的敏感内容。

## 13. 分阶段实施

本节采用“核心轨道 + 可选后台增强轨道”。核心轨道完成后已经可以实现 App 内下载、自动命名、SHA-256 校验和系统安装；只有确认需要后台通知和跨进程恢复，才继续实施 Phase 5。

### Phase 0：依赖决策与平台 Spike

目标：

- 证明已有 Dio 可以稳定写入指定 `.apk.part` 文件并报告进度。
- 证明 `crypto` 可以流式计算 APK SHA-256。
- 证明 `open_filex` 或替代 installer adapter 可以通过最小 FileProvider 配置打开系统安装器。
- 明确是否真的需要后台增强轨道。

实施：

1. 不引入 background_downloader，不修改正式更新入口。
2. 使用临时测试代码验证 Dio stream、重定向、指定文件名和取消行为。
3. 使用小型测试文件验证 crypto 的流式摘要结果。
4. 用已签名测试 APK 验证 content URI、MIME、未知来源权限和系统安装器。
5. 确认 installer 的 FileProvider authority 不与现有插件冲突，paths 只覆盖更新目录。
6. 只有产品确认需要后台下载时，才做 background_downloader 的独立 Spike：通知、任务恢复、任务数据库所有权和 Android 版本限制。

交付：

- 依赖兼容记录。
- Installer/FileProvider ADR。
- “仅核心轨道”或“核心 + 后台增强”决策记录。
- 若选择后台增强，补充插件任务数据库和通知所有权记录。

验收：

- 服务器返回 `application/zip` 时，Y300 仍写入标准 `.apk.part`/`.apk` 文件名。
- 不向外部 App 暴露 file URI。
- 测试 APK 可以从系统安装器打开。
- 不为尚未确认的后台需求增加插件。

本阶段不修改 UpgradeAlert 的 onUpdate，不接入正式 Gitee APK 下载。

### Phase 1：Artifact 与 Checksum 领域内核

目标：

- 在不接入真实下载和安装的前提下，建立可测试的制品、checksum 和验证边界。

实施：

1. 将 GiteeReleaseCandidate 映射为 AppUpdateArtifact。
2. 新增严格 AppUpdateChecksumParser 和 checksum repository contract。
3. 使用已有 Dio 实现 checksum 文本 adapter，继续隔离论坛请求头。
4. 复用当前 Gitee URI policy。
5. 新增 ArtifactVerifier contract 和 crypto 实现。
6. 增加大小写、文件名、空白、损坏正文和 hash mismatch 测试。

验收：

- 正确 checksum 能映射为 AppUpdateChecksum。
- 错误 filename 被拒绝。
- 64 位摘要不匹配时永远不能生成 ReadyToInstall。
- checksum 请求不带论坛 Cookie。
- 当前自动更新仍继续使用外部 launcher，不改变生产行为。

### Phase 2：前台下载、文件存储与原子提升

目标：

- 在 App 进程存活期间完成可取消、可重试、可观察进度的应用内下载。
- 将下载文件与可安装文件严格分离。

实施：

1. 创建 AppUpdateBinaryDownloader interface，核心实现使用 Dio `ResponseType.stream`。
2. 实现 AppUpdateFileStore，目录位于 application support 下的受保护 updates/staging 和 updates/verified。
3. 下载时固定使用 parser 生成的 canonical `.apk.part` 文件名，不使用服务器 Content-Type 或 URL path 文件名。
4. 进度只来自实际写入字节数，范围固定在 0 到 1。
5. 下载完成后进入 Verifying，通过 crypto 流式计算 SHA-256。
6. 校验成功后原子 promote 到 verified；校验失败立即删除 staging。
7. 同一 artifact identity 在内存中 single-flight，避免多个入口重复下载。
8. App 进程终止后的 `.part` 文件默认清理并允许重新下载，不在核心轨道伪造断点续传。

验收：

- App 内显示下载进度，页面 rebuild 不会创建第二个下载。
- 服务器返回 apk.zip 时，本地仍然保存为 canonical `.apk`。
- 任何 hash mismatch 都不能生成 ReadyToInstall。
- 100 MB 级别测试文件不会一次性加载到内存。
- verified 文件只来自校验成功的 staging 文件。
- 取消、失败和重试不会留下可被安装器误用的 staging 文件。

### Phase 3：Android Installer adapter

目标：

- 把 verified APK 安全交给系统安装器，并正确处理未知来源权限。

实施：

1. 增加 `REQUEST_INSTALL_PACKAGES`。
2. 配置最小 FileProvider paths，只暴露 verified 更新目录。
3. 实现 OpenFilexAppUpdateInstaller，或在 Spike 失败时实现同职责的窄 Android adapter。
4. 通过 permission_handler 或平台 adapter 处理未知来源权限状态。
5. 增加 installerLaunched、permissionRequired、unavailable 和 failed 结果。
6. App 恢复后根据实际 installed version 判断是否完成安装。
7. 不把“Intent 已打开”当成“安装成功”。

验收：

- Android 8/9/10/11/12/13/14/15 至少覆盖代表性设备。
- content URI 可以被系统安装器读取。
- 权限拒绝能返回 App 内可操作提示。
- 签名错误 APK 被系统拒绝。
- 成功覆盖安装后 App 数据仍保留。

### Phase 4：替换现有更新入口

目标：

- 将 UI 从外部浏览器下载切换到核心应用内下载，同时不改变 Upgrader 的提示语义。

实施：

1. AppUpdateAlertHost 的 onUpdate 改为调用 AppUpdateDownloadService。
2. AppUpdateCheckTile 的“立即下载”复用同一个 service。
3. 新增 AppUpdateDownloadHost 和专用下载/校验/安装 progress UI。
4. 将更多页状态改为消费 AppUpdateDownloadState。
5. 下载中显示取消；暂停/继续只有后台轨道启用且 adapter 支持时才显示。
6. 保留外部打开 Release 页面作为诊断 action，不作为默认 APK 下载路径。
7. 核心路径稳定后，取消 UrlLauncherAppUpdateLauncher 作为默认 launcher。

验收：

- 自动弹窗、手动检查和其它入口都复用同一个 artifact 下载流。
- 下载、校验、准备安装和失败每个阶段都有明确 UI。
- 不能从任何 UI 入口安装未经验证的文件。
- App 切到后台时，核心轨道可以暂停或被系统终止，UI 能在下次打开时明确显示可重试状态。
- 其它模块无新增网络请求、权限或状态变化。

### Phase 5：可选后台增强轨道

只有 Phase 4 完成且产品明确需要后台下载时才实施本阶段。

目标：

- 在不改变领域端口和 UI 状态模型的前提下，增加后台传输、通知和任务恢复。

实施：

1. 引入 background_downloader 作为唯一后台传输和任务通知 owner。
2. 实现 BackgroundDownloaderBinaryDownloader adapter，将插件状态映射为 AppUpdateBinaryEvent。
3. 用 plugin task id + artifact identity 去重，不创建完整的 SharedPreferencesTaskStore。
4. 只保存恢复所需的最小 artifact 关联信息，不能保存 APK 二进制。
5. 验证暂停、继续、取消、重试、App 重启恢复和任务不存在时的清理策略。
6. 通知被拒绝时，App 内状态仍然是唯一可用的 UI 状态来源。
7. 只有后台 adapter 声明支持时，UI 才展示暂停/继续和后台通知相关文案。

验收：

- 同一 artifact 不会创建第二个后台任务。
- App 重启后能恢复、重新校验或明确回到可重试状态。
- 进度单调且不会超过 0 到 1。
- 插件通知和 App UI 不会维护两套互相矛盾的进度。
- background_downloader 的任务数据库不会和 Y300 自己的任务数据库竞争所有权。

### Phase 6：恢复、清理与发布硬化

目标：

- 覆盖真实异常、安装生命周期和正式 Gitee Release。

实施：

1. 验证网络切换、断网、Gitee 429、超时和服务器 5xx。
2. 验证核心轨道的取消、重试、进程终止后清理和磁盘不足。
3. 若已实施 Phase 5，额外验证后台暂停、恢复、通知、任务恢复和 Android 前台服务限制。
4. 验证 checksum 缺失、错误、内容截断和 hash mismatch。
5. 验证未知来源权限拒绝、安装器不存在和用户取消安装。
6. 验证新版本启动后的安装完成确认和旧文件清理。
7. 在正式 JKS 下构建高版本 arm64 APK。
8. 手工创建 Gitee Release 并上传 APK/checksum。
9. 用含更新功能的旧版测试客户端覆盖安装新版。
10. 确认浏览器不再参与 APK 主下载路径，并将 Release 页面保留为诊断入口。
11. 更新发布 SOP、开发文档和真机测试记录。

验收：

- 完成旧版到新版的真实覆盖安装。
- App 内下载、自动命名和 SHA-256 校验正常。
- 若实施 Phase 5，App/通知后台进度和恢复也正常。
- apk.zip 不再是 Y300 应用内流程的结果。
- hash mismatch 不能到达安装器。
- 安装错误签名被 Android 拒绝。
- 失败不会破坏业务模块。
## 14. 测试策略

### 14.1 Domain 单元测试

- canonical APK filename 生成。
- artifact identity 稳定且不会被 URL query token 污染。
- checksum parser 接受合法 sha256sum。
- checksum parser 拒绝错误摘要长度。
- checksum parser 拒绝文件名不一致。
- checksum parser 拒绝多行和超长正文。
- hash mismatch 产生稳定 failure code。
- verifier 成功后才允许 promotion。
- 版本比较由 Upgrader 负责，领域层不自行比较。

### 14.2 Application service 测试

- start 同一 artifact 合并。
- start 不同 artifact 按策略拒绝或取消旧执行流。
- checksum 请求失败不会创建下载任务。
- 下载失败不会调用 verifier。
- 验证失败不会调用 installer。
- installer 打开后不会立即标记 installed。
- 已有 verified 文件必须重新通过校验后才能恢复 ReadyToInstall。
- 取消和重试操作幂等。

### 14.3 Platform adapter 测试

使用 fake downloader、fake file store、fake verifier 和 fake installer：

- Dio stream 的状态和字节进度正确映射。
- 进度边界正确。
- 网络异常转换为稳定 failure code。
- 指定 filename 仍然是 .apk。
- 文件路径不会越出更新目录。
- installer 使用 application/vnd.android.package-archive。

若实施 Phase 5，再增加 background_downloader adapter 测试：

- 插件状态正确映射。
- 同一 artifact identity 不创建重复任务。
- App 重启后任务不存在、任务完成和任务失败均能回到明确状态。
- 插件通知和 App 状态不会产生两套进度。

### 14.4 Widget 测试

- UpgradeAlert 点击立即更新开始同一个 task。
- 更多页手动检查发现更新后开始同一个 task。
- Snackbar 的立即下载开始同一个 task。
- 下载中显示百分比和取消。
- 校验中显示校验状态，不显示虚假的下载百分比。
- hash mismatch 显示失败和重试。
- readyToInstall 显示安装按钮。
- 发现遗留 `.part` 文件时 UI 显示可重试状态，不显示永久 Downloading。
- 未声明暂停能力时不显示暂停/继续按钮。

### 14.5 Android 集成测试

至少用以下场景验收：

| 场景 | 预期 |
| --- | --- |
| 正常 Wi-Fi 下载 | App 进度正常 |
| App 切到后台 | 核心轨道能取消、完成或在返回后明确显示状态 |
| App 被系统杀死 | 核心轨道清理或重新下载，不显示永久下载中 |
| 服务器返回 application/zip | 本地仍为 .apk |
| checksum 正确 | 可以进入安装 |
| checksum 错误 | 删除文件，不出现安装按钮 |
| 未知来源关闭 | 引导设置，不能误报下载失败 |
| 用户取消安装 | artifact 保留或回到可重试状态 |
| 错误签名 | Android 拒绝 |
| 新版覆盖安装 | 数据保留，版本提升 |

若实施 Phase 5，另外验收后台 Wi-Fi、通知权限、任务恢复和 Android 前台服务限制。

## 15. 发布与迁移 SOP

### 15.1 旧版测试客户端

由于当前 Gitee v0.0.1 APK 可能是在应用内更新功能之前构建的，不能直接作为 Phase 6 的旧版测试客户端。

正确顺序：

1. 在包含当前更新功能的源码上构建 versionName=0.0.1、versionCode=4。
2. 使用正式 JKS 签名。
3. 安装到专用测试设备。
4. 保留 App 数据。
5. 再构建 versionName=0.0.2、versionCode=5。
6. 上传 v0.0.2。
7. 从设备中的 v0.0.1 覆盖升级到 v0.0.2。

### 15.2 新 Release

正式 Release 仍由维护者手工完成：

~~~text
pubspec version:
  0.0.2+5

Gitee Tag:
  v0.0.2

APK:
  y300-v0.0.2-android-arm64-v8a-release.apk

Checksum:
  y300-v0.0.2-android-arm64-v8a-release.apk.sha256
~~~

发布前检查：

- applicationId=com.adws.y300。
- versionName 与 Tag 一致。
- versionCode 高于当前安装版本。
- 只有 arm64-v8a。
- 签名证书与历史版本一致。
- checksum 文本与 APK 文件名一致。
- Release notes 是纯文本。
- APK 和 checksum 均可匿名访问。

### 15.3 坏版本

禁止删除后复用相同 Tag：

~~~text
错误版：0.0.2+5 / v0.0.2
修复版：0.0.3+6 / v0.0.3
~~~

如果更新流程已经缓存错误版本，新的更高版本 identity 必须触发新的执行流，不能继续复用旧 artifact identity。

## 16. 兼容与回滚

### 16.1 代码回滚

Phase 4 以前保留 external URL adapter 作为人工诊断路径。若某个 Android 矩阵上的 installer 不稳定，可以：

1. 禁止自动安装入口。
2. 保留 verified artifact。
3. 提供“打开 Release 页面”诊断 action。
4. 修复 adapter 后重新启用。

不允许在下载失败后直接把未经校验的 APK URL 交给浏览器作为默认兜底。

### 16.2 已下载任务

核心轨道版本升级后：

- 启动时重新检查受保护更新目录中的 verified APK。
- verified APK 必须重新通过当前 checksum 校验后才能继续安装。
- staging 不完整或无法关联当前 artifact 的文件直接清理，不清理用户数据。
- 旧版浏览器下载的 apk.zip 不纳入导入，不尝试猜测其来源和完整性。

若实施 Phase 5：

- 新版本只按 background_downloader 的任务记录和最小 artifact 关联信息恢复。
- 插件任务记录不兼容时清理 staging 和后台任务，不清理用户数据。
- 不引入第二套完整的 Y300 task record schema。

### 16.3 数据迁移

本方案不迁移漫画下载、小说正文、图片缓存或用户选择的下载目录。更新 APK 是独立的技术 artifact，生命周期结束后单独清理。

## 17. 可观测性与诊断

### 17.1 事件

建议使用稳定事件：

~~~text
update_download_prepare
update_download_started
update_download_progress
update_download_completed
update_verification_started
update_verification_succeeded
update_verification_failed
update_installer_opened
update_install_permission_required
~~~

若实施 Phase 5，再增加 `update_download_paused`、`update_download_resumed`、`update_recovery_succeeded` 和 `update_recovery_failed`。

### 17.2 诊断内容

事件字段只包含：

- target version。
- release tag。
- task state。
- failure code。
- progress bucket。
- duration bucket。

不记录完整 URL、用户账号、Cookie、Token、文件绝对路径和 Release body。

## 18. Definition of Done

核心轨道完成条件：

1. Gitee Release 发现仍由现有 parser 和 Upgrader 负责。
2. App 内下载能指定 canonical .apk 文件名，不受 Gitee application/zip 影响。
3. App 内能显示下载进度，并支持取消、重试和明确失败。
4. 下载完成后必须经过 checksum filename 和 SHA-256 校验。
5. hash mismatch 永远不能进入 installer。
6. verified 文件使用受保护 AppUpdate 目录。
7. installer 使用 content URI 和 application/vnd.android.package-archive。
8. unknown source 权限失败有明确 UI。
9. Android 系统仍要求用户确认安装。
10. App 进程终止后不会永久显示假下载状态。
11. 正式签名 APK 可以从旧版覆盖安装新版并保留数据。
12. 不新增 Gitee Token、CI 发布、论坛 Cookie 或小说网络参数。
13. 漫画、小说、收藏、论坛和阅读器回归测试通过。
14. Android API 26、29、33、35 至少完成代表性设备验收。
15. 旧浏览器下载路径不再是默认 APK 下载路径。

后台增强附加条件，仅在实施 Phase 5 时要求：

16. App 切到后台后通知栏能显示任务进度。
17. 暂停、继续、取消和重试均可重复调用且幂等。
18. App 重启后能恢复任务、重新校验或明确回到可重试状态。
19. background_downloader 是唯一后台任务和通知进度来源。

## 19. Review 重点

Review 时必须重点确认：

- 若实施 background_downloader，其任务数据库是否和 Y300 的最小 artifact 关联信息保持单一事实来源。
- staging 和 verified 是否严格隔离。
- 任何异常分支是否可能绕过 verifier。
- installer 是否可能打开用户目录中的任意 APK。
- REQUEST_INSTALL_PACKAGES 是否只为 Android 自分发场景增加。
- open_filex 的 FileProvider 是否与其它插件冲突。
- Android 13+ 通知被拒绝时 App 内进度是否仍可用。
- App 被杀死后是否存在永久 Downloading 状态；核心轨道必须清理或重试，后台轨道必须恢复或明确失败。
- 安装器打开后是否误标记为安装成功。
- 旧 apk.zip 是否被错误导入。
- 是否重新引入了与 Upgrader 重复的版本、忽略或提醒状态。
- 是否触碰小说固定的 version=1 请求链路。

## 20. ADR 摘要

### ADR-1：保留 Upgrader，新增下载内核

选择：Upgrader 继续管理发现、比较和提示；下载、校验、安装由新的应用服务管理。

原因：Upgrader 不提供可靠的自托管 APK 传输和安装能力，强行扩展会混淆职责。

### ADR-2：前台下载作为核心，后台下载作为可选增强

选择：核心轨道使用已有 Dio 的流式下载；只有在确认需要后台通知和进程恢复时，才使用 background_downloader 9.5.6 作为可选平台 adapter。

原因：Dio 已足够实现 App 内进度、自动文件名和前台下载，能减少依赖和平台风险。background_downloader 的任务进度、通知、暂停、恢复和持久化能力很有价值，但不应为尚未确认的需求提前引入。

### ADR-3：SHA-256 使用 crypto 流式计算

选择：下载完成后通过 crypto 和 File.openRead 分块校验。

原因：不需要读取整个 APK 到内存，也不把 checksum 校验交给不透明插件。

### ADR-4：安装使用独立 adapter

选择：第一版以 open_filex 4.7.0 作为 installer adapter，并由 Y300 自己配置安装权限和最小 FileProvider paths。

原因：下载器不应拥有安装职责；如果插件在目标矩阵不稳定，只替换 installer adapter。

### ADR-5：系统确认是最终安装边界

选择：Y300 自动完成下载和校验，但不静默安装。

原因：普通 Android App 不应绕过未知来源权限和系统安装确认，Android 签名校验由系统完成。

### ADR-6：更新文件不进入用户下载目录

选择：APK 放入 AppUpdate 私有受保护目录。

原因：更新 artifact 是技术状态，不是漫画/小说/用户文件；避免被用户下载目录设置、清理或其它模块误处理。

### ADR-7：不把下载状态塞进一个 coordinator，也不建立重复任务数据库

选择：DownloadService 只编排，downloader、verifier、file store 和 installer 各自负责一个端口。核心轨道不建立任务数据库；后台轨道使用插件任务数据库作为唯一底层任务事实来源。

原因：便于测试、替换插件、处理 Android 差异和保证安全顺序，同时避免 SharedPreferences 任务状态与插件任务状态不一致。

### ADR-8：当前旧 Phase 4 延迟

选择：至少完成核心应用内下载、校验和安装链路后，再执行正式 Release 和真机覆盖升级演练；如果选择后台增强，则在发布前完成额外后台验收。

原因：先发布外部浏览器方案会把 apk.zip、手动校验和进度体验问题带入正式版本，增加迁移成本；同时不让可选后台能力阻塞核心更新功能。
