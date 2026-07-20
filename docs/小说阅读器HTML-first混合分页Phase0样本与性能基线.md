# 小说阅读器 HTML-first 混合分页 Phase 0 样本与性能基线

> 日期：2026-07-20
>
> 生成工具：`dart run tool/novel_reader_phase0_html_baseline.dart`
>
> 本文件只保存脱敏结构计数。正文、URL、Cookie、auth、完整请求头和本地文件路径不进入报告。

## 1. 样本结构报告

样本读取方式与现有 fixture 测试一致：使用 UTF-8 解码原始文件，并以第一个可匹配的正文节点作为主楼 message。选择优先级为 `postmessage_*`、`td.t_f`、`.message`、`.t_f`、`.pcb`、`article`、`body`。

| 样本 | 源 UTF-8 字节 | 主楼 message | message UTF-8 字节 | 普通文本节点 | 普通文本字符 | font | font-size | 前景色 | 背景色 | 图片 | 折叠 | 展开折叠 | 表格 | 表格行 | 表格单元格 | ruby | rt | rp | script | message 敏感标记 |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 文字背景色 | 114561 | `.message` | 47050 | 285 | 16467 | 40 | 2 | 12 | 13 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 10 | 无 |
| 折叠目录 | 456795 | `.message` | 105542 | 497 | 7774 | 9 | 0 | 6 | 0 | 0 | 26 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 11 | 无 |
| 字颜色字号 | 334535 | `.message` | 13975 | 125 | 3021 | 14 | 0 | 13 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 23 | 无 |
| 注音 | 142876 | `.message` | 1833 | 28 | 525 | 2 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 4 | 0 | 10 | 无 |

### 1.1 解读

- `文字背景色` 是字体、字号和前景/背景样式的主要基线，不能把 `<font>` 或 inline `style` 直接降成无样式纯文本。
- `折叠目录` 含 26 个 `.showcollapse_box`，需要保留原子折叠语义；本次首个主楼 message 没有 `showcollapse_active`，不能默认把所有目录展开。
- `字颜色字号` 含正文图片和大量作者颜色，图片必须继续沿用既有图片序列分类，不能按普通文本处理。
- `注音` 含 4 个 `<ruby>` 和 4 个 `<rt>`，没有 `<rp>`。ruby 与前后正文处于同一 inline context，Phase 1 前不得进入普通 TextPainter safe path。
- 页面脚本数量只作为外层页面诊断字段；敏感信息检查只作用于主楼 message，因此样本页面中的论坛脚本不会被误判为正文凭据。

## 2. 当前分页性能指标契约

Phase 0 不改变分页行为，只把当前 HTML-first 分页成本拆成可记录的指标。指标来自 `NovelReaderPaginationPlan`，并由 `NovelReaderPaginationDiagnostics` 传给诊断 sink：

| 成本类别 | 指标 | 含义 |
| --- | --- | --- |
| 总时长 | `layoutDuration` | surface 从请求分页计划到计划完成的总耗时 |
| HTML probe | `measurementCount` | breaker 发起的候选测量次数，包含命中缓存的候选 |
| 真实 renderer | `rendererValidationCount` | 未命中 metrics cache、实际交给 HTML renderer 测量的次数 |
| renderer 缓存 | `measurementCacheHitCount` | 候选 metrics cache 命中次数 |
| DOM slice | `domSliceCount` | `_sliceHtml` 被调用次数，代表候选 HTML 截断/重建成本 |
| Flutter frame | `frameWaitCount` | measurement session 等待 `endOfFrame` 或 post-frame 尺寸回调的次数 |
| 图片 | `readableImageCount`、`atomKindCounts[image]` | 全章可读图片数量与被拆成独立图片 atom 的数量 |
| 分段成本 | `preparationDuration`、`atomizationDuration`、`measurementDuration` | HTML 准备、atom 提取和真实测量的分项耗时 |

这些字段只用于性能诊断，不参与页码、正文、书签、进度或 SQLite 写入。缓存命中返回的 frame wait 计数固定为 0，避免把过去的等待重复累计。

## 3. 复现与采集

### 3.1 样本结构报告

在仓库根目录执行：

```text
dart run tool/novel_reader_phase0_html_baseline.dart
```

工具从 `docs/html/特殊格式/` 读取四个样本并输出 Markdown。样本缺失时以非零状态退出，避免生成不完整的“基线”。

### 3.2 运行时分页指标

在需要测量真实页面时注入 `NovelReaderDebugPaginationDiagnosticsSink`，记录一条布局诊断；默认 sink 仍为 no-op。重点比较以下字段：

```text
layoutDuration
measurementCount
rendererValidationCount
domSliceCount
frameWaitCount
readableImageCount
measurementDuration
```

诊断日志不得记录正文、请求头、Cookie、auth、完整 URL 或本地路径。Phase 0 只建立指标契约和采集入口，不能把一次设备运行时间当成所有设备的性能承诺。

## 4. Phase 0 结论与边界

- 当前成本主要可以按 HTML probe、DOM slice、图片 atom 和 Flutter frame wait 进行拆分，后续优化可以用同一组指标比较前后差异。
- 当前真实 renderer 仍是最终视觉权威，Phase 0 没有引入 TextPainter 分页，也没有修改 safe/complex 路由。
- 四个样本已经证明后续 classifier 至少需要覆盖普通文字、字体样式、背景色、普通图片、折叠、表格和 ruby。
- 进入 Phase 1 前，不应把 `ruby`、表格、折叠、图片或未知字体误放进普通文字 fast path。
