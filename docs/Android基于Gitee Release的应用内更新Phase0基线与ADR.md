# Android 基于 Gitee Release 的应用内更新 Phase 0 基线与 ADR

> 状态：Phase 0 实施基线（2026-07-18）
> 范围：公开 Release 协议、版本模型、Gitee 防腐 parser、纯更新策略
> 非目标：真实 HTTP repository、检查更新 UI、DownloadManager、APK 安装

## 1. 公开发布源基线

Y300 使用公开仓库作为第一版 Android 自分发更新源：

```text
Repository: QAQadws/y300-releases
Latest API: https://gitee.com/api/v5/repos/QAQadws/y300-releases/releases/latest
Release page: https://gitee.com/QAQadws/y300-releases/releases
```

2026-07-18 实测 latest API 无需 `access_token` 即可返回 `200`。真实响应存在：

- `tag_name`
- `prerelease`
- `name`
- `body`
- `created_at`
- `assets[].name`
- `assets[].browser_download_url`

真实响应不存在根级 `draft`、`published_at`、`html_url` 和附件大小。当前 assets 包含 APK、对应 `.apk.sha256` 以及 Gitee 自动源码 `.zip/.tar.gz`；客户端不能按数组位置或 MIME 猜测更新附件。

脱敏 fixture 位于：

`test/features/app_update/fixtures/phase0/gitee_latest_release_v0_0_1.json`

fixture 不加入 `pubspec.yaml` 的 release assets，不包含真实 author 身份或凭据，只保留协议字段、未知字段占位和可复核的公开制品摘要。

## 2. Release 协议

正式 Tag 严格为：

```text
v{major}.{minor}.{patch}
```

第一版只接受稳定三段 SemVer，例如 `v0.0.1`。以下形式全部拒绝：

```text
0.0.1
v0.0
v00.0.1
v0.0.1-beta
v0.0.1+4
```

正式 APK 严格为：

```text
y300-v{versionName}-android-arm64-v8a-release.apk
```

同一 Release 必须同时存在：

```text
y300-v{versionName}-android-arm64-v8a-release.apk.sha256
```

checksum 文本严格为：

```text
{64位小写SHA-256}  {完整APK文件名}
```

两段之间固定两个 ASCII 空格，允许末尾最多一个 `LF/CRLF`，总响应上限 1 KiB。缺 checksum、重复 checksum、HTTP URL、错误文件名、大写摘要、额外行或非 canonical 格式均失败，不提供跳过校验的 fallback。

parser 根据 Tag 生成 APK/checksum 两个期望文件名，要求 assets 中各自恰好一个完全匹配项。源码压缩包和其它 ABI 均忽略；缺失、重复、非 HTTPS URL 或 `prerelease=true` 都返回可分类失败。

发布纪律：每次正式发布必须同时提升 `versionName` 和 `versionCode`。不能发布 `0.0.1+5` 覆盖 `0.0.1+4`；修复版必须至少为 `0.0.2+5`，Tag 为 `v0.0.2`。

## 3. 制品与签名基线

公开附件已经通过匿名完整下载验证，不只验证 API 中存在 URL：

| 项目 | 基线 |
| --- | --- |
| APK | `y300-v0.0.1-android-arm64-v8a-release.apk` |
| 字节数 | `31,215,750` |
| APK SHA-256 | `fbf38c93718f0709363c2eb26d613030b87d78f984329a87b24a05e79f547077` |
| checksum asset | `y300-v0.0.1-android-arm64-v8a-release.apk.sha256` |
| checksum 字节数 | `107` |
| applicationId | `com.adws.y300` |
| versionName | `0.0.1` |
| versionCode | `4` |
| native ABI | `arm64-v8a` |
| signer certificate SHA-256 | `6c3f720b52f587142c156543b20208de775372928201b590758bb4be6f7c8d68` |
| APK signature | v2 verified，single signer |

远端 checksum 已匿名读取并严格解析，其摘要与远端完整下载 APK、本地正式 Gradle 产物三者一致；远端/本地 APK 的字节数、APK SHA-256 和证书 SHA-256 也完全一致。后续 Release 必须继续使用同一份 JKS；更换证书会破坏 Android 覆盖安装和 Phase 3 的安装前校验。

## 4. Phase 0 模块边界

Phase 0 新增：

```text
lib/features/app_update/domain/models
  app_release.dart
  app_update_decision.dart
  app_update_failure.dart
  installed_app_version.dart

lib/features/app_update/domain/services
  app_update_policy.dart
  app_release_checksum_parser.dart
  app_version_codec.dart

lib/features/app_update/data/gitee
  gitee_release_dto.dart
  gitee_release_parser.dart
```

依赖方向固定为：

```text
Gitee raw JSON
  -> data DTO / anti-corruption parser
  -> AppRelease + checksum asset metadata
  -> AppUpdatePolicy
  -> AppUpdateDecision

checksum text
  -> AppReleaseChecksumParser
  -> AppReleaseChecksum expected digest
```

domain 不依赖 Dio、Riverpod、Flutter Widget、MethodChannel 或 Android API。Phase 0 parser 是纯同步函数，policy 是纯 SemVer 比较；测试不会访问网络、下载 APK 或调起安装器。

## 5. ADR 决策

### ADR-1：不增加稳定 JSON，不在客户端保存 Gitee Token

公开 latest API 是 Release 元数据的唯一在线来源。Token 只允许在未来 CI Secrets 中用于发布，不能进入 Dart 常量、fixture、日志或 APK。

### ADR-2：更新发现只比较稳定 SemVer versionName

Gitee Tag 只展示 `versionName`。项目直接依赖 `pub_semver`，并先通过严格三段版本 codec，再执行数值语义比较。禁止字符串、浮点数和各层重复实现版本权重。

```text
remote > installed -> AppUpdateAvailable
remote = installed -> AppUpToDate
remote < installed -> AppUpToDate(localVersionIsNewer=true)
```

### ADR-3：versionCode 只负责 Android 安装顺序

Gitee latest 响应和 Tag 都不提供 `versionCode`，更新发现不得从 Release 正文或文件名猜测。Phase 3 下载完成后由 PackageManager 读取 APK Manifest，并要求 archive versionName 与 Tag 一致、archive versionCode 严格大于当前安装值。

### ADR-4：只接受唯一精确 APK/checksum 对

parser 不取前两个 asset，不按扩展名模糊匹配，也不接受通用 APK。精确 APK 文件名锁定产品、versionName、Android ABI 和 Release 构建类型；checksum 必须在同一 Release 中以 `${apkName}.sha256` 唯一存在。

### ADR-5：checksum 必需但不是信任根

checksum 用于发现传输损坏、CDN 错误或误上传。因为 APK 与 checksum 来自同一 Gitee Release，它不能替代 APK 自身签名。运行时必须先比较 APK SHA-256，再继续验证当前/归档证书并交给 Android 安装器；checksum 缺失或错误时禁止降级跳过。

### ADR-6：供应商字段停留在 data 层

`tag_name`、`browser_download_url` 等 Gitee 命名只存在于 DTO/parser。presentation 和 domain 只依赖 `AppRelease`、`AppReleaseAsset` 与稳定失败分类。

### ADR-7：Phase 0 不提前接入运行时能力

本阶段不引入 `package_info_plus`、真实 Gitee HTTP repository、自动检查、UI、下载和安装。Phase 1 复用本阶段 parser/policy 接入 HTTP 与手动 UI；Phase 2/3 再分别接入 DownloadManager 和 PackageManager/安装器。

## 6. 测试基线

Phase 0 测试必须覆盖：

- 真实脱敏 fixture 成功解析。
- 自动源码附件被忽略。
- 唯一 checksum metadata 映射到 APK，缺失、重复与 HTTP URL 被拒绝。
- 真实 checksum 文本、1 KiB 上限、两个空格、完整文件名、大小写和单行规则被锁定。
- 未知 Gitee 字段被忽略。
- Release notes 缺失与时间不可解析时安全降级。
- 非 canonical Tag、Prerelease、缺 APK、重复 APK、HTTP URL 被拒绝。
- 缺字段、错误类型和非对象 payload 被分类。
- `1.0.10 > 1.0.9` 使用数值 SemVer 语义。
- 远端版本等于或低于本地版本时不提示更新。
- 相同 versionName 不会因为内部 build 假设而误报更新。

## 7. Phase 0 验收结论

- 当前 `v0.0.1` Release 的 APK/checksum 名称与内容符合协议，无需删除或重建。
- 公开 API、APK 与 checksum 均可匿名访问，远端制品、摘要、Manifest、ABI 和签名基线可复核。
- Gitee 真实响应与 checksum 已转为脱敏测试资源。
- 严格版本 codec、Release parser、checksum parser、失败分类、领域模型和更新策略已建立。
- 生产代码没有新增任何网络请求、UI、下载、权限或安装行为。

完成本文件所列测试和 analyze 后，Phase 1 可以直接复用这些边界实现手动检查更新。
