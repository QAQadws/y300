import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/posting/domain/services/new_thread_poll_normalizer.dart';
import 'package:y300/features/posting/domain/services/new_thread_tags_normalizer.dart';
import 'package:y300/features/posting/domain/services/posting_draft_extras_codec.dart';
import 'package:y300/features/posting/domain/services/thread_creation_submission_mapper.dart';

final threadCreationPreparationProvider =
    Provider<ThreadCreationPreparationRepository>((ref) {
      return ref.watch(yamiboForumClientProvider).threadCreationPreparation!;
    });

final threadCreationCommandProvider = Provider<ThreadCreationCommand>((ref) {
  return ref.watch(yamiboForumClientProvider).threadCreationCommand!;
});

final newThreadTagsNormalizerProvider = Provider<NewThreadTagsNormalizer>((_) {
  return const NewThreadTagsNormalizer();
});

final newThreadPollNormalizerProvider = Provider<NewThreadPollNormalizer>((_) {
  return const NewThreadPollNormalizer();
});

final postingDraftExtrasCodecProvider = Provider<PostingDraftExtrasCodec>((_) {
  return const PostingDraftExtrasCodec();
});

final threadCreationSubmissionMapperProvider =
    Provider<ThreadCreationSubmissionMapper>((ref) {
      return DefaultThreadCreationSubmissionMapper(
        tagsNormalizer: ref.watch(newThreadTagsNormalizerProvider),
        pollNormalizer: ref.watch(newThreadPollNormalizerProvider),
      );
    });
