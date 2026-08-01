import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_preview_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_state.dart';
import 'package:y300/features/thread/presentation/widgets/post_edit_attachment_panel.dart';
import 'package:y300/l10n/app_localizations.dart';
import '../../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('shows an image card and confirms explicit deletion', (
    tester,
  ) async {
    String? deletedAid;
    final state = PostEditComposerState.initial(
      target: _target,
      snapshot: _snapshot(
        images: [
          PostEditExistingImage(
            aid: '12',
            imageUri: Uri.parse('https://bbs.yamibo.com/image.jpg'),
            isAssociated: true,
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: PostEditAttachmentPanel(
            state: state,
            resolver: const _MissingResolver(),
            onDeleteImage: (aid) => deletedAid = aid,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('post-edit-delete-image-12')), findsOneWidget);
    final panelContent = tester.widget<Container>(
      find.byKey(const Key('post-edit-attachment-panel-content')),
    );
    expect(panelContent.color, isNull);
    expect(
      find.descendant(
        of: find.byType(PostEditAttachmentPanel),
        matching: find.byWidgetPredicate((widget) {
          final decoration = widget is DecoratedBox ? widget.decoration : null;
          return decoration is BoxDecoration && decoration.border != null;
        }),
      ),
      findsNothing,
    );
    final deleteButton = find.byKey(const Key('post-edit-delete-image-12'));
    expect(tester.getSize(deleteButton), const Size.square(40));
    final deleteVisual = find.byKey(
      const Key('post-edit-delete-image-visual-12'),
    );
    expect(tester.getSize(deleteVisual), const Size.square(24));
    final closeIcon = tester.widget<Icon>(
      find.descendant(of: deleteVisual, matching: find.byIcon(Icons.close)),
    );
    expect(closeIcon.size, 14);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(PostEditAttachmentPanel)),
    );
    expect(find.text(l10n.postEditDeleteImageTitle), findsOneWidget);
    await tester.tap(find.byKey(const Key('post-edit-confirm-delete-image')));
    await tester.pumpAndSettle();
    expect(deletedAid, '12');
  });

  testWidgets('shows the localized empty state', (tester) async {
    final state = PostEditComposerState.initial(
      target: _target,
      snapshot: _snapshot(),
    );
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: PostEditAttachmentPanel(
            state: state,
            resolver: const _MissingResolver(),
            onDeleteImage: (_) {},
          ),
        ),
      ),
    );

    expect(
      find.text(
        AppLocalizations.of(
          tester.element(find.byType(PostEditAttachmentPanel)),
        ).postEditNoImages,
      ),
      findsOneWidget,
    );
  });

  testWidgets('keeps a large image collection scrollable in a bounded panel', (
    tester,
  ) async {
    final state = PostEditComposerState.initial(
      target: _target,
      snapshot: _snapshot(
        images: [
          for (var index = 1; index <= 20; index += 1)
            PostEditExistingImage(
              aid: '$index',
              imageUri: Uri.parse('https://bbs.yamibo.com/$index.jpg'),
              isAssociated: true,
            ),
        ],
      ),
    );
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: PostEditAttachmentPanel(
              state: state,
              resolver: const _MissingResolver(),
              onDeleteImage: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -180),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

final class _MissingResolver implements ComposerAttachmentPreviewResolver {
  const _MissingResolver();

  @override
  ComposerAttachmentResolution resolve(String aid) {
    return ComposerAttachmentResolution(
      aid: aid,
      availability: ComposerAttachmentAvailability.missing,
    );
  }
}

final _target = PostEditTarget(
  editUri: Uri.parse(
    'https://bbs.yamibo.com/forum.php?mod=post&action=edit&tid=20&pid=30',
  ),
  fid: '5',
  tid: '20',
  pid: '30',
  page: 1,
  isFirstPost: false,
);

PostEditFormSnapshot _snapshot({
  List<PostEditExistingImage> images = const <PostEditExistingImage>[],
}) {
  return PostEditFormSnapshot(
    target: _target,
    sourceUri: _target.editUri,
    submitUri: _target.editUri,
    formHash: 'hash',
    postTime: 'time',
    rawMessage: '[attach]12[/attach]',
    originalSubject: '',
    successfulControls: const <PostEditFormField>[],
    existingImages: images,
    structureEvidence: PostEditFormStructureEvidence(
      allNamedControlNamesInDomOrder: const <String>[],
    ),
    baselineFingerprint: 'baseline',
  );
}
