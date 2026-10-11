/// Establishes a canonical authenticated Discuz viewer identity.
///
/// Unlike profile compatibility paths, this never falls back to a content
/// owner's ID. Its range is exact on both Dart VM and web targets.
String? discuzMessageAttentionIdentity(Object? value) {
  const maximumExactInteger = 9007199254740991;
  final text = switch (value) {
    String value => value,
    int value when value > 0 && value <= maximumExactInteger =>
      value.toString(),
    _ => null,
  };
  if (text == null || _positiveDecimal.stringMatch(text) != text) return null;
  final parsed = int.tryParse(text);
  return parsed != null && parsed <= maximumExactInteger ? text : null;
}

final _positiveDecimal = RegExp(r'^[1-9][0-9]*$');
