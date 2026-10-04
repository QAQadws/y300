# forum_markup_core

Y300 的本地纯 Dart 语法包，负责合法 `attach` / `attachimg` token 与无损
`collapse=0` 模型、解析和序列化。运行时无第三方依赖，通过仓库内 path 依赖使用。

```yaml
dependencies:
  forum_markup_core:
    path: packages/forum_markup_core
```

唯一公开入口为 `package:forum_markup_core/forum_markup_core.dart`。
`lib/src` 为内部实现；消费者共享一套类型，不保留应用内副本。
沿用现有 `Composer*` 名称以保持调用契约。

```dart
import 'package:forum_markup_core/forum_markup_core.dart';

const grammar = ComposerAttachBbCodeGrammar();
final tokens = grammar.scan('📖[attachimg]123[/attachimg]');
// start/end 为 Dart String 的 UTF-16 偏移，rawCode 保留原始大小写。
final code = grammar.codeFor('123', ComposerAttachTagKind.attachImg);

const source = '[COLLAPSE=0,Notes]\r\nBody[/COLLAPSE]';
final document = const ComposerCollapseDocumentParser().parse(source);
final restored = const ComposerCollapseSerializer().serialize(document);
assert(restored == source);
```

## 兼容契约

- 附件 token 只接受正十进制 aid（无前导 0、无周围空白）与匹配的开闭标签，
  大小写不敏感；非法内容保留原文。
  `tokenPatternSource` 不含捕获组，可供 Host 组合扫描表达式。
- collapse opening 必须位于行首，以 LF 或 CRLF 结束，且只支持 mode `0`。
  默认最多 16 层，标题可以为空或包含逗号。
- 不完整、行内、交叉或超深结构整段回退为原文，并返回 issue；`isLossless=false`
  表示未能结构化解析，原文仍完整保存在 text part 中。
- 未修改的合法结构保留原始 opening/closing、大小写与行终止符。修改标题后
  opening 重新生成 LF 形式；正文中的用户换行保持。
- `codeFor` 是拼接方法，只修剪 aid，不负责验证；调用者应先用 `isLegalAid`。
  `serializeBlock` 调用者应提供合法标题（`isValidTitle`）与正文；不新增隐式修复。
- collapse identity factory 的 ID 仅用于 Host 内存中的节点身份，不写入 BBCode。
  parse issue 和 token 的 offset 同样使用 UTF-16 单位。

Quill、Widget、附件预览/状态、上传、草稿和本地化由应用负责。
旧草稿的容错提取与论坛客户端编辑回读的宽容 canonicalization 保留各自规则；
严格编辑器语法不会替换这些业务边界。本包仅处理上述语法子集。

## 验证与维护

在本目录执行：

```shell
dart pub get
dart analyze --fatal-infos
dart test
dart run example/basic_markup.dart
```

包内验证纯语法、源码保持和公开依赖边界；App 保留 Quill、预览、选择映射及
帖子编辑集成回归。两层都由仓库 CI 执行。公开方法签名、UTF-16 偏移和无损行为
属于兼容契约，变更时同步版本、说明及相应回归。
