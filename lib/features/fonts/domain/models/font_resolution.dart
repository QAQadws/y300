import 'font_library_failure.dart';
import 'resolved_font.dart';

final class FontResolution {
  const FontResolution({
    required this.requestedId,
    required this.font,
    this.failure,
  });

  final String requestedId;
  final ResolvedFont font;
  final FontLibraryFailure? failure;

  bool get isFallback => failure != null;
}
