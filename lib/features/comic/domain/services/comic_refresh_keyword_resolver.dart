import 'package:y300/features/comic/domain/services/comic_episode_refresh_service.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';

enum ComicRefreshKeywordSource {
  customSearchTitle,
  customTitle,
  displayTitle,
  sourceTitle,
  subjectNormalized,
}

class ComicRefreshKeyword {
  const ComicRefreshKeyword({required this.source, required this.value});

  final ComicRefreshKeywordSource source;
  final String value;
}

abstract class ComicRefreshKeywordResolver {
  List<ComicRefreshKeyword> resolve(
    ComicEpisodeRefreshRequest request,
    String subject,
  );
}

class DefaultComicRefreshKeywordResolver
    implements ComicRefreshKeywordResolver {
  const DefaultComicRefreshKeywordResolver({
    required ComicSubjectParser subjectParser,
    ComicReaderFeatureFlags featureFlags = ComicReaderFeatureFlags.defaults,
  }) : _subjectParser = subjectParser,
       _featureFlags = featureFlags;

  final ComicSubjectParser _subjectParser;
  final ComicReaderFeatureFlags _featureFlags;

  @override
  List<ComicRefreshKeyword> resolve(
    ComicEpisodeRefreshRequest request,
    String subject,
  ) {
    final choices = <ComicRefreshKeyword>[
      ComicRefreshKeyword(
        source: ComicRefreshKeywordSource.customSearchTitle,
        value: _nonEmptyOrEmpty(request.customSearchTitle),
      ),
      ComicRefreshKeyword(
        source: ComicRefreshKeywordSource.customTitle,
        value: _nonEmptyOrEmpty(request.customTitle),
      ),
      ComicRefreshKeyword(
        source: ComicRefreshKeywordSource.displayTitle,
        value: _nonEmptyOrEmpty(_parseSearchTitle(request.displayTitle)),
      ),
      ComicRefreshKeyword(
        source: ComicRefreshKeywordSource.sourceTitle,
        value: _nonEmptyOrEmpty(_parseSearchTitle(request.sourceTitle)),
      ),
      ComicRefreshKeyword(
        source: ComicRefreshKeywordSource.subjectNormalized,
        value: _nonEmptyOrEmpty(_parseSearchTitle(subject)),
      ),
    ];
    final unique = <String, ComicRefreshKeyword>{};
    for (final choice in choices) {
      if (choice.value.isEmpty) {
        continue;
      }
      unique.putIfAbsent(choice.value, () => choice);
      if (!_featureFlags.readerRefreshMultiKeywordEnabled) {
        break;
      }
    }
    return unique.values.toList(growable: false);
  }

  String? _parseSearchTitle(String? title) {
    final raw = _nonEmptyOrNull(title);
    if (raw == null) {
      return null;
    }
    final normalized = _nonEmptyOrNull(
      _subjectParser.parse(raw).normalizedTitle,
    );
    return normalized ?? raw;
  }

  String _nonEmptyOrEmpty(String? value) {
    return _nonEmptyOrNull(value) ?? '';
  }

  String? _nonEmptyOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
