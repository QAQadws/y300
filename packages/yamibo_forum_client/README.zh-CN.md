# yamibo_forum_client

`yamibo_forum_client` 是 Y300 使用的非官方 Yamibo 论坛纯 Dart 客户端，提供来源中立的读取契约、基础认证、结构化写命令、Discuz/HTML adapter、受保护图片流和 WAF 协调协议。它不依赖 Flutter、Riverpod、SQLite 或 Y300。

当前版本为 `0.10.0`，继续设置 `publish_to: none`，通过本地 path 或 Git 子目录使用。英文 [README.md](README.md) 是规范文档；版本与兼容政策见 [VERSIONING.md](VERSIONING.md)、[MIGRATION.md](MIGRATION.md) 和 [API_STABILITY.md](API_STABILITY.md)。许可证为 [GPL-3.0-only](LICENSE)。

## 安装

仓库内使用 path：

```yaml
dependencies:
  yamibo_forum_client:
    path: packages/yamibo_forum_client
```

第三方仓库可使用 Git 依赖，并固定到经过验证的 commit 或 tag：

```yaml
dependencies:
  yamibo_forum_client:
    git:
      url: https://github.com/QAQadws/y300.git
      ref: <verified-commit>
      path: packages/yamibo_forum_client
```

## 临时上手

```dart
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

final client = YamiboForumClientBuilder.ephemeralDio()
    .buildStandardClient();
final result = await client.loadForumDirectory(
  const ForumDirectoryQuery(),
);
```

`ephemeralDio()` 自动使用已验证的 Yamibo 地址与浏览器身份，并提供内存 Cookie、Session、document、snapshot 和表情缓存。它只适合试用、测试和短生命周期工具；进程退出后所有状态都会丢失。

## 生产装配

```dart
final client = YamiboForumClientBuilder.standardDio(
  config: ForumClientConfig.yamibo(),
  cookies: persistentCookieStore,
  caches: ForumClientCachePorts(
    documents: persistentDocumentStore,
    snapshots: persistentSnapshotStore,
    stickers: persistentStickerStore,
  ),
  waf: platformWafDelegate,
  logger: applicationLogger,
).buildStandardClient();
```

生产 Host 需要提供持久 Cookie、三个缓存端口，以及论坛启用挑战时的 `ForumWafRecoveryDelegate`。Package 负责 Dio、请求身份、Session 投影、formhash、协议 adapter 和来源矩阵；WebView 与平台生命周期仍由 Host 负责。

`ForumClientConfig.yamibo()` 对移动 HTML 和 Discuz API 使用移动 Chromium UA，对桌面 HTML 和受保护图片使用桌面 Chromium UA。自定义 UA 时，WAF delegate 必须使用完全相同的身份。

## 读取与能力

读取返回 `DataReadResult`。成功结果同时包含业务数据、capability 和来源 metadata；调用方应先检查 capability，再开放对应功能。`supported + null/empty` 表示来源已经检查但业务数据为空，`unsupported` 表示来源无法提供，两者不能混用。

标准来源矩阵包括：

- 论坛首页、目录、版块列表和帖子详情：HTML-first；
- Tag、公开资料和日志：HTML；
- 收藏目录、当前用户资料、提醒、私信和表情：Discuz API；
- 漫画目录/发现/评论与 ingestion：Discuz v4 API；
- 小说作者帖子：固定 `viewthread version=1`；
- 搜索、完整评分、楼层定位：当前已验证的 HTML/AJAX/redirect 协议。

可以仅替换一个业务来源，其余标准来源保持不变：

```dart
final client = builder.buildStandardClient(
  sourceOverrides: ForumClientSourcePlan(
    threadDetail: newApiThreadRepository,
  ),
);
```

不存在全局 HTML/API 开关。

## 认证与命令

Cookie 是认证事实来源，Session/formhash 是可重新获取的投影。标准客户端支持密码登录、会话解析和标准登出；登录只有在 profile 回读证明稳定非零 uid 后才算 applied。

所有写操作都返回五态结果：

- `DataCommandApplied`：后置条件已经证明；
- `DataCommandRejected`：服务器明确拒绝；
- `DataCommandNotSent`：发送前校验或 Session 准备失败；
- `DataCommandOutcomeUnknown`：请求已发送，但结果无法确认；
- `DataCommandUnsupported`：当前来源不支持。

普通命令失败不会自动重发；只有同站 HTTP 405 经 WAF delegate 验证恢复后，传输层允许重放一次。`outcomeUnknown` 必须保留用户输入，并由用户明确决定是否重试。

当前结构化命令覆盖收藏/取消收藏、评分、点评、投票、发帖、回复、普通帖子编辑，以及图片附件上传和删除。服务器原始 JSON、XML/CDATA、HTML、Cookie 和 formhash 不会进入回执。

## 受保护图片与 WAF

标准 Dio runtime 同时实现 `ForumResourceClient`。成功结果提供只能订阅一次的字节流，调用方应完整消费或取消订阅，并自行负责原子落盘和图片解码。Package 不提供 Flutter `ImageProvider`、图片磁盘缓存、预加载、CBZ 或阅读器恢复。

同站图片共享论坛 Cookie，仅 HTTP 405 会触发 Yamibo WAF 恢复；第三方图片不携带 Yamibo Cookie，也不触发 Yamibo WAF。重定向有次数上限，禁止 HTTPS 降级。

## 尚未覆盖与有意留在 Host 的边界

尚未覆盖的论坛能力：

- 复杂帖子编辑表单的 WebView fallback；
- 非图片附件、附件描述/readperm/price、替换和批量删除；
- 通知状态变更和私信发送。

有意由 App/Host 保留：

- WebView 登录、浏览、fallback、平台 Cookie 同步和生命周期；
- Flutter WAF WebView；
- 图片缓存、解码、预加载和阅读器恢复；
- SQLite、书架、漫画/小说同步、阅读进度、下载队列和 UI。

## 公共入口

- `yamibo_forum_client.dart`：facade、builder、runtime 与 Host ports；
- `yamibo_forum_client_contracts.dart`：来源中立契约、模型和结果；
- `yamibo_forum_client_adapters.dart`：实验性的 adapter factory 及少量公开 parser/mapper。

第三方代码不得导入 `package:yamibo_forum_client/src/...`。贡献和发布检查见 [CONTRIBUTING.md](CONTRIBUTING.md) 与 [RELEASING.md](RELEASING.md)。
