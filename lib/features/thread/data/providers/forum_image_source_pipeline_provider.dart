import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/config/app_config.dart';

final forumImageSourcePipelineProvider = Provider<ForumImageSourcePipeline>((
  ref,
) {
  return const DefaultForumImageSourcePipeline(
    siteBaseUrl: AppConfig.siteBaseUrl,
  );
});
