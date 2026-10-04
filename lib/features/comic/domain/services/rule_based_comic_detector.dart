import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_detector.dart';

class RuleBasedComicDetector implements ComicDetector {
  RuleBasedComicDetector({this.threshold = 60});

  final int threshold;

  static final RegExp _subjectKeyword = RegExp(
    r'(\u7b2c\s*\d+(\.\d+)?\s*\u8bdd|\u6c49\u5316|\[[^\]]*\u7ec4\]|\u3010[^\u3011]*\u7ec4\u3011)',
    caseSensitive: false,
  );

  static final RegExp _episodeLink = RegExp(
    r'thread-\d+-\d+-\d+\.html',
    caseSensitive: false,
  );

  static final RegExp _weakTextKeyword = RegExp(
    r'(\u76ee\u5f55|\u56fe\u6e90|\u5d4c\u5b57|\u6821\u5bf9)',
    caseSensitive: false,
  );

  @override
  ComicCandidateInfo detect({
    required String fid,
    required String subject,
    required String message,
  }) {
    var score = 0;
    final reasons = <String>[];

    if (fid == '30') {
      score += 40;
      reasons.add('fid=30');
    }

    final imageCount = RegExp(
      r'<img\b',
      caseSensitive: false,
    ).allMatches(message).length;
    if (imageCount >= 2) {
      score += 35;
      reasons.add('\u56fe\u7247\u6570\u91cf>=2');
    }

    if (_subjectKeyword.hasMatch(subject)) {
      score += 20;
      reasons.add('\u6807\u9898\u547d\u4e2d\u6f2b\u753b\u5173\u952e\u8bcd');
    }

    final linkCount = _episodeLink.allMatches(message).length;
    if (linkCount >= 2) {
      score += 15;
      reasons.add('\u7ae0\u8282\u94fe\u63a5\u6570\u91cf>=2');
    }

    if (_weakTextKeyword.hasMatch(message)) {
      score += 10;
      reasons.add('\u6b63\u6587\u547d\u4e2d\u5f31\u5173\u952e\u8bcd');
    }

    return ComicCandidateInfo(
      isCandidate: score >= threshold,
      score: score,
      reasons: reasons,
    );
  }
}
