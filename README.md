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

环境要求：最新版 Flutter stable、JDK 17 和 Android SDK。具体 SDK 兼容范围以 [`pubspec.yaml`](./pubspec.yaml) 为准。

```bash
git clone https://github.com/QAQadws/y300.git
cd y300
flutter pub get
flutter run
```

检查与构建：

```bash
dart format .
flutter test
flutter analyze
flutter build apk --release --target-platform android-arm64
```

公开分发前请配置自己的 release keystore，不要提交签名文件、密码、账号凭据或包含认证信息的日志

## 设计参考

Y300 的部分 UI 设计与交互参考自 [kodjodevf/mangayomi](https://github.com/kodjodevf/mangayomi)

## 免责声明

Y300 不是 Yamibo / 百合会官方客户端。论坛帖子、漫画、小说、图片及其他内容归原作者或相应权利人所有。使用时请尊重原作者，并遵守 Yamibo 的相关规则

## 许可证

Copyright (c) 2026 QAQadws and contributors

本项目源代码依据 [GNU General Public License v3.0](./LICENSE) 授权，许可证标识为 `GPL-3.0-only`。第三方名称、商标、内容和用户数据不属于本项目源代码许可证的授权范围
