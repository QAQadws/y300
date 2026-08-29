import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_service.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/domain/services/new_thread_poll_normalizer.dart';
import 'package:y300/features/posting/domain/services/new_thread_tags_normalizer.dart';

class ThreadCreationDraftInput {
  const ThreadCreationDraftInput({
    required this.subject,
    required this.message,
    required this.selectedTypeId,
    required this.useSignature,
    required this.allowNoticeAuthor,
    required this.bbCodeOff,
    required this.smileyOff,
    required this.parseUrlOff,
    this.imageAttachments = const <ComposerImageAttachment>[],
    this.additionalValidAttachmentAids = const <String>[],
    this.tags = const <String>[],
    this.special = NewThreadSpecial.normal,
    this.poll,
  });

  final String subject;
  final String message;
  final String? selectedTypeId;
  final bool useSignature;
  final bool allowNoticeAuthor;
  final bool bbCodeOff;
  final bool smileyOff;
  final bool parseUrlOff;
  final List<ComposerImageAttachment> imageAttachments;
  final List<String> additionalValidAttachmentAids;
  final List<String> tags;
  final NewThreadSpecial special;
  final NewThreadPollDraft? poll;
}

abstract interface class ThreadCreationSubmissionMapper {
  ThreadCreationSubmission map({
    required ThreadCreationDraftInput input,
    required ThreadCreationPreparation preparation,
  });
}

class DefaultThreadCreationSubmissionMapper
    implements ThreadCreationSubmissionMapper {
  const DefaultThreadCreationSubmissionMapper({
    this.attachBbCodeService = const ComposerAttachBbCodeService(),
    this.tagsNormalizer = const NewThreadTagsNormalizer(),
    this.pollNormalizer = const NewThreadPollNormalizer(),
  });

  final ComposerAttachBbCodeService attachBbCodeService;
  final NewThreadTagsNormalizer tagsNormalizer;
  final NewThreadPollNormalizer pollNormalizer;

  @override
  ThreadCreationSubmission map({
    required ThreadCreationDraftInput input,
    required ThreadCreationPreparation preparation,
  }) {
    final normalizedPoll = input.special == NewThreadSpecial.poll
        ? pollNormalizer.normalize(input.poll)
        : null;
    return ThreadCreationSubmission(
      preparation: preparation,
      subject: input.subject.trim(),
      message: input.message.trim(),
      typeId: _resolveTypeId(input.selectedTypeId, preparation),
      useSignature: input.useSignature,
      notifyAuthor: input.allowNoticeAuthor,
      disableBbCode: input.bbCodeOff,
      disableSmileys: input.smileyOff,
      disableUrlParsing: input.parseUrlOff,
      attachmentIds: _resolveAttachmentIds(input),
      tags: List<String>.unmodifiable(tagsNormalizer.normalize(input.tags)),
      kind: input.special == NewThreadSpecial.poll
          ? ThreadCreationKind.poll
          : ThreadCreationKind.ordinary,
      poll: normalizedPoll == null
          ? null
          : ThreadPollSubmission(
              options: List<String>.unmodifiable(normalizedPoll.options),
              maximumChoices: normalizedPoll.multiple
                  ? normalizedPoll.maxChoices
                  : 1,
              expirationDays: normalizedPoll.expirationDays,
              publicVoters: normalizedPoll.overt,
              resultsAfterVote: normalizedPoll.visibilityPoll,
            ),
      // readperm UI is intentionally a later Y300 slice. The package contract
      // is ready now, while the current App preserves unrestricted posting.
      minimumReadAccess: 0,
    );
  }

  String _resolveTypeId(
    String? selected,
    ThreadCreationPreparation preparation,
  ) {
    final value = selected?.trim() ?? '';
    if (value.isEmpty || value == '0') return '0';
    return preparation.threadTypes.any((item) => item.id == value)
        ? value
        : '0';
  }

  List<String> _resolveAttachmentIds(ThreadCreationDraftInput input) {
    final valid = <String>{
      for (final attachment in input.imageAttachments)
        if (attachment.canEnterSubmitPayload) attachment.aid!.trim(),
      for (final aid in input.additionalValidAttachmentAids)
        if (aid.trim().isNotEmpty) aid.trim(),
    };
    final seen = <String>{};
    return <String>[
      for (final aid in attachBbCodeService.extractAttachAids(input.message))
        if (valid.contains(aid) && seen.add(aid)) aid,
    ];
  }
}
