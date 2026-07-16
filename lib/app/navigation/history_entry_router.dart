import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/comic/presentation/comic_detail_page.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/presentation/forum_shell_mode_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_page.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/novel/presentation/novel_detail_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

typedef HistoryForumModeLoader = Future<ForumShellMode> Function();
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
  );
});

class HistoryEntryRouter {
  const HistoryEntryRouter({
    required HistoryForumModeLoader loadForumMode,
    HistoryNativeThreadPageBuilder nativeThreadPageBuilder =
        _buildNativeThreadPage,
    HistoryWorkPageBuilder comicPageBuilder = _buildComicPage,
    HistoryWorkPageBuilder novelPageBuilder = _buildNovelPage,
    HistoryWebViewPageBuilder webViewPageBuilder = _buildWebViewPage,
  }) : _loadForumMode = loadForumMode,
       _nativeThreadPageBuilder = nativeThreadPageBuilder,
       _comicPageBuilder = comicPageBuilder,
       _novelPageBuilder = novelPageBuilder,
       _webViewPageBuilder = webViewPageBuilder;

  final HistoryForumModeLoader _loadForumMode;
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
        HistoryTargetType.comic => _buildWorkDestination(
          entry,
          label: '漫画',
          builder: _comicPageBuilder,
        ),
        HistoryTargetType.novel => _buildWorkDestination(
          entry,
          label: '小说',
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
    final tid = entry.target.id.trim();
    if (!RegExp(r'^[1-9]\d*$').hasMatch(tid)) {
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

  Object _buildWorkDestination(
    HistoryEntry entry, {
    required String label,
    required HistoryWorkPageBuilder builder,
  }) {
    final workId = entry.target.id.trim();
    if (workId.isEmpty) {
      return HistoryOpenUnavailable(
        message: '$label记录已失效',
        fallbackTid: entry.sourceTid,
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
