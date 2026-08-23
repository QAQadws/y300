import 'data_parse_exception.dart';

abstract final class StrictJson {
  static Map<String, Object?> map(
    Object? value, {
    String code = 'map_expected',
  }) {
    if (value is! Map) throw DataParseException(code);
    return <String, Object?>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }

  static String string(
    Object? value, {
    required String code,
    bool allowEmpty = false,
  }) {
    if (value is! String) throw DataParseException(code);
    final result = value.trim();
    if (!allowEmpty && result.isEmpty) throw DataParseException(code);
    return result;
  }

  static int integer(
    Object? value, {
    required String code,
    bool allowNegative = true,
  }) {
    final result = switch (value) {
      int value => value,
      String value => int.tryParse(value.trim()),
      _ => null,
    };
    if (result == null || (!allowNegative && result < 0)) {
      throw DataParseException(code);
    }
    return result;
  }

  static bool boolean(Object? value, {required String code}) {
    if (value is bool) return value;
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case '1':
        case 'true':
          return true;
        case '0':
        case 'false':
          return false;
      }
    }
    throw DataParseException(code);
  }

  static List<Object?> list(Object? value, {required String code}) {
    if (value is! List) throw DataParseException(code);
    return List<Object?>.from(value);
  }
}
