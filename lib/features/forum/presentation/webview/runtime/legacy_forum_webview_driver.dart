import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart' as webview;
import 'package:y300/features/forum/domain/models/forum_webview_runtime_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver_contract.dart';

class LegacyForumWebViewDriver implements ForumWebViewDriver {
  LegacyForumWebViewDriver()
    : _controller = webview.WebViewController(),
      _cookieManager = webview.WebViewCookieManager();

  final webview.WebViewController _controller;
  final webview.WebViewCookieManager _cookieManager;

  static const ForumWebViewCapabilityProfile _capabilityProfile =
      ForumWebViewCapabilityProfile(
        engine: ForumWebViewEngine.legacy,
        documentStartMode: ForumWebViewDocumentStartMode.unavailable,
        supportsContentBlockers: false,
        supportsTransparentBackground: false,
        supportsPlatformScrollTuning: false,
        supportsCookieHooks: false,
        supportsPageCommitVisible: false,
      );

  @override
  Widget buildWidget({Key? key}) {
    return webview.WebViewWidget(key: key, controller: _controller);
  }

  @override
  Future<ForumWebViewCapabilityProfile> probeCapabilities() async {
    return _capabilityProfile;
  }

  @override
  Future<void> initialize({
    required ForumWebViewCallbacks callbacks,
    required ForumWebViewBootstrapConfig bootstrapConfig,
  }) async {
    await _controller.setJavaScriptMode(webview.JavaScriptMode.unrestricted);
    final customUserAgent = bootstrapConfig.networkPolicy.customUserAgent;
    if (customUserAgent != null && customUserAgent.trim().isNotEmpty) {
      await _controller.setUserAgent(customUserAgent);
    }
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
  Future<void> load(Uri uri, {Map<String, String> headers = const {}}) {
    return _controller.loadRequest(uri, headers: headers);
  }

  @override
  Future<void> reload() {
    return _controller.reload();
  }

  @override
  Future<bool> clearCookies() {
    return _cookieManager.clearCookies();
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
