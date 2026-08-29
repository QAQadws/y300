import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/domain/services/thread_creation_submission_mapper.dart';

void main() {
  const mapper = DefaultThreadCreationSubmissionMapper();
  const preparation = ThreadCreationPreparation(
    fid: '33',
    forumName: 'fixture-forum',
    threadTypes: <ThreadCreationType>[
      ThreadCreationType(id: '10', name: 'fixture-type'),
    ],
    threadSorts: <ThreadCreationSort>[],
    typeRequired: false,
    sortRequired: false,
    maxSubjectLength: 80,
    maxMessageLength: 10000,
    token: _TestPreparationToken(),
  );

  test('maps Y300 draft fields without exposing protocol state', () {
    final result = mapper.map(
      preparation: preparation,
      input: ThreadCreationDraftInput(
        subject: '  subject  ',
        message: 'body [attach]100[/attach] [attach]999[/attach]',
        selectedTypeId: '10',
        useSignature: true,
        allowNoticeAuthor: false,
        bbCodeOff: false,
        smileyOff: true,
        parseUrlOff: true,
        imageAttachments: const <ComposerImageAttachment>[
          ComposerImageAttachment(
            localId: 'image-1',
            localPath: 'fixture.jpg',
            fileName: 'fixture.jpg',
            mimeType: 'image/jpeg',
            order: 0,
            status: ComposerImageAttachmentStatus.uploaded,
            aid: '100',
          ),
        ],
        tags: const <String>['  tag  ', 'tag'],
      ),
    );

    expect(result.subject, 'subject');
    expect(result.typeId, '10');
    expect(result.attachmentIds, const <String>['100']);
    expect(result.tags, const <String>['tag']);
    expect(result.disableSmileys, isTrue);
    expect(result.disableUrlParsing, isTrue);
    expect(result.minimumReadAccess, 0);
  });

  test('maps normalized poll fields into package submission', () {
    final result = mapper.map(
      preparation: preparation,
      input: const ThreadCreationDraftInput(
        subject: 'poll',
        message: 'body',
        selectedTypeId: null,
        useSignature: false,
        allowNoticeAuthor: true,
        bbCodeOff: false,
        smileyOff: false,
        parseUrlOff: false,
        special: NewThreadSpecial.poll,
        poll: NewThreadPollDraft(
          options: <String>[' A ', '', 'B'],
          multiple: true,
          maxChoices: 2,
          expirationDays: 7,
          overt: true,
          visibilityPoll: true,
        ),
      ),
    );

    expect(result.kind, ThreadCreationKind.poll);
    expect(result.typeId, '0');
    expect(result.poll?.options, const <String>['A', 'B']);
    expect(result.poll?.maximumChoices, 2);
    expect(result.poll?.expirationDays, 7);
    expect(result.poll?.publicVoters, isTrue);
    expect(result.poll?.resultsAfterVote, isTrue);
  });
}

final class _TestPreparationToken implements ThreadCreationPreparationToken {
  const _TestPreparationToken();
}
