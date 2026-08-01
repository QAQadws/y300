import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

final forumWebViewExternalLauncherProvider =
    Provider<ForumWebViewExternalLauncher>((ref) {
      return UrlLauncherForumWebViewExternalLauncher();
    });

abstract class ForumWebViewExternalLauncher {
  Future<bool> launch(Uri uri);
}

class UrlLauncherForumWebViewExternalLauncher
    implements ForumWebViewExternalLauncher {
  @override
  Future<bool> launch(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
