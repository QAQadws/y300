# Y300

<div align="center">
  <strong>面向 Yamibo / 百合会内容浏览与阅读场景的第三方 Flutter 客户端</strong>
</div>

<p align="center">
  <img alt="Flutter 3.44.4" src="https://img.shields.io/badge/Flutter-3.44.4-02569B?logo=flutter&logoColor=white">
  <img alt="Dart 3.12" src="https://img.shields.io/badge/Dart-3.12-0175C2?logo=dart&logoColor=white">
  <img alt="License: GPL v3" src="https://img.shields.io/badge/License-GPLv3-blue.svg">
  <img alt="Development status" src="https://img.shields.io/badge/status-active%20development-orange">
</p>

> **主视觉图片占位**
>
> 建议路径：`.github/assets/readme/hero.png`<br>
> 建议内容：论坛、书架、漫画阅读器和小说阅读器的组合界面。<br>
> 建议尺寸：`1600 x 900` 或其他 16:9 图片。添加图片后，用实际图片替换本占位块。

Y300 将论坛浏览、收藏同步、漫画管理和小说阅读整合在一个客户端中。项目当前以 Android 为主要运行与发布平台，重视本地数据管理、阅读体验以及对 Discuz/Yamibo 页面结构的兼容




## 功能概览

### 论坛

- 浏览论坛首页、版块、主题列表与帖子详情
- 支持原生解析模式与 WebView 模式
- 支持登录、搜索、收藏、回复、发帖及部分 Discuz 互动能力
- 统一处理 Yamibo HTML、移动 API、Cookie、会话与表单请求

### 收藏与书架

- 同步论坛收藏，并将内容整理为漫画或小说
- 漫画、小说使用统一的书架与详情交互
- 支持分类、筛选、排序、网格/列表显示和自定义封面等本地管理能力
- 底部的论坛、收藏、漫画、小说和记录入口可调整显示状态与顺序

### 漫画

- 从帖子或目录发现并管理漫画章节
- 支持纵向、从左到右和从右到左的图片阅读模式
- 支持阅读进度、已读状态、书签、章节切换和阅读偏好
- 支持章节下载队列、图片级下载进度、失败重试与断点续传
- 下载内容与普通可清理缓存分开管理

### 小说

- 从作者楼层和目录中发现小说章节，并保留正文 HTML 结构
- 支持滚动阅读、LTR 分页和 RTL 分页
- 支持字号、行距、阅读主题以及简体/繁体转换
- 支持图片、表格、折叠块、注音和复杂行内样式等混合正文
- 统一记录每部小说的上次阅读章节与进度

### 本地体验

- 本地保存书架、分类、阅读记录、书签、下载状态与个性化设置
- 提供历史记录、缓存清理、缓存上限和下载位置管理
- 支持浅色、深色及跟随系统的应用外观
- 支持应用内检查更新与 Android 安装流程

## 界面预览

| 论坛与帖子 | 书架与详情 |
| --- | --- |
| **图片占位**：`.github/assets/readme/forum.png`<br>建议展示论坛首页或原生帖子详情。 | **图片占位**：`.github/assets/readme/library.png`<br>建议展示漫画/小说书架与作品详情。 |

| 漫画阅读器 | 小说阅读器 |
| --- | --- |
| **图片占位**：`.github/assets/readme/comic-reader.png`<br>建议展示阅读工具栏、进度和章节导航。 | **图片占位**：`.github/assets/readme/novel-reader.png`<br>建议同时展示滚动与分页阅读效果。 |

建议截图隐藏用户名、UID、Cookie、私信、草稿以及其他账号相关信息


## 下载与安装

### 获取 Android 版本

发布版本通过 [Gitee Releases](https://gitee.com/QAQadws/y300-releases/releases) 提供。请选择文件名形如下面格式的 APK：

```text
y300-v<version>-android-arm64-v8a-release.apk
```

安装前请注意：

1. APK 仅适用于 `arm64-v8a` Android 设备
2. 从旧版本覆盖安装时，Android 会校验应用 ID 与签名是否一致
3. 请只安装项目维护者发布或你自行构建的 APK
4. 首次侧载时，Android 可能要求你授权当前安装来源

### 登录要求

浏览公开内容通常不要求登录。收藏同步、回复、发帖、个人资料及受权限限制的内容需要有效的 Yamibo 账号和网络连接

## 本地开发

### 环境要求

- Flutter `3.44.4` stable
- Dart `3.12` 或满足 [`pubspec.yaml`](./pubspec.yaml) 的兼容版本
- JDK 17。
- Android SDK，以及可用的 Android 设备或模拟器

使用其他 Flutter 版本前，请先检查依赖兼容性和生成的原生工程差异

### 获取并运行

```bash
git clone https://github.com/QAQadws/y300.git
cd y300
flutter pub get
flutter run
```

项目默认不要求把账号凭据写入源码。需要登录时，请在应用内完成登录流程

### 质量检查

提交代码前至少运行与改动范围相关的测试，并执行静态分析：

```bash
flutter analyze
flutter test
```

测试数量较多时，可以先运行受影响模块的定向测试：

```bash
flutter test test/features/<feature>/<test_file>.dart
```

### 构建 Android arm64 APK

```bash
flutter build apk \
  --release \
  --target-platform android-arm64
```

未配置 `android/key.properties` 时，本地 release 构建会回退到 debug 签名，仅适合开发验证。公开分发必须使用稳定且妥善保管的 release keystore；不要提交 keystore、密码或 `key.properties`



## 项目架构

项目采用按功能模块组织的轻量 Clean Architecture，并使用 Riverpod 完成依赖装配

```text
lib/
├── app/                 # 应用顶层装配、导航和全局设置
├── core/                # 网络、配置、媒体、日志等基础设施
├── features/            # forum、comic、novel、thread 等业务模块
│   └── <feature>/
│       ├── data/        # 数据源、repository 实现、本地存储和 provider
│       ├── domain/      # 领域模型、契约、解析器和业务服务
│       └── presentation/# 页面、controller、adapter 和 UI 状态
├── shared/              # 通用组件
└── main.dart            # Flutter 入口

test/                    # 与 lib 模块边界对应的测试
docs/                    # ADR、阶段方案、开发记录和技术说明
```

主要技术组件：

- **状态与装配**：Flutter Riverpod
- **网络**：Dio、自定义 Yamibo 网关、Cookie/session/formhash 管理
- **本地存储**：SQLite（sqflite）与 SharedPreferences
- **HTML**：`html`、`csslib`、`flutter_widget_from_html_core` 等解析和渲染能力
- **阅读器**：共享图片阅读引擎与小说 HTML-first 混合分页管线
- **下载与缓存**：漫画下载队列、受保护文件、常规磁盘缓存和容量维护


## 数据与隐私

Y300 需要连接 Yamibo 及应用更新发布源。为维持登录和本地阅读体验，应用会在设备上保存必要的会话 Cookie、书架数据、阅读进度、缓存和下载文件

- 不要在 Issue、日志或测试样本中提交 Cookie、密码、auth、saltkey、formhash、私信或完整账号抓包
- 添加论坛 JSON/HTML 测试样本前，应移除认证字段和可识别个人身份的信息
- 清理普通缓存不会等同于删除书架、阅读记录或已下载内容
- 卸载应用、清除应用数据或手动删除存储目录可能导致本地数据丢失

本项目当前未提供云同步或账号级跨设备备份承诺

## 贡献指南

欢迎通过 Issue 和 Pull Request 改进项目。建议流程：

1. 先搜索现有 Issue，确认问题是否已经被记录
2. Fork 仓库并从最新开发分支创建功能分支
3. 遵循现有 `data / domain / presentation` 模块边界，避免把业务逻辑集中到页面中
4. 为修复或新行为补充定向测试
5. 运行 `dart format`、相关 `flutter test` 和 `flutter analyze`
6. 在 Pull Request 中说明问题、实现方式、验证结果和可能的兼容风险

开发时还应遵守以下项目约束：

- 所有源文件、文档和测试样本使用 UTF-8
- 小说解析请求继续使用 `version=1`，不要改为 `version=4`
- 不提交真实账号凭据、签名文件、下载产物或包含敏感信息的抓包
- 优先复用现有 service、repository、adapter 和 provider，不建立平行的数据流

## 问题反馈

请通过 [GitHub Issues](https://github.com/QAQadws/y300/issues) 提交问题。一个有帮助的报告通常包含：

- Y300 版本、Android 版本和设备架构
- 可重复的操作步骤、预期行为与实际行为
- 已脱敏的错误日志或截图
- 问题对应的论坛页面类型；必要时提供公开链接

请勿公开提交登录 Cookie、Token、密码、私信内容或包含认证字段的完整响应

## 免责声明

- Y300 不是 Yamibo / 百合会官方客户端，也不代表其运营方立场
- 论坛帖子、漫画、小说、图片及其他内容的权利归原作者或相应权利人所有
- 使用者应遵守所在地法律法规、Yamibo 服务规则及内容权利人的授权范围
- 由于网络、权限、反爬机制或上游 HTML/API 变化，部分功能可能临时不可用
- 本项目不对第三方内容的准确性、可用性、版权状态或长期可访问性作保证

## 许可证

Copyright (c) 2026 QAQadws and contributors

本项目源代码依据 [GNU General Public License v3.0](./LICENSE) 授权，许可证标识为 `GPL-3.0-only`。分发本项目或其衍生版本时，必须遵守 GPL v3 对应源代码与许可证告知等要求

Yamibo / 百合会名称及商标、论坛帖子、漫画、小说、图片、用户数据、测试样本中的第三方内容，以及其他不由 Y300 项目贡献者持有权利的素材，不属于本项目源代码许可证的授权范围；相关权利归原作者或相应权利人所有
