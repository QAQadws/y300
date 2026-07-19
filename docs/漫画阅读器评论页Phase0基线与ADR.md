# 漫画阅读器评论页 Phase 0 基线与 ADR

> 状态：Accepted
> 日期：2026-07-19
> 覆盖阶段：Phase 0 / Phase 1
> 关联方案：`漫画阅读器评论页分阶段实施方案.md`

## 1. 基线

### 1.1 现有请求边界

Y300 已经存在两条帖子详情读取链路：

```text
解析模式帖子页
  -> threadRepositoryProvider
  -> ThreadDetailHtmlRepository
  -> HTML 请求 / HTML-first parser / 文档缓存

结构化漫画发现与同步
  -> threadJsonRepositoryProvider
  -> ApiThreadRepository
  -> module=viewthread JSON API
```

漫画评论只需要第二条 JSON 链路。评论 Phase 1 新增的 `ThreadReplyPageRepository` 包装 JSON repository，不读取 HTML，不建立第二个 API client，不接入完整帖子详情 controller。

### 1.2 输入数据形状

脱敏 fixture 固定保留以下结构：

- `Variables.thread.tid`、`thread.replies`。
- `Variables.ppp`。
- `Variables.postlist` 顶层楼层。
- 楼层的 `pid`、`first`、`author`、`authorid`、`dateline`、`number`、`message`。
- `comments` 和 `commentcount` 作为应被忽略的点评字段。
- `message` 中同时存在普通 HTML 图片和表情图片，证明正文将在后续阶段交给现有 HTML renderer，而不是由评论 loader 判断资源类型。

样本约束：

```text
replies = 39
ppp = 20
包含首楼的总楼层数 = 40
候选页数 = ceil(40 / 20) = 2
有效评论数 = 39
```

fixture 不包含 Cookie、`auth`、`saltkey`、登录用户名、真实认证 JSON 或完整远程抓取响应。

### 1.3 当前阶段不包含

- 评论卡片和 HTML widget UI。
- reader tail、PageView advance 节点和垂直展开面。
- 头像 widget 的实际网络加载。
- 下一章节图片预加载。
- 评论正文的持久化缓存。

## 2. ADR-001：评论请求使用 JSON-only adapter

### Context

评论需要按照 `replies/ppp` 获取全部顶层楼层。解析模式帖子页的 HTML repository 有 HTML-first 缓存、主题准备和完整帖子生命周期，不适合在漫画 reader 中作为分页 API 使用。

### Decision

新增 `ThreadReplyPageRepository`，生产实现 `ApiThreadReplyPageRepository` 包装 `threadJsonRepositoryProvider` 提供的 `ApiThreadRepository`。

```text
ComicCommentLoader
  -> ThreadReplyPageRepository
  -> threadJsonRepositoryProvider
  -> ApiThreadRepository
  -> ApiClient.getParsed(module: viewthread)
```

### Consequences

- 评论分页不会发起 HTML 请求。
- JSON API 的 Cookie、请求头和错误映射继续由现有 `ApiClient` 负责。
- 评论数据层不会依赖 HTML cache、ThreadDetailPage 或 WebView。
- 后续评论正文渲染仍可单独复用 `ForumHtmlContentView`；数据传输和 HTML 展示保持两个职责。

## 3. ADR-002：只排除首楼，不按作者过滤

### Context

用户确认只排除 `first=1` 的首楼。楼主可能在后续楼层再次发言，不能因为 `authorid` 与首楼相同就删除后续回复。

### Decision

loader 的过滤顺序为：

1. `post.isFirst == true` 的楼层不生成评论项。
2. 其它顶层 `postlist` 楼层都保留，包括楼主后续回复。
3. 跨页以 `pid` 去重。
4. `comments`、`commentcount` 等点评字段完全不读取为评论项。

如果极旧响应缺少 `first`，实现只允许使用 page 1 的 `number == 1` 和对应 `pid` 做窄范围兜底，绝不按用户名或作者 ID 过滤。

### Consequences

- “楼主”不是评论过滤条件；“首楼身份”才是过滤条件。
- 顶层回帖和楼中楼点评不会混淆。
- Phase 1 测试必须包含楼主后续回复。

## 4. ADR-003：评论 loader 负责分页与单飞

### Context

UI 不应自行计算页数、并发请求或合并页面。章节切换和 reader 生命周期还会让旧请求迟到，因此需要领域层稳定控制。

### Decision

`DefaultComicCommentLoader` 负责：

- 先请求 page 1。
- 使用 `ceil((replies + 1) / ppp)` 推断候选页数。
- 受到 `maxPageRequests=100` 限制。
- 后续页最多 `maxConcurrentPages=2` 并发。
- 按页顺序合并，按 `pid` 去重。
- 后续页失败返回 `partialFailure`，不伪造完整 `success`。
- 同一 `sourceTid` 的并发调用共享一个 Future。

`ComicCommentCancellationToken` 只表达调用方是否还愿意等待。它不把 Dio 类型泄漏到 domain，也不强行取消可能被其它调用复用的共享网络任务。

### Consequences

- 同一章节不会因为重复进入尾页而重复请求相同页面。
- 章节切换时旧 UI 可以立即停止等待。
- 后续阶段可以在不修改分页算法的前提下增加渐进式页面快照。

## 5. ADR-004：头像 URL 是确定性 forum adapter

### Context

评论 API 的 `authorid` 是稳定来源信息，头像路径遵循 Discuz 的九位数字分组规则。

### Decision

`DefaultForumAvatarUrlBuilder` 只接受不超过 9 位的纯数字 ID，左侧补零至 9 位，按 `3+2+2+2` 分组后生成：

```text
422014 -> 000422014 -> 000/42/20/14_avatar_middle.jpg
8      -> 000000008 -> 000/00/00/08_avatar_middle.jpg
```

builder 不发请求、不持有 Widget 状态、不记录认证信息。后续 presentation 层使用 `ForumCachedAvatar` 负责缓存、默认头像和失败回退。

## 6. Phase 1 完成标准

- JSON adapter 可以把 `viewthread` page 映射为类型稳定的 `ThreadReplyPage`。
- `replies=39/ppp=20` 得到两页候选，合并后 39 条有效评论。
- 只排除 `first=1`，楼主后续回复仍存在。
- 点评字段不出现在 `ComicCommentItem`。
- 重复 `pid` 只出现一次。
- page 2 失败返回局部失败，page 1 的有效评论仍保留。
- 同一 `sourceTid` 并发调用只产生一套网络请求。
- 取消调用方停止等待，底层共享请求可继续完成。
- 422014、8、非法头像 ID 都有稳定测试。
- 相关 Dart 格式化、Flutter 测试和 `flutter analyze` 通过。
