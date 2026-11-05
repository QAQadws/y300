import '../document/forum_body_document.dart';
import 'forum_body_length.dart';
import 'forum_body_box_style.dart';

/// Non-inherited box values have their own shorthand/longhand cascade.
final class ForumBodyBoxResolver {
  const ForumBodyBoxResolver();

  ForumBodyBoxStyle resolveBoxStyle({
    required ForumBodyElement node,
    required ForumBodyBoxStyle parent,
    required double fontSize,
    required double rootFontSize,
    required void Function(String property, String value) onUnsupported,
  }) {
    var width = const ForumBodyBoxStyle().width;
    ForumBodyLength? height;
    var minimum = ForumBodyLength.zero;
    ForumBodyLength? maximum;
    var sizing = ForumBodyBoxSizing.contentBox;
    final important = <String>{};
    for (final declaration in node.style.declarations) {
      final name = declaration.property;
      if (!const {
        'width',
        'height',
        'min-width',
        'max-width',
        'box-sizing',
      }.contains(name)) {
        continue;
      }
      final raw = declaration.value.trim().toLowerCase();
      if (name == 'box-sizing') {
        final candidate = switch (raw) {
          'inherit' => parent.sizing,
          'initial' ||
          'unset' ||
          'content-box' => ForumBodyBoxSizing.contentBox,
          'border-box' => ForumBodyBoxSizing.borderBox,
          _ => null,
        };
        if (candidate == null) {
          onUnsupported(name, declaration.value);
        } else if (!important.contains(name) || declaration.important) {
          sizing = candidate;
          if (declaration.important) important.add(name);
        }
        continue;
      }
      ForumBodyLength? candidate;
      final initial = switch (name) {
        'min-width' => ForumBodyLength.zero,
        'width' || 'height' when node.kind == ForumBodyElementKind.image =>
          const ForumBodyLength(0, ForumBodyLengthUnit.auto),
        _ => null,
      };
      if (raw == 'inherit') {
        candidate = switch (name) {
          'width' => parent.width ?? initial,
          'height' => parent.height ?? initial,
          'min-width' => parent.minWidth,
          _ => parent.maxWidth,
        };
      } else if (raw == 'initial' ||
          raw == 'unset' ||
          (raw == 'auto' && name != 'max-width') ||
          (raw == 'none' && name == 'max-width')) {
        candidate = initial;
      } else {
        final parsed = ForumBodyLength.tryParse(raw);
        if (parsed == null ||
            parsed.unit == ForumBodyLengthUnit.auto ||
            parsed.value < 0) {
          onUnsupported(name, declaration.value);
          continue;
        }
        candidate = parsed.computed(
          fontSize: fontSize,
          rootFontSize: rootFontSize,
        );
        if (!candidate.value.isFinite) {
          onUnsupported(name, declaration.value);
          continue;
        }
      }
      if (!important.contains(name) || declaration.important) {
        switch (name) {
          case 'width':
            width = candidate;
          case 'height':
            height = candidate;
          case 'min-width':
            minimum = candidate!;
          case 'max-width':
            maximum = candidate;
        }
        if (declaration.important) important.add(name);
      }
    }
    return ForumBodyBoxStyle(
      width: width,
      height: height,
      minWidth: minimum,
      maxWidth: maximum,
      sizing: sizing,
    );
  }

  ForumBodyInsets resolve({
    required ForumBodyElement node,
    required String property,
    required ForumBodyInsets defaults,
    required ForumBodyInsets parent,
    required double fontSize,
    required double rootFontSize,
    required void Function(String property, String value) onUnsupported,
  }) {
    List<ForumBodyLength> sidesOf(ForumBodyInsets insets) => [
      insets.top,
      insets.right,
      insets.bottom,
      insets.left,
    ];
    final values = sidesOf(defaults);
    final inherited = sidesOf(parent);
    final important = [false, false, false, false];
    const sides = ['top', 'right', 'bottom', 'left'];
    for (final declaration in node.style.declarations) {
      final name = declaration.property;
      final side = sides.indexWhere((side) => name == '$property-$side');
      if (name != property && side < 0) continue;
      final raw = declaration.value.toLowerCase();
      final indices = side < 0 ? [0, 1, 2, 3] : [side];
      List<ForumBodyLength>? candidate;
      if (raw == 'inherit') {
        candidate = inherited;
      } else if (raw == 'initial' || raw == 'unset') {
        candidate = List.filled(4, ForumBodyLength.zero);
      } else if (side < 0) {
        final parsed = ForumBodyInsets.tryParse(raw);
        if (parsed != null) candidate = sidesOf(parsed);
      } else {
        final parsed = ForumBodyLength.tryParse(raw);
        if (parsed != null) candidate = List.filled(4, parsed);
      }
      if (candidate == null ||
          indices.any(
            (i) =>
                property == 'padding' &&
                (candidate![i].unit == ForumBodyLengthUnit.auto ||
                    candidate[i].value < 0),
          )) {
        onUnsupported(name, declaration.value);
        continue;
      }
      final computed = candidate
          .map(
            (value) =>
                value.computed(fontSize: fontSize, rootFontSize: rootFontSize),
          )
          .toList();
      if (indices.any((i) => !computed[i].value.isFinite)) {
        onUnsupported(name, declaration.value);
        continue;
      }
      for (final i in indices) {
        if (!important[i] || declaration.important) {
          values[i] = computed[i];
          important[i] = declaration.important;
        }
      }
    }
    return ForumBodyInsets(
      top: values[0],
      right: values[1],
      bottom: values[2],
      left: values[3],
    );
  }
}
