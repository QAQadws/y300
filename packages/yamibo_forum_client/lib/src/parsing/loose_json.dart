// ignore_for_file: public_member_api_docs

typedef JsonMap = Map<String, Object?>;

abstract final class LooseJson {
  static String string(Object? value, {String fallback = ''}) =>
      value?.toString() ?? fallback;

  static int integer(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static bool boolean(Object? value, {bool fallback = false}) {
    if (value is bool) return value;
    return switch (value?.toString().toLowerCase()) {
      '1' || 'true' => true,
      '0' || 'false' => false,
      _ => fallback,
    };
  }

  static JsonMap map(Object? value) {
    if (value is! Map) return <String, Object?>{};
    return <String, Object?>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }

  static List<Object?> list(Object? value) =>
      value is List ? List<Object?>.from(value) : <Object?>[];
}
