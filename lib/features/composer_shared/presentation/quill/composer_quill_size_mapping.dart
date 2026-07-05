const Map<int, String> composerDiscuzSizeToQuillSize = {
  1: '10',
  2: '12',
  3: '14',
  4: '16',
  5: '18',
  6: '20',
  7: '24',
};

String? composerQuillSizeForDiscuzSize(int discuzSize) {
  return composerDiscuzSizeToQuillSize[discuzSize];
}

String? composerDiscuzSizeForQuillSize(Object? value) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final parsed = double.tryParse(raw);
  if (parsed == null) {
    return null;
  }

  for (final entry in composerDiscuzSizeToQuillSize.entries) {
    final quillSize = double.parse(entry.value);
    if (parsed == quillSize) {
      return entry.key.toString();
    }
  }

  final legacyDiscuzSize = int.tryParse(raw);
  if (legacyDiscuzSize == null ||
      legacyDiscuzSize < 1 ||
      legacyDiscuzSize > 7) {
    return null;
  }
  return legacyDiscuzSize.toString();
}
