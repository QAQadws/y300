import '../document/forum_body_document.dart';
import 'forum_body_list_style.dart';

/// Resolves only inherited list presentation. It does not count items, walk
/// descendants, create source text, or grant block-flow format capability.
ForumBodyListStyle resolveForumBodyListStyle({
  required ForumBodyElement node,
  required ForumBodyListStyle parent,
  required void Function(String property, String value) onUnsupported,
}) {
  var type = parent.type;
  var position = parent.position;
  if (node.kind == ForumBodyElementKind.list) {
    type = node.tag == 'ol'
        ? ForumBodyListMarkerType.decimal
        : ForumBodyListMarkerType.disc;
    final hint = node.attributes['type']?.trim();
    final hinted = switch (hint) {
      '1' => ForumBodyListMarkerType.decimal,
      'a' => ForumBodyListMarkerType.lowerAlpha,
      'A' => ForumBodyListMarkerType.upperAlpha,
      'i' => ForumBodyListMarkerType.lowerRoman,
      'I' => ForumBodyListMarkerType.upperRoman,
      _ => _type(hint?.toLowerCase() ?? ''),
    };
    if (hinted != null) type = hinted;
    // Discuz emits ordered BBCode lists as UL, with these semantic classes.
    // The normal inline cascade below remains stronger than site defaults.
    final classes = node.attributes['class']?.split(RegExp(r'\s+')) ?? const [];
    if (classes.contains('litype_1')) {
      type = ForumBodyListMarkerType.decimal;
    } else if (classes.contains('litype_2')) {
      type = ForumBodyListMarkerType.lowerAlpha;
    } else if (classes.contains('litype_3')) {
      type = ForumBodyListMarkerType.upperAlpha;
    }
  }
  var typeImportant = false, positionImportant = false;
  for (final declaration in node.style.declarations) {
    final property = declaration.property;
    if (property != 'list-style' &&
        property != 'list-style-type' &&
        property != 'list-style-position') {
      continue;
    }
    final raw = declaration.value.trim().toLowerCase();
    ForumBodyListMarkerType? nextType;
    ForumBodyListMarkerPosition? nextPosition;
    final inherited = raw == 'inherit' || raw == 'unset';
    final initial = raw == 'initial';
    if (property == 'list-style-type') {
      nextType = inherited
          ? parent.type
          : initial
          ? ForumBodyListMarkerType.disc
          : _type(raw);
    } else if (property == 'list-style-position') {
      nextPosition = inherited
          ? parent.position
          : initial
          ? ForumBodyListMarkerPosition.outside
          : _position(raw);
    } else if (inherited || initial) {
      nextType = inherited ? parent.type : ForumBodyListMarkerType.disc;
      nextPosition = inherited
          ? parent.position
          : ForumBodyListMarkerPosition.outside;
    } else {
      final shorthand = _shorthand(raw);
      nextType = shorthand?.type;
      nextPosition = shorthand?.position;
    }
    if (nextType == null && nextPosition == null) {
      onUnsupported(property, declaration.value);
      continue;
    }
    if (nextType != null && (!typeImportant || declaration.important)) {
      type = nextType;
      typeImportant = declaration.important;
    }
    if (nextPosition != null && (!positionImportant || declaration.important)) {
      position = nextPosition;
      positionImportant = declaration.important;
    }
  }
  return type == parent.type && position == parent.position
      ? parent
      : ForumBodyListStyle(type: type, position: position);
}

ForumBodyListMarkerType? _type(String value) => switch (value) {
  'disc' => ForumBodyListMarkerType.disc,
  'circle' => ForumBodyListMarkerType.circle,
  'square' => ForumBodyListMarkerType.square,
  'decimal' => ForumBodyListMarkerType.decimal,
  'lower-alpha' || 'lower-latin' => ForumBodyListMarkerType.lowerAlpha,
  'upper-alpha' || 'upper-latin' => ForumBodyListMarkerType.upperAlpha,
  'lower-roman' => ForumBodyListMarkerType.lowerRoman,
  'upper-roman' => ForumBodyListMarkerType.upperRoman,
  'none' => ForumBodyListMarkerType.none,
  _ => null,
};

ForumBodyListMarkerPosition? _position(String value) => switch (value) {
  'outside' => ForumBodyListMarkerPosition.outside,
  'inside' => ForumBodyListMarkerPosition.inside,
  _ => null,
};

ForumBodyListStyle? _shorthand(String value) {
  final tokens = value.split(RegExp(r'\s+'));
  if (tokens.isEmpty || tokens.length > 3) return null;
  ForumBodyListMarkerType? type;
  ForumBodyListMarkerPosition? position;
  var noneCount = 0;
  for (final token in tokens) {
    if (token == 'none') {
      noneCount++;
    } else if (_type(token) case final marker?) {
      if (type != null) return null;
      type = marker;
    } else if (_position(token) case final place?) {
      if (position != null) return null;
      position = place;
    } else {
      // Marker images and custom CSS counters need a resource/format handler.
      return null;
    }
  }
  if (noneCount > (type == null ? 2 : 1)) return null;
  return ForumBodyListStyle(
    type:
        type ??
        (noneCount > 0
            ? ForumBodyListMarkerType.none
            : ForumBodyListMarkerType.disc),
    position: position ?? ForumBodyListMarkerPosition.outside,
  );
}
