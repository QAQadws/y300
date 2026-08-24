import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_preview_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attachment_preview_resolvers.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_attachment_preview.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_message_editor_surface.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_toolbar_action.dart';
import 'package:y300/features/image_loading/presentation/app_image.dart';
import 'package:y300/shared/widgets/forum_content_spacing.dart';
import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('injects extra toolbar action into source surface', (
    tester,
  ) async {
    var pressed = false;
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _buildSurface(
        surface: ComposerSurfacePreference.source,
        sourceController: controller,
        action: ComposerToolbarAction(
          key: const Key('extra-source-action'),
          icon: Icons.collections,
          tooltip: 'extra',
          onPressed: () => pressed = true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('extra-source-action')));
    expect(pressed, isTrue);
  });

  testWidgets('source surface presents a reactive custom bottom panel', (
    tester,
  ) async {
    final content = ValueNotifier<String>('first');
    addTearDown(content.dispose);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _buildSurface(
        surface: ComposerSurfacePreference.source,
        sourceController: controller,
        action: ComposerToolbarAction.panel(
          key: const Key('source-panel-action'),
          icon: Icons.collections,
          tooltip: 'panel',
          panelBuilder: (_) => ValueListenableBuilder<String>(
            valueListenable: content,
            builder: (_, value, _) =>
                Text(value, key: const Key('source-panel-content')),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('source-panel-action')));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('first'), findsOneWidget);
    content.value = 'second';
    await tester.pump();
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('injects extra toolbar action into Quill surface', (
    tester,
  ) async {
    var pressed = false;

    await tester.pumpWidget(
      _buildSurface(
        surface: ComposerSurfacePreference.quill,
        action: ComposerToolbarAction(
          key: const Key('extra-quill-action'),
          icon: Icons.collections,
          tooltip: 'extra',
          onPressed: () => pressed = true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('extra-quill-action')));
    expect(pressed, isTrue);
  });

  testWidgets('disables extra toolbar actions with the editor surface', (
    tester,
  ) async {
    var pressed = false;
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _buildSurface(
        surface: ComposerSurfacePreference.source,
        sourceController: controller,
        enabled: false,
        action: ComposerToolbarAction(
          key: const Key('disabled-extra-action'),
          icon: Icons.collections,
          tooltip: 'disabled',
          onPressed: () => pressed = true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('disabled-extra-action')));
    expect(pressed, isFalse);
  });

  testWidgets('disables custom panel actions with the editor surface', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _buildSurface(
        surface: ComposerSurfacePreference.source,
        sourceController: controller,
        enabled: false,
        action: ComposerToolbarAction.panel(
          key: const Key('disabled-panel-action'),
          icon: Icons.collections,
          tooltip: 'disabled panel',
          panelBuilder: (_) =>
              const SizedBox(key: Key('disabled-panel-content')),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const Key('disabled-panel-action')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('disabled-panel-content')), findsNothing);
  });

  testWidgets(
    'shared Quill surface applies its body width to remote attachments',
    (tester) async {
      const surfaceWidth = 420.0;
      const referer = 'https://bbs.yamibo.com/forum.php?mod=post';
      final sourceController = TextEditingController();
      addTearDown(sourceController.dispose);
      final resolver = MapComposerAttachmentPreviewResolver(
        resolutions: const {
          '1624572': ComposerAttachmentResolution(
            aid: '1624572',
            availability: ComposerAttachmentAvailability.available,
            preview: ComposerRemoteImagePreview(
              url:
                  'https://bbs.yamibo.com/data/attachment/forum/202607/23/example.jpg',
              referer: referer,
            ),
          ),
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: const [],
          child: LocalizedTestApp(
            home: Scaffold(
              body: SizedBox(
                width: surfaceWidth,
                height: 360,
                child: ComposerMessageEditorSurface(
                  surface: ComposerSurfacePreference.quill,
                  message: '[attachimg]1624572[/attachimg]',
                  sourceController: sourceController,
                  enabled: true,
                  bbCodeRenderer: const FlutterBbCodeForumRenderer(),
                  stickerGroups: const [],
                  initialStickerGroupId: null,
                  onStickerGroupChanged: (_) {},
                  onMessageChanged: (_) {},
                  attachmentResolver: resolver,
                  keyPrefix: 'remote-surface-test',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final preview = tester.widget<ComposerAttachmentPreviewImage>(
        find.byKey(const Key('composer-quill-attach-preview-1624572')),
      );
      expect(
        preview.maxWidth,
        closeTo(_expectedAttachmentMaxWidth(surfaceWidth), 0.001),
      );
      final image = tester.widget<AppImage>(find.byType(AppImage));
      expect(
        image.networkSource?.resolvedUrl,
        'https://bbs.yamibo.com/data/attachment/forum/202607/23/example.jpg',
      );
      expect(image.networkSource?.referer, referer);
    },
  );
}

Widget _buildSurface({
  required ComposerSurfacePreference surface,
  required ComposerToolbarAction action,
  TextEditingController? sourceController,
  bool enabled = true,
}) {
  return LocalizedTestApp(
    home: Scaffold(
      body: SizedBox(
        width: 420,
        height: 360,
        child: ComposerMessageEditorSurface(
          surface: surface,
          message: '正文',
          sourceController: sourceController ?? TextEditingController(),
          enabled: enabled,
          bbCodeRenderer: const FlutterBbCodeForumRenderer(),
          stickerGroups: const [],
          initialStickerGroupId: null,
          onStickerGroupChanged: (_) {},
          onMessageChanged: (_) {},
          keyPrefix: 'surface-test',
          extraToolbarActions: [action],
        ),
      ),
    ),
  );
}

double _expectedAttachmentMaxWidth(double surfaceWidth) {
  return surfaceWidth -
      (ForumContentSpacing.composerQuillSurfaceHorizontal * 2) -
      (ForumContentSpacing.quillInnerHorizontal * 2) -
      4;
}
