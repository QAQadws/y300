# 旧渲染开发对比

正式小说路由默认使用原生显示，release 始终使用原生后端。旧后端只能由 debug/profile 工具显式注入，不作为故障回退或用户设置。

```dart
NovelReaderPage(
  novelId: workId,
  initialEpisodeId: episodeId,
  nativePagination: false,
  comparisonSurfaceFactory: createLegacyNovelReaderSurface,
)
```

`novel/legacy_reader_surface.dart` 实现 App 的 `NovelReaderComparisonSurface` 显示端口。正式页面继续拥有唯一 UI、菜单、导航、阅读资格和持久化回调；开发实现只拥有旧显示的分页缓存和临时转换位置提示。工厂为每条阅读路由创建独立实例，controller owner 变化重置缓存，退出关闭实例，来源返回或公共位置更新先退役旧提示。迟到提示不得跨代次回填。

`WidgetRef` 仅在同步 build 调用中借用，不保存进缓存、异步任务或显示实例；由同一 App provider 装配既有准备服务，避免额外包装 Widget 或第二套协议/会话。文字基础算法统一使用 `forum_content_renderer/forum_text.dart`，对比实现不复制坐标算法。

对比测试和工具通过相对路径导入此目录，生产 `lib/` 不能导入 `tool/`。性能记录须明确后端、固定来源、字体、布局、缓存状态和实际绘制时间；同一页面的恢复和业务语义仍由 App 回归覆盖。

旧 HTML 分页的 engine/model/cache/coordinator 唯一实现位于 `novel/presentation/`。`html_pagination_core` 是 App 开发依赖，生产 `lib/` 不导入旧包或本目录；只有显式对比入口和对应集成测试消费它们。
