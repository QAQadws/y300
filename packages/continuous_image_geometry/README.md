# continuous_image_geometry

连续图片阅读的纯 Dart 几何核心，无第三方运行时依赖。公开入口为
`package:continuous_image_geometry/continuous_image_geometry.dart`。

包负责初始尺寸提示、实测 extent 存储、可见区间查询与高度变化后的滚动补偿计划。
它不负责图片获取、缓存、解码、Flutter 控制器、会话失效或执行滚动。
长图切片、预加载、tail/advance 页面与业务 flow policy 继续由 Host 管理。

## 输入与输出

- `ContinuousImageLayoutItem` 是只读输入接口：`id`、`index`、`knownDimensions`、
  `effectiveKnownDimensionSource`、`fallbackAspectRatio`、`spacingAfter`。
  Host 图片对象可直接实现它，无需为每次查询复制列表或传入 URL、缓存 key、referer。
- `ContinuousImageLayoutResolver` 按顺序使用有效候选：显式 HTML 尺寸、显式持久化尺寸、
  item 已知尺寸、探测尺寸；全无效时使用 item 的 fallback aspect ratio，非法 fallback 回到 `0.7`。
  decoded 尺寸通过独立的 `resolveDecodedHint` 校验，不改变初始候选优先级。
- `ContinuousImageExtentRegistry` 与 `InMemoryContinuousImageExtentRegistry` 保存实测高度，
  缺少实测值时按宽度和 resolver 的比例估算偏移。`estimateOffsetForIndex` 的参数是列表位置；
  可见区间返回的索引则是 item 提供的 `index`。
- `ContinuousImageLayoutIndex` 构造一次几何快照，再查询首个、末个可见图片与最后一个末端位于可见区间的图片。
  图片边缘采用 inclusive 判断；图片之间的纯 gap、图片之后的 tail 区域可能没有可见图片。
- `ContinuousImageScrollAnchorCoordinator` 只返回补偿计划。Host 显式传入
  `allowScrollOffsetCompensation`；计划可能立即执行、等滚动空闲后执行或不执行。

尺寸来源枚举只是提示的来源标签；owner/item ID 是 Host 提供的不透明标识。
它们不建立网络、业务模型或账号会话依赖。

## Host 必须保持的约定

Extent 按 **itemId** 存储，不按 `(ownerId, itemId)` 存储；同 itemId 的新记录覆盖旧记录。
Host 应提供适合当前阅读器的 item ID；切换 owner 或同 owner 刷新时按现有策略调用
`clearForOwner`，退出时释放或清理局部 registry。owner 字段支持清理和补偿匹配，不能替代 Host 的 session/generation 校验；
迟到的尺寸、decode、frame 与 extent 回调必须先由 Host 拒绝。

Items、实测高度、宽度或 spacing 改变后，Host 必须重建 layout index。已有 index 不会随 registry
修改而自动更新；实测高度优先于估算高度，也不会根据另一宽度自动缩放。
测量时机、布局失效、滚动活动判断、偏移补偿执行与持久化仍由 Host 决定。
Host 先读取 previous extent 并计算补偿计划，再写入 next extent、重建 index，最后按原滚动时序执行计划。

构造 index 后的区间查询使用二分，且不再逐图读取 registry。这是算法性质，不是设备帧率或内存承诺；
真实图片解码、Flutter 布局与阅读性能仍需在实际 Host 中验证。

## 验证与示例

在包目录运行 `dart test`、`dart analyze`，以及 `dart run example/geometry.dart`。
示例使用私有不可变类实现输入接口，演示候选尺寸优先级、inclusive 边缘/gap 与 extent 更新后的重建。
包测试不依赖 Flutter 或 App 文件；Host 的会话、控件与漫画/帖子消费者回归仍在应用测试中执行。
仓库级公开入口、纯依赖、测试独立性与旧路径退役检查集中在 App 的
`test/architecture/continuous_image_geometry_boundary_test.dart`，复用现有指令解析工具；
包内算法测试保持独立，不读取 App 的守护或辅助文件。
