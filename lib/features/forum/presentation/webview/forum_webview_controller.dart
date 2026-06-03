import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_state.dart';
import 'package:y300/features/tags/data/tag_providers.dart';

final forumWebViewControllerProvider =
    AsyncNotifierProvider.autoDispose<ForumWebViewController, ForumWebViewState>(
      ForumWebViewController.new,
    );

class ForumWebViewController extends AsyncNotifier<ForumWebViewState> {
  ForumWebViewNavigator get _navigator => ref.read(forumWebViewNavigatorProvider);

  @override
  FutureOr<ForumWebViewState> build() {
    return _initialState();
  }

  ForumWebViewState _initialState() {
    final homeUri = _navigator.homeUri;
    return ForumWebViewState(
      currentUri: homeUri,
      pageKind: _navigator.classify(homeUri),
      fid: null,
      tid: null,
      boardName: null,
      pageTitle: null,
      canGoBack: false,
      isLoading: true,
      loadingProgress: 0,
    );
  }

  ForumWebViewState get _currentState => state.value ?? _initialState();

  void onPageStarted(String rawUrl) {
    final uri = _navigator.resolve(rawUrl);
    final current = _currentState;
    final pageKind = _navigator.classify(uri);
    final fid = _resolveFidForStartedPage(
      pageKind: pageKind,
      uri: uri,
      previousFid: current.fid,
    );
    final tid = _navigator.extractTid(uri);
    state = AsyncData(
      current.copyWith(
        currentUri: uri,
        pageKind: pageKind,
        fid: fid,
        clearFid: fid == null,
        tid: tid,
        clearTid: tid == null,
        clearBoardName: true,
        clearPageTitle: true,
        isLoading: true,
        loadingProgress: 0,
      ),
    );
  }

  Future<void> onPageFinished({
    required String rawUrl,
    required String? pageTitle,
    required bool canGoBack,
  }) async {
    final uri = _navigator.resolve(rawUrl);
    final current = _currentState;
    final pageKind = _navigator.classify(uri);
    final fid = _resolveFidForFinishedPage(
      pageKind: pageKind,
      uri: uri,
      currentFid: current.fid,
    );
    final tid = _navigator.extractTid(uri);
    final normalizedTitle = _normalizeText(pageTitle);
    final boardName = await _resolveBoardName(
      pageKind: pageKind,
      fid: fid,
      pageTitle: normalizedTitle,
    );
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        currentUri: uri,
        pageKind: pageKind,
        fid: fid,
        clearFid: fid == null,
        tid: tid,
        clearTid: tid == null,
        boardName: boardName,
        clearBoardName: boardName == null,
        pageTitle: pageKind == ForumWebViewPageKind.home ? null : normalizedTitle,
        clearPageTitle:
            pageKind == ForumWebViewPageKind.home || normalizedTitle == null,
        canGoBack: canGoBack,
        isLoading: false,
        loadingProgress: 100,
      ),
    );
  }

  void onProgress(int progress) {
    final normalized = progress.clamp(0, 100).toInt();
    final current = _currentState;
    state = AsyncData(
      current.copyWith(
        loadingProgress: normalized,
        isLoading: normalized < 100 || current.isLoading,
      ),
    );
  }

  String? _resolveFidForStartedPage({
    required ForumWebViewPageKind pageKind,
    required Uri uri,
    required String? previousFid,
  }) {
    final extracted = _navigator.extractFid(uri);
    if (pageKind == ForumWebViewPageKind.threadDetail) {
      return extracted ?? previousFid;
    }
    return extracted;
  }

  String? _resolveFidForFinishedPage({
    required ForumWebViewPageKind pageKind,
    required Uri uri,
    required String? currentFid,
  }) {
    final extracted = _navigator.extractFid(uri);
    if (pageKind == ForumWebViewPageKind.threadDetail) {
      return extracted ?? currentFid;
    }
    return extracted;
  }

  Future<String?> _resolveBoardName({
    required ForumWebViewPageKind pageKind,
    required String? fid,
    required String? pageTitle,
  }) async {
    if (pageKind == ForumWebViewPageKind.home) {
      return null;
    }

    if (fid != null) {
      try {
        final lookup = await ref.read(forumTagLookupProvider.future);
        final boardName = _normalizeText(lookup.findBoard(fid: fid)?.name);
        if (boardName != null) {
          return boardName;
        }
      } catch (_) {
        // 标签加载失败时降级到页面标题/基础文案，不阻断 WebView 主流程。
      }
    }

    if (pageTitle != null) {
      return pageTitle;
    }
    if (fid != null) {
      return 'fid=$fid';
    }
    return switch (pageKind) {
      ForumWebViewPageKind.forumDisplay => '帖子列表',
      ForumWebViewPageKind.threadDetail => '帖子详情',
      ForumWebViewPageKind.search => '搜索',
      ForumWebViewPageKind.other => '百合会论坛',
      ForumWebViewPageKind.home => null,
    };
  }

  String? _normalizeText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
