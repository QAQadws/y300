import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/thread/data/services/post_edit_contract_diagnostic_recorder.dart';
import 'package:y300/features/thread/domain/models/post_edit_diagnostic_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';

final postEditContractDiagnosticRecorderProvider =
    Provider<PostEditContractDiagnosticRecorder>((ref) {
      return DefaultPostEditContractDiagnosticRecorder(
        writeLog: (message) => ref.watch(loggerProvider).i(message),
      );
    });

final threadPostEditPreparationRepositoryProvider =
    Provider<ThreadPostEditPreparationRepository>((ref) {
      return ref.watch(yamiboForumClientProvider).threadPostEditPreparation!;
    });

final threadPostEditCommandProvider = Provider<ThreadPostEditCommand>((ref) {
  return ref.watch(yamiboForumClientProvider).threadPostEditCommand!;
});

final postEditImageAttachmentDeleteCommandProvider =
    Provider<ForumPostImageAttachmentDeleteCommand>((ref) {
      return ref.watch(yamiboForumClientProvider).postImageAttachmentDelete!;
    });

final postEditPreparationProvider = FutureProvider.autoDispose
    .family<
      DataReadResult<ThreadPostEditPreparation, ThreadPostEditCapabilities>,
      PostEditTarget
    >((ref, target) {
      return ref
          .watch(threadPostEditPreparationRepositoryProvider)
          .load(
            ThreadPostEditPreparationRequest(target: target.toClientTarget()),
          );
    });
