import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/services/forum_webview_script_injector.dart';
import 'package:y300/features/forum/domain/services/forum_webview_thread_menu_bridge.dart';
import 'package:webview_flutter/webview_flutter.dart' as webview;

final forumWebViewDriverProvider = Provider.autoDispose<ForumWebViewDriver>((
  ref,
) {
  return FlutterForumWebViewDriver();
});

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
  });

  final void Function(String url) onPageStarted;
  final Future<void> Function(String url) onPageFinished;
  final void Function(int progress) onProgress;
  final FutureOr<ForumWebViewNavigationDecision> Function(String url)
      onNavigationRequest;
}

abstract class ForumWebViewDriver
    implements ForumWebViewScriptTarget, ForumWebViewThreadMenuTarget {
  Future<void> initialize({required ForumWebViewCallbacks callbacks});

  Widget buildWidget({Key? key});

  Future<void> load(Uri uri);

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

class FlutterForumWebViewDriver implements ForumWebViewDriver {
  FlutterForumWebViewDriver()
      : _controller = webview.WebViewController(),
        _cookieManager = webview.WebViewCookieManager();

  final webview.WebViewController _controller;
  final webview.WebViewCookieManager _cookieManager;

  @override
  Widget buildWidget({Key? key}) {
    return webview.WebViewWidget(
      key: key,
      controller: _controller,
    );
  }

  @override
  Future<void> initialize({required ForumWebViewCallbacks callbacks}) async {
    await _controller.setJavaScriptMode(webview.JavaScriptMode.unrestricted);
    await _controller.setNavigationDelegate(
      webview.NavigationDelegate(
        onProgress: callbacks.onProgress,
        onPageStarted: callbacks.onPageStarted,
        onPageFinished: (url) {
          unawaited(callbacks.onPageFinished(url));
        },
        onNavigationRequest: (request) async {
          final decision = await callbacks.onNavigationRequest(request.url);
          return switch (decision) {
            ForumWebViewNavigationDecision.navigate =>
              webview.NavigationDecision.navigate,
            ForumWebViewNavigationDecision.prevent =>
              webview.NavigationDecision.prevent,
          };
        },
      ),
    );
  }

  @override
  Future<void> load(Uri uri) {
    return _controller.loadRequest(uri);
  }

  @override
  Future<String?> getTitle() {
    return _controller.getTitle();
  }

  @override
  Future<bool> canGoBack() {
    return _controller.canGoBack();
  }

  @override
  Future<void> goBack() {
    return _controller.goBack();
  }

  @override
  Future<void> runJavaScript(String script) {
    return _controller.runJavaScript(script);
  }

  @override
  Future<Object?> runJavaScriptReturningResult(String script) {
    return _controller.runJavaScriptReturningResult(script);
  }

  @override
  Future<void> seedCookies({
    required String domain,
    required Map<String, String> cookies,
    String path = '/',
  }) async {
    for (final entry in cookies.entries) {
      await _cookieManager.setCookie(
        webview.WebViewCookie(
          name: entry.key,
          value: entry.value,
          domain: domain,
          path: path,
        ),
      );
    }
  }
}
