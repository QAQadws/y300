import 'dart:async';

import 'package:flutter/material.dart';
import 'package:y300/features/forum/domain/models/forum_webview_runtime_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_script_injector.dart';
import 'package:y300/features/forum/domain/services/forum_webview_thread_menu_bridge.dart';

typedef ForumWebViewDriverFactory = ForumWebViewDriver Function();

enum ForumWebViewNavigationDecision {
  navigate,
  prevent,
}

class ForumWebViewCallbacks {
  const ForumWebViewCallbacks({
    required this.onPageStarted,
    required this.onPageFinished,
    required this.onProgress,
    required this.onNavigationRequest,
    this.onPageCommitVisible,
  });

  final void Function(String url) onPageStarted;
  final Future<void> Function(String url) onPageFinished;
  final void Function(int progress) onProgress;
  final void Function(String url)? onPageCommitVisible;
  final FutureOr<ForumWebViewNavigationDecision> Function(String url)
      onNavigationRequest;
}

abstract class ForumWebViewDriver
    implements ForumWebViewScriptTarget, ForumWebViewThreadMenuTarget {
  Future<ForumWebViewCapabilityProfile> probeCapabilities();

  Future<void> initialize({
    required ForumWebViewCallbacks callbacks,
    required ForumWebViewBootstrapConfig bootstrapConfig,
  });

  Widget buildWidget({Key? key});

  Future<void> load(Uri uri);

  Future<void> reload();

  Future<bool> clearCookies();

  Future<String?> getTitle();

  Future<bool> canGoBack();

  Future<void> goBack();

  @override
  Future<Object?> runJavaScriptReturningResult(String script);

  Future<void> seedCookies({
    required String domain,
    required Map<String, String> cookies,
    String path,
  });
}
