# 小说阅读器复杂 HTML 流式分页 Phase 0 基线与 ADR

> 状态：Phase 0 已完成，ADR 已接受；Phase 1-3 已落地
>
> 日期：2026-07-21
>
> 关联方案：`docs/小说阅读器复杂HTML流式分页分阶段实施方案.md`
>
> 本阶段范围：样本、characterization tests、诊断基线和架构裁定；不修改生产分页行为

## 1. Phase 0 结论

Phase 0 已经用真实结构样本证明：当前前两页低填充并非作者正文天然不可拆，也不是页面高度估算问题，而是两个短标题因为无效 `<font face>` 被分类为 `complexHtml/unsupportedFont`，随后被当前 `appendComplexBlock` 立即封页。

确定性测试基线：

```text
input:
  invalid font title + invalid font chapter heading + normal div body

classification:
  safeText:   3 atoms
  complexHtml: 2 atoms
  unsupportedFont: 2 reasons

pagination:
  pages: 3
  complex blocks: 2
  complex measurements: 2
  renderer validations: 0
  page 1 fullness: 0.0500
  page 2 fullness: 0.0500
```

两次本机 Debug 测试运行中，fake measurement adapter 下首个稳定页分别为
`29,047µs` 和 `36,360µs`。该观测区间只证明增量首屏诊断入口可工作，
不是 Profile/Release 性能门禁，也不作为稳定断言。

Phase 0 未修改 classifier、style resolver、planner、composer、renderer 或缓存 revision，因此用户当前仍会看到既有独占页行为。目标行为测试以 `skip` 固定，计划在 Phase 5 接入 flowable complex composer 后启用。

## 2. 用户 JSON 样本处理

### 2.1 原始响应

用户提供两份 `version=1`、UTF-8 Yamibo API JSON：

| 来源 | 原始大小 | tid | post 数 | Phase 0 价值 |
| --- | ---: | --- | ---: | --- |
| 第一份响应 | 84,550 bytes | `511960` | 20 | 表格、正文图片、居中分隔符和普通文字边界 |
| 第二份响应 | 1,156,290 bytes | `565218` | 100 | 异常 `font face`、折叠目录、Ruby 和大量 div 正文 |

两份原始响应都包含 `Variables.auth` 等认证信息，因此原始文件没有复制到仓库。

### 2.2 脱敏 fixture

新增：

- `test/features/novel/fixtures/pagination/flowable_complex_invalid_font_v1.html`
- `test/features/novel/fixtures/pagination/thread_511960_complex_blocks_v1.json`
- `test/features/novel/fixtures/pagination/thread_565218_pid_41425048_complex_v1.json`

继续复用：

- `test/features/novel/fixtures/pagination/thread_565218_pid_41425060_v1.json`
- `test/features/novel/fixtures/pagination/centered_divider_overflow_v1.html`
- `test/features/novel/fixtures/pagination/act23_ruby_collapse_v1.html`

新增 JSON 只保留：

- `Version=1`、`Charset=UTF-8`。
- 用于生产 parser 的最小 thread/postlist 外形。
- 来源 tid/pid，便于确认样本来自哪一个结构位置。
- 最小图片、表格、折叠、异常字体和普通正文 HTML。
- 脱敏 fixture author。

明确移除：

- `cookiepre`。
- `auth`。
- `saltkey`。
- `formhash`。
- `member_uid`。
- `member_username`。
- 完整 20/100 楼响应。
- 与分页结构无关的用户信息、回复正文和统计详情。

自动化同时检查敏感 key 不存在于 `Variables`，所有新增 post 使用 `authorid=1` 的 fixture 身份。

## 3. Phase 0 生产链路证据（历史）

```text
prepared HTML
  -> DefaultNovelReaderHtmlFlowUnitExtractor
  -> NovelReaderPaginationAtomExtractor
  -> NovelReaderPaginationAtomClassifier
      invalid face
        -> ForumHtmlTextStyleResolver.unsupportedFontFamily
        -> NovelReaderPaginationRoute.complexHtml
        -> NovelReaderPaginationRouteReason.unsupportedFont
  -> NovelReaderComplexBlockPaginationEngine
      -> whole-atom renderer measurement
  -> NovelReaderPaginationPageComposer.appendComplexBlock
      -> keepPageOpen=false for complexHtml
      -> emit immediately
```

Phase 0 时的 production hybrid planner 不会对这两个标题执行复杂 HTML 二分，
它们各自只被整块测量一次。Phase 5 已替换该行为，当前生产链路见第 16 节；本节
只保留初始问题证据。

## 4. Fixture 路由基线

Phase 0 自动化锁定以下 route 存在性：

| Fixture | 精确 route/reason 基线 |
| --- | --- |
| invalid font title HTML | `complexHtml/unsupportedFont` × 2，另有 safe text |
| tid `511960` 脱敏样本 | `isolatedImage=1`、`tableBlock=1`、`safeText=13` |
| tid `565218`, pid `41425048` 脱敏样本 | `complexHtml/unsupportedFont=1`、`collapseBlock=2`、`safeText=9` |
| 已有 pid `41425060` 样本 | `safeText=95`、`rubyInline=2` |

已有 `novel_reader_user_json_pagination_fixture_test.dart` 继续锁定 pid `41425060` 的精确基线：

```text
safeText: 95 atoms
rubyInline: 2 atoms
page count: 8..15
average fullness: > 0.8
```

Phase 0 没有放宽任何现有 route。

## 5. ADR-001：Route 与布局能力解耦

### 决策

接受。

route/reason 只描述结构和风险来源；独立 layout policy 描述测量、拆分、放置和 overflow 行为。

### 原因

`unsupportedFont` 表示 TextPainter 快速路径不能保证字体度量一致，不表示正文没有合法文本边界。继续用 `complexHtml` 同时表达渲染方式和不可拆性，会重复产生短文本独占页。

### 后果

Phase 1 必须引入 capability model，并停止从 `route == complexHtml` 直接推导 `isBreakable=false`。

## 6. ADR-002：产品指定 dedicated content

### 决策

以下内容始终独占页：

- 正文 readable image。
- 表格。
- 折叠块。

它们在 composer 中必须通过显式 dedicated API 前后 flush，不继续使用“如果能放入上一页就尝试组合”的隐式行为。

### 原因

- 图片尺寸和视觉干扰与普通文字不同。
- 表格具有共同列宽、rowspan/colspan 和横向滚动语义。
- 折叠块展开后高度变化，不能污染后续 page index。

## 7. ADR-003：真正的 Widget 从 complex text 中分离

### 决策

`iframe`、`video`、`audio`、`canvas`、`object` 和没有稳定 inline adapter 的 WidgetSpan 归入独立 `atomicWidget` policy。

### 原因

“除图片/表格/折叠外的 complex HTML 可二分”只适用于以文字为主体、布局高度随范围单调增长的内容。真实嵌入 Widget 没有可靠文字范围，不能通过文本二分安全拆分。

### 后果

Phase 1 必须让 `atomicWidget` 成为明确 route/policy，而不是继续隐藏在通用 `complexHtml` 中。

## 8. ADR-004：复杂文字使用 DOM 合法边界二分

### 决策

以文字为主体且满足单调布局条件的复杂 HTML 使用：

```text
DOM parse/index once
  -> legal semantic boundaries
  -> upper-bound binary search
  -> persistent ForumHtmlWidgetPostRenderer measure session
  -> largest verified fitting prefix
```

禁止按 HTML 字符串长度切分。

### 必须保护

- grapheme cluster。
- HTML entity。
- Ruby base/rt/rp cluster。
- protected inline smiley/widget。
- anchor 连续性。
- 标签闭合。

### 性能约束

- safe text 保持 TextPainter 一次布局。
- 每 complex fragment 最多 12 次 probe。
- 相同 range 和 buffer composition 必须可缓存。
- 取消令牌必须在每次 probe 前后检查。

## 9. ADR-005：无效 quote-only font face 是 no-op normalization

### 决策

`face` 为空、只包含单双引号或 quote entity、规范化后没有可用 family token 时，Phase 2 删除 `face` 属性，保留 `<font>`、文字、颜色、字号和外层 strong。

### 不包括

- 不删除有效未知字体。
- 不把未知字体强制映射为 Roboto。
- 不修改正文文字。
- 不在 novel 中复制共享 style resolver。

### 原因

本次 `face="&amp;quot"` 是损坏的遗留属性，没有可实现的字体视觉语义。让它触发整页 complex fallback 只增加分页成本和空白。

## 10. ADR-006：最终 renderer 继续作为高度权威

### 决策

flowable complex search 的每个候选由 `ForumHtmlWidgetPostRenderer` 测量。DOM index 和二分只选择范围，不近似复杂 CSS 或 Ruby line box。

### 后果

- 必须复用现有 persistent measure session。
- candidate cache key 必须包含 layout identity、range 和 buffer signature。
- 最终 accepted candidate 应命中已有测量结果。

## 11. ADR-007：增量发布与已发布页面不可变

### 决策

只发布 composer 已封口的稳定页。已发布页之后出现迟到 mismatch 时，不允许原地改写前页；应取消当前 generation，并由现有 performance policy 回到纵向或重启未发布 plan。

### 原因

页面重排会破坏 page index、阅读进度、书签和用户正在查看的内容。

## 12. ADR-008：失败测试管理

### 决策

Phase 0 曾同时保留：

- 通过的 characterization test：断言当前两个独占页和 5% fullness。
- 跳过的目标行为 test：断言标题、章节名和后续正文应进入同页。

不允许主分支持续红灯。Phase 5 已反转旧 characterization：no-op normalizer 下
两个 `unsupportedFont` atom 仍保持 flowable route，但标题、章节名和后续正文
现在合为 1 页。旧 3 页与 5% fullness 继续保留在本 ADR 和历史提交中，不再作为
当前生产行为断言。

## 13. Rollback

每个后续阶段必须可以独立回退：

```text
Phase 1 capability model
  -> 默认 policy 映射为当前行为

Phase 2 normalization
  -> 提升 normalizer revision
  -> 可按规则开关停用

Phase 3-4 index/search
  -> 纯 service，未接生产 composer

Phase 5 production integration
  -> 提升 renderer revision
  -> 出现错误时关闭 flowable complex policy
  -> 回到当前 whole-atom complex behavior 或纵向模式
```

rollback 不回写正文，不涉及数据库迁移。

## 14. Phase 0 自动化

新增：

- `test/features/novel/presentation/novel_reader_complex_html_flow_phase0_test.dart`

覆盖：

- 两个 `unsupportedFont` 分类证据。
- 当前三页计划和前两页 5% fullness。
- measurement/probe 基线。
- JSON 脱敏契约。
- safe、Ruby、图片、表格、折叠 route 存在性。
- 跳过的 Phase 5 目标行为。

推荐验证命令：

```text
flutter test test/features/novel/presentation/novel_reader_complex_html_flow_phase0_test.dart
flutter test test/features/novel/presentation/novel_reader_user_json_pagination_fixture_test.dart
flutter test test/features/novel/presentation/novel_reader_hybrid_pagination_fixture_test.dart
flutter analyze
```

## 15. Phase 0 完成门禁

- [x] 两份 JSON 以 UTF-8、`version=1` 读取。
- [x] 原始认证信息未写入仓库。
- [x] 已有重复 pid fixture 被复用，没有复制完整响应。
- [x] 异常字体标题最小 fixture 已建立。
- [x] 当前 route、reason、页数、fullness、measurement 和首屏诊断已记录。
- [x] safe/Ruby/image/table/collapse 基线已锁定。
- [x] 目标行为已建立为 skipped test。
- [x] ADR 已裁定 route/policy、dedicated、atomic、二分、缓存和 rollback。
- [x] 生产分页行为未修改。

## 16. Phase 1-5 后续实施记录

Phase 1 已将 route reason 与 layout policy 解耦，并引入
`flowableComplexText`、`atomicWidget`、flowability inspector 和 capability
diagnostics。该阶段仍通过旧 whole-atom engine 输出页面，因此无效字体样本的
默认可见基线尚未变化。

Phase 2 已在小说共享 chapter preparation 边界加入 revision `1` 的 legacy
markup normalizer。默认路径会删除两个 quote-only `font face`，保留所有正文、
wrapper 和其它样式属性，使样本全部进入 `safeText` 并从 3 页降为 1 页。
Phase 5 之前注入 `NoopNovelReaderLegacyMarkupNormalizer` 可以复现本 ADR 记录的
3 页、两次 whole-atom measurement 和前两页 `0.0500` fullness。Phase 5 后同一
注入路径会保留两个 flowable route 作为迁移证据，但新 engine 会把它们与相邻
safe text 合为 1 页；旧行为证据继续保存在本 ADR 和历史提交中。

Phase 3 已抽取共享 `NovelReaderHtmlDomTextIndex`：既有 safe slicer 继续使用
rune 坐标，新 complex session 使用 grapheme 坐标，两者共用单次 DOM parse、
不可变节点索引和 wrapper clone。Ruby 与已知 protected inline 节点拥有不可拆
range，合法 boundary 携带连续 anchor；空白 slice 明确返回不可渲染。该 session
尚未接入 planner、renderer probe 或 composer，因此 Phase 0/2 的可见分页基线
不因 Phase 3 再次变化。

Phase 4 已新增纯 `NovelReaderComplexHtmlFitSearcher`。它在 Phase 3 合法 boundary
上先执行 whole-remainder fast check，再按语义 coarse boundary 与 grapheme fine
boundary 两层 upper-bound；当前 buffer 连最小片段都放不下时自动改为空白整页
重试，并通过 `requiresFreshPage` 返回明确的封页证据。搜索最多调用 measure
session 12 次，取消在每次 probe 前后检查，非单调高度使用稳定错误终止，预算
不足时只返回已测量的最大 fit。缓存与并发 single-flight 继续复用既有
`NovelReaderCachingPaginationMeasureSession`。该 service 仅由确定性 fake
measurer 测试，尚未接入生产 planner、真实 renderer 或 composer，因此可见分页
基线仍保持不变。

Phase 5 已新增 `NovelReaderFlowableComplexPaginationEngine` 并接入生产 hybrid
planner。每个 flowable atom 只建立一个 DOM session，engine 循环消费 Phase 4
结果；composer 使用 renderer 返回的组合总高度，按 `requiresFreshPage` 封旧页，
按 `flushAfterAppend` 只发布已封口片段。短 complex 可以与前后 safe text 合页，
长 complex 可以跨页且 anchor 连续。Boundary/index、measurement、非单调和整页
最小片段 overflow 都通过稳定 reason 原子降级，不丢正文。

表格、折叠与 atomic/legacy complex 已改走显式 dedicated API，前后强制 flush，
不再尝试 composition probe；dedicated 页具有独立 page 标记与 gap reason，不参与
文本页填充率统计。Planner/diagnostics 新增 fragment、boundary、probe/cache、
budget、minimum fragment、dedicated/atomic page 和 failure reason 计数。生产
renderer revision 已提升到 `13`，旧 plan cache 自动失效。Ruby/protected-inline
仍保留旧路径，等待 Phase 6。

下一阶段为 Phase 6：把 Ruby cluster 和已知稳定尺寸 protected-inline adapter
接入相同 flowable engine，同时保持未知 inline widget 的 atomic fallback。
