/// Encodes only edit-draft metadata that is safe to persist locally.
final class PostEditDraftExtrasCodec {
  const PostEditDraftExtrasCodec();

  static const String baselineFingerprintKey = 'baselineFingerprint';

  String? baselineFingerprint(Map<String, String> extras) {
    final value = extras[baselineFingerprintKey]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Map<String, String> encode({required String baselineFingerprint}) {
    return <String, String>{baselineFingerprintKey: baselineFingerprint};
  }
}
