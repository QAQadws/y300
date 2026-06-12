/// 编辑器双模式：源码（直接输入 BBCode）/ 预览（渲染后展示）。
///
/// reply 与（后续阶段的）posting 共用同一个枚举，避免每个业务侧再分别定义一遍。
/// 旧的 `ReplyComposerMode` 通过 typedef 继续暴露，调用方不需要立刻迁移。
enum ComposerEditorMode {
  source,
  preview,
}
