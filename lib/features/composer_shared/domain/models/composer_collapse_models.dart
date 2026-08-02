import 'dart:collection';

/// The only collapse wire mode currently supported by the composer.
enum ComposerCollapseMode {
  collapsed(0);

  const ComposerCollapseMode(this.wireValue);

  final int wireValue;

  static ComposerCollapseMode? fromWireValue(String value) {
    return value.trim() == '0' ? ComposerCollapseMode.collapsed : null;
  }
}

enum ComposerCollapseParseIssueCode {
  malformedOpening,
  unsupportedMode,
  unexpectedClosing,
  missingClosing,
  maximumDepthExceeded,
}

final class ComposerCollapseParseIssue {
  const ComposerCollapseParseIssue({required this.code, required this.offset});

  final ComposerCollapseParseIssueCode code;
  final int offset;
}

/// A recursively parsed message. Text parts retain their original BBCode so
/// the collapse layer never rewrites unrelated tags.
final class ComposerCollapseDocument {
  ComposerCollapseDocument({
    required this.source,
    required List<ComposerCollapsePart> parts,
    List<ComposerCollapseParseIssue>? issues,
    this.isLossless = true,
  }) : parts = UnmodifiableListView<ComposerCollapsePart>(parts),
       issues = UnmodifiableListView<ComposerCollapseParseIssue>(
         issues ?? const <ComposerCollapseParseIssue>[],
       );

  final String source;
  final List<ComposerCollapsePart> parts;
  final List<ComposerCollapseParseIssue> issues;
  final bool isLossless;

  bool get hasCollapse => parts.any((part) => part is ComposerCollapseBlock);

  ComposerCollapseDocument copyWith({
    String? source,
    List<ComposerCollapsePart>? parts,
    List<ComposerCollapseParseIssue>? issues,
    bool? isLossless,
  }) {
    return ComposerCollapseDocument(
      source: source ?? this.source,
      parts: parts ?? this.parts,
      issues: issues ?? this.issues,
      isLossless: isLossless ?? this.isLossless,
    );
  }
}

sealed class ComposerCollapsePart {
  const ComposerCollapsePart();
}

final class ComposerCollapseText extends ComposerCollapsePart {
  const ComposerCollapseText(this.value);

  final String value;
}

final class ComposerCollapseBlock extends ComposerCollapsePart {
  const ComposerCollapseBlock({
    required this.id,
    required this.title,
    required this.body,
    this.mode = ComposerCollapseMode.collapsed,
    this.rawOpeningLine,
    this.rawClosing,
  });

  /// Session-local identity. It is never serialized into BBCode.
  final String id;
  final String title;
  final ComposerCollapseDocument body;
  final ComposerCollapseMode mode;

  /// Original validated opening header including its mandatory line ending.
  final String? rawOpeningLine;
  final String? rawClosing;

  ComposerCollapseBlock copyWith({
    String? id,
    String? title,
    ComposerCollapseDocument? body,
    ComposerCollapseMode? mode,
  }) {
    return ComposerCollapseBlock(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      mode: mode ?? this.mode,
      rawOpeningLine: title == null ? rawOpeningLine : null,
      rawClosing: rawClosing,
    );
  }
}

final class ComposerCollapseIdentityFactory {
  ComposerCollapseIdentityFactory({String prefix = 'collapse'})
    : _prefix = prefix;

  final String _prefix;
  int _next = 0;

  String next() => '$_prefix-${_next++}';
}
