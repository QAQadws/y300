import 'package:flutter_quill/flutter_quill.dart';

/// Captures the complete inline style selected for future input.
final class ComposerQuillTypingStyleSnapshot {
  const ComposerQuillTypingStyleSnapshot._(this.style);

  static final List<Attribute> _managedAttributes = <Attribute>[
    Attribute.bold,
    Attribute.italic,
    Attribute.underline,
    Attribute.strikeThrough,
    Attribute.size,
    Attribute.color,
    Attribute.background,
    Attribute.link,
  ];

  final Style style;

  factory ComposerQuillTypingStyleSnapshot.capture(QuillController controller) {
    final selectedAttributes = controller.getSelectionStyle().attributes;
    return ComposerQuillTypingStyleSnapshot._(
      Style.attr(<String, Attribute>{
        for (final attribute in _managedAttributes)
          attribute.key:
              selectedAttributes[attribute.key] ??
              Attribute.clone(attribute, null),
      }),
    );
  }

  void restore(QuillController controller) {
    controller.forceToggledStyle(style);
  }
}
