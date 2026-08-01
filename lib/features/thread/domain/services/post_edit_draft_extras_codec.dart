import 'dart:convert';

/// Encodes only edit-draft metadata that is safe to persist locally.
final class PostEditDraftExtrasCodec {
  const PostEditDraftExtrasCodec();

  static const String baselineFingerprintKey = 'baselineFingerprint';
  static const String deletedAidTombstonesKey = 'deletedAidTombstones';

  String? baselineFingerprint(Map<String, String> extras) {
    final value = extras[baselineFingerprintKey]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Set<String> deletedAidTombstones(Map<String, String> extras) {
    final raw = extras[deletedAidTombstonesKey];
    if (raw == null || raw.trim().isEmpty) {
      return const <String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<Object?>) {
        return const <String>{};
      }
      return {
        for (final value in decoded)
          if (value is String && _isPositiveAid(value.trim())) value.trim(),
      };
    } on Object {
      return const <String>{};
    }
  }

  Map<String, String> encode({
    required String baselineFingerprint,
    Iterable<String> deletedAidTombstones = const <String>[],
  }) {
    final normalized =
        deletedAidTombstones
            .map((aid) => aid.trim())
            .where(_isPositiveAid)
            .toSet()
            .toList()
          ..sort();
    return <String, String>{
      baselineFingerprintKey: baselineFingerprint,
      if (normalized.isNotEmpty)
        deletedAidTombstonesKey: jsonEncode(normalized),
    };
  }

  static bool _isPositiveAid(String value) {
    return RegExp(r'^[1-9]\d*$').hasMatch(value);
  }
}
