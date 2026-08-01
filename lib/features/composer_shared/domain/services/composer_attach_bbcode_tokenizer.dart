import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_preview_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_grammar.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attachment_preview_resolvers.dart';

/// Replaces resolvable attachment codes with private preview tags so the
/// BBCode renderer can display local or remote images without changing the
/// editor's source message.
class ComposerAttachBbCodeTokenizer {
  const ComposerAttachBbCodeTokenizer();

  static const String previewTag = 'y300attach';
  static const String previewAttachImgTag = 'y300attachimg';

  String encodeForPreview(
    String source, [
    List<ComposerImageAttachment> imageAttachments =
        const <ComposerImageAttachment>[],
  ]) {
    final effectiveResolver = UploadedComposerAttachmentPreviewResolver(
      imageAttachments: imageAttachments,
    );
    return encodeForPreviewWithResolver(source, effectiveResolver);
  }

  String encodeForPreviewWithResolver(
    String source,
    ComposerAttachmentPreviewResolver resolver,
  ) {
    if (source.isEmpty) {
      return source;
    }

    return source.replaceAllMapped(
      RegExp(
        ComposerAttachBbCodeGrammar.tokenPatternSource,
        caseSensitive: false,
      ),
      (match) {
        final token = ComposerAttachBbCodeGrammar().scan(match.group(0)!);
        if (token.isEmpty) {
          return match.group(0)!;
        }
        final attachment = resolver.resolve(token.single.aid);
        if (!attachment.isAvailable) {
          return match.group(0)!;
        }
        final tag = token.single.kind == ComposerAttachTagKind.attachImg
            ? previewAttachImgTag
            : previewTag;
        return '[$tag]${token.single.aid}[/$tag]';
      },
    );
  }
}
