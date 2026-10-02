import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_embeds.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_sticker_embed_builder.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_sticker_text_codec.dart';
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
  static const _codec = ComposerStickerTextCodec();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _selectedStickers = <String, StickerItem>{};
  late final QuillController _controller;
  late String _source;
  var _generation = 0;
  var _applyingExternalValue = false;
  var _pickerOpen = false;

  @override
  void initState() {
    super.initState();
    _source = widget.value;
    _controller = QuillController(
      document: _codec.decodeDocument(_source),
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: !widget.enabled,
      config: QuillControllerConfig(
        // Pinned Quill 11.5.1 exposes the interception needed to avoid its
        // internal rich-copy cache through these experimental public hooks.
        // ignore: experimental_member_use
        clipboardConfig: QuillClipboardConfig(
          // ignore: experimental_member_use
          enableExternalRichPaste: false,
          // ignore: experimental_member_use
          onClipboardPaste: _pastePlainText,
        ),
      ),
      onReplaceText: (_, _, data) => _isPlainTextOrSticker(data),
    )..addListener(_handleChanged);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant ComposerStickerInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      _generation += 1;
      _controller.readOnly = !widget.enabled;
    }
    if (widget.value != _source) {
      _generation += 1;
      _source = widget.value;
      _applyingExternalValue = true;
      try {
        _controller.document = _codec.decodeDocument(
          _source,
          stickerCodes: _selectedStickers.keys,
        );
        _controller.updateSelection(
          TextSelection.collapsed(offset: _controller.document.length - 1),
          ChangeSource.local,
        );
      } finally {
        _applyingExternalValue = false;
      }
    }
  }

  @override
  void dispose() {
    _generation += 1;
    _controller.removeListener(_handleChanged);
    _controller.dispose();
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _isPlainTextOrSticker(Object? data) {
    if (data is String) return true;
    if (data is Embeddable) return data.type == composerQuillStickerEmbedType;
    return data is Delta &&
        data.toList().every((operation) {
          return operation.isInsert &&
              (operation.attributes?.isEmpty ?? true) &&
              (operation.data is String ||
                  composerQuillEmbedData(
                        operation.data,
                        composerQuillStickerEmbedType,
                      ) !=
                      null);
        });
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  void _handleChanged() {
    if (_applyingExternalValue) return;
    final source = _codec.encodeDocument(_controller.document);
    if (source == _source) return;
    _generation += 1;
    setState(() => _source = source);
    // Parent echo updates must not rebuild the document or IME composing span.
    widget.onChanged(source);
  }

  TextSelection get _selection {
    final end = _controller.document.length - 1;
    final selection = _controller.selection;
    if (!selection.isValid) return TextSelection.collapsed(offset: end);
    return TextSelection(
      baseOffset: selection.start.clamp(0, end),
      extentOffset: selection.end.clamp(0, end),
    );
  }

  bool _canApplyInsertion(int generation, TextSelection selection) {
    return mounted &&
        widget.enabled &&
        generation == _generation &&
        selection == _selection;
  }

  Future<void> _pickSticker() async {
    if (!widget.enabled || _pickerOpen) return;
    final generation = _generation;
    final selection = _selection;
    _pickerOpen = true;
    final sticker = await showModalBottomSheet<StickerItem>(
      context: context,
      builder: (_) => const StickerPickerSheet(),
    );
    if (!mounted) return;
    _pickerOpen = false;
    if (sticker == null || !_canApplyInsertion(generation, selection)) return;
    // Replacing a literal code with its embed can leave serialized text
    // unchanged, so the image lookup must rebuild independently of onChanged.
    setState(() => _selectedStickers[sticker.code] = sticker);
    _controller.replaceText(
      selection.start,
      selection.end - selection.start,
      composerQuillStickerEmbed(sticker.code),
      TextSelection.collapsed(offset: selection.start + 1),
    );
    _focusNode.requestFocus();
  }

  Future<bool> _pastePlainText() async {
    if (!widget.enabled) return true;
    final generation = _generation;
    final selection = _selection;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!_canApplyInsertion(generation, selection)) return true;
    final text = data?.text;
    if (text == null || text.isEmpty) return true;
    final fragment = _codec.decodeFragment(
      text,
      stickerCodes: _selectedStickers.keys,
    );
    final insertedLength = fragment.toList().fold<int>(
      0,
      (length, operation) => length + operation.length!,
    );
    _controller.replaceText(
      selection.start,
      selection.end - selection.start,
      fragment,
      TextSelection.collapsed(offset: selection.start + insertedLength),
    );
    // Always handled: Quill's internal copy cache can otherwise restore rich
    // deltas from another editor even with external rich paste disabled.
    return true;
  }

  KeyEventResult? _handleKeyPressed(KeyEvent event, Node? _) {
    final keyboard = HardwareKeyboard.instance;
    // AltGr is reported as Ctrl+Alt on some keyboards and may type ordinary
    // characters. Quill's formatting shortcuts do not include Alt.
    if (keyboard.isAltPressed) return null;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) return null;
    const formattingKeys = <LogicalKeyboardKey>[
      LogicalKeyboardKey.keyB,
      LogicalKeyboardKey.keyI,
      LogicalKeyboardKey.keyU,
      LogicalKeyboardKey.keyK,
      LogicalKeyboardKey.keyM,
      LogicalKeyboardKey.keyG,
      LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.backquote,
      LogicalKeyboardKey.tilde,
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
    ];
    const shiftedFormattingKeys = <LogicalKeyboardKey>[
      LogicalKeyboardKey.keyS,
      LogicalKeyboardKey.keyL,
      LogicalKeyboardKey.keyO,
      LogicalKeyboardKey.keyC,
    ];
    if (formattingKeys.contains(event.logicalKey) ||
        keyboard.isShiftPressed &&
            shiftedFormattingKeys.contains(event.logicalKey)) {
      return KeyEventResult.handled;
    }
    return null;
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
            isEmpty: _source.isEmpty,
            isFocused: _focusNode.hasFocus,
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
                      controller: _controller,
                      focusNode: _focusNode,
                      scrollController: _scrollController,
                      config: QuillEditorConfig(
                        minHeight: (lineHeight * widget.minLines).clamp(
                          0.0,
                          maxHeight,
                        ),
                        maxHeight: maxHeight,
                        scrollPhysics: const ClampingScrollPhysics(),
                        // Pinned Quill public hook runs before formatting actions.
                        // ignore: experimental_member_use
                        onKeyPressed: _handleKeyPressed,
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
                            stickers: _selectedStickers.values.toList(
                              growable: false,
                            ),
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
