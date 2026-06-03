import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_state.dart';

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
      isLoading: true,
      loadingProgress: 0,
    );
  }

  ForumWebViewState get _currentState => state.value ?? _initialState();

  void onPageStarted(String rawUrl) {
    final uri = _navigator.resolve(rawUrl);
    state = AsyncData(
      _currentState.copyWith(
        currentUri: uri,
        pageKind: _navigator.classify(uri),
        isLoading: true,
        loadingProgress: 0,
      ),
    );
  }

  void onPageFinished(String rawUrl) {
    final uri = _navigator.resolve(rawUrl);
    state = AsyncData(
      _currentState.copyWith(
        currentUri: uri,
        pageKind: _navigator.classify(uri),
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
}
