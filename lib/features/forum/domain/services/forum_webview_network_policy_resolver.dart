import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/models/forum_webview_network_policy_models.dart';

final forumWebViewNetworkPolicyResolverProvider =
    Provider<ForumWebViewNetworkPolicyResolver>((ref) {
      return const DefaultForumWebViewNetworkPolicyResolver();
    });

abstract class ForumWebViewNetworkPolicyResolver {
  ForumWebViewNetworkPolicy resolve(Uri uri);
}

class DefaultForumWebViewNetworkPolicyResolver
    implements ForumWebViewNetworkPolicyResolver {
  const DefaultForumWebViewNetworkPolicyResolver();

  static const ForumWebViewNetworkPolicy _defaultPolicy =
      ForumWebViewNetworkPolicy(
        customUserAgent: null,
        extraHeaders: <String, String>{},
        preferAppLocale: true,
      );

  @override
  ForumWebViewNetworkPolicy resolve(Uri uri) {
    return _defaultPolicy;
  }
}
