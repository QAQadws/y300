import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ThreadContentKind {
  unknown,
  comic,
  novel,
  forum,
}

class ThreadContentClassifier {
  const ThreadContentClassifier();

  static const Map<String, String> announcementTypeIds = <String, String>{
    '30': '65',
    '49': '121',
    '55': '147',
  };

  ThreadContentKind classify({
    required String fid,
    required String typeid,
    String? tagName,
  }) {
    final normalizedFid = fid.trim();
    final normalizedTypeid = typeid.trim();
    final normalizedTag = tagName?.trim();
    if (normalizedFid.isEmpty) {
      return ThreadContentKind.unknown;
    }
    final isAnnouncement = normalizedTag == '公告' ||
        announcementTypeIds[normalizedFid] == normalizedTypeid;

    if (normalizedFid == '30' && !isAnnouncement) {
      return ThreadContentKind.comic;
    }
    if ((normalizedFid == '49' || normalizedFid == '55') && !isAnnouncement) {
      return ThreadContentKind.novel;
    }
    return ThreadContentKind.forum;
  }
}

final threadContentClassifierProvider = Provider<ThreadContentClassifier>((ref) {
  return const ThreadContentClassifier();
});
