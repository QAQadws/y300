import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/composer_shared/data/repositories/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/services/composer_image_picker.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/data/repositories/sticker_picker_preferences_repository.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_attachment_verification_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_unused_image_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_failure_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_preferences_repository.dart';
import 'package:y300/features/composer_shared/domain/services/composer_draft_attachment_sanitizer.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_service.dart';
import 'package:y300/features/composer_shared/domain/services/composer_draft_attachment_verification_service.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/reply/data/providers/reply_providers.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/presentation/reply_composer_page.dart';
import 'package:y300/features/reply/presentation/reply_composer_state.dart';

const _replyApplied = DataCommandApplied<ThreadReplyReceipt>(
  ThreadReplyReceipt(
    tid: '572063',
    pid: '41554318',
    publicationState: ThreadPublicationState.published,
  ),
);

void main() {
  testWidgets('ReplyComposerPage builds dark theme chrome', (tester) async {
    await tester.pumpWidget(_buildPage(theme: AppTheme.dark()));
    await tester.pump();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(
      find.byKey(const Key('reply-composer-quill-editor')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reply-composer-send-button')), findsOneWidget);
  });

  testWidgets('ReplyComposerPage localizes chrome and preserves raw reply', (
    tester,
  ) async {
    const rawReply = '[quote]引用原文[/quote]\n简体與繁體';
    await tester.pumpWidget(_buildPage(locale: const Locale('zh', 'TW')));
    await tester.pumpAndSettle();

    expect(find.text('回覆帖子'), findsOneWidget);
    expect(find.byTooltip('送出'), findsOneWidget);
    await _enterReplySourceText(tester, rawReply);
    final field = tester.widget<TextField>(
      find.byKey(const Key('reply-composer-message-input')),
    );
    expect(field.controller?.text, rawReply);
  });

  testWidgets('ReplyComposerPage shows minimal composer UI', (tester) async {
    await tester.pumpWidget(_buildPage());
    await tester.pump();

    expect(find.text('回复帖子'), findsOneWidget);
    expect(find.text('预览'), findsNothing);
    expect(
      find.byKey(const Key('reply-composer-source-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reply-composer-more-button')), findsOneWidget);
    expect(
      find.byKey(const Key('reply-composer-sticker-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reply-composer-format-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reply-composer-color-button')), findsNothing);
    expect(
      find.byKey(const Key('reply-composer-backcolor-button')),
      findsNothing,
    );
    expect(find.byKey(const Key('reply-composer-link-button')), findsOneWidget);
    expect(find.byKey(const Key('reply-composer-size-button')), findsNothing);
    expect(
      find.byKey(const Key('reply-composer-quote-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reply-composer-code-button')), findsNothing);
    expect(
      find.byKey(const Key('reply-composer-align-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reply-composer-message-input')), findsNothing);
    expect(
      find.byKey(const Key('reply-composer-bbcode-preview-panel')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('reply-composer-use-signature-switch')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('reply-composer-image-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reply-composer-send-button')), findsOneWidget);
  });

  testWidgets('ReplyComposerPage restores and updates the default surface', (
    tester,
  ) async {
    final preferencesRepository = _FakeComposerPreferencesRepository(
      preferences: const ComposerPreferences(
        defaultSurface: ComposerSurfacePreference.source,
        newDraftUseSignature: true,
      ),
    );
    await tester.pumpWidget(
      _buildPage(preferencesRepository: preferencesRepository),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('reply-composer-message-input')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reply-composer-quill-editor')), findsNothing);

    await tester.tap(find.byKey(const Key('reply-composer-source-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('reply-composer-quill-editor')),
      findsOneWidget,
    );
    expect(
      preferencesRepository.preferences.defaultSurface,
      ComposerSurfacePreference.quill,
    );
  });

  testWidgets('ReplyComposerPage wraps selection with quote BBCode', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage());
    await tester.pump();
    await _enterReplySourceText(tester, '前引用后');
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    editable.controller.selection = const TextSelection(
      baseOffset: 1,
      extentOffset: 3,
    );

    await tester.tap(find.byKey(const Key('reply-composer-quote-button')));
    await tester.pump();

    expect(editable.controller.text, '前[quote]引用[/quote]后');
  });

  testWidgets('ReplyComposerPage wraps selection from text context menu', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage());
    await tester.pump();
    await _enterReplySourceText(tester, '前选中后');
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    editable.controller.selection = const TextSelection(
      baseOffset: 1,
      extentOffset: 3,
    );
    tester.state<EditableTextState>(find.byType(EditableText)).showToolbar();
    await tester.pumpAndSettle();

    expect(find.text('代码'), findsNothing);

    await tester.tap(find.text('引用'));
    await tester.pumpAndSettle();

    expect(editable.controller.text, '前[quote]选中[/quote]后');
  });

  testWidgets('ReplyComposerPage inserts picked backcolor BBCode', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage());
    await tester.pump();
    await _openReplySourceEditor(tester);

    await tester.tap(find.byKey(const Key('reply-composer-backcolor-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('reply-composer-backcolor-sheet')),
      findsOneWidget,
    );
    final picker = tester.widget<ColorPicker>(
      find.byKey(const Key('reply-composer-backcolor-picker')),
    );
    picker.onColorChanged(const Color(0xffff33aa));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('reply-composer-backcolor-use-button')),
    );
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.controller.text, '[backcolor=#ff33aa][/backcolor]');
    expect(editable.controller.selection.baseOffset, 19);
    expect(editable.controller.selection.extentOffset, 19);
  });

  testWidgets('ReplyComposerPage places more action before image and send', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage());
    await tester.pump();

    final moreCenter = tester.getCenter(
      find.byKey(const Key('reply-composer-more-button')),
    );
    final sendCenter = tester.getCenter(
      find.byKey(const Key('reply-composer-send-button')),
    );

    final sourceCenter = tester.getCenter(
      find.byKey(const Key('reply-composer-source-button')),
    );

    expect(sourceCenter.dx, lessThan(moreCenter.dx));
    expect(moreCenter.dx, lessThan(sendCenter.dx));
  });

  testWidgets('ReplyComposerPage keeps Quill toolbar pinned to bottom', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage());
    await tester.pump();

    final scaffoldBottom = tester.getBottomLeft(find.byType(Scaffold)).dy;
    final imageButtonBottom = tester
        .getBottomLeft(find.byKey(const Key('reply-composer-image-button')))
        .dy;

    expect(scaffoldBottom - imageButtonBottom, lessThan(64));
  });

  testWidgets('ReplyComposerPage restores draft into input', (tester) async {
    final args = _threadArgs();
    final draftRepository = _MemoryReplyDraftRepository();
    await draftRepository.saveDraft(
      ReplyDraftSnapshot(
        identity: args.identity,
        message: '恢复的草稿',
        useSignature: false,
        updatedAt: DateTime.utc(2026, 6, 6),
      ),
    );

    await tester.pumpWidget(
      _buildPage(args: args, draftRepository: draftRepository),
    );
    await tester.pump();
    await tester.pump();

    await _openReplySourceEditor(tester);
    final restoredField = tester.widget<TextField>(
      find.byKey(const Key('reply-composer-message-input')),
    );
    expect(restoredField.controller?.text, '恢复的草稿');
    expect(find.text('已恢复未发送草稿'), findsOneWidget);
    expect(
      find.byKey(const Key('reply-composer-restored-draft-banner')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('reply-composer-use-signature-switch')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('reply-composer-more-button')));
    await tester.pumpAndSettle();
    final switchTile = tester.widget<SwitchListTile>(
      find.byKey(const Key('reply-composer-use-signature-switch')),
    );
    expect(switchTile.value, isFalse);
    await tester.tap(
      find.byKey(const Key('reply-composer-use-signature-switch')),
    );
    await tester.pumpAndSettle();
    final toggledSwitchTile = tester.widget<SwitchListTile>(
      find.byKey(const Key('reply-composer-use-signature-switch')),
    );
    expect(toggledSwitchTile.value, isTrue);
  });

  testWidgets('ReplyComposerPage restores uploaded image without upload UI', (
    tester,
  ) async {
    final args = _threadArgs();
    final draftRepository = _MemoryReplyDraftRepository();
    await draftRepository.saveDraft(
      ReplyDraftSnapshot(
        identity: args.identity,
        message: '正文\n[attach]123456[/attach]',
        useSignature: true,
        updatedAt: DateTime.utc(2026, 6, 8),
        imageAttachments: [
          _uploadedAttachment(
            localId: 'image-1',
            aid: '123456',
            uploadedAt: DateTime.utc(2026, 6, 8, 10),
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _buildPage(args: args, draftRepository: draftRepository),
    );
    await tester.pump();

    expect(find.byKey(const Key('reply-composer-image-queue')), findsNothing);
    expect(find.textContaining('已上传'), findsNothing);
    expect(
      find.byKey(const Key('composer-quill-attach-123456')),
      findsOneWidget,
    );
  });

  testWidgets('ReplyComposerPage resets persisted content after confirmation', (
    tester,
  ) async {
    final args = _threadArgs();
    final draftRepository = _MemoryReplyDraftRepository();
    await draftRepository.saveDraft(
      ReplyDraftSnapshot(
        identity: args.identity,
        message: '正文\n[attach]123456[/attach]',
        useSignature: false,
        updatedAt: DateTime.now(),
        imageAttachments: [
          _uploadedAttachment(
            localId: 'image-1',
            aid: '123456',
            uploadedAt: DateTime.now(),
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _buildPage(args: args, draftRepository: draftRepository),
    );
    await tester.pumpAndSettle();
    await _openReplySourceEditor(tester);

    await tester.tap(find.byKey(const Key('reply-composer-more-button')));
    await tester.pumpAndSettle();
    final resetTile = tester.widget<ListTile>(
      find.byKey(const Key('reply-composer-reset-draft-button')),
    );
    expect(resetTile.enabled, isTrue);

    await tester.tap(
      find.byKey(const Key('reply-composer-reset-draft-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('重置草稿？'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('reply-composer-reset-cancel-button')),
    );
    await tester.pumpAndSettle();
    var messageField = tester.widget<TextField>(
      find.byKey(const Key('reply-composer-message-input')),
    );
    expect(messageField.controller?.text, contains('正文'));

    await tester.tap(find.byKey(const Key('reply-composer-more-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('reply-composer-reset-draft-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('reply-composer-reset-confirm-button')),
    );
    await tester.pumpAndSettle();

    messageField = tester.widget<TextField>(
      find.byKey(const Key('reply-composer-message-input')),
    );
    expect(messageField.controller?.text, isEmpty);
    expect(find.byKey(const Key('reply-composer-image-queue')), findsNothing);
    expect(await draftRepository.loadDraft(args.identity), isNull);

    await tester.tap(find.byKey(const Key('reply-composer-more-button')));
    await tester.pumpAndSettle();
    final signatureSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('reply-composer-use-signature-switch')),
    );
    expect(signatureSwitch.value, isFalse);
    final disabledResetTile = tester.widget<ListTile>(
      find.byKey(const Key('reply-composer-reset-draft-button')),
    );
    expect(disabledResetTile.enabled, isFalse);
  });

  testWidgets('ReplyComposerPage restores uploaded attach embed', (
    tester,
  ) async {
    const path = 'E:/test/reply/restored.png';
    final args = _threadArgs();
    final draftRepository = _MemoryReplyDraftRepository();
    await draftRepository.saveDraft(
      ReplyDraftSnapshot(
        identity: args.identity,
        message: '正文\n[attach]123456[/attach]',
        useSignature: true,
        updatedAt: DateTime.utc(2026, 6, 8),
        imageAttachments: [
          _uploadedAttachment(
            localId: 'image-1',
            aid: '123456',
            uploadedAt: DateTime.utc(2026, 6, 8, 10),
            localPath: path,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _buildPage(args: args, draftRepository: draftRepository),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('composer-quill-attach-123456')),
      findsOneWidget,
    );
    expect(
      find.textContaining('[attach]123456[/attach]', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('ReplyComposerPage keeps remote-valid image after cache expiry', (
    tester,
  ) async {
    final args = _threadArgs();
    final draftRepository = _MemoryReplyDraftRepository(
      now: () => DateTime.utc(2026, 6, 8, 12),
    );
    await draftRepository.saveDraft(
      ReplyDraftSnapshot(
        identity: args.identity,
        message: '正文\n[attach]123456[/attach]',
        useSignature: true,
        updatedAt: DateTime.utc(2026, 6, 8),
        imageAttachments: [
          _uploadedAttachment(
            localId: 'expired',
            aid: '123456',
            uploadedAt: DateTime.utc(2026, 5, 24, 12),
            cachePath: '/cache/expired.jpg',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _buildPage(
        args: args,
        draftRepository: draftRepository,
        draftVerificationService: const _PassThroughDraftVerificationService(),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('composer-quill-attach-123456')),
      findsOneWidget,
    );
    await _openReplySourceEditor(tester);
    final sanitizedField = tester.widget<TextField>(
      find.byKey(const Key('reply-composer-message-input')),
    );
    expect(sanitizedField.controller?.text, '正文\n[attach]123456[/attach]');
  });

  testWidgets('ReplyComposerPage reports failed draft image verification', (
    tester,
  ) async {
    final args = _threadArgs();
    final draftRepository = _MemoryReplyDraftRepository();
    await draftRepository.saveDraft(
      ReplyDraftSnapshot(
        identity: args.identity,
        message: '正文\n[attach]123456[/attach]',
        useSignature: true,
        updatedAt: DateTime.utc(2026, 8, 3),
        imageAttachments: [
          _uploadedAttachment(
            localId: 'image-1',
            aid: '123456',
            uploadedAt: DateTime.utc(2026, 8, 3),
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _buildPage(
        args: args,
        draftRepository: draftRepository,
        draftVerificationService:
            const _FailedDraftAttachmentVerificationService(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('reply-composer-draft-image-verification-error')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reply-composer-retry-draft-image-verification')),
      findsOneWidget,
    );
    final sendButton = tester.widget<IconButton>(
      find.byKey(const Key('reply-composer-send-button')),
    );
    expect(sendButton.onPressed, isNotNull);
  });

  testWidgets('ReplyComposerPage reports invalid images but keeps BBCode', (
    tester,
  ) async {
    final args = _threadArgs();
    final draftRepository = _MemoryReplyDraftRepository();
    await draftRepository.saveDraft(
      ReplyDraftSnapshot(
        identity: args.identity,
        message: '正文\n[attach]123456[/attach]',
        useSignature: true,
        updatedAt: DateTime.utc(2026, 8, 3),
        imageAttachments: [
          _uploadedAttachment(
            localId: 'image-1',
            aid: '123456',
            uploadedAt: DateTime.utc(2026, 8, 3),
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _buildPage(
        args: args,
        draftRepository: draftRepository,
        draftVerificationService:
            const _InvalidDraftAttachmentVerificationService(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('reply-composer-invalid-draft-images-snackbar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reply-composer-invalid-draft-images')),
      findsNothing,
    );

    // A normal page rebuild must not enqueue the same verification result again.
    await tester.tap(find.byKey(const Key('reply-composer-source-button')));
    await tester.pump();
    expect(
      find.byKey(const Key('reply-composer-invalid-draft-images-snackbar')),
      findsOneWidget,
    );

    await _openReplySourceEditor(tester);
    final source = tester.widget<TextField>(
      find.byKey(const Key('reply-composer-message-input')),
    );
    expect(source.controller?.text, '正文\n[attach]123456[/attach]');
  });

  testWidgets('ReplyComposerPage keeps send disabled for empty input', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage());
    await tester.pump();

    final sendButton = tester.widget<IconButton>(
      find.byKey(const Key('reply-composer-send-button')),
    );
    expect(sendButton.onPressed, isNull);
  });

  testWidgets('ReplyComposerPage switches source and Quill editor', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage());
    await tester.pump();

    expect(
      find.byKey(const Key('reply-composer-quill-editor')),
      findsOneWidget,
    );
    await _enterReplySourceText(tester, '[b]粗体内容[/b]');
    await tester.pump();

    expect(
      find.byKey(const Key('reply-composer-bbcode-preview-panel')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('reply-composer-message-input')),
      findsOneWidget,
    );
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.controller.text, '[b]粗体内容[/b]');
    final sourceField = tester.widget<TextField>(
      find.byKey(const Key('reply-composer-message-input')),
    );
    final decoration = sourceField.decoration;
    expect(decoration?.border, InputBorder.none);
    expect(decoration?.enabledBorder, InputBorder.none);
    expect(decoration?.focusedBorder, InputBorder.none);
    expect(decoration?.disabledBorder, InputBorder.none);
    expect(decoration?.filled, isFalse);
    expect(decoration?.fillColor, isNull);

    await tester.tap(find.byKey(const Key('reply-composer-source-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('reply-composer-quill-editor')),
      findsOneWidget,
    );
    expect(find.text('粗体内容', findRichText: true), findsOneWidget);
  });

  testWidgets('ReplyComposerPage pops sent result after successful submit', (
    tester,
  ) async {
    final replyRepository = _FakeThreadReplyAdapter(result: _replyApplied);
    ReplyComposerResult? poppedResult;

    await tester.pumpWidget(
      _buildLauncher(
        replyRepository: replyRepository,
        onResult: (result) {
          poppedResult = result;
        },
      ),
    );

    await tester.tap(find.byKey(const Key('open-reply-composer-page')));
    await tester.pumpAndSettle();
    await _enterReplySourceText(tester, '提交内容');
    await tester.pump();
    await tester.tap(find.byKey(const Key('reply-composer-send-button')));
    await tester.pumpAndSettle();

    expect(replyRepository.sentDrafts.single.message, '提交内容');
    expect(poppedResult?.sent, isTrue);
    expect(poppedResult?.rawSuccessDetail, isNull);
  });

  testWidgets('ReplyComposerPage submits raw source message from source mode', (
    tester,
  ) async {
    final replyRepository = _FakeThreadReplyAdapter(result: _replyApplied);

    await tester.pumpWidget(_buildLauncher(replyRepository: replyRepository));

    await tester.tap(find.byKey(const Key('open-reply-composer-page')));
    await tester.pumpAndSettle();
    await _enterReplySourceText(tester, '[quote]原始源码[/quote]');
    await tester.pump();
    await tester.tap(find.byKey(const Key('reply-composer-send-button')));
    await tester.pumpAndSettle();

    expect(replyRepository.sentDrafts.single.message, '[quote]原始源码[/quote]');
  });

  testWidgets('ReplyComposerPage inserts sticker code at cursor position', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage(stickerGroups: _stickerGroups));
    await tester.pump();
    await _enterReplySourceText(tester, '前后');
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    editable.controller.selection = const TextSelection.collapsed(offset: 1);

    await tester.tap(find.byKey(const Key('reply-composer-sticker-button')));
    await tester.pumpAndSettle();
    expect(find.text('貓貓蟲'), findsOneWidget);
    expect(find.text('{:9_656:}'), findsNothing);
    await tester.tap(find.byKey(const Key('reply-sticker-item-{:9_656:}')));
    await tester.pumpAndSettle();

    expect(find.text('前{:9_656:}后'), findsOneWidget);
  });

  testWidgets('ReplyComposerPage shows inserted sticker as Quill embed', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage(stickerGroups: _stickerGroups));
    await tester.pump();
    await _enterReplySourceText(tester, '{:9_656:}');
    await tester.pump();
    await tester.tap(find.byKey(const Key('reply-composer-source-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('composer-quill-sticker-{:9_656:}')),
      findsOneWidget,
    );
    expect(find.textContaining('{:9_656:}', findRichText: true), findsNothing);
  });

  testWidgets('ReplyComposerPage submits raw sticker code', (tester) async {
    final replyRepository = _FakeThreadReplyAdapter(result: _replyApplied);

    await tester.pumpWidget(
      _buildLauncher(
        replyRepository: replyRepository,
        stickerGroups: _stickerGroups,
      ),
    );

    await tester.tap(find.byKey(const Key('open-reply-composer-page')));
    await tester.pumpAndSettle();
    await _enterReplySourceText(tester, '表情{:9_656:}');
    await tester.pump();
    await tester.tap(find.byKey(const Key('reply-composer-send-button')));
    await tester.pumpAndSettle();

    expect(replyRepository.sentDrafts.single.message, '表情{:9_656:}');
  });

  testWidgets('ReplyComposerPage shows post reply preparation banner', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage(args: _postArgs()));
    await tester.pump();
    await tester.pump();

    expect(find.text('回复楼层'), findsOneWidget);
    expect(
      find.byKey(const Key('reply-composer-reference-banner')),
      findsOneWidget,
    );
    expect(find.textContaining('引用正文'), findsOneWidget);
  });

  testWidgets('ReplyComposerPage shows post preparation failure and retry', (
    tester,
  ) async {
    final replyRepository = _FakeThreadReplyAdapter(
      preparationResult:
          const DataReadFailure<
            ThreadReplyPreparation,
            ThreadReplyCapabilities
          >(
            kind: DataReadFailureKind.parse,
            diagnosticMessage: 'test_form_parse_failure',
          ),
    );

    await tester.pumpWidget(
      _buildPage(args: _postArgs(), replyRepository: replyRepository),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('reply-composer-preparation-error')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reply-composer-retry-prepare-button')),
      findsOneWidget,
    );
    final sendButton = tester.widget<IconButton>(
      find.byKey(const Key('reply-composer-send-button')),
    );
    expect(sendButton.onPressed, isNull);
  });

  testWidgets('ReplyComposerPage disables image button while preparing post', (
    tester,
  ) async {
    final preparationCompleter =
        Completer<
          DataReadResult<ThreadReplyPreparation, ThreadReplyCapabilities>
        >();
    await tester.pumpWidget(
      _buildPage(
        args: _postArgs(),
        replyRepository: _FakeThreadReplyAdapter(
          asyncPreparationResult: preparationCompleter.future,
        ),
      ),
    );
    await tester.pump();

    final imageButton = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const Key('reply-composer-image-button')),
        matching: find.byType(IconButton),
      ),
    );
    expect(imageButton.onPressed, isNull);
    preparationCompleter.complete(
      DataReadSuccess<ThreadReplyPreparation, ThreadReplyCapabilities>(
        data: const ThreadReplyPreparation(
          target: ThreadReplyTarget.post(
            fid: '33',
            tid: '572063',
            pid: '41554317',
          ),
          token: _TestThreadReplyToken(),
        ),
        capabilities: _threadReplyCapabilities,
        metadata: const DataReadMetadata.network(),
      ),
    );
  });

  testWidgets('ReplyComposerPage does not show fixed upload queue', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildPage(
        imagePicker: _FakeReplyImagePicker(
          images: const [
            ReplyPickedImage(
              path: '/gallery/first.jpg',
              fileName: 'first.jpg',
              mimeType: 'image/jpeg',
              originalIndex: 0,
            ),
          ],
        ),
        imageUploadCoordinator: _FakeReplyImageUploadCoordinator(
          events: [
            ComposerImageUploadEvent.started(localId: '', current: 1, total: 1),
          ],
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reply-composer-image-button')));
    await tester.pump();

    expect(find.byKey(const Key('reply-composer-image-queue')), findsNothing);
    expect(find.text('first.jpg'), findsNothing);
    expect(find.textContaining('上传中'), findsNothing);
  });

  testWidgets('ReplyComposerPage inserts image block at the captured cursor', (
    tester,
  ) async {
    final replyRepository = _FakeThreadReplyAdapter();
    await tester.pumpWidget(
      _buildPage(
        replyRepository: replyRepository,
        imagePicker: _FakeReplyImagePicker(
          images: const [
            ReplyPickedImage(
              path: '/gallery/first.jpg',
              fileName: 'first.jpg',
              mimeType: 'image/jpeg',
              originalIndex: 0,
            ),
          ],
        ),
        imageUploadCoordinator: _FakeReplyImageUploadCoordinator(
          events: [
            ComposerImageUploadEvent.uploaded(
              localId: '',
              current: 1,
              total: 1,
              uploadedImage: ReplyUploadedImage(
                localId: '',
                aid: '123456',
                uploadedAt: DateTime.now(),
              ),
            ),
            const ComposerImageUploadEvent.completed(total: 1),
          ],
        ),
      ),
    );
    await tester.pump();
    await _enterReplySourceText(tester, '正文');
    await tester.pump();
    await tester.tap(find.byKey(const Key('reply-composer-source-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reply-composer-image-button')));
    await _pumpUntilMessageContains(tester, '[attach]123456[/attach]');
    await tester.pump();
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(
      editable.controller.text,
      anyOf('正文\n[attach]123456[/attach]', '正文\n[attach]123456[/attach]\n'),
    );
    expect(find.byKey(const Key('reply-composer-image-queue')), findsNothing);
    expect(find.text('first.jpg 已上传'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reply-composer-send-button')));
    await tester.pumpAndSettle();

    expect(
      replyRepository.sentDrafts.single.message,
      anyOf('正文\n[attach]123456[/attach]', '正文\n[attach]123456[/attach]\n'),
    );
  });

  testWidgets(
    'ReplyComposerPage shows uploaded image embed and submits raw attach code',
    (tester) async {
      const path = 'E:/test/reply/uploaded.png';
      final replyRepository = _FakeThreadReplyAdapter();
      await tester.pumpWidget(
        _buildPage(
          replyRepository: replyRepository,
          imagePicker: _FakeReplyImagePicker(
            images: [
              ReplyPickedImage(
                path: path,
                fileName: 'uploaded.png',
                mimeType: 'image/png',
                originalIndex: 0,
              ),
            ],
          ),
          imageUploadCoordinator: _FakeReplyImageUploadCoordinator(
            events: [
              ComposerImageUploadEvent.uploaded(
                localId: '',
                current: 1,
                total: 1,
                uploadedImage: ReplyUploadedImage(
                  localId: '',
                  aid: '123456',
                  uploadedAt: DateTime.now(),
                ),
              ),
              const ComposerImageUploadEvent.completed(total: 1),
            ],
          ),
        ),
      );
      await tester.pump();
      await _enterReplySourceText(tester, '正文');
      await tester.pump();
      await tester.tap(find.byKey(const Key('reply-composer-source-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reply-composer-image-button')));
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('composer-quill-attach-123456')),
      );
      await tester.pump();

      expect(find.byKey(const Key('reply-composer-image-queue')), findsNothing);
      expect(find.text('uploaded.png 已上传'), findsOneWidget);
      expect(
        find.byKey(const Key('composer-quill-attach-123456')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('composer-quill-attach-image-123456')),
        findsOneWidget,
      );
      final previewImage = tester.widget<_TestAttachPreviewImage>(
        find.byKey(const Key('composer-quill-attach-image-123456')),
      );
      expect(previewImage.file.path, path);
      expect(
        find.textContaining('[attach]123456[/attach]', findRichText: true),
        findsNothing,
      );

      await _openReplySourceEditor(tester);
      final sourceField = tester.widget<TextField>(
        find.byKey(const Key('reply-composer-message-input')),
      );
      expect(
        sourceField.controller?.text,
        anyOf('正文\n[attach]123456[/attach]', '正文\n[attach]123456[/attach]\n'),
      );
      await tester.tap(find.byKey(const Key('reply-composer-send-button')));
      await tester.pumpAndSettle();

      expect(
        replyRepository.sentDrafts.single.message,
        anyOf('正文\n[attach]123456[/attach]', '正文\n[attach]123456[/attach]\n'),
      );
    },
  );

  testWidgets(
    'ReplyComposerPage shows upload failure without changing message',
    (tester) async {
      await tester.pumpWidget(
        _buildPage(
          imagePicker: _FakeReplyImagePicker(
            images: const [
              ReplyPickedImage(
                path: '/gallery/first.jpg',
                fileName: 'first.jpg',
                mimeType: 'image/jpeg',
                originalIndex: 0,
              ),
            ],
          ),
          imageUploadCoordinator: _FakeReplyImageUploadCoordinator(
            events: [
              ComposerImageUploadEvent.failed(
                localId: '',
                current: 1,
                total: 1,
                failure: const ComposerImageUploadFailure(
                  code: ComposerImageUploadFailureCode.server,
                  detail: '图片上传失败',
                ),
              ),
              const ComposerImageUploadEvent.completed(total: 1),
            ],
          ),
        ),
      );
      await tester.pump();
      await _enterReplySourceText(tester, '正文');
      await tester.pump();
      await tester.tap(find.byKey(const Key('reply-composer-source-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reply-composer-image-button')));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('上传失败'), findsWidgets);
      expect(find.byKey(const Key('reply-composer-image-error')), findsNothing);
      await _openReplySourceEditor(tester);
      final sourceField = tester.widget<TextField>(
        find.byKey(const Key('reply-composer-message-input')),
      );
      expect(sourceField.controller?.text, '正文');
      expect(find.textContaining('[attach]'), findsNothing);
    },
  );

  testWidgets('ReplyComposerPage submits post reply with prepared token', (
    tester,
  ) async {
    final replyRepository = _FakeThreadReplyAdapter();
    await tester.pumpWidget(
      _buildPage(args: _postArgs(), replyRepository: replyRepository),
    );
    await tester.pump();
    await tester.pump();
    await _enterReplySourceText(tester, '楼层回复');
    await tester.pump();
    await tester.tap(find.byKey(const Key('reply-composer-send-button')));
    await tester.pumpAndSettle();

    final draft = replyRepository.sentDrafts.single;
    expect(draft.target.pid, '41554317');
    expect(draft.preparation?.token, isA<_TestThreadReplyToken>());
    expect(draft.preparation?.quotePreview, '引用正文');
  });

  testWidgets('ReplyComposerPage confirms leaving with unsent input', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildLauncher(draftRepository: _MemoryReplyDraftRepository()),
    );
    await tester.tap(find.byKey(const Key('open-reply-composer-page')));
    await tester.pumpAndSettle();
    await _enterReplySourceText(tester, '未发送内容');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('保存草稿并离开？'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('reply-composer-continue-edit-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('reply-composer-message-input')),
      findsOneWidget,
    );
  });

  testWidgets('ReplyComposerPage saves draft and leaves after confirmation', (
    tester,
  ) async {
    final draftRepository = _MemoryReplyDraftRepository();
    await tester.pumpWidget(_buildLauncher(draftRepository: draftRepository));
    await tester.tap(find.byKey(const Key('open-reply-composer-page')));
    await tester.pumpAndSettle();
    await _enterReplySourceText(tester, '离开前保存');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reply-composer-save-leave-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open-reply-composer-page')), findsOneWidget);
    expect(
      (await draftRepository.loadDraft(_threadArgs().identity))?.message,
      '离开前保存',
    );
  });

  testWidgets('ReplyComposerPage leaves without confirmation for empty input', (
    tester,
  ) async {
    await tester.pumpWidget(_buildLauncher());
    await tester.tap(find.byKey(const Key('open-reply-composer-page')));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('保存草稿并离开？'), findsNothing);
    expect(find.byKey(const Key('open-reply-composer-page')), findsOneWidget);
  });

  testWidgets(
    'ReplyComposerPage successful submit does not show leave confirm',
    (tester) async {
      final replyRepository = _FakeThreadReplyAdapter(result: _replyApplied);
      await tester.pumpWidget(_buildLauncher(replyRepository: replyRepository));
      await tester.tap(find.byKey(const Key('open-reply-composer-page')));
      await tester.pumpAndSettle();
      await _enterReplySourceText(tester, '提交内容');
      await tester.pump();
      await tester.tap(find.byKey(const Key('reply-composer-send-button')));
      await tester.pumpAndSettle();

      expect(find.text('保存草稿并离开？'), findsNothing);
      expect(find.byKey(const Key('open-reply-composer-page')), findsOneWidget);
    },
  );

  testWidgets(
    'ReplyComposerPage source editor inserts the image at a mid message caret',
    (tester) async {
      await tester.pumpWidget(
        _buildPage(
          preferencesRepository: _FakeComposerPreferencesRepository(
            preferences: const ComposerPreferences(
              defaultSurface: ComposerSurfacePreference.source,
              newDraftUseSignature: true,
            ),
          ),
          imagePicker: _FakeReplyImagePicker(
            images: const [
              ReplyPickedImage(
                path: '/gallery/first.jpg',
                fileName: 'first.jpg',
                mimeType: 'image/jpeg',
                originalIndex: 0,
              ),
            ],
          ),
          imageUploadCoordinator: _uploadedAidCoordinator('123456'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('reply-composer-message-input')),
        '第一行\n第二行',
      );
      await tester.pump();
      final field = tester.widget<TextField>(
        find.byKey(const Key('reply-composer-message-input')),
      );
      field.controller!.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();

      await tester.tap(find.byKey(const Key('reply-composer-image-button')));
      await _pumpUntilMessageContains(tester, '[attach]123456[/attach]');
      await tester.pump();

      expect(field.controller!.text, '第一行\n[attach]123456[/attach]\n第二行');
      // 图片下一行的开头，也就是 `第二行` 的第一个字符前。
      expect(
        field.controller!.selection,
        const TextSelection.collapsed(offset: 28),
      );
    },
  );

  testWidgets(
    'ReplyComposerPage quill editor inserts the image at a mid message caret',
    (tester) async {
      await tester.pumpWidget(
        _buildPage(
          imagePicker: _FakeReplyImagePicker(
            images: const [
              ReplyPickedImage(
                path: '/gallery/first.jpg',
                fileName: 'first.jpg',
                mimeType: 'image/jpeg',
                originalIndex: 0,
              ),
            ],
          ),
          imageUploadCoordinator: _uploadedAidCoordinator('123456'),
        ),
      );
      await tester.pumpAndSettle();
      final quill = tester
          .widget<QuillEditor>(find.byType(QuillEditor))
          .controller;
      quill.document = Document()..insert(0, '第一行\n第二行');
      quill.updateSelection(
        const TextSelection.collapsed(offset: 3),
        ChangeSource.local,
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('reply-composer-image-button')));
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('composer-quill-attach-123456')),
      );
      await tester.pump();

      // 图片是长度 1 的 embed：`第一行`(0-2) `\n`(3) 图片(4) `\n`(5) `第二行`(6-8)。
      expect(quill.document.toPlainText(), '第一行\n￼\n第二行\n');
      expect(quill.selection, const TextSelection.collapsed(offset: 6));

      await _openReplySourceEditor(tester);
      final field = tester.widget<TextField>(
        find.byKey(const Key('reply-composer-message-input')),
      );
      expect(field.controller!.text, '第一行\n[attach]123456[/attach]\n第二行');
    },
  );

  testWidgets(
    'ReplyComposerPage parks the upload when the captured caret is overwritten',
    (tester) async {
      final hold = Completer<void>();
      await tester.pumpWidget(
        _buildPage(
          preferencesRepository: _FakeComposerPreferencesRepository(
            preferences: const ComposerPreferences(
              defaultSurface: ComposerSurfacePreference.source,
              newDraftUseSignature: true,
            ),
          ),
          imagePicker: _FakeReplyImagePicker(
            images: const [
              ReplyPickedImage(
                path: '/gallery/first.jpg',
                fileName: 'first.jpg',
                mimeType: 'image/jpeg',
                originalIndex: 0,
              ),
            ],
          ),
          imageUploadCoordinator: _uploadedAidCoordinator(
            '123456',
            holdUntil: hold,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final inputFinder = find.byKey(const Key('reply-composer-message-input'));
      await tester.enterText(inputFinder, '第一行\n第二行');
      await tester.pump();
      final field = tester.widget<TextField>(inputFinder);
      field.controller!.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();

      await tester.tap(find.byKey(const Key('reply-composer-image-button')));
      await tester.pump();
      // 上传期间整段重写正文，捕获的光标已经不存在。
      await tester.enterText(inputFinder, '完全替换');
      await tester.pump();
      hold.complete();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('reply-composer-pending-attachment')),
        findsOneWidget,
      );
      expect(field.controller!.text, '完全替换');

      // 重新选好位置后再点图片按钮，才把已上传的附件插进来。
      field.controller!.selection = const TextSelection.collapsed(offset: 2);
      await tester.pump();
      await tester.tap(find.byKey(const Key('reply-composer-image-button')));
      await tester.pumpAndSettle();

      expect(field.controller!.text, '完全\n[attach]123456[/attach]\n替换');
      expect(
        find.byKey(const Key('reply-composer-pending-attachment')),
        findsNothing,
      );
    },
  );
}

_FakeReplyImageUploadCoordinator _uploadedAidCoordinator(
  String aid, {
  Completer<void>? holdUntil,
}) {
  return _FakeReplyImageUploadCoordinator(
    holdUntil: holdUntil,
    events: [
      ComposerImageUploadEvent.uploaded(
        localId: '',
        current: 1,
        total: 1,
        uploadedImage: ReplyUploadedImage(
          localId: '',
          aid: aid,
          uploadedAt: DateTime(2026, 7, 26),
        ),
      ),
      const ComposerImageUploadEvent.completed(total: 1),
    ],
  );
}

Widget _buildPage({
  ReplyComposerArgs? args,
  ComposerDraftRepository? draftRepository,
  ComposerPreferencesRepository? preferencesRepository,
  _FakeThreadReplyAdapter? replyRepository,
  ComposerImagePicker? imagePicker,
  ComposerImageUploadCoordinator? imageUploadCoordinator,
  ComposerDraftAttachmentVerificationService? draftVerificationService,
  List<StickerGroup> stickerGroups = const [],
  ThemeData? theme,
  Locale locale = const Locale('zh'),
}) {
  return ProviderScope(
    overrides: [
      composerDraftRepositoryProvider.overrideWithValue(
        draftRepository ?? _MemoryReplyDraftRepository(),
      ),
      composerPreferencesRepositoryProvider.overrideWithValue(
        preferencesRepository ?? _FakeComposerPreferencesRepository(),
      ),
      threadReplyPreparationProvider.overrideWithValue(
        replyRepository ?? _FakeThreadReplyAdapter(),
      ),
      threadReplyCommandProvider.overrideWithValue(
        replyRepository ?? _FakeThreadReplyAdapter(),
      ),
      composerImagePickerProvider.overrideWithValue(
        imagePicker ?? _FakeReplyImagePicker(),
      ),
      composerImageUploadCoordinatorProvider.overrideWithValue(
        imageUploadCoordinator ?? _FakeReplyImageUploadCoordinator(),
      ),
      composerDraftAttachmentVerificationServiceProvider.overrideWithValue(
        draftVerificationService ??
            const _NoopDraftAttachmentVerificationService(),
      ),
      forumBbCodeRendererProvider.overrideWithValue(_testRenderer),
      stickerGroupsProvider.overrideWith((_) async => stickerGroups),
      stickerPickerPreferencesRepositoryProvider.overrideWithValue(
        _FakeStickerPickerPreferencesRepository(),
      ),
      imageCacheServiceProvider.overrideWithValue(_FailingImageCacheService()),
    ],
    child: LocalizedTestApp(
      locale: locale,
      theme: theme,
      home: ReplyComposerPage(args: args ?? _threadArgs()),
    ),
  );
}

Future<void> _pumpUntilMessageContains(
  WidgetTester tester,
  String expected, {
  int maxPumps = 12,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump();
    if (find
        .byKey(const Key('reply-composer-message-input'))
        .evaluate()
        .isEmpty) {
      await _openReplySourceEditor(tester);
    }
    final sourceField = tester.widget<TextField>(
      find.byKey(const Key('reply-composer-message-input')),
    );
    if ((sourceField.controller?.text ?? '').contains(expected)) {
      return;
    }
  }
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 12,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump();
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
}

Future<void> _enterReplySourceText(WidgetTester tester, String text) async {
  await _openReplySourceEditor(tester);
  await tester.enterText(
    find.byKey(const Key('reply-composer-message-input')),
    text,
  );
}

Future<void> _openReplySourceEditor(WidgetTester tester) async {
  if (find
      .byKey(const Key('reply-composer-message-input'))
      .evaluate()
      .isNotEmpty) {
    return;
  }
  await tester.tap(find.byKey(const Key('reply-composer-source-button')));
  await tester.pumpAndSettle();
}

Widget _buildLauncher({
  ComposerDraftRepository? draftRepository,
  _FakeThreadReplyAdapter? replyRepository,
  List<StickerGroup> stickerGroups = const [],
  ThemeData? theme,
  ValueChanged<ReplyComposerResult>? onResult,
}) {
  return ProviderScope(
    overrides: [
      composerDraftRepositoryProvider.overrideWithValue(
        draftRepository ?? _MemoryReplyDraftRepository(),
      ),
      composerPreferencesRepositoryProvider.overrideWithValue(
        _FakeComposerPreferencesRepository(),
      ),
      threadReplyPreparationProvider.overrideWithValue(
        replyRepository ?? _FakeThreadReplyAdapter(),
      ),
      threadReplyCommandProvider.overrideWithValue(
        replyRepository ?? _FakeThreadReplyAdapter(),
      ),
      composerImagePickerProvider.overrideWithValue(_FakeReplyImagePicker()),
      composerImageUploadCoordinatorProvider.overrideWithValue(
        _FakeReplyImageUploadCoordinator(),
      ),
      composerDraftAttachmentVerificationServiceProvider.overrideWithValue(
        const _NoopDraftAttachmentVerificationService(),
      ),
      forumBbCodeRendererProvider.overrideWithValue(_testRenderer),
      stickerGroupsProvider.overrideWith((_) async => stickerGroups),
      stickerPickerPreferencesRepositoryProvider.overrideWithValue(
        _FakeStickerPickerPreferencesRepository(),
      ),
      imageCacheServiceProvider.overrideWithValue(_FailingImageCacheService()),
    ],
    child: LocalizedTestApp(
      theme: theme,
      home: _ReplyComposerLauncher(onResult: onResult ?? ((_) {})),
    ),
  );
}

final _stickerGroups = [
  StickerGroup(
    id: 'bugcat',
    title: '貓貓蟲',
    stickers: [_sticker(code: '{:9_656:}', imagePath: 'bugcat/Capoo16.gif')],
  ),
];

class _FakeComposerPreferencesRepository
    implements ComposerPreferencesRepository {
  _FakeComposerPreferencesRepository({ComposerPreferences? preferences})
    : preferences = preferences ?? ComposerPreferences.defaults();

  ComposerPreferences preferences;

  @override
  Future<ComposerPreferences> load() async => preferences;

  @override
  Future<void> save(ComposerPreferences preferences) async {
    this.preferences = preferences;
  }
}

StickerItem _sticker({required String code, required String imagePath}) {
  return StickerItem(
    code: code,
    rawCodePattern: code,
    imagePath: imagePath,
    imageUrl: 'https://bbs.yamibo.com/static/image/smiley/$imagePath',
    cacheKey: ImageCacheKeys.remoteSmiley(imagePath),
  );
}

ReplyComposerArgs _threadArgs() {
  return const ReplyComposerArgs(
    target: ReplyTarget.thread(fid: '33', tid: '572063'),
  );
}

ReplyComposerArgs _postArgs() {
  final uri = Uri.parse(
    'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=33&tid=572063&repquote=41554317&mobile=2',
  );
  return ReplyComposerArgs(
    target: ReplyTarget.post(
      fid: '33',
      tid: '572063',
      pid: '41554317',
      sourceUri: uri,
    ),
    replyFormUri: uri,
  );
}

class _ReplyComposerLauncher extends StatelessWidget {
  const _ReplyComposerLauncher({required this.onResult});

  final ValueChanged<ReplyComposerResult> onResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          key: const Key('open-reply-composer-page'),
          onPressed: () async {
            final result = await Navigator.of(context)
                .push<ReplyComposerResult>(
                  MaterialPageRoute<ReplyComposerResult>(
                    builder: (_) => ReplyComposerPage(args: _threadArgs()),
                  ),
                );
            if (result != null) {
              onResult(result);
            }
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}

class _MemoryReplyDraftRepository implements ComposerDraftRepository {
  _MemoryReplyDraftRepository({DateTime Function()? now}) : _now = now;

  final Map<String, ComposerDraftSnapshot> _drafts =
      <String, ComposerDraftSnapshot>{};
  final DateTime Function()? _now;
  static const ComposerDraftAttachmentSanitizer _sanitizer =
      ComposerDraftAttachmentSanitizer();

  @override
  Future<void> deleteDraft(ComposerDraftIdentity identity) async {
    _drafts.remove(identity.storageKey);
  }

  @override
  Future<List<ComposerDraftSnapshot>> listDraftsForThread({
    required String fid,
    required String tid,
  }) async {
    return _drafts.values
        .where(
          (draft) => draft.identity.fid == fid && draft.identity.tid == tid,
        )
        .toList(growable: false);
  }

  @override
  Future<ComposerDraftSnapshot?> loadDraft(
    ComposerDraftIdentity identity,
  ) async {
    final draft = _drafts[identity.storageKey];
    final now = _now;
    if (draft == null || now == null) {
      return draft;
    }
    final result = _sanitizer.sanitize(
      message: draft.message,
      imageAttachments: draft.imageAttachments,
      now: now(),
    );
    final sanitized = ComposerDraftSnapshot(
      identity: draft.identity,
      message: result.message,
      useSignature: draft.useSignature,
      updatedAt: draft.updatedAt,
      imageAttachments: result.imageAttachments,
    );
    if (sanitized.isEmpty) {
      _drafts.remove(identity.storageKey);
      return null;
    }
    _drafts[identity.storageKey] = sanitized;
    return sanitized;
  }

  @override
  Future<ComposerDraftPruneResult> pruneDrafts({
    Duration maxAge = const Duration(days: 30),
    int maxCount = 100,
  }) async {
    return ComposerDraftPruneResult(removedCount: 0, keptCount: _drafts.length);
  }

  @override
  Future<void> saveDraft(ComposerDraftSnapshot draft) async {
    if (draft.isEmpty) {
      _drafts.remove(draft.identity.storageKey);
      return;
    }
    _drafts[draft.identity.storageKey] = draft;
  }
}

ReplyImageAttachment _uploadedAttachment({
  required String localId,
  required String aid,
  required DateTime uploadedAt,
  String? localPath,
  String? cachePath,
}) {
  return ReplyImageAttachment(
    localId: localId,
    localPath: localPath ?? '/gallery/$localId.jpg',
    fileName: '$localId.jpg',
    mimeType: 'image/jpeg',
    order: 0,
    status: ReplyImageAttachmentStatus.uploaded,
    aid: aid,
    uploadedAt: uploadedAt,
    cachePath: cachePath,
  );
}

class _NoopDraftAttachmentVerificationService
    implements ComposerDraftAttachmentVerificationService {
  const _NoopDraftAttachmentVerificationService();

  @override
  Future<ComposerDraftAttachmentVerificationResult> verify(
    ComposerDraftSnapshot draft,
  ) async {
    return ComposerDraftAttachmentVerificationResult(
      draft: draft,
      verification: const ComposerDraftAttachmentVerification.notRequired(),
    );
  }
}

class _FailedDraftAttachmentVerificationService
    implements ComposerDraftAttachmentVerificationService {
  const _FailedDraftAttachmentVerificationService();

  @override
  Future<ComposerDraftAttachmentVerificationResult> verify(
    ComposerDraftSnapshot draft,
  ) async {
    return ComposerDraftAttachmentVerificationResult(
      draft: draft,
      verification: ComposerDraftAttachmentVerification.failed(
        unverifiedAids: const <String>{'123456'},
      ),
    );
  }
}

class _InvalidDraftAttachmentVerificationService
    implements ComposerDraftAttachmentVerificationService {
  const _InvalidDraftAttachmentVerificationService();

  @override
  Future<ComposerDraftAttachmentVerificationResult> verify(
    ComposerDraftSnapshot draft,
  ) async {
    return ComposerDraftAttachmentVerificationResult(
      draft: ReplyDraftSnapshot(
        identity: draft.identity,
        message: draft.message,
        subject: draft.subject,
        extras: draft.extras,
        useSignature: draft.useSignature,
        updatedAt: draft.updatedAt,
        imageAttachments: const [],
      ),
      verification: ComposerDraftAttachmentVerification.verified(
        imagesByAid: const {},
        checkedAids: const <String>{'123456'},
        invalidAidCount: 1,
      ),
    );
  }
}

class _PassThroughDraftVerificationService
    implements ComposerDraftAttachmentVerificationService {
  const _PassThroughDraftVerificationService();

  @override
  Future<ComposerDraftAttachmentVerificationResult> verify(
    ComposerDraftSnapshot draft,
  ) async {
    final aids = const ComposerAttachBbCodeService()
        .extractAttachAids(draft.message)
        .toSet();
    return ComposerDraftAttachmentVerificationResult(
      draft: draft,
      verification: ComposerDraftAttachmentVerification.verified(
        imagesByAid: <String, ComposerUnusedImage>{
          for (final aid in aids)
            aid: ComposerUnusedImage(
              aid: aid,
              thumbnailUri: Uri.parse(
                'https://bbs.yamibo.com/forum.php?mod=image&aid=$aid&size=300x300',
              ),
              thumbnailRefererUri: Uri.parse(
                'https://bbs.yamibo.com/forum.php?mod=ajax&action=imagelist&posttime=0',
              ),
            ),
        },
        checkedAids: aids,
        invalidAidCount: 0,
      ),
    );
  }
}

final _testRenderer = FlutterBbCodeForumRenderer(
  attachImageBuilder: _buildTestAttachPreviewImage,
  attachFileExists: _testAttachFileExists,
  stickerImageBuilder: _buildTestStickerPreviewImage,
);

Widget _buildTestAttachPreviewImage(File file, Key key) {
  return _TestAttachPreviewImage(file: file, key: key);
}

Widget _buildTestStickerPreviewImage(StickerItem sticker, Key key) {
  return _TestStickerPreviewImage(sticker: sticker, key: key);
}

bool _testAttachFileExists(File file) {
  return !file.path.contains('/missing/');
}

class _TestAttachPreviewImage extends StatelessWidget {
  const _TestAttachPreviewImage({super.key, required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 28, height: 28);
  }
}

class _TestStickerPreviewImage extends StatelessWidget {
  const _TestStickerPreviewImage({super.key, required this.sticker});

  final StickerItem sticker;

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 28, height: 28);
  }
}

class _FakeStickerPickerPreferencesRepository
    implements StickerPickerPreferencesRepository {
  String? lastGroupId;

  @override
  Future<String?> loadLastGroupId() async {
    return lastGroupId;
  }

  @override
  Future<void> saveLastGroupId(String groupId) async {
    lastGroupId = groupId;
  }
}

class _FailingImageCacheService implements ImageCacheService {
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult.failed;
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult.failed;
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    return 0;
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }

  @override
  Future<void> clearUnprotected() async {}
}

class _FakeReplyImagePicker implements ComposerImagePicker {
  _FakeReplyImagePicker({this.images = const <ComposerPickedImage>[]});

  final List<ComposerPickedImage> images;

  @override
  Future<List<ComposerPickedImage>> pickImagesInOrder() async {
    return images;
  }
}

class _FakeReplyImageUploadCoordinator
    implements ComposerImageUploadCoordinator {
  _FakeReplyImageUploadCoordinator({
    this.events = const <ComposerImageUploadEvent>[],
    this.holdUntil,
  });

  final List<ComposerImageUploadEvent> events;

  /// 用来把"上传中"停在一个可控的点上，好在期间改动正文。
  final Completer<void>? holdUntil;

  @override
  void cancel() {}

  @override
  Stream<ComposerImageUploadEvent> uploadInOrder({
    required String fid,
    required List<ComposerImageAttachment> attachments,
  }) async* {
    if (holdUntil != null) {
      await holdUntil!.future;
    }
    for (final event in events) {
      if (event.type == ComposerImageUploadEventType.completed) {
        yield ComposerImageUploadEvent.completed(total: event.total);
        continue;
      }
      final localId = event.localId.isNotEmpty
          ? event.localId
          : attachments[(event.current - 1)
                    .clamp(0, attachments.length - 1)
                    .toInt()]
                .localId;
      yield switch (event.type) {
        ComposerImageUploadEventType.started =>
          ComposerImageUploadEvent.started(
            localId: localId,
            current: event.current,
            total: event.total,
          ),
        ComposerImageUploadEventType.progress =>
          ComposerImageUploadEvent.progress(
            localId: localId,
            current: event.current,
            total: event.total,
            progress: event.progress ?? 0,
          ),
        ComposerImageUploadEventType.uploaded =>
          ComposerImageUploadEvent.uploaded(
            localId: localId,
            current: event.current,
            total: event.total,
            uploadedImage: ComposerUploadedImage(
              localId: localId,
              aid: event.uploadedImage!.aid,
              uploadedAt: event.uploadedImage!.uploadedAt,
            ),
          ),
        ComposerImageUploadEventType.failed => ComposerImageUploadEvent.failed(
          localId: localId,
          current: event.current,
          total: event.total,
          failure:
              event.failure ??
              const ComposerImageUploadFailure(
                code: ComposerImageUploadFailureCode.unknown,
              ),
        ),
        ComposerImageUploadEventType.completed =>
          ComposerImageUploadEvent.completed(total: event.total),
      };
    }
  }
}

final class _TestThreadReplyToken implements ThreadReplyPreparationToken {
  const _TestThreadReplyToken();
}

final ThreadReplyCapabilities _threadReplyCapabilities =
    ThreadReplyCapabilities(
      values: DataCapabilitySet<ThreadReplyCapability>.supported(
        ThreadReplyCapability.values,
      ),
    );

class _FakeThreadReplyAdapter
    implements ThreadReplyPreparationRepository, ThreadReplyCommand {
  _FakeThreadReplyAdapter({
    DataCommandResult<ThreadReplyReceipt>? result,
    DataReadResult<ThreadReplyPreparation, ThreadReplyCapabilities>?
    preparationResult,
    this.asyncPreparationResult,
  }) : result =
           result ??
           const DataCommandApplied<ThreadReplyReceipt>(
             ThreadReplyReceipt(
               tid: '572063',
               pid: '41554318',
               publicationState: ThreadPublicationState.published,
             ),
           ),
       preparationResult =
           preparationResult ??
           DataReadSuccess<ThreadReplyPreparation, ThreadReplyCapabilities>(
             data: const ThreadReplyPreparation(
               target: ThreadReplyTarget.post(
                 fid: '33',
                 tid: '572063',
                 pid: '41554317',
               ),
               quotePreview: '引用正文',
               token: _TestThreadReplyToken(),
             ),
             capabilities: _threadReplyCapabilities,
             metadata: const DataReadMetadata.network(),
           );

  final DataCommandResult<ThreadReplyReceipt> result;
  final DataReadResult<ThreadReplyPreparation, ThreadReplyCapabilities>
  preparationResult;
  final Future<DataReadResult<ThreadReplyPreparation, ThreadReplyCapabilities>>?
  asyncPreparationResult;
  final List<ThreadReplySubmission> sentDrafts = <ThreadReplySubmission>[];

  @override
  ThreadReplyCapabilities get capabilities => _threadReplyCapabilities;

  @override
  Future<DataCommandResult<ThreadReplyReceipt>> execute(
    ThreadReplySubmission submission,
  ) async {
    sentDrafts.add(submission);
    return result;
  }

  @override
  Future<DataReadResult<ThreadReplyPreparation, ThreadReplyCapabilities>> load(
    ThreadReplyPreparationRequest request,
  ) async {
    final asyncPreparationResult = this.asyncPreparationResult;
    if (asyncPreparationResult != null) {
      return asyncPreparationResult;
    }
    return preparationResult;
  }
}
