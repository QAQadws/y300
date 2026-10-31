enum ForumBodyLengthUnit { px, pt, em, rem, percent, auto }

/// CSS lengths remain relative until the containing block's width is known.
final class ForumBodyLength {
  const ForumBodyLength(this.value, [this.unit = ForumBodyLengthUnit.px]);
  static const zero = ForumBodyLength(0);
  final double value;
  final ForumBodyLengthUnit unit;

  static final _pattern = RegExp(
    r'^([+-]?(?:\d+(?:\.\d*)?|\.\d+))(px|pt|em|rem|%)?$',
  );

  static ForumBodyLength? tryParse(String raw) {
    final text = raw.trim().toLowerCase();
    if (text == 'auto') {
      return const ForumBodyLength(0, ForumBodyLengthUnit.auto);
    }
    final match = _pattern.firstMatch(text);
    if (match == null) return null;
    final value = double.tryParse(match[1]!);
    if (value == null || !value.isFinite || (match[2] == null && value != 0)) {
      return null;
    }
    return ForumBodyLength(value, switch (match[2]) {
      'pt' => ForumBodyLengthUnit.pt,
      'em' => ForumBodyLengthUnit.em,
      'rem' => ForumBodyLengthUnit.rem,
      '%' => ForumBodyLengthUnit.percent,
      _ => ForumBodyLengthUnit.px,
    });
  }

  double resolve({
    required double fontSize,
    required double rootFontSize,
    required double reference,
  }) => switch (unit) {
    ForumBodyLengthUnit.px => value,
    ForumBodyLengthUnit.pt => value * 96 / 72,
    ForumBodyLengthUnit.em => value * fontSize,
    ForumBodyLengthUnit.rem => value * rootFontSize,
    ForumBodyLengthUnit.percent => value * reference / 100,
    ForumBodyLengthUnit.auto => throw StateError(
      'Auto length needs box layout',
    ),
  };

  ForumBodyLength computed({
    required double fontSize,
    required double rootFontSize,
  }) => unit == ForumBodyLengthUnit.percent || unit == ForumBodyLengthUnit.auto
      ? this
      : ForumBodyLength(
          resolve(fontSize: fontSize, rootFontSize: rootFontSize, reference: 0),
        );

  @override
  bool operator ==(Object other) =>
      other is ForumBodyLength && value == other.value && unit == other.unit;
  @override
  int get hashCode => Object.hash(value, unit);
}

final class ForumBodyInsets {
  const ForumBodyInsets({
    this.top = ForumBodyLength.zero,
    this.right = ForumBodyLength.zero,
    this.bottom = ForumBodyLength.zero,
    this.left = ForumBodyLength.zero,
  });
  final ForumBodyLength top;
  final ForumBodyLength right;
  final ForumBodyLength bottom;
  final ForumBodyLength left;

  static ForumBodyInsets? tryParse(String raw) {
    final parts = raw.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.length > 4) return null;
    final lengths = parts.map(ForumBodyLength.tryParse).toList();
    if (lengths.any((part) => part == null)) return null;
    final first = lengths[0]!;
    final second = lengths.length > 1 ? lengths[1]! : first;
    return ForumBodyInsets(
      top: first,
      right: second,
      bottom: lengths.length > 2 ? lengths[2]! : first,
      left: lengths.length > 3 ? lengths[3]! : second,
    );
  }
}
