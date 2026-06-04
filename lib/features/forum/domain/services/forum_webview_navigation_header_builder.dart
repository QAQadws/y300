import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/forum/domain/models/forum_webview_network_policy_models.dart';

final forumWebViewNavigationHeaderBuilderProvider =
    Provider<ForumWebViewNavigationHeaderBuilder>((ref) {
      return DefaultForumWebViewNavigationHeaderBuilder();
    });

abstract class ForumWebViewNavigationHeaderBuilder {
  Map<String, String> build({
    required Uri targetUri,
    Uri? referrerUri,
    required ForumWebViewNetworkPolicy policy,
  });
}

class DefaultForumWebViewNavigationHeaderBuilder
    implements ForumWebViewNavigationHeaderBuilder {
  DefaultForumWebViewNavigationHeaderBuilder({
    Locale? Function()? localeReader,
  }) : _localeReader = localeReader ?? (() => PlatformDispatcher.instance.locale);

  static const String _fallbackAcceptLanguage = 'zh-CN,zh;q=0.9,en;q=0.8';
  static final Uri _siteRootUri = Uri.parse('${AppConfig.siteBaseUrl}/');

  final Locale? Function() _localeReader;

  @override
  Map<String, String> build({
    required Uri targetUri,
    Uri? referrerUri,
    required ForumWebViewNetworkPolicy policy,
  }) {
    final headers = Map<String, String>.from(policy.extraHeaders);
    _removeHeaderCaseInsensitive(headers, 'cookie');
    _removeHeaderCaseInsensitive(headers, 'user-agent');
    final explicitAcceptLanguage = _removeHeaderCaseInsensitive(
      headers,
      'accept-language',
    );
    _removeHeaderCaseInsensitive(headers, 'referer');

    if (policy.preferAppLocale) {
      headers['Accept-Language'] =
          _buildAcceptLanguage(_localeReader()) ??
          explicitAcceptLanguage ??
          _fallbackAcceptLanguage;
    } else if (explicitAcceptLanguage != null &&
        explicitAcceptLanguage.trim().isNotEmpty) {
      headers['Accept-Language'] = explicitAcceptLanguage;
    }

    headers['Referer'] = _buildReferer(targetUri: targetUri, referrerUri: referrerUri);
    return headers;
  }

  String _buildReferer({
    required Uri targetUri,
    Uri? referrerUri,
  }) {
    if (referrerUri != null &&
        referrerUri.hasScheme &&
        referrerUri.host == targetUri.host) {
      return referrerUri.toString();
    }
    return _siteRootUri.toString();
  }

  String? _buildAcceptLanguage(Locale? locale) {
    final languageCode = locale?.languageCode.trim();
    if (languageCode == null || languageCode.isEmpty) {
      return null;
    }

    final countryCode = locale?.countryCode?.trim();
    if (countryCode != null && countryCode.isNotEmpty) {
      return '$languageCode-$countryCode,$languageCode;q=0.9,en;q=0.8';
    }
    return '$languageCode,en;q=0.8';
  }

  String? _removeHeaderCaseInsensitive(
    Map<String, String> headers,
    String name,
  ) {
    String? value;
    final matchingKeys = headers.keys
        .where((key) => key.toLowerCase() == name.toLowerCase())
        .toList(growable: false);
    for (final key in matchingKeys) {
      value ??= headers[key];
      headers.remove(key);
    }
    return value;
  }
}
