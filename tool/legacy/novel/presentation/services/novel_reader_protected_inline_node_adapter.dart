import 'package:html/dom.dart' as html_dom;

enum NovelReaderProtectedInlineNodeKind { forumSmiley, declaredInlineImage }

enum NovelReaderProtectedInlineNodeFailure {
  unsupportedElement,
  missingStableDimensions,
  invalidStableDimensions,
}

final class NovelReaderProtectedInlineNodeAssessment {
  const NovelReaderProtectedInlineNodeAssessment.notProtected()
    : isCandidate = false,
      kind = null,
      width = null,
      height = null,
      failure = null;

  const NovelReaderProtectedInlineNodeAssessment.stable({
    required this.kind,
    required this.width,
    required this.height,
  }) : isCandidate = true,
       failure = null;

  const NovelReaderProtectedInlineNodeAssessment.unstable({
    required this.kind,
    required this.failure,
  }) : isCandidate = true,
       width = null,
       height = null;

  final bool isCandidate;
  final NovelReaderProtectedInlineNodeKind? kind;
  final double? width;
  final double? height;
  final NovelReaderProtectedInlineNodeFailure? failure;

  bool get isStable => isCandidate && failure == null;
}

abstract interface class NovelReaderProtectedInlineNodeAdapter {
  NovelReaderProtectedInlineNodeAssessment assess(html_dom.Element element);
}

/// Admits only inline images whose layout box is fixed before remote loading.
/// This keeps already published pagination pages immutable after image decode.
final class DefaultNovelReaderProtectedInlineNodeAdapter
    implements NovelReaderProtectedInlineNodeAdapter {
  const DefaultNovelReaderProtectedInlineNodeAdapter();

  @override
  NovelReaderProtectedInlineNodeAssessment assess(html_dom.Element element) {
    final isDeclared = element.attributes.containsKey(
      'data-y300-protected-inline',
    );
    final isForumSmiley = _isForumSmiley(element);
    if (!isDeclared && !isForumSmiley) {
      return const NovelReaderProtectedInlineNodeAssessment.notProtected();
    }

    final kind = isForumSmiley
        ? NovelReaderProtectedInlineNodeKind.forumSmiley
        : NovelReaderProtectedInlineNodeKind.declaredInlineImage;
    if (element.localName?.toLowerCase() != 'img') {
      return NovelReaderProtectedInlineNodeAssessment.unstable(
        kind: kind,
        failure: NovelReaderProtectedInlineNodeFailure.unsupportedElement,
      );
    }

    final rawWidth = element.attributes['width'];
    final rawHeight = element.attributes['height'];
    if (rawWidth == null || rawHeight == null) {
      return NovelReaderProtectedInlineNodeAssessment.unstable(
        kind: kind,
        failure: NovelReaderProtectedInlineNodeFailure.missingStableDimensions,
      );
    }
    final width = _parseDimension(rawWidth);
    final height = _parseDimension(rawHeight);
    if (width == null || height == null) {
      return NovelReaderProtectedInlineNodeAssessment.unstable(
        kind: kind,
        failure: NovelReaderProtectedInlineNodeFailure.invalidStableDimensions,
      );
    }
    return NovelReaderProtectedInlineNodeAssessment.stable(
      kind: kind,
      width: width,
      height: height,
    );
  }

  bool _isForumSmiley(html_dom.Element element) {
    if (element.localName?.toLowerCase() != 'img') {
      return false;
    }
    if (element.attributes.containsKey('smilieid')) {
      return true;
    }
    final source = <String?>[
      element.attributes['src'],
      element.attributes['data-src'],
      element.attributes['data-original'],
      element.attributes['file'],
      element.attributes['zoomfile'],
    ].whereType<String>().join(' ').toLowerCase();
    final hasSmileyClass = element.classes.any((value) {
      final normalized = value.toLowerCase();
      return normalized.contains('smilie') || normalized.contains('smiley');
    });
    return source.contains('static/image/smiley/') ||
        source.contains('/smiley/') ||
        hasSmileyClass;
  }

  double? _parseDimension(String value) {
    final normalized = value.trim().toLowerCase().replaceFirst(
      RegExp(r'px$'),
      '',
    );
    final parsed = double.tryParse(normalized);
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      return null;
    }
    return parsed;
  }
}
