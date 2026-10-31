import '../document/forum_body_document.dart';
import 'forum_body_length.dart';

/// Non-inherited box values have their own shorthand/longhand cascade.
final class ForumBodyBoxResolver {
  const ForumBodyBoxResolver();

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
