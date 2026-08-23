import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_search_candidate_ranker.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';

abstract class ComicEpisodeLinkMerger {
  List<ComicEpisodeLink> merge(
    List<ComicEpisodeLink> primary,
    List<ComicEpisodeLink> supplement, {
    bool preferSupplement = false,
  });

  List<ComicEpisodeLink> sort(List<ComicEpisodeLink> links);

  List<ComicEpisodeLink> fromSearchCandidates(
    List<ComicSearchCandidate> candidates, {
    required String Function(String tid) threadUrlBuilder,
  });
}

class DefaultComicEpisodeLinkMerger implements ComicEpisodeLinkMerger {
  const DefaultComicEpisodeLinkMerger({
    required ComicSubjectParser subjectParser,
  }) : _subjectParser = subjectParser;

  final ComicSubjectParser _subjectParser;

  @override
  List<ComicEpisodeLink> merge(
    List<ComicEpisodeLink> primary,
    List<ComicEpisodeLink> supplement, {
    bool preferSupplement = false,
  }) {
    final merged = <String, ComicEpisodeLink>{};
    for (final link in primary) {
      merged.putIfAbsent(_linkIdentity(link), () => link);
    }
    for (final link in supplement) {
      final key = _linkIdentity(link);
      if (preferSupplement) {
        merged[key] = link;
      } else {
        merged.putIfAbsent(key, () => link);
      }
    }
    return merged.values.toList(growable: false);
  }

  @override
  List<ComicEpisodeLink> sort(List<ComicEpisodeLink> links) {
    final sorted = links.toList()
      ..sort((a, b) {
        final episodeOrder = _compareEpisodeOrder(
          _sortLabelForLink(a),
          _sortLabelForLink(b),
        );
        if (episodeOrder != 0) {
          return episodeOrder;
        }
        final tidOrder = _compareTid(_linkIdentity(a), _linkIdentity(b));
        if (tidOrder != 0) {
          return tidOrder;
        }
        return _linkTitleForSort(a).compareTo(_linkTitleForSort(b));
      });
    return sorted;
  }

  @override
  List<ComicEpisodeLink> fromSearchCandidates(
    List<ComicSearchCandidate> candidates, {
    required String Function(String tid) threadUrlBuilder,
  }) {
    final sortedCandidates = candidates.toList()
      ..sort((a, b) {
        final episodeOrder = _compareEpisodeOrder(a.title, b.title);
        if (episodeOrder != 0) {
          return episodeOrder;
        }
        final tidOrder = _compareTid(a.tid, b.tid);
        if (tidOrder != 0) {
          return tidOrder;
        }
        return a.searchIndex.compareTo(b.searchIndex);
      });

    final links = <ComicEpisodeLink>[];
    for (final candidate in sortedCandidates) {
      final metadata = _subjectParser.parse(candidate.title);
      final episodeLabel = metadata.episodeLabel?.trim();
      if (episodeLabel == null || episodeLabel.isEmpty) {
        continue;
      }
      final tid = candidate.tid.trim();
      if (tid.isEmpty) {
        continue;
      }
      links.add(
        ComicEpisodeLink(
          url: threadUrlBuilder(tid),
          rawText: candidate.title,
          episodeTitle: episodeLabel,
        ),
      );
    }
    return merge(const <ComicEpisodeLink>[], links);
  }

  int _compareEpisodeOrder(String a, String b) {
    final aKey = _EpisodeSortKey.tryParse(a);
    final bKey = _EpisodeSortKey.tryParse(b);
    if (aKey != null && bKey != null) {
      return aKey.compareTo(bKey);
    }
    if (aKey != null && bKey == null) {
      return -1;
    }
    if (aKey == null && bKey != null) {
      return 1;
    }
    return 0;
  }

  String _sortLabelForLink(ComicEpisodeLink link) {
    final title = _linkTitleForSort(link);
    final parsedLabel = _subjectParser.parse(title).episodeLabel?.trim();
    if (parsedLabel != null && parsedLabel.isNotEmpty) {
      return parsedLabel;
    }
    return title;
  }

  String _linkTitleForSort(ComicEpisodeLink link) {
    final episodeTitle = link.episodeTitle?.trim();
    if (episodeTitle != null && episodeTitle.isNotEmpty) {
      return episodeTitle;
    }
    return link.rawText.trim();
  }

  int _compareTid(String a, String b) {
    final aTid = int.tryParse(a.replaceFirst('tid:', '').trim());
    final bTid = int.tryParse(b.replaceFirst('tid:', '').trim());
    if (aTid != null && bTid != null && aTid != bTid) {
      return aTid.compareTo(bTid);
    }
    if (aTid != null && bTid == null) {
      return -1;
    }
    if (aTid == null && bTid != null) {
      return 1;
    }
    return a.trim().compareTo(b.trim());
  }

  String _linkIdentity(ComicEpisodeLink link) {
    final uri = Uri.tryParse(link.url.trim());
    final tid = uri?.queryParameters['tid']?.trim();
    if (tid != null && tid.isNotEmpty) {
      return 'tid:$tid';
    }
    final threadMatch = RegExp(
      r'thread-(\d+)-',
      caseSensitive: false,
    ).firstMatch(link.url);
    final threadTid = threadMatch?.group(1)?.trim();
    if (threadTid != null && threadTid.isNotEmpty) {
      return 'tid:$threadTid';
    }
    return link.url.trim();
  }
}

class _EpisodeSortKey implements Comparable<_EpisodeSortKey> {
  const _EpisodeSortKey({
    required this.group,
    required this.number,
    required this.suffixRank,
  });

  static final RegExp _episodePattern = RegExp(
    r'^第?\s*(\d+(?:\.\d+)?)\s*(?:话|話|卷|集|篇|章)?\s*(前|上|中|下|后)?$',
    caseSensitive: false,
  );
  static final RegExp _specialPattern = RegExp(
    r'^(番外|特典|附录|附錄|短篇|SP|卷后附录|卷後附錄|卷彩页|卷彩頁|小剧场|小劇場|小漫画|小漫畫|单行本|單行本)$',
    caseSensitive: false,
  );

  final int group;
  final double number;
  final int suffixRank;

  static _EpisodeSortKey? tryParse(String title) {
    if (_specialPattern.hasMatch(title.trim())) {
      return const _EpisodeSortKey(group: 1, number: 0, suffixRank: 0);
    }
    final match = _episodePattern.firstMatch(title);
    if (match == null) {
      return null;
    }
    final number = double.tryParse(match.group(1) ?? '');
    if (number == null) {
      return null;
    }
    return _EpisodeSortKey(
      group: 0,
      number: number,
      suffixRank: _suffixRank(match.group(2)),
    );
  }

  static int _suffixRank(String? suffix) {
    return switch (suffix?.trim()) {
      '前' => -20,
      '上' => -10,
      '中' => 0,
      null || '' => 10,
      '下' => 20,
      '后' => 30,
      _ => 10,
    };
  }

  @override
  int compareTo(_EpisodeSortKey other) {
    final groupOrder = group.compareTo(other.group);
    if (groupOrder != 0) {
      return groupOrder;
    }
    final numberOrder = number.compareTo(other.number);
    if (numberOrder != 0) {
      return numberOrder;
    }
    return suffixRank.compareTo(other.suffixRank);
  }
}
