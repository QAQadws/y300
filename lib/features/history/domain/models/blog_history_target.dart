import 'package:y300/features/history/domain/models/history_models.dart';

/// Keeps both identities needed to reopen a journal in the existing history key.
final class BlogHistoryTarget {
  factory BlogHistoryTarget({
    required String ownerUserId,
    required String blogId,
  }) {
    return BlogHistoryTarget._(_normalizeId(ownerUserId), _normalizeId(blogId));
  }

  const BlogHistoryTarget._(this.ownerUserId, this.blogId);

  final String ownerUserId;
  final String blogId;

  String get encodedId => '$ownerUserId:$blogId';

  HistoryTargetKey get key =>
      HistoryTargetKey(type: HistoryTargetType.blog, id: encodedId);

  static BlogHistoryTarget? tryParse(String value) {
    final parts = value.split(':');
    if (parts.length != 2) {
      return null;
    }
    try {
      return BlogHistoryTarget(ownerUserId: parts[0], blogId: parts[1]);
    } on FormatException {
      return null;
    }
  }

  static String _normalizeId(String value) {
    final normalized = value.trim();
    if (!RegExp(r'^\d+$').hasMatch(normalized)) {
      throw const FormatException('Invalid blog history identity');
    }
    final parsed = BigInt.tryParse(normalized);
    if (parsed == null || parsed <= BigInt.zero) {
      throw const FormatException('Invalid blog history identity');
    }
    return parsed.toString();
  }
}
