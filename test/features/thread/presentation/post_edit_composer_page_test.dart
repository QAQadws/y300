import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/data/services/composer_image_picker.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_preferences_repository.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';
import 'package:y300/features/thread/data/providers/post_edit_providers.dart';
import 'package:y300/features/thread/domain/models/post_edit_composer_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_submit_models.dart';
import 'package:y300/features/thread/domain/repositories/post_edit_repository.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_controller.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_page.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_state.dart';
import 'package:y300/features/thread/presentation/widgets/post_edit_attachment_panel.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('dirty message leaves immediately without a draft dialog', (
    tester,
  ) async {
    final results = <Object?>[];
    final args = _args(_snapshot(message: '服务器正文'));
    await tester.pumpWidget(_buildApp(args: args, results: results));
    await _openEditor(tester);

    expect(find.byKey(const Key('post-edit-more-button')), findsNothing);
    expect(
      find.byKey(const Key('post-edit-composer-quill-editor')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('post-edit-composer-source-view')),
      findsNothing,
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PostEditComposerPage)),
    );
    container
        .read(postEditComposerControllerProvider(args).notifier)
        .updateMessage('本地修改');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(PostEditComposerPage), findsNothing);
    expect(results, <Object?>[null]);
  });

  testWidgets('image manager is hosted by the Quill keyboard panel', (
    tester,
  ) async {
    final results = <Object?>[];
    final args = _args(
      _snapshot(
        message: '服务器正文',
        images: [
          PostEditExistingImage(
            aid: '12',
            imageUri: Uri.parse('https://bbs.yamibo.com/12.jpg'),
            isAssociated: true,
          ),
        ],
      ),
    );
    await tester.pumpWidget(_buildApp(args: args, results: results));
    await _openEditor(tester);

    await tester.tap(find.byKey(const Key('post-edit-manage-images-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(PostEditAttachmentPanel), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(PostEditAttachmentPanel),
        matching: find.byKey(const Key('post-edit-composer-tool-panel')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('possible server mutation returns a structured refresh result', (
    tester,
  ) async {
    final results = <Object?>[];
    final args = _args(
      _snapshot(
        message: '服务器正文',
        images: [
          PostEditExistingImage(
            aid: '12',
            imageUri: Uri.parse('https://bbs.yamibo.com/12.jpg'),
            isAssociated: true,
          ),
        ],
      ),
    );
    await tester.pumpWidget(_buildApp(args: args, results: results));
    await _openEditor(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PostEditComposerPage)),
    );
    await container
        .read(postEditComposerControllerProvider(args).notifier)
        .deleteImage('12');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(results, hasLength(1));
    final result = results.single as PostEditRouteResult;
    expect(result.outcome, PostEditRouteOutcome.dismissed);
    expect(result.serverMutationPossible, isTrue);
  });
}

Widget _buildApp({
  required PostEditComposerArgs args,
  required List<Object?> results,
}) {
  return ProviderScope(
    overrides: [
      postEditRepositoryProvider.overrideWithValue(
        const _ImmediatePostEditRepository(),
      ),
      composerPreferencesRepositoryProvider.overrideWithValue(
        const _MemoryComposerPreferencesRepository(),
      ),
      composerImagePickerProvider.overrideWithValue(const _NoopImagePicker()),
      composerImageUploadCoordinatorProvider.overrideWithValue(
        const _NoopUploadCoordinator(),
      ),
      stickerGroupsProvider.overrideWith((_) async => const []),
    ],
    child: LocalizedTestApp(
      home: _PostEditLauncher(args: args, results: results),
    ),
  );
}

Future<void> _openEditor(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-post-edit')));
  await tester.pumpAndSettle();
  expect(find.byType(PostEditComposerPage), findsOneWidget);
}

class _PostEditLauncher extends StatelessWidget {
  const _PostEditLauncher({required this.args, required this.results});

  final PostEditComposerArgs args;
  final List<Object?> results;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          key: const Key('open-post-edit'),
          onPressed: () async {
            final result = await Navigator.of(context).push<Object?>(
              MaterialPageRoute<Object?>(
                builder: (_) => PostEditComposerPage(args: args),
              ),
            );
            results.add(result);
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}

PostEditComposerArgs _args(PostEditFormSnapshot snapshot) {
  return PostEditComposerArgs(
    preparation: PostEditPreparation(
      target: snapshot.target,
      decision: const PostEditNativeSupported(profileVersion: 1),
      snapshot: snapshot,
    ),
  );
}

PostEditFormSnapshot _snapshot({
  required String message,
  List<PostEditExistingImage> images = const <PostEditExistingImage>[],
}) {
  final target = PostEditTarget(
    editUri: Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=5&tid=20&pid=30',
    ),
    fid: '5',
    tid: '20',
    pid: '30',
    page: 1,
    isFirstPost: false,
  );
  return PostEditFormSnapshot(
    target: target,
    sourceUri: target.editUri,
    submitUri: Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=post&action=edit&editsubmit=yes',
    ),
    formHash: 'test-formhash',
    postTime: '1700000000',
    rawMessage: message,
    originalSubject: 'subject',
    successfulControls: [
      PostEditFormField(
        name: 'message',
        value: message,
        controlKind: PostEditFormControlKind.textarea,
      ),
    ],
    existingImages: images,
    structureEvidence: PostEditFormStructureEvidence(
      allNamedControlNamesInDomOrder: const <String>['message'],
    ),
    baselineFingerprint: 'baseline',
  );
}

class _ImmediatePostEditRepository implements PostEditRepository {
  const _ImmediatePostEditRepository();

  @override
  Future<ApiResult<PostEditAttachmentDeleteResult>> deleteImage(
    PostEditAttachmentDeleteCommand command,
  ) async {
    return ApiSuccess(
      PostEditAttachmentDeleteResult(
        aid: command.aid,
        outcome: PostEditAttachmentDeleteOutcome.deleted,
        deletedCount: 1,
      ),
    );
  }

  @override
  Future<ApiResult<PostEditPreparation>> loadForm(PostEditTarget target) async {
    return const ApiFailure(
      ApiError(type: ApiErrorType.network, message: 'not used'),
    );
  }

  @override
  Future<ApiResult<PostEditSubmitResponse>> submit(
    PostEditSubmitPayload payload, {
    required PostEditTarget target,
  }) async {
    return const ApiFailure(
      ApiError(type: ApiErrorType.network, message: 'not used'),
    );
  }
}

class _MemoryComposerPreferencesRepository
    implements ComposerPreferencesRepository {
  const _MemoryComposerPreferencesRepository();

  @override
  Future<ComposerPreferences> load() async => ComposerPreferences.defaults();

  @override
  Future<void> save(ComposerPreferences preferences) async {}
}

class _NoopImagePicker implements ComposerImagePicker {
  const _NoopImagePicker();

  @override
  Future<List<ComposerPickedImage>> pickImagesInOrder() async => const [];
}

class _NoopUploadCoordinator implements ComposerImageUploadCoordinator {
  const _NoopUploadCoordinator();

  @override
  void cancel() {}

  @override
  Stream<ComposerImageUploadEvent> uploadInOrder({
    required String fid,
    required List<ComposerImageAttachment> attachments,
  }) {
    return const Stream<ComposerImageUploadEvent>.empty();
  }
}
