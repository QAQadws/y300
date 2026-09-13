# Y300

<div align="center">
  <strong>面向 Yamibo / 百合会内容浏览与阅读场景的第三方 Flutter 客户端</strong>
</div>

<p align="center">
  <img alt="License: GPL v3" src="https://img.shields.io/badge/License-GPLv3-blue.svg">
  <img alt="Development status" src="https://img.shields.io/badge/status-active%20development-orange">
</p>

Y300 将论坛浏览、收藏同步、漫画管理和小说阅读整合在一个 Android 客户端中

## 功能

- 浏览论坛、版块、帖子，支持登录、搜索、收藏、回复和发帖
- 同步论坛收藏，并整理为漫画或小说书架
- 漫画支持纵向、LTR、RTL 阅读，记录进度并提供章节下载
- 小说支持滚动与分页阅读、主题排版、简繁转换和书签
- 本地保存书架、历史、阅读状态、偏好设置与下载内容
- 支持缓存管理、深色模式和应用内更新

## 下载

Android 版本通过 [GitHub Releases](https://github.com/QAQadws/y300/releases) 和 [Gitee Releases](https://gitee.com/QAQadws/y300-releases/releases) 发布，请下载名称类似下面格式的 APK：

```text
y300-v<version>-android-arm64-v8a-release.apk
```

目前仅提供适用于 `arm64-v8a` Android 设备的安装包。项目主体基于 Flutter，具备迁移至 iOS 的基础，但通知、应用更新等平台相关能力仍需适配。请只安装项目维护者发布或自行构建的 APK

## 本地开发

环境要求：使用 [`.flutter-version`](./.flutter-version) 固定的 Flutter（当前 3.44.4）、JDK 17 和 Android SDK。本地与 CI 使用相同 SDK；依赖以两个已提交的 `pubspec.lock` 为准。

```bash
git clone https://github.com/QAQadws/y300.git
cd y300
flutter pub get --enforce-lockfile
flutter run
```

检查与构建：

```bash
dart format <本次修改的Dart文件>
flutter analyze --no-pub
flutter test --no-pub
cd packages/yamibo_forum_client
dart pub get --enforce-lockfile
dart analyze --fatal-infos
dart test
cd ../..
flutter build apk --no-pub --release --target-platform android-arm64
```

锁文件统一记录 `https://pub.dev`。使用镜像的本地环境在更新锁文件前，应将 `PUB_HOSTED_URL` 临时设置为 `https://pub.dev`；不要把镜像来源变化或无关依赖升级带入提交。修改 ARB 后运行 `flutter gen-l10n`，提交生成文件并确保未翻译报告为空。

## CI 与发布

每个面向 `main` 的 PR 和 `main` 提交都会运行静态分析、协议包全部测试、App 两个 shard 的全部测试及 Android release 构建验证。固定的 `CI` 检查汇总全部结果；正常合并要求检查通过且分支与 `main` 同步。PR 构建使用调试签名验证编译，其 APK 不上传。

```bash
gh pr checks --watch
gh run view <run-id> --log-failed
gh workflow run y300.yml --ref <branch> -f mode=check
```

发布前在 `main` 中提交新的 `X.Y.Z+buildNumber`，确认版本名和版本码均超过现有发布，然后为该提交创建 tag：

```bash
git tag -a vX.Y.Z <已合入main的提交SHA> -m "Release vX.Y.Z"
git push origin vX.Y.Z
gh run list --workflow y300.yml
gh run watch <run-id>
gh release view vX.Y.Z --web
```

正式 tag 触发相同的完整 CI，通过后才访问 `android-release` Environment 中的签名 Secret，校验 APK 的版本、包名、arm64 ABI 和发布证书，并上传 APK、同名 `.sha256` 与 `release-manifest.json` 到 GitHub 草稿。你核对发布说明和安装包后公开发布，再将相同产物上传 Gitee；应用内更新继续读取 Gitee。

```bash
gh workflow run y300.yml --ref vX.Y.Z -f mode=release
gh run download <run-id> --dir <下载目录>
```

手动发布仅接受现有正式 tag；同一 tag／提交的草稿可重试补齐附件，保留人工编辑的说明与其中的工作流身份标记。已公开 Release 不覆盖，不移动或重建正式 tag。Actions 产物保留 30 天，公开仓库的产物不是私密存储。签名文件、密码及真实论坛样本不得上传。完整配置与故障恢复约定见 [CI/CD 维护说明](./tool/ci/README.md)。

## 设计参考

Y300 的部分 UI 设计与交互参考自 [kodjodevf/mangayomi](https://github.com/kodjodevf/mangayomi)

## 免责声明

Y300 不是 Yamibo / 百合会官方客户端。论坛帖子、漫画、小说、图片及其他内容归原作者或相应权利人所有。使用时请尊重原作者，并遵守 Yamibo 的相关规则

## 许可证

Copyright (c) 2026 QAQadws and contributors

本项目源代码依据 [GNU General Public License v3.0](./LICENSE) 授权，许可证标识为 `GPL-3.0-only`。第三方名称、商标、内容和用户数据不属于本项目源代码许可证的授权范围
