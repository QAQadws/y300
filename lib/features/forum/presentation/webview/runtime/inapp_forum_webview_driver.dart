import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as inapp;
import 'package:y300/features/forum/domain/models/forum_webview_runtime_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver_contract.dart';

class InAppForumWebViewDriver implements ForumWebViewDriver {
  InAppForumWebViewDriver() : _cookieManager = inapp.CookieManager.instance();

  final inapp.CookieManager _cookieManager;
  final Completer<inapp.InAppWebViewController> _controllerCompleter =
      Completer<inapp.InAppWebViewController>();
  inapp.InAppWebViewController? _controller;
  ForumWebViewCallbacks? _callbacks;

  static const ForumWebViewCapabilityProfile _capabilityProfile =
      ForumWebViewCapabilityProfile(
        engine: ForumWebViewEngine.advanced,
        documentStartMode: ForumWebViewDocumentStartMode.bestEffort,
        supportsContentBlockers: false,
        supportsTransparentBackground: true,
        supportsPlatformScrollTuning: true,
        supportsCookieHooks: true,
      );

  @override
  Widget buildWidget({Key? key}) {
    return inapp.InAppWebView(
      key: key,
      initialSettings: inapp.InAppWebViewSettings(
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        transparentBackground: true,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        if (!_controllerCompleter.isCompleted) {
          _controllerCompleter.complete(controller);
        }
      },
      onLoadStart: (controller, url) {
        final callbacks = _callbacks;
        if (callbacks == null || url == null) {
          return;
        }
        callbacks.onPageStarted(url.toString());
      },
      onLoadStop: (controller, url) async {
        final callbacks = _callbacks;
        if (callbacks == null || url == null) {
          return;
        }
        await callbacks.onPageFinished(url.toString());
      },
      onProgressChanged: (controller, progress) {
        _callbacks?.onProgress(progress);
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final callbacks = _callbacks;
        final url = navigationAction.request.url;
        if (callbacks == null || url == null) {
          return inapp.NavigationActionPolicy.ALLOW;
        }
        final decision = await callbacks.onNavigationRequest(url.toString());
        return switch (decision) {
          ForumWebViewNavigationDecision.navigate =>
            inapp.NavigationActionPolicy.ALLOW,
          ForumWebViewNavigationDecision.prevent =>
            inapp.NavigationActionPolicy.CANCEL,
        };
      },
    );
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
    _callbacks = callbacks;
  }

  @override
  Future<void> load(Uri uri) async {
    final controller = await _requireController();
    await controller.loadUrl(
      urlRequest: inapp.URLRequest(url: inapp.WebUri(uri.toString())),
    );
  }

  @override
  Future<void> reload() async {
    final controller = await _requireController();
    await controller.reload();
  }

  @override
  Future<bool> clearCookies() {
    return _cookieManager.deleteAllCookies();
  }

  @override
  Future<String?> getTitle() async {
    final controller = await _requireController();
    return controller.getTitle();
  }

  @override
  Future<bool> canGoBack() async {
    final controller = await _requireController();
    return controller.canGoBack();
  }

  @override
  Future<void> goBack() async {
    final controller = await _requireController();
    await controller.goBack();
  }

  @override
  Future<void> runJavaScript(String script) async {
    final controller = await _requireController();
    await controller.evaluateJavascript(source: script);
  }

  @override
  Future<Object?> runJavaScriptReturningResult(String script) async {
    final controller = await _requireController();
    return controller.evaluateJavascript(source: script);
  }

  @override
  Future<void> seedCookies({
    required String domain,
    required Map<String, String> cookies,
    String path = '/',
  }) async {
    final cookieUri = Uri(
      scheme: 'https',
      host: domain,
      path: path,
    );
    final webUri = inapp.WebUri(cookieUri.toString());
    for (final entry in cookies.entries) {
      await _cookieManager.setCookie(
        url: webUri,
        name: entry.key,
        value: entry.value,
        path: path,
      );
    }
  }

  Future<inapp.InAppWebViewController> _requireController() async {
    final controller = _controller;
    if (controller != null) {
      return controller;
    }
    return _controllerCompleter.future;
  }
}
