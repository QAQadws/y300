# AGENTS.md

全部编写工作请用UTF-8，你全部的读取代码的工作也是UTF-8编码

## 项目背景

本仓库是 Y300 Flutter/Dart 应用。项目包含论坛、收藏、漫画、小说、书架、搜索、帖子详情和本地持久化等功能模块。进入本仓库工作时，必须先理解相关模块的既有写法，并让改动贴合当前架构。

## `lib` 架构地图

应用按功能模块组织代码，通用基础设施放在 `core`，跨功能 UI 和契约放在 `shared` 与 `library_shared`，Riverpod provider 是主要依赖组合方式。

- `lib/main.dart`：Flutter 入口文件。
- `lib/app`：应用顶层装配，例如 `Y300App`。
- `lib/core/config`：全局配置常量。
- `lib/core/network`：共享网络基础设施，包括 API client、cookie store、logger、请求头构建和网络 provider。
- `lib/core/utils`：跨模块使用的小型解析工具和通用工具。
- `lib/shared/widgets`：不属于单一功能模块的可复用 UI 组件，尤其是书架相关展示组件。

大多数 feature 模块采用轻量 Clean Architecture 分层：

- `data`：repository、API/data-source 实现、本地持久化、Riverpod provider、DTO 和集成服务。
- `domain`：稳定模型、契约、业务服务、分类器、解析器，以及不应依赖 Flutter Widget 的领域逻辑。
- `presentation`：页面、controller、adapter、视图状态和 UI 组合。

### 功能模块职责

- `auth`：登录流程、认证 repository 和登录 controller。
- `cache`：图片缓存、受保护封面缓存、缓存维护和缓存相关 UI 辅助能力。
- `comic`：漫画书架、详情和阅读器模块。负责漫画 repository、本地漫画数据库访问、解析服务、章节发现/刷新、重复漫画合并、下载、阅读偏好、封面提升，以及漫画搜索刷新队列。
- `favorites`：论坛收藏同步和收藏书架模块。负责远端收藏 API、本地收藏缓存、收藏内容导入漫画/小说、收藏同步进度，以及收藏导入后的漫画自动刷新。
- `forum`：论坛首页和版块帖子列表浏览。
- `history`：历史记录相关页面展示。
- `library_shared`：漫画、小说、收藏共用的书架/详情抽象。包含模块 adapter、书架状态持久化、刷新总线、排序/筛选模型、统一书架/详情 controller 和可复用页面。
- `more`：更多页、设置和数据存储管理。
- `novel`：小说书架、详情和阅读器模块。负责小说 repository、帖子网关、章节发现、下载、封面缓存写入和小说阅读 controller。
- `profile`：当前用户/profile repository，包括搜索、回复、收藏等动作所需的 formhash 获取。
- `reply`：论坛回复提交模型、repository 抽象和 API 实现。
- `search`：Discuz 论坛搜索服务、HTML 解析器、搜索调度/限流和搜索页 UI。
- `startup`：主壳页面和启动后的后台任务编排。
- `storage`：下载/存储位置模型、repository 和文件系统服务抽象。
- `tags`：论坛标签加载和查询服务，用于判断帖子内容类型。
- `thread`：帖子详情数据/repository、内容分类器、帖子详情页/controller、回复入口和帖子收藏动作服务。

### 跨模块流转说明

- 帖子详情由 `ThreadContentClassifier` 根据 fid/typeid/tag 元数据判断内容类型，tag 数据来自 `tags`。
- 收藏同步可以把帖子导入漫画或小说模块，然后通过 `LibraryShelfRefreshBus` 发出书架刷新信号。
- 漫画刷新分层执行：先做当前帖/目录发现，直接发现不足时再进入搜索 fallback 或持久化漫画搜索刷新队列。
- 统一书架和统一详情页应依赖 `library_shared` 的 adapter 契约，而不是直接依赖具体漫画/小说/收藏 repository。
- 搜索请求默认应经过搜索调度器和限流器；只有已有明确理由和既有模式时，才直接使用底层 raw service。

## 强制约束

当不只是微调代码而是写了较多的代码时
要写好测试(写好注释)
然后请执行flutter analyze和flutter test来确保你写的代码的正确性，发现问题就修正，然后继续flutter analyze和flutter test，如此往复来修复代码
## 工程实现要求

实现代码改动时：

- 优先考虑工程化、现代化、可维护的实现。
- 考虑设计模式、设计原则和现有模块边界。
- 不要把所有逻辑耦合到一个地方。
- 优先使用职责清晰的小型 service、adapter 或 interface，避免庞大纠缠的流程。
- 保持代码解耦，方便 review。
- 引入新抽象前，先遵循项目已有约定。
- 在非显而易见的决策或复杂逻辑处添加简洁注释，方便 review。
- 不要添加只是复述代码表面含义的噪音注释。

## 文档要求

当代码行为、架构、工作流或 review 重点发生变化时：

- 更新 `docs/开发文档.md`。（在文档开头追加新内容即可）（如果仅微调代码时不需要更新docs/开发文档.md）
- 已经不需要更新 `docs/Review文档.md`了。
- 文档应聚焦“改了什么、为什么改、需要用户 review 或测试什么”。

## 协作说明

- 如果用户提供测试或 analyzer 输出，根据输出修复问题，但不要自行运行这些命令。
- 如果遇到已有未提交改动，保留用户改动，并基于当前状态继续工作，不要回退无关改动。
- 优先做范围明确、能解决问题且不破坏整体一致性的最小改动。


## 方案创建
- 对于方案的规划要优先考虑工程化、现代化、可维护的实现。
- 考虑设计模式、设计原则和现有模块边界。
- 不要把所有逻辑耦合到一个地方。


## 重要决策
小说的解析要version=1，而不是version=4，要不然可能会发生格式错误，目前已经实现了，但是我希望你记住而不要乱改