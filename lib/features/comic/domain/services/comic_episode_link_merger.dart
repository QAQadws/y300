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
    required String excludeTid,
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
          _linkTitleForSort(a),
          _linkTitleForSort(b),
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
    required String excludeTid,
  }) {
    final sortedCandidates = candidates.toList()
      ..sort((a, b) {
        final episodeOrder = _compareEpisodeOrder(a.item.title, b.item.title);
        if (episodeOrder != 0) {
          return episodeOrder;
        }
        final tidOrder = _compareTid(a.item.tid, b.item.tid);
        if (tidOrder != 0) {
          return tidOrder;
        }
        return a.searchIndex.compareTo(b.searchIndex);
      });

    return merge(
      const <ComicEpisodeLink>[],
      sortedCandidates
          .where((candidate) => candidate.item.tid.trim() != excludeTid)
          .map(_episodeLinkFromSearchItem)
          .toList(growable: false),
    );
  }

  ComicEpisodeLink _episodeLinkFromSearchItem(ComicSearchCandidate candidate) {
    final item = candidate.item;
    final metadata = _subjectParser.parse(item.title);
    final episodeLabel = metadata.episodeLabel?.trim();
    return ComicEpisodeLink(
      url: item.url.trim(),
      rawText: item.title,
      episodeTitle: episodeLabel == null || episodeLabel.isEmpty
          ? item.title
          : episodeLabel,
    );
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
    required this.number,
    required this.suffixRank,
  });

  static final RegExp _episodePattern = RegExp(
    r'第?\s*(\d+(?:\.\d+)?)\s*(?:话|話|卷|集|篇|章)\s*(上篇|下篇|前篇|后篇|後篇|上|中|下|前|后|後)?',
    caseSensitive: false,
  );

  final double number;
  final int suffixRank;

  static _EpisodeSortKey? tryParse(String title) {
    final match = _episodePattern.firstMatch(title);
    if (match == null) {
      return null;
    }
    final number = double.tryParse(match.group(1) ?? '');
    if (number == null) {
      return null;
    }
    return _EpisodeSortKey(
      number: number,
      suffixRank: _suffixRank(match.group(2)),
    );
  }

  static int _suffixRank(String? suffix) {
    return switch (suffix?.trim()) {
      '前' || '前篇' => -30,
      '上' || '上篇' => -20,
      '中' => 0,
      null || '' => 10,
      '下' || '下篇' => 20,
      '后' || '後' || '后篇' || '後篇' => 30,
      _ => 10,
    };
  }

  @override
  int compareTo(_EpisodeSortKey other) {
    final numberOrder = number.compareTo(other.number);
    if (numberOrder != 0) {
      return numberOrder;
    }
    return suffixRank.compareTo(other.suffixRank);
  }
}
