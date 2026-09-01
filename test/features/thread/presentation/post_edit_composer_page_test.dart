import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/data/services/composer_image_picker.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_preferences_repository.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';
import 'package:y300/features/thread/data/providers/post_edit_providers.dart';
import 'package:y300/features/thread/domain/models/post_edit_composer_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_controller.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_page.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_state.dart';
import 'package:y300/features/thread/presentation/widgets/post_edit_attachment_panel.dart';
import 'package:y300/features/image_loading/presentation/app_image.dart';
import 'package:y300/features/image_loading/data/app_image_providers.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/post_edit_test_support.dart';

void main() {
  testWidgets('source action edits raw BBCode without opening WebView', (
    tester,
  ) async {
    final results = <Object?>[];
    final args = _args(
      _snapshot(
        message: '[b]服务器正文[/b][attachimg]12[/attachimg]',
        isFirstPost: true,
        images: [
          ThreadPostEditImageAttachment(
            aid: '12',
            imageUri: Uri.parse('https://bbs.yamibo.com/12.jpg'),
            isAssociated: true,
          ),
        ],
      ),
    );
    await tester.pumpWidget(_buildApp(args: args, results: results));
    await _openEditor(tester);

    expect(
      find.byKey(const Key('post-edit-composer-source-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('post-edit-composer-quill-editor')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('post-edit-composer-source-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('post-edit-composer-quill-editor')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('post-edit-composer-source-view')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('post-edit-subject-input')), findsOneWidget);
    expect(
      find.byKey(const Key('post-edit-manage-images-button')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('post-edit-manage-images-button')));
    await tester.pumpAndSettle();
    expect(find.byType(PostEditAttachmentPanel), findsOneWidget);
    Navigator.of(tester.element(find.byType(PostEditAttachmentPanel))).pop();
    await tester.pumpAndSettle();

    final sourceInput = find.byKey(
      const Key('post-edit-composer-message-input'),
    );
    expect(
      tester.widget<TextField>(sourceInput).controller!.text,
      contains('12'),
    );

    await tester.enterText(sourceInput, '[i]源码修改[/i][attachimg]12[/attachimg]');
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PostEditComposerPage)),
    );
    expect(
      container.read(postEditComposerControllerProvider(args)).value!.message,
      '[i]源码修改[/i][attachimg]12[/attachimg]',
    );

    await tester.tap(find.byKey(const Key('post-edit-composer-source-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('post-edit-composer-quill-editor')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('post-edit-composer-source-view')),
      findsNothing,
    );
    expect(
      container.read(postEditComposerControllerProvider(args)).value!.message,
      '[i]源码修改[/i][attachimg]12[/attachimg]',
    );
  });

  testWidgets('uses and updates the shared composer surface preference', (
    tester,
  ) async {
    final results = <Object?>[];
    final preferencesRepository = _MemoryComposerPreferencesRepository(
      const ComposerPreferences(
        defaultSurface: ComposerSurfacePreference.source,
        newDraftUseSignature: true,
      ),
    );
    final args = _args(_snapshot(message: '服务器正文'));
    await tester.pumpWidget(
      _buildApp(
        args: args,
        results: results,
        preferencesRepository: preferencesRepository,
      ),
    );
    await _openEditor(tester);

    expect(
      find.byKey(const Key('post-edit-composer-source-view')),
      findsOneWidget,
    );
    final scaffold = tester.widget<Scaffold>(
      find.byKey(const Key('post-edit-composer-page')),
    );
    expect(scaffold.resizeToAvoidBottomInset, isTrue);

    await tester.tap(find.byKey(const Key('post-edit-composer-source-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('post-edit-composer-quill-editor')),
      findsOneWidget,
    );
    expect(
      preferencesRepository.preferences.defaultSurface,
      ComposerSurfacePreference.quill,
    );
  });

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
          ThreadPostEditImageAttachment(
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

  testWidgets('post edit delegates keyboard insets to the shared Quill host', (
    tester,
  ) async {
    final results = <Object?>[];
    final args = _args(_snapshot(message: '服务器正文'));
    await tester.pumpWidget(_buildApp(args: args, results: results));
    await _openEditor(tester);

    final scaffold = tester.widget<Scaffold>(
      find.byKey(const Key('post-edit-composer-page')),
    );
    final bodySafeArea = tester.widget<SafeArea>(
      find.byKey(const Key('post-edit-composer-safe-area')),
    );

    expect(scaffold.resizeToAvoidBottomInset, isFalse);
    expect(bodySafeArea.bottom, isFalse);
    expect(
      find.byKey(const Key('post-edit-composer-format-button')),
      findsOneWidget,
    );
  });

  testWidgets('message updates keep remote attachment referer', (tester) async {
    final results = <Object?>[];
    final args = _args(
      _snapshot(
        message: '[attachimg]12[/attachimg]',
        images: [
          ThreadPostEditImageAttachment(
            aid: '12',
            imageUri: Uri.parse('https://bbs.yamibo.com/12.jpg'),
            isAssociated: true,
          ),
        ],
      ),
    );
    final referer = args.snapshot.sourceUri.toString();
    await tester.pumpWidget(_buildApp(args: args, results: results));
    await _openEditor(tester);
    await tester.pump();

    expect(find.byType(AppImage), findsOneWidget);
    expect(
      tester.widget<AppImage>(find.byType(AppImage)).networkSource?.referer,
      referer,
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PostEditComposerPage)),
    );
    container
        .read(postEditComposerControllerProvider(args).notifier)
        .updateMessage('前缀[attachimg]12[/attachimg]');
    await tester.pump();
    await tester.pump();

    expect(find.byType(AppImage), findsOneWidget);
    expect(
      tester.widget<AppImage>(find.byType(AppImage)).networkSource?.referer,
      referer,
    );
  });

  testWidgets('first-post edit shows the server subject', (tester) async {
    final results = <Object?>[];
    final args = _args(
      _snapshot(message: '服务器正文', isFirstPost: true, subject: '论坛近期考虑升级吗'),
    );
    await tester.pumpWidget(_buildApp(args: args, results: results));
    await _openEditor(tester);

    final subject = find.byKey(const Key('post-edit-subject-input'));
    expect(subject, findsOneWidget);
    expect(tester.widget<TextField>(subject).controller!.text, '论坛近期考虑升级吗');

    await tester.enterText(subject, '新的标题');
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('post-edit-save-button')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('floor edit does not show a subject field', (tester) async {
    final results = <Object?>[];
    final args = _args(_snapshot(message: '服务器正文'));
    await tester.pumpWidget(_buildApp(args: args, results: results));
    await _openEditor(tester);

    expect(find.byKey(const Key('post-edit-subject-input')), findsNothing);
  });

  testWidgets('possible server mutation returns a structured refresh result', (
    tester,
  ) async {
    final results = <Object?>[];
    final args = _args(
      _snapshot(
        message: '服务器正文',
        images: [
          ThreadPostEditImageAttachment(
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
  ComposerPreferencesRepository? preferencesRepository,
}) {
  return ProviderScope(
    overrides: [
      threadPostEditPreparationRepositoryProvider.overrideWithValue(
        const _UnusedPreparationRepository(),
      ),
      threadPostEditCommandProvider.overrideWithValue(
        const _UnusedEditCommand(),
      ),
      postEditImageAttachmentDeleteCommandProvider.overrideWithValue(
        const _AppliedAttachmentDeleteCommand(),
      ),
      composerPreferencesRepositoryProvider.overrideWithValue(
        preferencesRepository ?? _MemoryComposerPreferencesRepository(),
      ),
      composerImagePickerProvider.overrideWithValue(const _NoopImagePicker()),
      composerImageUploadCoordinatorProvider.overrideWithValue(
        const _NoopUploadCoordinator(),
      ),
      appImageCacheManagerProvider.overrideWith(
        (ref) async => throw StateError('network images are not loaded here'),
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

PostEditComposerArgs _args(ThreadPostEditPreparation snapshot) {
  return PostEditComposerArgs(
    target: _targetFromPreparation(snapshot),
    preparation: snapshot,
  );
}

ThreadPostEditPreparation _snapshot({
  required String message,
  List<ThreadPostEditImageAttachment> images =
      const <ThreadPostEditImageAttachment>[],
  bool isFirstPost = false,
  String subject = 'subject',
}) {
  final target = buildPostEditTarget(
    fid: '5',
    tid: '20',
    pid: '30',
    isFirstPost: isFirstPost,
  );
  return buildPostEditPreparation(
    target: target,
    isFirstPost: isFirstPost,
    subject: subject,
    message: message,
    existingImages: images,
    revision: 'baseline',
  );
}

PostEditTarget _targetFromPreparation(ThreadPostEditPreparation preparation) {
  final target = preparation.target;
  return PostEditTarget(
    editUri: target.formUri,
    fid: target.fid,
    tid: target.tid,
    pid: target.pid,
    page: target.page,
    isFirstPost: target.isFirstPost,
  );
}

class _AppliedAttachmentDeleteCommand
    implements ForumPostImageAttachmentDeleteCommand {
  const _AppliedAttachmentDeleteCommand();

  @override
  Future<DataCommandResult<ForumImageAttachmentDeleteReceipt>> execute(
    DeletePostImageAttachmentRequest request,
  ) async {
    return DataCommandApplied(
      ForumImageAttachmentDeleteReceipt(aid: request.aid, deletedCount: 1),
    );
  }
}

class _UnusedPreparationRepository
    implements ThreadPostEditPreparationRepository {
  const _UnusedPreparationRepository();

  @override
  ThreadPostEditCapabilities get capabilities => buildPostEditCapabilities();

  @override
  Future<DataReadResult<ThreadPostEditPreparation, ThreadPostEditCapabilities>>
  load(ThreadPostEditPreparationRequest request) async {
    return DataReadFailure(
      kind: DataReadFailureKind.network,
      diagnosticMessage: 'not_used',
    );
  }
}

class _UnusedEditCommand implements ThreadPostEditCommand {
  const _UnusedEditCommand();

  @override
  ThreadPostEditCapabilities get capabilities => buildPostEditCapabilities();

  @override
  Future<DataCommandResult<ThreadPostEditReceipt>> execute(
    ThreadPostEditSubmission submission,
  ) async {
    return const DataCommandNotSent(
      DataCommandFailure(
        kind: DataCommandFailureKind.validation,
        retryPolicy: DataCommandRetryPolicy.never,
        diagnosticMessage: 'not_used',
      ),
    );
  }
}

class _MemoryComposerPreferencesRepository
    implements ComposerPreferencesRepository {
  _MemoryComposerPreferencesRepository([
    ComposerPreferences? initialPreferences,
  ]) : preferences = initialPreferences ?? ComposerPreferences.defaults();

  ComposerPreferences preferences;

  @override
  Future<ComposerPreferences> load() async => preferences;

  @override
  Future<void> save(ComposerPreferences preferences) async {
    this.preferences = preferences;
  }
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
