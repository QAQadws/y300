import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_sticker_text_controller.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_sticker_embed_builder.dart';
import 'package:y300/features/composer_shared/presentation/widgets/sticker_picker_sheet.dart';
import 'package:y300/l10n/app_localizations.dart';

/// A bounded plain-text editor whose only authored embeds are forum stickers.
class ComposerStickerInput extends StatefulWidget {
  const ComposerStickerInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.hintText,
    this.semanticLabel,
    this.keyPrefix = 'message',
    this.minLines = 1,
    this.maxLines = 5,
  }) : assert(minLines > 0),
       assert(maxLines >= minLines);

  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String? hintText;
  final String? semanticLabel;
  final String keyPrefix;
  final int minLines;
  final int maxLines;

  @override
  State<ComposerStickerInput> createState() => _ComposerStickerInputState();
}

class _ComposerStickerInputState extends State<ComposerStickerInput> {
  late final ComposerStickerTextController _controller;
  var _pickerOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = ComposerStickerTextController(
      value: widget.value,
      onChanged: (source) => widget.onChanged(source),
      readOnly: !widget.enabled,
    )..addListener(_handleChanged);
  }

  @override
  void didUpdateWidget(covariant ComposerStickerInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.update(value: widget.value, readOnly: !widget.enabled);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _pickSticker() async {
    if (!widget.enabled || _pickerOpen) return;
    final generation = _controller.generation;
    final selection = _controller.selection;
    _pickerOpen = true;
    final sticker = await showModalBottomSheet<StickerItem>(
      context: context,
      builder: (_) => const StickerPickerSheet(),
    );
    if (!mounted) return;
    _pickerOpen = false;
    if (sticker == null ||
        !_controller.canApplyInsertion(generation, selection)) {
      return;
    }
    _controller.insertSticker(sticker);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = (theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16))
        .copyWith(height: 1.5, color: theme.y300NativeContent.body);
    final textScaler = MediaQuery.textScalerOf(context);
    final painter = TextPainter(
      text: TextSpan(text: 'M', style: style),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final lineHeight = painter.height;
    painter.dispose();
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox.square(
          dimension: 48,
          child: IconButton(
            key: Key('${widget.keyPrefix}-sticker-button'),
            tooltip: AppLocalizations.of(context).composerSticker,
            onPressed: widget.enabled ? _pickSticker : null,
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.mood, size: 28),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: InputDecorator(
            isEmpty: _controller.source.isEmpty,
            isFocused: _controller.focusNode.hasFocus,
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              enabled: widget.enabled,
              hintText: widget.hintText,
              // This grows like a chat composer, without a form field's
              // label reserve and default vertical padding.
              isDense: true,
              constraints: const BoxConstraints(minHeight: 44),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: border,
              enabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: BorderSide(
                  color: theme.y300NativeContent.accent,
                  width: 1.2,
                ),
              ),
            ).applyDefaults(theme.inputDecorationTheme),
            // A scrolling editor has no stable text baseline. Treat it as a
            // box so decoration/hint baseline alignment cannot move its viewport.
            child: IgnoreBaseline(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // InputDecorator has already reserved its themed padding. A
                  // short keyboard viewport may leave less than one full line.
                  final maxHeight = (lineHeight * widget.maxLines).clamp(
                    0.0,
                    constraints.maxHeight,
                  );
                  if (maxHeight == 0) return const SizedBox.shrink();
                  return Semantics(
                    label: widget.semanticLabel,
                    child: QuillEditor.basic(
                      key: Key('${widget.keyPrefix}-input'),
                      controller: _controller.quill,
                      focusNode: _controller.focusNode,
                      scrollController: _controller.scrollController,
                      config: QuillEditorConfig(
                        minHeight: (lineHeight * widget.minLines).clamp(
                          0.0,
                          maxHeight,
                        ),
                        maxHeight: maxHeight,
                        scrollPhysics: const ClampingScrollPhysics(),
                        // Pinned Quill public hook runs before formatting actions.
                        // ignore: experimental_member_use
                        onKeyPressed: _controller.handleKeyPressed,
                        customStyles: DefaultStyles(
                          paragraph: DefaultTextBlockStyle(
                            style,
                            const HorizontalSpacing(0, 0),
                            const VerticalSpacing(0, 0),
                            const VerticalSpacing(0, 0),
                            null,
                          ),
                        ),
                        embedBuilders: [
                          ComposerQuillStickerEmbedBuilder(
                            stickers: _controller.stickers,
                            fixedSize:
                                textScaler.scale(style.fontSize ?? 16) * 1.25,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
