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

## CI

`.github/workflows/y300.yml` 是唯一工作流入口。面向 `main` 的 PR、`main` push、`v*` tag 和手动运行均验证当前事件的固定提交，覆盖工作流校验、变更 Dart 格式、本地化生成、静态分析、协议包全部测试、App 两个 shard 的全部测试及 Android arm64 release 构建。

固定的 `CI` 检查要求所有必要任务成功；失败、取消或跳过均不能放行。正常合并要求 PR、检查通过且基于最新 `main` 验证，不要求额外审阅人数，管理员保留紧急绕过。构建使用临时调试签名验证编译，APK 不上传。

```bash
gh pr checks --watch
gh run view <run-id> --log-failed
gh workflow run y300.yml --ref <branch-or-tag>
```

各任务的分析、测试及构建结果和耗时写入运行摘要。截图测试失败时保留比较图片 7 天，可用 `gh run download <run-id> --dir <下载目录>` 下载并检查差异。修复后提交 PR 即可重新运行，不自动重试失败测试。

当前工作流只负责 CI 检查，不读取签名 Secret，也不创建或公开 Release。正式签名、发布校验和 Release 草稿自动化暂缓；推送 tag 不会发布安装包。

## 设计参考

Y300 的部分 UI 设计与交互参考自 [kodjodevf/mangayomi](https://github.com/kodjodevf/mangayomi)

## 免责声明

Y300 不是 Yamibo / 百合会官方客户端。论坛帖子、漫画、小说、图片及其他内容归原作者或相应权利人所有。使用时请尊重原作者，并遵守 Yamibo 的相关规则

## 许可证

Copyright (c) 2026 QAQadws and contributors

本项目源代码依据 [GNU General Public License v3.0](./LICENSE) 授权，许可证标识为 `GPL-3.0-only`。第三方名称、商标、内容和用户数据不属于本项目源代码许可证的授权范围
