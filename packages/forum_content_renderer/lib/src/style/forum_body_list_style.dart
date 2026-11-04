enum ForumBodyListMarkerType {
  disc,
  circle,
  square,
  decimal,
  lowerAlpha,
  upperAlpha,
  lowerRoman,
  upperRoman,
  none,
}

enum ForumBodyListMarkerPosition { outside, inside }

/// Inherited list presentation only. Ordinals belong to the consuming list's
/// structural counter, and labels never become body/source text.
final class ForumBodyListStyle {
  const ForumBodyListStyle({
    this.type = ForumBodyListMarkerType.disc,
    this.position = ForumBodyListMarkerPosition.outside,
  });
  final ForumBodyListMarkerType type;
  final ForumBodyListMarkerPosition position;

  String? labelFor(int ordinal) => switch (type) {
    ForumBodyListMarkerType.none => null,
    ForumBodyListMarkerType.disc => '•',
    ForumBodyListMarkerType.circle => '◦',
    ForumBodyListMarkerType.square => '▪',
    ForumBodyListMarkerType.decimal => '$ordinal.',
    ForumBodyListMarkerType.lowerAlpha => '${_alpha(ordinal)}.',
    ForumBodyListMarkerType.upperAlpha => '${_alpha(ordinal).toUpperCase()}.',
    ForumBodyListMarkerType.lowerRoman => '${_roman(ordinal)}.',
    ForumBodyListMarkerType.upperRoman => '${_roman(ordinal).toUpperCase()}.',
  };

  static String _alpha(int value) {
    if (value <= 0) return '$value';
    final units = <int>[];
    while (value > 0) {
      value--;
      units.add(0x61 + value % 26);
      value ~/= 26;
    }
    return String.fromCharCodes(units.reversed);
  }

  static String _roman(int value) {
    // CSS's built-in roman counter falls back to decimal outside this range.
    if (value <= 0 || value > 3999) return '$value';
    final result = StringBuffer();
    for (final (amount, token) in const [
      (1000, 'm'),
      (900, 'cm'),
      (500, 'd'),
      (400, 'cd'),
      (100, 'c'),
      (90, 'xc'),
      (50, 'l'),
      (40, 'xl'),
      (10, 'x'),
      (9, 'ix'),
      (5, 'v'),
      (4, 'iv'),
      (1, 'i'),
    ]) {
      while (value >= amount) {
        result.write(token);
        value -= amount;
      }
    }
    return result.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForumBodyListStyle &&
          type == other.type &&
          position == other.position;
  @override
  int get hashCode => Object.hash(type, position);
}
