import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_embeds.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_sticker_text_codec.dart';

/// Lossless plain-text editing with caller-provided sticker metadata.
///
/// Layout and catalog loading belong to the surface using this controller.
class ComposerStickerTextController extends ChangeNotifier {
  ComposerStickerTextController({
    required String value,
    required ValueChanged<String> onChanged,
    bool readOnly = false,
    Iterable<StickerItem> stickers = const [],
  }) : _source = value,
       _onChanged = onChanged {
    _mergeStickers(stickers);
    quill = QuillController(
      document: _codec.decodeDocument(_source, stickerCodes: _stickers.keys),
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: readOnly,
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
    focusNode.addListener(_handleFocusChanged);
  }

  static const _codec = ComposerStickerTextCodec();
  final ValueChanged<String> _onChanged;
  final _stickers = <String, StickerItem>{};
  final focusNode = FocusNode();
  final scrollController = ScrollController();
  late final QuillController quill;
  String _source;
  var _generation = 0;
  var _applyingExternalValue = false;
  var _disposed = false;

  String get source => _source;
  int get generation => _generation;
  bool get readOnly => quill.readOnly;
  List<StickerItem> get stickers => List.unmodifiable(_stickers.values);

  TextSelection get selection {
    final end = quill.document.length - 1;
    final current = quill.selection;
    if (!current.isValid) return TextSelection.collapsed(offset: end);
    return TextSelection(
      baseOffset: current.start.clamp(0, end),
      extentOffset: current.end.clamp(0, end),
    );
  }

  void update({
    required String value,
    required bool readOnly,
    Iterable<StickerItem>? stickers,
  }) {
    if (_disposed) return;
    var changed = stickers != null && _mergeStickers(stickers);
    if (quill.readOnly != readOnly) {
      _generation += 1;
      quill.readOnly = readOnly;
      changed = true;
    }
    changed = _applyExternalValue(value) || changed;
    if (changed) notifyListeners();
  }

  void loadExternalValue(String value) {
    if (_disposed || !_applyExternalValue(value)) return;
    notifyListeners();
  }

  bool _applyExternalValue(String value) {
    // Parent echoes must not replace the document or its IME composing span.
    if (value == _source) return false;
    _generation += 1;
    _source = value;
    _applyingExternalValue = true;
    try {
      quill.document = _codec.decodeDocument(
        _source,
        stickerCodes: _stickers.keys,
      );
      quill.updateSelection(
        TextSelection.collapsed(offset: quill.document.length - 1),
        ChangeSource.local,
      );
    } finally {
      _applyingExternalValue = false;
    }
    return true;
  }

  bool _mergeStickers(Iterable<StickerItem> stickers) {
    var changed = false;
    for (final sticker in stickers) {
      final previous = _stickers[sticker.code];
      if (previous?.rawCodePattern == sticker.rawCodePattern &&
          previous?.imagePath == sticker.imagePath &&
          previous?.imageUrl == sticker.imageUrl &&
          previous?.cacheKey == sticker.cacheKey) {
        continue;
      }
      _stickers[sticker.code] = sticker;
      changed = true;
    }
    return changed;
  }

  bool canApplyInsertion(int generation, TextSelection selection) {
    return !_disposed &&
        !readOnly &&
        generation == _generation &&
        selection == this.selection;
  }

  /// Callers must also validate their async picker against [canApplyInsertion].
  bool insertSticker(StickerItem sticker) {
    if (_disposed || readOnly || sticker.code.isEmpty) return false;
    final current = selection;
    final metadataChanged = _mergeStickers([sticker]);
    quill.replaceText(
      current.start,
      current.end - current.start,
      composerQuillStickerEmbed(sticker.code),
      TextSelection.collapsed(offset: current.start + 1),
    );
    // An equivalent literal code can become an embed without changing source.
    if (metadataChanged) notifyListeners();
    focusNode.requestFocus();
    return true;
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
    if (!_disposed) notifyListeners();
  }

  void _handleChanged() {
    if (_applyingExternalValue || _disposed) return;
    final source = _codec.encodeDocument(quill.document);
    if (source == _source) return;
    _generation += 1;
    _source = source;
    notifyListeners();
    _onChanged(source);
  }

  Future<bool> _pastePlainText() async {
    if (_disposed || readOnly) return true;
    final generation = _generation;
    final current = selection;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!canApplyInsertion(generation, current)) return true;
    final text = data?.text;
    if (text == null || text.isEmpty) return true;
    final fragment = _codec.decodeFragment(text, stickerCodes: _stickers.keys);
    final insertedLength = fragment.toList().fold<int>(
      0,
      (length, operation) => length + operation.length!,
    );
    quill.replaceText(
      current.start,
      current.end - current.start,
      fragment,
      TextSelection.collapsed(offset: current.start + insertedLength),
    );
    // Quill's internal copy cache can restore rich deltas from another editor
    // even when external rich paste is disabled, so always handle the paste.
    return true;
  }

  KeyEventResult? handleKeyPressed(KeyEvent event, Node? _) {
    final keyboard = HardwareKeyboard.instance;
    // AltGr may type ordinary characters and is reported as Ctrl+Alt.
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
  void dispose() {
    _disposed = true;
    _generation += 1;
    quill.removeListener(_handleChanged);
    quill.dispose();
    focusNode.removeListener(_handleFocusChanged);
    focusNode.dispose();
    scrollController.dispose();
    super.dispose();
  }
}
