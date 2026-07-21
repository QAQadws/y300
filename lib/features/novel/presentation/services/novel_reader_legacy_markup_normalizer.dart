import 'package:y300/features/novel/presentation/models/novel_reader_legacy_markup_normalization.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_fragment_codec.dart';

abstract interface class NovelReaderLegacyMarkupNormalizer {
  int get revision;

  NovelReaderLegacyMarkupNormalizationResult normalize(String html);
}

final class DefaultNovelReaderLegacyMarkupNormalizer
    implements NovelReaderLegacyMarkupNormalizer {
  const DefaultNovelReaderLegacyMarkupNormalizer({
    ForumHtmlFragmentCodec fragmentCodec =
        const HtmlPackageForumHtmlFragmentCodec(),
  }) : _fragmentCodec = fragmentCodec;

  static const currentRevision = 1;

  final ForumHtmlFragmentCodec _fragmentCodec;

  @override
  int get revision => currentRevision;

  @override
  NovelReaderLegacyMarkupNormalizationResult normalize(String html) {
    if (!_fontFaceCandidatePattern.hasMatch(html)) {
      return NovelReaderLegacyMarkupNormalizationResult(
        html: html,
        summary: const NovelReaderLegacyMarkupNormalizationSummary(
          revision: currentRevision,
          normalizedAttributeCount: 0,
        ),
      );
    }
    final fragment = _fragmentCodec.parse(html);
    final reasonCounts = <NovelReaderLegacyMarkupNormalizationReason, int>{};

    for (final font in fragment.querySelectorAll('font[face]')) {
      final reason = _invalidFaceReason(font.attributes['face'] ?? '');
      if (reason == null) {
        continue;
      }
      font.attributes.remove('face');
      reasonCounts.update(reason, (count) => count + 1, ifAbsent: () => 1);
    }

    final count = reasonCounts.values.fold<int>(
      0,
      (total, value) => total + value,
    );
    return NovelReaderLegacyMarkupNormalizationResult(
      html: count == 0 ? html : _fragmentCodec.serialize(fragment),
      summary: NovelReaderLegacyMarkupNormalizationSummary(
        revision: revision,
        normalizedAttributeCount: count,
        reasonCounts:
            Map<NovelReaderLegacyMarkupNormalizationReason, int>.unmodifiable(
              reasonCounts,
            ),
      ),
    );
  }

  NovelReaderLegacyMarkupNormalizationReason? _invalidFaceReason(String face) {
    final trimmed = face.trim();
    if (trimmed.isEmpty) {
      return NovelReaderLegacyMarkupNormalizationReason.emptyFontFace;
    }

    final decoded = _decodeQuoteEntities(trimmed);
    var hasUsableToken = false;
    for (final rune in decoded.runes) {
      if (_isFamilyDelimiter(rune)) {
        continue;
      }
      hasUsableToken = true;
      break;
    }
    if (hasUsableToken) {
      return null;
    }
    return decoded.contains(',')
        ? NovelReaderLegacyMarkupNormalizationReason
              .invalidNoUsableFontFamilyToken
        : NovelReaderLegacyMarkupNormalizationReason.invalidQuoteOnlyFontFace;
  }

  String _decodeQuoteEntities(String value) {
    var decoded = value;
    for (var pass = 0; pass < 3; pass++) {
      final next = decoded.replaceAllMapped(_quoteEntityPattern, (match) {
        final entity = match.group(0)!.toLowerCase();
        return entity.contains('apos') ||
                entity.contains('39') ||
                entity.contains('27')
            ? "'"
            : '"';
      });
      if (next == decoded) {
        break;
      }
      decoded = next;
    }
    return decoded;
  }

  bool _isFamilyDelimiter(int rune) {
    if (rune == 0x22 || rune == 0x27 || rune == 0x2C || rune == 0x3000) {
      return true;
    }
    return String.fromCharCode(rune).trim().isEmpty;
  }

  static final _quoteEntityPattern = RegExp(
    r'&(?:quot|apos|#0*34|#x0*22|#0*39|#x0*27);?',
    caseSensitive: false,
  );
  static final _fontFaceCandidatePattern = RegExp(
    r'<font\b[^>]*\bface\b',
    caseSensitive: false,
  );
}

final class NoopNovelReaderLegacyMarkupNormalizer
    implements NovelReaderLegacyMarkupNormalizer {
  const NoopNovelReaderLegacyMarkupNormalizer();

  @override
  int get revision => 0;

  @override
  NovelReaderLegacyMarkupNormalizationResult normalize(String html) {
    return NovelReaderLegacyMarkupNormalizationResult(
      html: html,
      summary: NovelReaderLegacyMarkupNormalizationSummary.none,
    );
  }
}
