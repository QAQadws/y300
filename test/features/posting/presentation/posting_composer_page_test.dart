import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/data/repositories/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/services/composer_image_picker.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/data/repositories/sticker_picker_preferences_repository.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_preferences_repository.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/posting/data/repositories/new_thread_repository.dart';
import 'package:y300/features/posting/data/repositories/posting_form_metadata_repository.dart';
import 'package:y300/features/posting/data/providers/posting_providers.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/domain/models/posting_target.dart';
import 'package:y300/features/posting/presentation/posting_composer_page.dart';
import 'package:y300/features/posting/presentation/posting_composer_state.dart';

part 'posting_composer_page_test_fakes.dart';

void main() {
  testWidgets('PostingComposerPage builds dark theme chrome', (tester) async {
    await tester.pumpWidget(
      _buildPage(
        theme: AppTheme.dark(),
        metadataRepository: _FakeMetadataRepository.success(_metadata()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(
      find.byKey(const Key('posting-composer-subject-input')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('posting-composer-quill-editor')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('posting-composer-message-input')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('posting-composer-format-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('posting-composer-link-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('posting-composer-align-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('posting-composer-quote-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('posting-composer-sticker-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('posting-composer-image-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('posting-composer-color-button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('posting-composer-backcolor-button')),
      findsNothing,
    );
    expect(find.byKey(const Key('posting-composer-size-button')), findsNothing);
    expect(find.byKey(const Key('posting-composer-code-button')), findsNothing);
    expect(
      find.byKey(const Key('posting-composer-send-button')),
      findsOneWidget,
    );
  });

  testWidgets('PostingComposerPage uses AppBar foreground for action buttons', (
    tester,
  ) async {
    final theme = AppTheme.dark();
    final appBarForeground = theme.appBarTheme.foregroundColor!;

    await tester.pumpWidget(
      _buildPage(
        theme: theme,
        metadataRepository: _FakeMetadataRepository.success(_metadata()),
      ),
    );
    await tester.pumpAndSettle();

    for (final key in const [
      Key('posting-composer-source-button'),
      Key('posting-composer-more-button'),
      Key('posting-composer-send-button'),
    ]) {
      final action = tester.widget<IconButton>(find.byKey(key));
      final foreground = action.style?.foregroundColor;

      expect(foreground?.resolve(<WidgetState>{}), appBarForeground);
      expect(
        foreground?.resolve(<WidgetState>{WidgetState.disabled}),
        appBarForeground.withValues(alpha: 0.38),
      );
    }
  });

  testWidgets('PostingComposerPage places source before more and send', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildPage(
        metadataRepository: _FakeMetadataRepository.success(_metadata()),
      ),
    );
    await tester.pumpAndSettle();

    final sourceCenter = tester.getCenter(
      find.byKey(const Key('posting-composer-source-button')),
    );
    final moreCenter = tester.getCenter(
      find.byKey(const Key('posting-composer-more-button')),
    );
    final sendCenter = tester.getCenter(
      find.byKey(const Key('posting-composer-send-button')),
    );

    expect(sourceCenter.dx, lessThan(moreCenter.dx));
    expect(moreCenter.dx, lessThan(sendCenter.dx));
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byKey(const Key('posting-composer-image-button')),
      ),
      findsNothing,
    );
  });

  testWidgets('PostingComposerPage toggles Quill and source editor', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildPage(
        metadataRepository: _FakeMetadataRepository.success(_metadata()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('posting-composer-quill-editor')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('posting-composer-bbcode-preview-panel')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('posting-composer-message-input')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('posting-composer-source-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('posting-composer-source-view')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('posting-composer-message-input')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('posting-composer-quill-editor')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('posting-composer-bbcode-preview-panel')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const Key('posting-composer-message-input')),
      '[b]正文[/b]',
    );
    await tester.pump();

    final messageField = tester.widget<TextField>(
      find.byKey(const Key('posting-composer-message-input')),
    );
    expect(messageField.controller?.text, '[b]正文[/b]');

    await tester.tap(find.byKey(const Key('posting-composer-source-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('posting-composer-source-view')), findsNothing);
    expect(
      find.byKey(const Key('posting-composer-quill-editor')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('posting-composer-source-button')));
    await tester.pumpAndSettle();

    final restoredField = tester.widget<TextField>(
      find.byKey(const Key('posting-composer-message-input')),
    );
    expect(restoredField.controller?.text, '[b]正文[/b]');
  });

  testWidgets('PostingComposerPage starts from the saved source surface', (
    tester,
  ) async {
    final preferencesRepository = _FakeComposerPreferencesRepository(
      preferences: const ComposerPreferences(
        defaultSurface: ComposerSurfacePreference.source,
        newDraftUseSignature: true,
      ),
    );
    await tester.pumpWidget(
      _buildPage(
        preferencesRepository: preferencesRepository,
        metadataRepository: _FakeMetadataRepository.success(_metadata()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('posting-composer-message-input')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('posting-composer-quill-editor')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('posting-composer-source-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('posting-composer-quill-editor')),
      findsOneWidget,
    );
    expect(
      preferencesRepository.preferences.defaultSurface,
      ComposerSurfacePreference.quill,
    );
  });

  testWidgets('PostingComposerPage source editor inserts link BBCode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildPage(
        metadataRepository: _FakeMetadataRepository.success(_metadata()),
      ),
    );
    await tester.pumpAndSettle();

    await _enterPostingSourceMode(tester);
    await tester.tap(find.byKey(const Key('posting-composer-link-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('posting-composer-link-sheet')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('posting-composer-link-url-input')),
      'https://example.com',
    );
    await tester.enterText(
      find.byKey(const Key('posting-composer-link-label-input')),
      '示例链接',
    );
    await tester.tap(find.byKey(const Key('posting-composer-link-use-button')));
    await tester.pumpAndSettle();

    final messageField = tester.widget<TextField>(
      find.byKey(const Key('posting-composer-message-input')),
    );
    final controller = messageField.controller!;
    expect(controller.text, '[url=https://example.com]示例链接[/url]');
    expect(controller.selection.baseOffset, controller.text.length);
  });

  testWidgets('PostingComposerPage warns restored draft includes tags', (
    tester,
  ) async {
    final draftRepository = _MemoryDraftRepository();
    await draftRepository.saveDraft(
      ComposerDraftSnapshot(
        identity: const ComposerDraftIdentity.newThread(fid: '33'),
        subject: '草稿标题',
        message: '草稿正文',
        useSignature: true,
        updatedAt: DateTime.now(),
        extras: const <String, String>{'tags': '标签一'},
      ),
    );

    await tester.pumpWidget(
      _buildPage(
        draftRepository: draftRepository,
        metadataRepository: _FakeMetadataRepository.success(_metadata()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已恢复未发送的草稿，请注意已恢复的主题标签'), findsOneWidget);
    expect(find.text('已恢复未发送草稿'), findsNothing);
  });

  testWidgets(
    'PostingComposerPage resets persisted title and message after confirmation',
    (tester) async {
      const identity = ComposerDraftIdentity.newThread(fid: '33');
      final draftRepository = _MemoryDraftRepository();
      await draftRepository.saveDraft(
        ComposerDraftSnapshot(
          identity: identity,
          subject: '草稿标题',
          message: '草稿正文',
          useSignature: false,
          updatedAt: DateTime.now(),
          extras: const <String, String>{'tags': '标签一'},
        ),
      );
      await tester.pumpWidget(
        _buildPage(
          draftRepository: draftRepository,
          metadataRepository: _FakeMetadataRepository.success(_metadata()),
        ),
      );
      await tester.pumpAndSettle();
      await _enterPostingSourceMode(tester);

      await tester.tap(find.byKey(const Key('posting-composer-more-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('posting-composer-reset-draft-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('重置草稿？'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('posting-composer-reset-confirm-button')),
      );
      await tester.pumpAndSettle();

      final subjectField = tester.widget<TextField>(
        find.byKey(const Key('posting-composer-subject-input')),
      );
      final messageField = tester.widget<TextField>(
        find.byKey(const Key('posting-composer-message-input')),
      );
      expect(subjectField.controller?.text, isEmpty);
      expect(messageField.controller?.text, isEmpty);
      expect(await draftRepository.loadDraft(identity), isNull);

      await tester.tap(find.byKey(const Key('posting-composer-more-button')));
      await tester.pumpAndSettle();
      final signatureSwitch = tester.widget<SwitchListTile>(
        find.byKey(const Key('posting-composer-use-signature-switch')),
      );
      expect(signatureSwitch.value, isFalse);
      final resetTile = tester.widget<ListTile>(
        find.byKey(const Key('posting-composer-reset-draft-button')),
      );
      expect(resetTile.enabled, isFalse);
    },
  );

  testWidgets('PostingComposerPage moves posting options into more sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildPage(
        metadataRepository: _FakeMetadataRepository.success(_metadata()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('posting-composer-use-signature-switch')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('posting-composer-allow-notice-author-switch')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('posting-composer-bbcode-off-switch')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('posting-composer-smiley-off-switch')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('posting-composer-parseurl-off-switch')),
      findsNothing,
    );
    expect(find.byKey(const Key('posting-composer-tags-field')), findsNothing);
    expect(
      find.byKey(const Key('posting-composer-special-switch')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('posting-composer-more-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('posting-composer-settings-sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('posting-composer-tags-field')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('posting-composer-tags-input')),
      '标签一,',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('posting-composer-tag-chip-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('posting-composer-use-signature-switch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('posting-composer-allow-notice-author-switch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('posting-composer-bbcode-off-switch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('posting-composer-smiley-off-switch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('posting-composer-parseurl-off-switch')),
      findsOneWidget,
    );

    final signatureSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('posting-composer-use-signature-switch')),
    );
    expect(signatureSwitch.value, isTrue);
    await tester.tap(
      find.byKey(const Key('posting-composer-use-signature-switch')),
    );
    await tester.pumpAndSettle();
    final toggledSignatureSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('posting-composer-use-signature-switch')),
    );
    expect(toggledSignatureSwitch.value, isFalse);
  });

  testWidgets(
    'PostingComposerPage shows metadata loading SnackBar first frame',
    (tester) async {
      final completer = Completer<void>();
      final metadataRepository = _FakeMetadataRepository.heldSuccess(
        _metadata(),
        completer.future,
      );

      await tester.pumpWidget(
        _buildPage(metadataRepository: metadataRepository),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('posting-composer-metadata-loading')),
        findsNothing,
      );
      expect(find.text('正在加载发帖表单'), findsOneWidget);
      // 加载中时 AppBar 标题回退到"发帖"。
      expect(find.text('发帖'), findsOneWidget);

      // 解开 metadata 拉取，避免悬挂 future。
      completer.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'PostingComposerPage shows AppBar with forum name after metadata load',
    (tester) async {
      await tester.pumpWidget(
        _buildPage(
          metadataRepository: _FakeMetadataRepository.success(
            _metadata(forumName: '日常版'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('发帖 — 日常版'), findsOneWidget);
      expect(
        find.byKey(const Key('posting-composer-metadata-loading')),
        findsNothing,
      );
    },
  );

  testWidgets('PostingComposerPage shows metadata error and retries', (
    tester,
  ) async {
    final metadataRepository = _FakeMetadataRepository.failure(
      const ApiError(type: ApiErrorType.network, message: '网络挂了'),
    );

    await tester.pumpWidget(_buildPage(metadataRepository: metadataRepository));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('posting-composer-metadata-error')),
      findsOneWidget,
    );
    expect(find.textContaining('网络挂了'), findsOneWidget);

    metadataRepository.queueSuccess(_metadata());
    await tester.tap(
      find.byKey(const Key('posting-composer-metadata-retry-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('posting-composer-metadata-error')),
      findsNothing,
    );
    expect(find.text('发帖 — 日常版'), findsOneWidget);
    expect(metadataRepository.callCount, 2);
  });

  testWidgets(
    'PostingComposerPage send button is disabled when required type is unselected',
    (tester) async {
      await tester.pumpWidget(
        _buildPage(
          metadataRepository: _FakeMetadataRepository.success(
            _metadata(typeRequired: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _enterPostingSourceMode(tester);
      // 输入标题 + 正文，但没选分类。
      await tester.enterText(
        find.byKey(const Key('posting-composer-subject-input')),
        '我的标题',
      );
      await tester.enterText(
        find.byKey(const Key('posting-composer-message-input')),
        '正文',
      );
      await tester.pump();

      final sendButton = tester.widget<IconButton>(
        find.byKey(const Key('posting-composer-send-button')),
      );
      expect(sendButton.onPressed, isNull);

      await tester.ensureVisible(
        find.byKey(const Key('posting-composer-type-toggle')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('posting-composer-type-toggle')));
      await tester.pumpAndSettle();
      // 选了分类之后按钮启用。
      await tester.tap(find.byKey(const Key('posting-composer-type-111')));
      await tester.pumpAndSettle();
      final enabledSend = tester.widget<IconButton>(
        find.byKey(const Key('posting-composer-send-button')),
      );
      expect(enabledSend.onPressed, isNotNull);
    },
  );

  testWidgets(
    'PostingComposerPage hides type selector when forum has no thread types',
    (tester) async {
      await tester.pumpWidget(
        _buildPage(
          metadataRepository: _FakeMetadataRepository.success(
            _metadata(types: const []),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _enterPostingSourceMode(tester);
      expect(
        find.byKey(const Key('posting-composer-type-selector')),
        findsNothing,
      );
      // 标题 + 正文非空时，"无分类"逻辑等价 typeid='0'，可以提交。
      await tester.enterText(
        find.byKey(const Key('posting-composer-subject-input')),
        '标题',
      );
      await tester.enterText(
        find.byKey(const Key('posting-composer-message-input')),
        '正文',
      );
      await tester.pump();
      final sendButton = tester.widget<IconButton>(
        find.byKey(const Key('posting-composer-send-button')),
      );
      expect(sendButton.onPressed, isNotNull);
    },
  );

  testWidgets(
    'PostingComposerPage type selector hides "无分类" when type is required',
    (tester) async {
      await tester.pumpWidget(
        _buildPage(
          metadataRepository: _FakeMetadataRepository.success(
            _metadata(typeRequired: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('posting-composer-type-none')), findsNothing);
      expect(find.byKey(const Key('posting-composer-type-111')), findsNothing);

      await tester.tap(find.byKey(const Key('posting-composer-type-toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('posting-composer-type-none')), findsNothing);
      expect(
        find.byKey(const Key('posting-composer-type-111')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('posting-composer-type-222')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'PostingComposerPage places required type and special dropdowns in one row',
    (tester) async {
      await tester.pumpWidget(
        _buildPage(
          metadataRepository: _FakeMetadataRepository.success(
            _metadata(typeRequired: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('未选择'), findsOneWidget);
      expect(find.byKey(const Key('posting-composer-type-111')), findsNothing);
      final typeSize = tester.getSize(
        find.byKey(const Key('posting-composer-type-toggle')),
      );
      final specialSize = tester.getSize(
        find.byKey(const Key('posting-composer-special-switch')),
      );
      final typeTopLeft = tester.getTopLeft(
        find.byKey(const Key('posting-composer-type-toggle')),
      );
      final specialTopLeft = tester.getTopLeft(
        find.byKey(const Key('posting-composer-special-switch')),
      );
      final quillTopLeft = tester.getTopLeft(
        find.byKey(const Key('posting-composer-quill-editor')),
      );
      expect((typeSize.width - specialSize.width).abs(), lessThan(1));
      expect(typeTopLeft.dy, specialTopLeft.dy);
      expect(specialTopLeft.dx, greaterThan(typeTopLeft.dx));
      expect(
        quillTopLeft.dy -
            tester
                .getBottomLeft(
                  find.byKey(const Key('posting-composer-special-switch')),
                )
                .dy,
        lessThan(64),
      );

      final switchTopBefore = tester.getTopLeft(
        find.byKey(const Key('posting-composer-special-switch')),
      );
      await tester.tap(find.byKey(const Key('posting-composer-type-toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));

      final openArrowFinder = find.descendant(
        of: find.byKey(const Key('posting-composer-type-toggle')),
        matching: find.byType(RotationTransition),
      );
      final openArrow =
          openArrowFinder.evaluate().single.widget as RotationTransition;
      expect(openArrow.turns.value, 0.5);

      expect(
        find.byKey(const Key('posting-composer-type-111')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('posting-composer-type-111')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('posting-composer-type-111')), findsNothing);
      final summary = tester.widget<Text>(
        find.byKey(const Key('posting-composer-type-summary')),
      );
      expect(summary.data, '日常');
      expect(
        tester.getTopLeft(
          find.byKey(const Key('posting-composer-special-switch')),
        ),
        switchTopBefore,
      );

      await tester.tap(
        find.byKey(const Key('posting-composer-special-switch')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(
        find.byKey(const Key('posting-composer-special-poll')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('posting-composer-special-poll')));
      await tester.pumpAndSettle();

      final specialSummary = tester.widget<Text>(
        find.byKey(const Key('posting-composer-special-summary')),
      );
      expect(specialSummary.data, '投票');
      expect(
        find.byKey(const Key('posting-composer-poll-config-toggle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('posting-composer-poll-config-summary')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('posting-composer-poll-config-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('posting-composer-poll-editor')),
        findsOneWidget,
      );
      final visibleQuillAfterPoll = find.byKey(
        const Key('posting-composer-quill-editor'),
      );
      if (visibleQuillAfterPoll.evaluate().isNotEmpty) {
        expect(
          tester
              .getBottomLeft(
                find.byKey(const Key('posting-composer-poll-config-panel')),
              )
              .dy,
          lessThanOrEqualTo(tester.getTopLeft(visibleQuillAfterPoll).dy),
        );
      }

      await tester.tap(
        find.byKey(const Key('posting-composer-poll-config-toggle')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('posting-composer-poll-config-toggle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('posting-composer-poll-config-panel')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('posting-composer-poll-editor')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('posting-composer-quill-editor')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('posting-composer-format-button')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('posting-composer-poll-config-toggle')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('posting-composer-poll-config-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('posting-composer-poll-editor')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('posting-composer-special-switch')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('posting-composer-special-normal')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('posting-composer-poll-config-toggle')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('posting-composer-poll-config-panel')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'PostingComposerPage edits expandable poll config and submits payload',
    (tester) async {
      final newThreadRepository = _FakeNewThreadRepository();
      await tester.pumpWidget(
        _buildLauncher(
          newThreadRepository: newThreadRepository,
          metadataRepository: _FakeMetadataRepository.success(_metadata()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-posting-composer-page')));
      await tester.pumpAndSettle();

      await _enterPostingSourceMode(tester);
      await tester.enterText(
        find.byKey(const Key('posting-composer-subject-input')),
        '投票标题',
      );
      await tester.enterText(
        find.byKey(const Key('posting-composer-message-input')),
        '投票正文',
      );
      await tester.tap(
        find.byKey(const Key('posting-composer-special-switch')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('posting-composer-special-poll')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('posting-composer-poll-config-panel')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('posting-composer-poll-add-option')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('posting-composer-poll-add-option')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('posting-composer-poll-option-0')),
        '选项 A',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('posting-composer-poll-option-1')),
        '选项 B',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('posting-composer-poll-multiple-switch')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('posting-composer-poll-multiple-switch')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('posting-composer-poll-expiration')),
      );
      await tester.enterText(
        find.byKey(const Key('posting-composer-poll-expiration')),
        '7',
      );
      await tester.pumpAndSettle();

      final summary = tester.widget<Text>(
        find.byKey(const Key('posting-composer-poll-config-summary')),
      );
      expect(summary.data, '已填 2 项 / 多选');
      await tester.tap(find.byKey(const Key('posting-composer-send-button')));
      await tester.pumpAndSettle();

      expect(newThreadRepository.submittedPayloads, hasLength(1));
      final payload = newThreadRepository.submittedPayloads.single;
      expect(payload.subject, '投票标题');
      expect(payload.message, '投票正文');
      expect(payload.special, NewThreadSpecial.poll);
      expect(payload.poll, isNotNull);
      expect(payload.poll!.options, const ['选项 A', '选项 B']);
      expect(payload.poll!.multiple, isTrue);
      expect(payload.poll!.maxChoices, 2);
      expect(payload.poll!.expirationDays, 7);
    },
  );

  testWidgets(
    'PostingComposerPage shows length counters when metadata declares limits',
    (tester) async {
      await tester.pumpWidget(
        _buildPage(
          metadataRepository: _FakeMetadataRepository.success(
            const NewThreadFormMetadata(
              fid: '33',
              forumName: '日常版',
              formHash: 'fh',
              threadTypes: <ThreadType>[],
              threadSorts: <ThreadSort>[],
              typeRequired: false,
              sortRequired: false,
              maxSubjectLength: 5,
              maxMessageLength: 10,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _enterPostingSourceMode(tester);
      // 没输入时计数显示 0/limit。
      // 加了 tags / special switch / poll 配置入口之后，message-counter 在窄
      // 视口下被推到 fold 之外。ListView 对屏外子项不建 element，
      // ensureVisible 拿不到 element 会抛 No element。所以分两阶段断言：
      //   1) 滚之前 subject-counter 在 viewport 顶部，能直接断言 "0 / 5"。
      //   2) scrollUntilVisible 把 message-counter 滚进来，再断言 "0 / 10"。
      // 不要在滚动后回头断言 subject 的文本——滚远了 ListView 可能已经把
      // 旧 element 释放，find.text 会丢。
      // page 里 TextField 内部也有 Scrollable，所以显式锁定到外层 ListView，
      // 否则默认 find.byType(Scrollable) 命中多个会抛 single 异常。
      expect(
        find.byKey(const Key('posting-composer-subject-counter')),
        findsOneWidget,
      );
      expect(find.text('0 / 5'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('posting-composer-message-counter')),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const Key('posting-composer-message-counter')),
        findsOneWidget,
      );
      expect(find.text('0 / 10'), findsOneWidget);

      // 把 ListView 滚回顶部再输入 subject——否则输入框可能已经在屏外，
      // enterText 会失败。
      await tester.scrollUntilVisible(
        find.byKey(const Key('posting-composer-subject-input')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const Key('posting-composer-subject-input')),
        '六个字符的标题',
      );
      // 滚回正文输入框再敲正文。
      await tester.scrollUntilVisible(
        find.byKey(const Key('posting-composer-message-input')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const Key('posting-composer-message-input')),
        '正文',
      );
      await tester.pump();

      // 标题超限后发送按钮禁用；先把 subject-counter 滚回视口再断言文本。
      await tester.scrollUntilVisible(
        find.byKey(const Key('posting-composer-subject-counter')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('7 / 5'), findsOneWidget);
      final sendButton = tester.widget<IconButton>(
        find.byKey(const Key('posting-composer-send-button')),
      );
      expect(sendButton.onPressed, isNull);
    },
  );

  testWidgets('PostingComposerPage reports uploaded image with SnackBar', (
    tester,
  ) async {
    final imagePicker = _FakeImagePicker(
      images: const [
        ComposerPickedImage(
          path: '/gallery/first.jpg',
          fileName: 'first.jpg',
          mimeType: 'image/jpeg',
          originalIndex: 0,
        ),
      ],
    );
    final uploadCoordinator = _FakeUploadCoordinator(
      events: [
        ComposerImageUploadEvent.uploaded(
          localId: '',
          current: 1,
          total: 1,
          uploadedImage: ComposerUploadedImage(
            localId: '',
            aid: '777',
            uploadedAt: DateTime.now(),
          ),
        ),
        const ComposerImageUploadEvent.completed(total: 1),
      ],
    );
    await tester.pumpWidget(
      _buildPage(
        imagePicker: imagePicker,
        imageUploadCoordinator: uploadCoordinator,
        metadataRepository: _FakeMetadataRepository.success(_metadata()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('posting-composer-image-queue')), findsNothing);
    await tester.tap(find.byKey(const Key('posting-composer-image-button')));
    await tester.pump();
    await tester.pump();

    expect(imagePicker.pickCallCount, 1);
    expect(find.byKey(const Key('posting-composer-image-queue')), findsNothing);
    expect(find.text('first.jpg 已上传'), findsOneWidget);
  });

  testWidgets('PostingComposerPage submits and pops sent result', (
    tester,
  ) async {
    final newThreadRepository = _FakeNewThreadRepository();
    PostingComposerResult? popped;
    await tester.pumpWidget(
      _buildLauncher(
        newThreadRepository: newThreadRepository,
        metadataRepository: _FakeMetadataRepository.success(_metadata()),
        onResult: (r) => popped = r,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-posting-composer-page')));
    await tester.pumpAndSettle();

    await _enterPostingSourceMode(tester);
    await tester.enterText(
      find.byKey(const Key('posting-composer-subject-input')),
      '标题',
    );
    await tester.enterText(
      find.byKey(const Key('posting-composer-message-input')),
      '正文',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('posting-composer-send-button')));
    await tester.pumpAndSettle();

    expect(newThreadRepository.submittedPayloads, hasLength(1));
    expect(newThreadRepository.submittedPayloads.single.subject, '标题');
    expect(newThreadRepository.submittedPayloads.single.message, '正文');
    expect(popped?.sent, isTrue);
    expect(popped?.tid, '900001');
    expect(popped?.pid, '910001');
  });

  testWidgets(
    'PostingComposerPage confirms leaving with unsent input and saves draft',
    (tester) async {
      final draftRepository = _MemoryDraftRepository();
      await tester.pumpWidget(
        _buildLauncher(
          draftRepository: draftRepository,
          metadataRepository: _FakeMetadataRepository.success(_metadata()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-posting-composer-page')));
      await tester.pumpAndSettle();

      await _enterPostingSourceMode(tester);
      await tester.enterText(
        find.byKey(const Key('posting-composer-subject-input')),
        '草稿标题',
      );
      await tester.enterText(
        find.byKey(const Key('posting-composer-message-input')),
        '草稿正文',
      );
      await tester.pump();

      // 触发系统返回——通过 AppBar 上的 back button。
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('保存草稿并离开？'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('posting-composer-save-leave-button')),
      );
      await tester.pumpAndSettle();

      const identity = ComposerDraftIdentity.newThread(fid: '33');
      final saved = await draftRepository.loadDraft(identity);
      expect(saved?.subject, '草稿标题');
      expect(saved?.message, '草稿正文');
    },
  );
}

Future<void> _enterPostingSourceMode(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('posting-composer-source-button')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('posting-composer-source-view')), findsOneWidget);
}
