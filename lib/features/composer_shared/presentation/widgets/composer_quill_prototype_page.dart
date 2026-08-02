import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/composer_bbcode_command.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_bbcode_codec.dart';
import 'package:y300/features/composer_shared/domain/services/composer_message_insertion_service.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_bbcode_context_menu.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_bbcode_source_editor.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_bbcode_toolbar.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_quill_prototype_editor.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_sticker_image.dart';
import 'package:y300/l10n/app_localizations.dart';

class ComposerQuillPrototypePage extends ConsumerStatefulWidget {
  const ComposerQuillPrototypePage({super.key});

  @override
  ConsumerState<ComposerQuillPrototypePage> createState() {
    return _ComposerQuillPrototypePageState();
  }
}

class _ComposerQuillPrototypePageState
    extends ConsumerState<ComposerQuillPrototypePage> {
  static const _codec = ComposerQuillBbCodeCodec();
  static const _insertionService = ComposerBbCodeInsertionService();
  static const _messageInsertionService = ComposerMessageInsertionService();

  final QuillController _quillController = QuillController.basic();
  final TextEditingController _sourceController = TextEditingController();
  final List<ComposerImageAttachment> _imageAttachments =
      <ComposerImageAttachment>[];
  _ComposerQuillPrototypeMode _mode = _ComposerQuillPrototypeMode.quill;
  String _bbCodeText = '';
  int _nextAid = 900001;

  @override
  void initState() {
    super.initState();
    _sourceController.text = _bbCodeText;
  }

  @override
  void dispose() {
    _sourceController.dispose();
    _quillController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stickerGroups = ref
        .watch(stickerGroupsProvider)
        .maybeWhen(
          data: (groups) => groups,
          orElse: () => const <StickerGroup>[],
        );
    final stickers = [for (final group in stickerGroups) ...group.stickers];
    return Scaffold(
      appBar: AppBar(
        title: Text(_titleForMode(context)),
        actions: [
          IconButton(
            key: Key(_actionKeyForMode()),
            tooltip: _actionTooltipForMode(context),
            icon: Icon(_actionIconForMode()),
            onPressed: _handlePrimaryAction,
          ),
        ],
      ),
      body: _buildBody(stickerGroups: stickerGroups, stickers: stickers),
    );
  }

  Widget _buildBody({
    required List<StickerGroup> stickerGroups,
    required List<StickerItem> stickers,
  }) {
    return switch (_mode) {
      _ComposerQuillPrototypeMode.quill => ComposerQuillPrototypeEditor(
        keyPrefix: 'composer-quill-prototype',
        controller: _quillController,
        stickers: stickers,
        stickerGroups: stickerGroups,
        imageAttachments: _imageAttachments,
        expand: true,
        onBbCodeChanged: _handleQuillBbCodeChanged,
        onImagePressed: _insertFakeUploadedImage,
      ),
      _ComposerQuillPrototypeMode.source => _SourceFineTuneView(
        controller: _sourceController,
        onStickerPressed: () => _insertSourceSticker(context),
        onCommandSelected: _applySourceCommand,
        onChanged: (value) => _bbCodeText = value,
      ),
    };
  }

  String _titleForMode(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (_mode) {
      _ComposerQuillPrototypeMode.quill => l10n.composerPrototypeTitle,
      _ComposerQuillPrototypeMode.source => l10n.composerPrototypeSourceTitle,
    };
  }

  String _actionKeyForMode() {
    return switch (_mode) {
      _ComposerQuillPrototypeMode.quill =>
        'composer-quill-prototype-source-button',
      _ComposerQuillPrototypeMode.source =>
        'composer-quill-prototype-quill-button',
    };
  }

  String _actionTooltipForMode(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (_mode) {
      _ComposerQuillPrototypeMode.quill => l10n.composerSourceMode,
      _ComposerQuillPrototypeMode.source => l10n.composerVisualMode,
    };
  }

  IconData _actionIconForMode() {
    return switch (_mode) {
      _ComposerQuillPrototypeMode.quill => Icons.code,
      _ComposerQuillPrototypeMode.source => Icons.edit_outlined,
    };
  }

  void _handlePrimaryAction() {
    setState(() {
      switch (_mode) {
        case _ComposerQuillPrototypeMode.quill:
          _sourceController.text = _bbCodeText;
          _mode = _ComposerQuillPrototypeMode.source;
          break;
        case _ComposerQuillPrototypeMode.source:
          _bbCodeText = _sourceController.text;
          _quillController.document = _codec.decodeDocument(_bbCodeText);
          _mode = _ComposerQuillPrototypeMode.quill;
          break;
      }
    });
  }

  void _handleQuillBbCodeChanged(String value) {
    _bbCodeText = value;
    if (_mode == _ComposerQuillPrototypeMode.quill &&
        _sourceController.text != value) {
      _sourceController.text = value;
    }
  }

  void _applySourceCommand(ComposerBbCodeCommand command) {
    final nextValue = _insertionService.wrapSelection(
      _sourceController.value,
      command,
    );
    setState(() {
      _sourceController.value = nextValue;
      _bbCodeText = nextValue.text;
    });
  }

  Future<void> _insertSourceSticker(BuildContext context) async {
    final sticker = await _pickSticker(context);
    if (sticker == null) {
      return;
    }
    final value = _sourceController.value;
    final selection = value.selection;
    final textLength = value.text.length;
    final start = selection.isValid
        ? selection.start.clamp(0, textLength).toInt()
        : textLength;
    final end = selection.isValid
        ? selection.end.clamp(0, textLength).toInt()
        : textLength;
    final rangeStart = start <= end ? start : end;
    final rangeEnd = start <= end ? end : start;
    final nextText = value.text.replaceRange(
      rangeStart,
      rangeEnd,
      sticker.code,
    );
    final nextOffset = rangeStart + sticker.code.length;
    setState(() {
      _sourceController.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextOffset),
      );
      _bbCodeText = nextText;
    });
  }

  Future<StickerItem?> _pickSticker(BuildContext context) async {
    final stickerGroups = await ref.read(stickerGroupsProvider.future);
    final stickers = [for (final group in stickerGroups) ...group.stickers];
    if (!context.mounted || stickers.isEmpty) {
      return null;
    }
    return showModalBottomSheet<StickerItem>(
      context: context,
      builder: (_) => _SourceStickerPicker(stickers: stickers),
    );
  }

  Future<void> _insertFakeUploadedImage(ComposerInsertionAnchor? anchor) async {
    final aid = (_nextAid++).toString();
    final attachmentCode = '[attach]$aid[/attach]';
    final attachment = ComposerImageAttachment(
      localId: 'quill-prototype-$aid',
      localPath: '',
      fileName: 'prototype-$aid.png',
      mimeType: 'image/png',
      order: _imageAttachments.length,
      status: ComposerImageAttachmentStatus.uploaded,
      aid: aid,
      uploadedAt: DateTime.now(),
    );
    final localInsertion = anchor?.localAttachmentInsertion;
    if (localInsertion != null &&
        localInsertion([attachmentCode]) ==
            ComposerLocalAttachmentInsertionResult.stale) {
      return;
    }
    setState(() {
      _imageAttachments.add(attachment);
      if (anchor != null && localInsertion == null) {
        final mutation = _messageInsertionService.insertAttachmentBlock(
          source: _bbCodeText,
          selection: anchor.selection,
          attachmentCodes: [attachmentCode],
          revision: 0,
        );
        _bbCodeText = mutation.nextSource;
        _sourceController.value = TextEditingValue(
          text: _bbCodeText,
          selection: TextSelection.collapsed(
            offset: mutation.resultSelection.start,
          ),
        );
        _quillController.document = _codec.decodeDocument(_bbCodeText);
      }
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            ).composerPrototypeAttachmentInserted(aid),
          ),
        ),
      );
  }
}

enum _ComposerQuillPrototypeMode { quill, source }

class _SourceFineTuneView extends StatelessWidget {
  const _SourceFineTuneView({
    required this.controller,
    required this.onStickerPressed,
    required this.onCommandSelected,
    required this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onStickerPressed;
  final ValueChanged<ComposerBbCodeCommand> onCommandSelected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('composer-quill-prototype-source-view'),
      padding: const EdgeInsets.all(16),
      children: [
        ComposerBbCodeToolbar(
          keyPrefix: 'composer-quill-source',
          onStickerPressed: onStickerPressed,
          onCommandSelected: onCommandSelected,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('composer-quill-prototype-source-input'),
          controller: controller,
          minLines: 12,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          contextMenuBuilder: ComposerBbCodeContextMenu.build,
          onChanged: onChanged,
          decoration: ComposerBbCodeSourceEditor.noBorderDecoration(
            AppLocalizations.of(context).composerSourceMode,
          ),
        ),
      ],
    );
  }
}

class _SourceStickerPicker extends StatelessWidget {
  const _SourceStickerPicker({required this.stickers});

  final List<StickerItem> stickers;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: GridView.builder(
        key: const Key('composer-quill-source-sticker-sheet'),
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 64,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: stickers.length,
        itemBuilder: (context, index) {
          final sticker = stickers[index];
          return IconButton(
            key: Key('composer-quill-source-sticker-item-${sticker.code}'),
            constraints: const BoxConstraints.tightFor(width: 56, height: 56),
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(sticker),
            icon: ComposerStickerImage(
              sticker: sticker,
              width: 48,
              height: 48,
              fit: BoxFit.contain,
              placeholder: const SizedBox.shrink(),
              errorPlaceholder: const Icon(Icons.broken_image_outlined),
            ),
          );
        },
      ),
    );
  }
}
