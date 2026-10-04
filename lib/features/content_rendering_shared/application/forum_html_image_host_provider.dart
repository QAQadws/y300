import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/content_rendering_shared/application/host/cache_forum_html_image_host.dart';
import 'package:y300/features/content_rendering_shared/presentation/contracts/forum_html_image_host.dart';

final forumHtmlImageHostProvider = Provider<ForumHtmlImageHost>((ref) {
  return CacheForumHtmlImageHost(
    dimensionIndex: ref.watch(forumImageDimensionIndexProvider),
  );
});
