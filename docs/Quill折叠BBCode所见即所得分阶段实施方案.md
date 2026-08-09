# Quill 折叠 BBCode 所见即所得实施方案

## 1. 当前不变量

Composer 中的折叠采用“主 Quill 原子卡片 + 独立全屏编辑页”，不再在卡片内部递归挂载可写 Quill 或标题输入框。

- 主消息编辑区始终只有根 Quill；一个合法折叠在 Delta 中占一个 `collapse` embed。
- collapse embed 是不可被其他格式包裹的无格式原子块：自身不携带 inline attributes，所在行不携带 quote、align 等 block attributes。跨越折叠的格式选区会在折叠两侧拆分，正文内部格式不受限制。
- 两个相邻 collapse card 在 Quill 中显示一行当前正文高度的视觉间距；该间距不是可编辑段落，不进入 Delta、复制文本、BBCode 或提交 payload。源码已有空行时由真实空行负责间距，不再叠加。
- 卡片箭头和标题区域只负责展开/收起，只有右侧编辑图标进入共享 `ComposerCollapseEditorPage`。页面固定持有一个标题 `TextField` 和一个正文 Quill，二者的 controller 在页面生命周期内保持稳定。
- 可视化编辑最多两层：第一层页面正文允许既有格式、引用、链接、表情、`attach`、`attachimg`、图片上传以及创建/编辑第二层折叠；第二层页面不显示折叠工具，也不提供第三层编辑入口。
- 历史三层及更深折叠仍递归解析、展开预览并无损序列化；超过两层的结构需要修改时使用主消息 Source 模式。
- 标题和正文可以删至空。删除页内文字不会穿越页面边界删除父节点；删除整个折叠只能使用页面的显式删除操作或在父 Quill/Source 模式处理原子节点。
- 不修改 Flutter SDK，也不探测 `EditorState` 的私有输入连接状态。

这组约束用于消除同一页面多套 Android `TextInputClient` 竞争。此前的递归 session、可写 path registry、焦点隔离帧、`onReplaceText` 输入守卫和旧 client-ID 过滤均不再属于生产方案。

## 2. Wire grammar 与领域边界

服务器协议保持：

```text
[collapse=0,标题]
正文
[/collapse]
```

`collapse` 大小写不敏感，模式只接受 `0`。标题从第一个逗号之后开始，可以包含逗号，但不能包含 `]`、CR、LF 或 `U+FFFC`。opening 必须位于行首并紧跟 LF/CRLF；该换行属于 envelope，不属于正文。空标题和空正文合法。

`ComposerCollapseBbCodeGrammar`、`ComposerCollapseDocumentParser` 和 `ComposerCollapseSerializer` 继续维护递归 AST 与 fail-closed 行为。合法两层、三层和并列嵌套必须原文 round-trip；未知模式、行内 opening、缺失 closing、交叉嵌套、非法标题和超深结构保留为普通源码，不猜测修复。

小说请求与解析继续固定使用 `version=1`，本功能不触碰该契约。

## 3. Quill embed 与卡片

保留 `Embeddable('collapse', payload) + EmbedBuilder`，payload 版本为 1：

```dart
{
  'collapse': {
    'version': 1,
    'id': 'session-local-id',
    'mode': 0,
    'title': '标题',
    'body': '正文 BBCode',
    'rawOpeningLine': '[collapse=0,标题]\r\n',
    'rawClosing': '[/collapse]',
  },
}
```

`CustomBlockEmbed` 只会改变一层 JSON 包装，不能解决输入连接竞争，因此不切换 payload 形状。codec 继续把根级合法折叠转换为一个原子 embed，并通过 serializer 输出完整 BBCode。`rawOpeningLine/rawClosing` 只在仍与标题和 mode 匹配时复用，否则输出 canonical LF 写法。

codec 在 decode 时不会把当前 active inline/block tags 附着到 collapse；encode 时也不会让 collapse 进入普通 inline wrapper 或 block grouping。共享 surface 另以最小 attributes-only Delta 清理用户跨选区格式产生的残留样式，保证活动 controller 与最终 wire 输出遵循同一不变量。非法行内 collapse 源码仍由 grammar 作为普通文本保留。

`_CollapseEmbedBuilder` 只构建：

- 共同负责展开/收起的箭头与标题区域；
- 位于 toggle 区域之外的独立编辑图标；
- 使用既有 `ForumBbCodeRenderer` 的正文预览。

展开预览复用 `ForumCollapseChrome`、表情、附件 resolver、远程图片 Referer/Cookie 和 `AppImage` 链。它不会构建子 Quill 或标题 `TextField`。

## 4. 新建、编辑与冲突提交

新建时先捕获根 Quill selection，不修改父文档。选区仅包含字符串 operation 时，用 codec 导出其格式化 BBCode 预填正文，并在保存时替换该选区；选区包含附件、表情、折叠或其他 embed 时保留原选区，以空正文创建。

保存由 `ComposerQuillCollapseInsertionService` 执行一次原子插入或替换，并保证 expanded embed 独占一行。取消或放弃修改不会触碰父文档。

编辑句柄保存：

- 父文档 generation；
- 节点 session-local id；
- 原 title/body/raw opening/raw closing 指纹。

真正外部 message replacement 会增加 generation。保存或删除只有在 generation 与 payload 指纹仍匹配时才提交；否则返回 conflict，独立页保持打开并提示用户，绝不覆盖新父文档。本地受控 message 回声与当前编码一致时不重建根 controller，也不增加 generation。

页面返回规则：未修改直接返回；有修改时返回/取消弹出放弃确认；上传和提交期间禁止保存、删除与退出。显式删除需要二次确认，成功提交后页面才关闭。

每个 Quill surface 持有“剩余可编辑折叠层数”：主消息为 2，进入第一层页面后正文为 1，进入第二层后正文为 0。第二层保存只原子修改第一层页面的本地正文，必须再保存第一层才写回主消息；取消第一层会一并放弃已经保存到其草稿中的第二层修改。

## 5. 局部附件与上传

`ComposerInsertionAnchor` 不再包含 document path 或 path revision，只可携带一个局部插入 closure。正文 Quill 在点图片按钮时把当时的局部 source selection 与局部 revision 绑定进 closure；上传完成后：

- 局部 revision tracker 可安全 remap 选区时，把图片代码写入独立页正文并返回 `applied`；父 message/revision 不变化。
- 页面已关闭、host generation 失效或期间编辑与捕获选区相交时返回 `stale`，沿用现有 pending attachment 提示，绝不回退写入根正文。

共享 surface 把附件列表、resolver、上传状态和进度通过只读 host controller 同步给独立页。上传期间页面不能退出；取消整个折叠编辑后，未被父 message 引用的 aid 不进入提交 payload，仍由既有草稿/过期附件维护处理。

## 6. 共享入口与本地化

`ComposerMessageEditorSurface` 统一承接 posting、reply topic、reply floor 和 post-edit。业务页面只传 message、revision、附件 resolver、上传进度和既有工具栏扩展，不复制折叠页面逻辑。

简体和繁体 ARB 提供新建/编辑页标题、正文 hint、放弃确认、删除确认和父文档冲突提示；保存、取消和删除复用 common 文案。修改 ARB 后执行 `flutter gen-l10n`。

## 7. 验收

自动化重点：

- 两层、三层、并列嵌套及格式/表情/附件的 parser、serializer、codec round-trip；
- 主卡片展开后仍只有根 Quill，没有嵌套 `TextField`；
- 新建取消不改父文档，保存只产生一次原子插入；
- 编辑保存、显式删除、dirty 返回和外部 replacement conflict；
- 标题/正文删至空，标准交互式 selection 保持开启；
- 第一层页面可创建/编辑第二层，第二层页面没有折叠工具或第三层编辑图标；
- 第二层保存只更新第一层草稿，第一层保存后才写回主消息，取消第一层会丢弃局部嵌套修改；
- 历史三层及更深折叠保持原始位置与 BBCode，并可继续展开预览；
- 局部上传的 selection remap、`applied/stale`、上传期间退出阻塞；
- posting、reply、post-edit 的草稿、附件、提交和 WebView gate 回归。

Widget fake input 不能替代 Android IME。最终必须在原问题键盘上验证标题与正文连续退格、剪切、长按选择背景/手柄、中文 composing、根正文与独立页快速切换，以及图片上传后的保存和取消。真机通过前不能宣称删除问题完成。
