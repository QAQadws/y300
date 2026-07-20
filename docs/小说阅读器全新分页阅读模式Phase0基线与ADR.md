# 小说阅读器全新分页阅读模式 Phase 0 基线与 ADR

> 状态：Phase 0 实施基线
>
> 日期：2026-07-20
>
> 对应方案：`docs/小说阅读器全新分页阅读模式分阶段实施方案.md`

## 1. Phase 0 结论

小说阅读器旧分页实现已经退出生产和测试边界。后续分页必须从当前 HTML-first 正文准备结果重新实现，不允许重新接回旧 `NovelReaderDocumentView`、旧估算 paginator 或旧 layout service。

当前阶段的有效阅读行为固定为：

- 正文视觉入口：`NovelReaderHtmlDocumentView`。
- HTML 准备入口：`NovelHtmlChapterRenderPreparer`。
- 最终正文 renderer：`ForumHtmlWidgetPostRenderer`。
- 用户默认阅读模式：`NovelReaderFlowMode.vertical`。
- 已保存的 `pagedLtr/pagedRtl` 偏好继续可以从 SharedPreferences 读取，但在新分页上线前只保留为 `persistedPreferences`，运行时 `effectivePreferences` 明确降级为 `vertical`。
- 阅读退出、滚动和章节切换只提交纵向 `scrollOffset/progressPercent`，不会调用已删除的旧分页进度入口。

## 2. 已移除的旧分页边界

Phase 0 删除以下旧分页实现：

- `novel_reader_paged_surface.dart`
- `novel_reader_document_view.dart`
- `novel_reader_layout_service.dart`
- `novel_reader_layout_key.dart`
- `novel_reader_layout_request.dart`
- `NovelReaderPaginator`
- `NovelReaderPageLayout`
- `NovelReaderPageSlice`
- `NovelReaderPaginationMetrics`
- `NovelReaderViewport`
- `NovelReaderController.onPagedPageChanged()`
- `novelReaderLayoutServiceProvider`
- `NovelReaderPage` 中旧分页 controller、恢复分支和占位“模式”按钮
- 只验证旧 RichBlock 分页 renderer、旧 layout cache 和旧 PageView 的测试替身

## 3. 继续保留的语义能力

以下类型不是旧分页专属能力，必须保留：

- `NovelReaderDocument`
  - 继续作为搜索、书签摘要和语义节点的输入。
  - 不再直接决定分页视觉布局。
- `NovelReaderTextAnchor`
  - 继续作为未来跨重排位置恢复的稳定语义锚点。
- `NovelReaderProgressSnapshot`
  - 继续承载现有 SQLite 进度字段和未来分页位置。
  - Phase 0 只提供纵向进度策略；新分页策略在后续阶段以 HTML-first 页片模型重新建立。
- `NovelReaderFlowMode` 的三个存储值
  - 保证已有偏好和 SQLite 行可以读取。
  - 保留值不代表继续支持旧分页布局。

## 4. ADR-001：视觉正文以 prepared HTML 为唯一来源

### 决策

新分页必须消费 `NovelHtmlChapterRenderPreparer` 产生的 prepared HTML 和全章图片序列，并继续通过 `ForumHtmlWidgetPostRenderer` 渲染页片。

### 原因

- 当前纵向阅读已经依赖新的主题适配、作者样式归一化、图片去重和缓存语义。
- 旧 `NovelReaderDocumentView` 只能渲染一部分 RichBlock 形态，无法保证与当前 HTML 正文一致。
- 共享同一 prepared HTML 可以让纵向和分页保持相同的链接、图片、表情、引用和颜色行为。

### 影响

- 后续分页算法不能直接读取旧 `NovelReaderPageSlice.blocks`。
- 如果分页需要 DOM flow unit，应从同一 prepared DOM 派生，不能再次用另一套 parser 解释原始 HTML。

## 5. ADR-002：删除旧分页，不建立兼容 adapter

### 决策

旧分页文件和 provider 直接删除，不保留 feature flag、兼容 facade 或“旧/新 paginator”双轨运行。

### 原因

- 旧分页没有当前产品入口，运行时已经强制纵向。
- 兼容 adapter 会让两种页面模型长期共存，增加重排、图片索引和进度恢复的歧义。
- 当前应用可以在新分页完成前稳定回退到纵向，不需要旧分页兜底。

### 影响

- 后续 Phase 1/2 必须建立全新的 HTML flow unit、page fragment 和 pagination key。
- 新分页测试不能复用旧 layout service 测试替身。

## 6. ADR-003：旧分页偏好可读，运行时明确降级

### 决策

在新分页完成前：

```text
persisted flowMode = pagedLtr / pagedRtl
  -> 读取并保留用户持久化值
  -> effective flowMode = vertical
  -> 使用 HTML-first 纵向正文
  -> 保存当前进度时写 vertical
```

### 原因

- 直接把存储值改写为 `vertical` 会过早丢失用户原有选择。
- 让旧值直接驱动已删除的 PageView 会恢复错误布局。
- `persisted/effective` 双层已经是现有 controller 的偏好预览边界，可以表达该降级而不新增状态机。

## 7. ADR-004：未来增加可空 pagination key

### 决策

新分页进入进度持久化阶段时，推荐为 `novel_reading_progress` 增加可空的 `pagination_key`（或语义等价的 `layout_fingerprint`）。Phase 0 不执行数据库 migration，也不写入该字段。

### 原因

- 旧 `page_index` 来自旧 renderer，不能证明属于未来的新 HTML 分页布局。
- 字号、行高、viewport、图片尺寸和 renderer revision 都可能改变页边界。
- nullable key 可以直接区分旧数据和同一新布局的数据，同时保持旧数据库行可读。

### 恢复优先级

后续实现固定为：

1. pagination key 相同且 pageIndex 有效。
2. 稳定 anchor + text offset。
3. progress percent。
4. 旧 pageIndex 仅作为最低优先级兼容候选。
5. 全部失效时回到第一页。

### 数据边界

- pagination key 只属于阅读进度。
- 不把页片 HTML、图片字节或分页缓存写入 SQLite。
- 不修改 `novel_episode_content` 的正文唯一来源语义。

## 8. HTML-first 回归基线

Phase 0 的回归基线由现有和新增测试共同约束：

- 主题变化会重新 prepare，旧主题迟到 future 不得覆盖新主题正文。
- 相同 prepare identity 会复用结果；字号变化会失效。
- 链接点击继续通过 `NovelReaderLink` 回调并获得规范化论坛 URL。
- 简繁转换在主题适配前完成。
- 普通正文图片保持全章稳定 sequence、attachment ID、URL 和 cache key。
- 默认偏好仍为字号 `18.5`、行高 `1.6`、护眼主题和纵向模式。
- 旧分页偏好读取后只影响 persisted state，不创建旧 PageView。

## 9. Phase 1 进入条件

只有满足以下条件才进入 Phase 1：

- 全仓库不再引用旧分页类型、provider 和文件。
- 小说纵向阅读器、controller、HTML preparer、HTML view、搜索和书签相关回归通过。
- `flutter analyze` 通过。
- 当前提交不包含新的分页算法、PageView 或数据库 migration。
- 新分页继续遵守小说请求 `version=1`，不修改水合网络链路。
