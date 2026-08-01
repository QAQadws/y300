import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as inapp;
import 'package:y300/features/forum/domain/models/forum_webview_runtime_models.dart';
import 'package:y300/features/forum/domain/models/forum_webview_resource_diagnostic_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_resource_classifier.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver_contract.dart';
import 'package:y300/features/forum/presentation/webview/runtime/forum_webview_platform_configurator.dart';

class InAppForumWebViewDriver implements ForumWebViewDriver {
  InAppForumWebViewDriver({
    required ForumWebViewPlatformConfigurator platformConfigurator,
    required ForumWebViewResourceClassifier resourceClassifier,
  }) : _platformConfigurator = platformConfigurator,
       _resourceClassifier = resourceClassifier,
       _cookieManager = inapp.CookieManager.instance();

  final ForumWebViewPlatformConfigurator _platformConfigurator;
  final ForumWebViewResourceClassifier _resourceClassifier;
  final inapp.CookieManager _cookieManager;
  final Completer<inapp.InAppWebViewController> _controllerCompleter =
      Completer<inapp.InAppWebViewController>();
  inapp.InAppWebViewController? _controller;
  ForumWebViewCallbacks? _callbacks;
  ForumWebViewBootstrapConfig? _bootstrapConfig;

  @override
  Widget buildWidget({Key? key}) {
    final bootstrapConfig = _bootstrapConfig;
    final initialSettings = bootstrapConfig != null
        ? _buildSettings(bootstrapConfig)
        : inapp.InAppWebViewSettings(
            javaScriptEnabled: true,
            useShouldOverrideUrlLoading: true,
            transparentBackground: true,
          );
    return inapp.InAppWebView(
      key: key,
      initialSettings: initialSettings,
      initialUserScripts: _buildInitialUserScripts(bootstrapConfig),
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
      onPageCommitVisible: (controller, url) {
        final onPageCommitVisible = _callbacks?.onPageCommitVisible;
        if (onPageCommitVisible == null || url == null) {
          return;
        }
        onPageCommitVisible(url.toString());
      },
      onLoadResource: (controller, resource) {
        final resourceUrl = resource.url;
        if (resourceUrl == null) {
          return;
        }
        _emitResourceDiagnostic(
          uri: _resolveUri(resourceUrl.toString()),
          isMainFrame: false,
        );
      },
      onReceivedError: (controller, request, error) {
        _emitResourceDiagnostic(
          uri: _resolveUri(request.url.toString()),
          isMainFrame: request.isForMainFrame ?? false,
          errorDescription: error.description,
        );
      },
      onReceivedHttpError: (controller, request, response) {
        _emitResourceDiagnostic(
          uri: _resolveUri(request.url.toString()),
          isMainFrame: request.isForMainFrame ?? false,
          statusCode: response.statusCode,
          errorDescription: response.reasonPhrase,
        );
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
    return ForumWebViewCapabilityProfile(
      engine: ForumWebViewEngine.advanced,
      documentStartMode: _resolveDocumentStartMode(),
      supportsContentBlockers: false,
      supportsTransparentBackground: true,
      supportsPlatformScrollTuning: true,
      supportsCookieHooks: true,
      supportsPageCommitVisible: true,
    );
  }

  @override
  Future<void> initialize({
    required ForumWebViewCallbacks callbacks,
    required ForumWebViewBootstrapConfig bootstrapConfig,
  }) async {
    _callbacks = callbacks;
    _bootstrapConfig = bootstrapConfig;
  }

  @override
  Future<void> load(Uri uri, {Map<String, String> headers = const {}}) async {
    final controller = await _requireController();
    await controller.loadUrl(
      urlRequest: inapp.URLRequest(
        url: inapp.WebUri(uri.toString()),
        headers: headers.isEmpty ? null : headers,
      ),
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
    final cookieUri = Uri(scheme: 'https', host: domain, path: path);
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

  inapp.InAppWebViewSettings _buildSettings(
    ForumWebViewBootstrapConfig bootstrapConfig,
  ) {
    final settings = _platformConfigurator.buildSettings(
      bootstrapConfig: bootstrapConfig,
    );
    final customUserAgent = bootstrapConfig.networkPolicy.customUserAgent;
    if (customUserAgent != null && customUserAgent.trim().isNotEmpty) {
      settings.userAgent = customUserAgent;
    }
    if (_callbacks?.onResourceDiagnostic != null) {
      settings.useOnLoadResource = true;
    }
    return settings;
  }

  ForumWebViewDocumentStartMode _resolveDocumentStartMode() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return ForumWebViewDocumentStartMode.reliable;
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return ForumWebViewDocumentStartMode.bestEffort;
    }
  }

  UnmodifiableListView<inapp.UserScript>? _buildInitialUserScripts(
    ForumWebViewBootstrapConfig? bootstrapConfig,
  ) {
    final initialUserScripts = bootstrapConfig?.initialUserScripts;
    if (initialUserScripts == null || initialUserScripts.isEmpty) {
      return null;
    }
    return UnmodifiableListView<inapp.UserScript>(
      initialUserScripts.map(_mapInitialUserScript),
    );
  }

  inapp.UserScript _mapInitialUserScript(ForumWebViewInitialUserScript script) {
    return inapp.UserScript(
      source: script.source,
      injectionTime: switch (script.injectionTime) {
        ForumWebViewInitialUserScriptInjectionTime.documentStart =>
          inapp.UserScriptInjectionTime.AT_DOCUMENT_START,
        ForumWebViewInitialUserScriptInjectionTime.documentEnd =>
          inapp.UserScriptInjectionTime.AT_DOCUMENT_END,
      },
      forMainFrameOnly: script.forMainFrameOnly,
    );
  }

  void _emitResourceDiagnostic({
    required Uri uri,
    required bool isMainFrame,
    int? statusCode,
    String? errorDescription,
  }) {
    final onResourceDiagnostic = _callbacks?.onResourceDiagnostic;
    if (onResourceDiagnostic == null) {
      return;
    }
    onResourceDiagnostic(
      ForumWebViewResourceDiagnosticEvent(
        uri: uri,
        kind: _resourceClassifier.classify(uri),
        statusCode: statusCode,
        errorDescription: errorDescription,
        isMainFrame: isMainFrame,
      ),
    );
  }

  Uri _resolveUri(String rawUrl) {
    return Uri.tryParse(rawUrl) ?? Uri();
  }
}
