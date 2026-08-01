import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_message_editor_surface.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_toolbar_action.dart';
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
