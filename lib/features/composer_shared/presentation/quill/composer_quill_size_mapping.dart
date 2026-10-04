import 'package:forum_content_renderer/forum_content_renderer.dart';

/// Flutter Quill's paragraph default is 16px, so Discuz size 3 must map to 16.
const Map<int, String> composerDiscuzSizeToQuillSize = {
  1: '12',
  2: '14',
  3: '16',
  4: '18',
  5: '20',
  6: '24',
  7: '28',
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
    if ((parsed - quillSize).abs() < 0.001) {
      return entry.key.toString();
    }
  }

  return DiscuzFontSizePolicy.normalize(raw)?.toString();
}
