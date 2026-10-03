import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/presentation/comic_detail_page.dart';
import 'package:y300/features/history/domain/models/blog_history_target.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/presentation/novel_detail_page.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

typedef HistoryWorkAvailabilityLoader = Future<bool> Function(String workId);
typedef HistoryNativeThreadPageBuilder =
    Widget Function(String tid, String subject, int? initialPage);
typedef HistoryNativeBlogPageBuilder =
    Widget Function({
      required String ownerUserId,
      required String blogId,
      required String title,
    });
typedef HistoryWorkPageBuilder = Widget Function(String workId);

final historyEntryRouterProvider = Provider<HistoryEntryRouter>((ref) {
  return HistoryEntryRouter(
    comicWorkExists: (workId) async {
      final detail = await ref
          .read(comicRepositoryProvider)
          .getComicDetail(comicId: workId);
      return detail != null;
    },
    novelWorkExists: (workId) async {
      final detail = await ref
          .read(novelRepositoryProvider)
          .getDetail(novelId: workId);
      return detail != null;
    },
  );
});

class HistoryEntryRouter {
  const HistoryEntryRouter({
    required HistoryWorkAvailabilityLoader comicWorkExists,
    required HistoryWorkAvailabilityLoader novelWorkExists,
    HistoryNativeThreadPageBuilder nativeThreadPageBuilder =
        _buildNativeThreadPage,
    HistoryNativeBlogPageBuilder nativeBlogPageBuilder = _buildNativeBlogPage,
    HistoryWorkPageBuilder comicPageBuilder = _buildComicPage,
    HistoryWorkPageBuilder novelPageBuilder = _buildNovelPage,
  }) : _comicWorkExists = comicWorkExists,
       _novelWorkExists = novelWorkExists,
       _nativeThreadPageBuilder = nativeThreadPageBuilder,
       _nativeBlogPageBuilder = nativeBlogPageBuilder,
       _comicPageBuilder = comicPageBuilder,
       _novelPageBuilder = novelPageBuilder;

  final HistoryWorkAvailabilityLoader _comicWorkExists;
  final HistoryWorkAvailabilityLoader _novelWorkExists;
  final HistoryNativeThreadPageBuilder _nativeThreadPageBuilder;
  final HistoryNativeBlogPageBuilder _nativeBlogPageBuilder;
  final HistoryWorkPageBuilder _comicPageBuilder;
  final HistoryWorkPageBuilder _novelPageBuilder;

  Future<HistoryOpenResult> open(
    BuildContext context,
    HistoryEntry entry,
  ) async {
    try {
      final page = switch (entry.target.type) {
        HistoryTargetType.thread => await _buildThreadDestination(entry),
        HistoryTargetType.blog => _buildBlogDestination(entry),
        HistoryTargetType.comic => await _buildWorkDestination(
          entry,
          exists: _comicWorkExists,
          builder: _comicPageBuilder,
        ),
        HistoryTargetType.novel => await _buildWorkDestination(
          entry,
          exists: _novelWorkExists,
          builder: _novelPageBuilder,
        ),
      };
      if (page case HistoryOpenUnavailable()) {
        return page;
      }
      if (page is! Widget) {
        return const HistoryOpenUnavailable(
          code: HistoryOpenUnavailableCode.targetMissing,
        );
      }
      if (!context.mounted) {
        return const HistoryOpenUnavailable(
          code: HistoryOpenUnavailableCode.pageClosed,
        );
      }
      unawaited(
        Navigator.of(
          context,
        ).push<void>(MaterialPageRoute<void>(builder: (_) => page)),
      );
      return const HistoryOpenSuccess();
    } catch (error) {
      return HistoryOpenFailure(error: error);
    }
  }

  Future<Object> _buildThreadDestination(HistoryEntry entry) async {
    final tid = _normalizeTid(entry.target.id);
    if (tid == null) {
      return const HistoryOpenUnavailable(
        code: HistoryOpenUnavailableCode.threadExpired,
      );
    }
    return _nativeThreadPageBuilder(
      tid,
      entry.title,
      _normalizedPage(entry.lastPage),
    );
  }

  Future<Object> _buildWorkDestination(
    HistoryEntry entry, {
    required HistoryWorkAvailabilityLoader exists,
    required HistoryWorkPageBuilder builder,
  }) async {
    final workId = entry.target.id.trim();
    final fallbackTid = _normalizeTid(entry.sourceTid);
    if (workId.isEmpty) {
      return HistoryOpenUnavailable(
        code: HistoryOpenUnavailableCode.targetMissing,
        targetType: entry.target.type,
        fallbackTid: fallbackTid,
      );
    }
    if (!await exists(workId)) {
      return HistoryOpenUnavailable(
        code: HistoryOpenUnavailableCode.localWorkRemoved,
        targetType: entry.target.type,
        fallbackTid: fallbackTid,
      );
    }
    return builder(workId);
  }

  Object _buildBlogDestination(HistoryEntry entry) {
    final target = BlogHistoryTarget.tryParse(entry.target.id);
    if (target == null) {
      return const HistoryOpenUnavailable(
        code: HistoryOpenUnavailableCode.targetMissing,
        targetType: HistoryTargetType.blog,
      );
    }
    // Blog history always resumes at the article, not a stored comment page.
    return _nativeBlogPageBuilder(
      ownerUserId: target.ownerUserId,
      blogId: target.blogId,
      title: entry.title,
    );
  }

  int? _normalizedPage(int? value) => value != null && value > 0 ? value : null;

  String? _normalizeTid(String? value) {
    final normalized = value?.trim();
    if (normalized == null || !RegExp(r'^\d+$').hasMatch(normalized)) {
      return null;
    }
    final parsed = BigInt.tryParse(normalized);
    return parsed != null && parsed > BigInt.zero ? parsed.toString() : null;
  }
}

Widget _buildNativeThreadPage(String tid, String subject, int? initialPage) {
  return ThreadDetailPage(tid: tid, subject: subject, initialPage: initialPage);
}

Widget _buildNativeBlogPage({
  required String ownerUserId,
  required String blogId,
  required String title,
}) => ProfileBlogDetailPage(
  ownerUserId: ownerUserId,
  blogId: blogId,
  initialTitle: title,
);

Widget _buildComicPage(String workId) => ComicDetailPage(comicId: workId);

Widget _buildNovelPage(String workId) => NovelDetailPage(novelId: workId);
