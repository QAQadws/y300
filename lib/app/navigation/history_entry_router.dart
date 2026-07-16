import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/presentation/comic_detail_page.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/presentation/forum_shell_mode_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_page.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/presentation/novel_detail_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

typedef HistoryForumModeLoader = Future<ForumShellMode> Function();
typedef HistoryWorkAvailabilityLoader = Future<bool> Function(String workId);
typedef HistoryNativeThreadPageBuilder =
    Widget Function(String tid, String subject, int? initialPage);
typedef HistoryWorkPageBuilder = Widget Function(String workId);
typedef HistoryWebViewPageBuilder = Widget Function(Uri initialUri);

final historyEntryRouterProvider = Provider<HistoryEntryRouter>((ref) {
  return HistoryEntryRouter(
    loadForumMode: () async {
      final current = ref.read(forumShellModeControllerProvider).value;
      return current ??
          await ref.read(forumModeSettingsRepositoryProvider).loadMode();
    },
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
    required HistoryForumModeLoader loadForumMode,
    required HistoryWorkAvailabilityLoader comicWorkExists,
    required HistoryWorkAvailabilityLoader novelWorkExists,
    HistoryNativeThreadPageBuilder nativeThreadPageBuilder =
        _buildNativeThreadPage,
    HistoryWorkPageBuilder comicPageBuilder = _buildComicPage,
    HistoryWorkPageBuilder novelPageBuilder = _buildNovelPage,
    HistoryWebViewPageBuilder webViewPageBuilder = _buildWebViewPage,
  }) : _loadForumMode = loadForumMode,
       _comicWorkExists = comicWorkExists,
       _novelWorkExists = novelWorkExists,
       _nativeThreadPageBuilder = nativeThreadPageBuilder,
       _comicPageBuilder = comicPageBuilder,
       _novelPageBuilder = novelPageBuilder,
       _webViewPageBuilder = webViewPageBuilder;

  final HistoryForumModeLoader _loadForumMode;
  final HistoryWorkAvailabilityLoader _comicWorkExists;
  final HistoryWorkAvailabilityLoader _novelWorkExists;
  final HistoryNativeThreadPageBuilder _nativeThreadPageBuilder;
  final HistoryWorkPageBuilder _comicPageBuilder;
  final HistoryWorkPageBuilder _novelPageBuilder;
  final HistoryWebViewPageBuilder _webViewPageBuilder;

  Future<HistoryOpenResult> open(
    BuildContext context,
    HistoryEntry entry,
  ) async {
    try {
      final page = switch (entry.target.type) {
        HistoryTargetType.thread => await _buildThreadDestination(entry),
        HistoryTargetType.comic => await _buildWorkDestination(
          entry,
          label: '漫画',
          exists: _comicWorkExists,
          builder: _comicPageBuilder,
        ),
        HistoryTargetType.novel => await _buildWorkDestination(
          entry,
          label: '小说',
          exists: _novelWorkExists,
          builder: _novelPageBuilder,
        ),
      };
      if (page case HistoryOpenUnavailable()) {
        return page;
      }
      if (page is! Widget) {
        return const HistoryOpenUnavailable(message: '记录目标无效');
      }
      if (!context.mounted) {
        return const HistoryOpenUnavailable(message: '当前页面已关闭');
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
      return const HistoryOpenUnavailable(message: '帖子记录已失效');
    }
    final mode = await _loadForumMode();
    if (mode == ForumShellMode.native) {
      return _nativeThreadPageBuilder(
        tid,
        entry.title,
        _normalizedPage(entry.lastPage),
      );
    }
    return _webViewPageBuilder(_threadUri(tid, entry.lastPage));
  }

  Future<Object> _buildWorkDestination(
    HistoryEntry entry, {
    required String label,
    required HistoryWorkAvailabilityLoader exists,
    required HistoryWorkPageBuilder builder,
  }) async {
    final workId = entry.target.id.trim();
    final fallbackTid = _normalizeTid(entry.sourceTid);
    if (workId.isEmpty) {
      return HistoryOpenUnavailable(
        message: '$label记录已失效',
        fallbackTid: fallbackTid,
      );
    }
    if (!await exists(workId)) {
      return HistoryOpenUnavailable(
        message: '$label作品已从本地移除',
        fallbackTid: fallbackTid,
      );
    }
    return builder(workId);
  }

  Uri _threadUri(String tid, int? page) {
    final base = Uri.parse(AppConfig.siteBaseUrl);
    return base.replace(
      path: '/forum.php',
      queryParameters: <String, String>{
        'mod': 'viewthread',
        'tid': tid,
        if (_normalizedPage(page) case final value?) 'page': '$value',
        'mobile': '2',
      },
      fragment: '',
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

Widget _buildComicPage(String workId) => ComicDetailPage(comicId: workId);

Widget _buildNovelPage(String workId) => NovelDetailPage(novelId: workId);

Widget _buildWebViewPage(Uri initialUri) {
  return ProviderScope(
    overrides: [
      forumWebViewInitialUriProvider.overrideWithValue(initialUri),
      forumWebViewPopOnRootBackProvider.overrideWithValue(true),
      forumWebViewDriverProvider.overrideWith((ref) {
        return ref.watch(forumWebViewDriverFactoryProvider).call();
      }),
      forumWebViewControllerProvider.overrideWith(ForumWebViewController.new),
    ],
    child: const ForumWebViewPage(),
  );
}
