import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/forum/domain/models/forum_webview_resource_diagnostic_models.dart';

final forumWebViewResourceClassifierProvider =
    Provider<ForumWebViewResourceClassifier>((ref) {
      return const DefaultForumWebViewResourceClassifier();
    });

abstract class ForumWebViewResourceClassifier {
  ForumWebViewResourceKind classify(Uri uri);
}

class DefaultForumWebViewResourceClassifier
    implements ForumWebViewResourceClassifier {
  const DefaultForumWebViewResourceClassifier();

  static final Uri _siteRootUri = Uri.parse(AppConfig.siteBaseUrl);

  @override
  ForumWebViewResourceKind classify(Uri uri) {
    if (!uri.hasScheme || uri.host != _siteRootUri.host) {
      return ForumWebViewResourceKind.other;
    }

    final path = uri.path.toLowerCase();
    final mod = uri.queryParameters['mod']?.toLowerCase();
    if (path.contains('/static/image/smiley/')) {
      return ForumWebViewResourceKind.smiley;
    }
    if (path.contains('/data/attachment/') || mod == 'attachment') {
      return ForumWebViewResourceKind.attachment;
    }
    if (path.startsWith('/static/')) {
      return ForumWebViewResourceKind.staticAsset;
    }
    return ForumWebViewResourceKind.other;
  }
}
