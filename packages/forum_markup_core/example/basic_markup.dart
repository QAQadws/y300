import 'package:forum_markup_core/forum_markup_core.dart';

void main() {
  const grammar = ComposerAttachBbCodeGrammar();
  final attachment = grammar.codeFor('123', ComposerAttachTagKind.attachImg);
  final tokens = grammar.scan('Image: $attachment');
  print(tokens.single.aid);

  const source = '[COLLAPSE=0,Notes]\r\nBody[/COLLAPSE]';
  final document = const ComposerCollapseDocumentParser().parse(source);
  print(document.hasCollapse);
  print(const ComposerCollapseSerializer().serialize(document) == source);
}
