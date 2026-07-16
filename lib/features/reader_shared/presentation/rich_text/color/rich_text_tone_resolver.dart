import 'dart:ui';

import 'package:material_color_utilities/contrast/contrast.dart';
import 'package:material_color_utilities/hct/hct.dart';
import 'package:y300/features/reader_shared/presentation/rich_text/color/rich_text_color_contrast.dart';

abstract interface class RichTextToneResolver {
  Color resolveReadableForeground({
    required Color requested,
    required Color background,
    required Color fallback,
    required double minimumContrast,
  });
}

/// Raised when neither HCT tone candidates nor the semantic fallback are
/// readable on the supplied surface.
final class RichTextToneResolutionFailure implements Exception {
  const RichTextToneResolutionFailure({
    required this.minimumContrast,
    required this.bestCandidateContrast,
    required this.fallbackContrast,
  });

  final double minimumContrast;
  final double bestCandidateContrast;
  final double fallbackContrast;

  @override
  String toString() {
    return 'RichTextToneResolutionFailure('
        'minimumContrast: $minimumContrast, '
        'bestCandidateContrast: $bestCandidateContrast, '
        'fallbackContrast: $fallbackContrast)';
  }
}

/// Resolves readable foreground colors with Material HCT tone candidates.
///
/// The requested color is returned unchanged when it already meets the target.
/// Adjusted candidates preserve its visible hue/chroma as far as the sRGB
/// gamut permits. Every generated ARGB value is rechecked with Flutter's final
/// luminance calculation before it can be returned.
final class MaterialRichTextToneResolver implements RichTextToneResolver {
  const MaterialRichTextToneResolver({
    RichTextColorContrast contrast = const FlutterRichTextColorContrast(),
  }) : _contrast = contrast;

  static const _comparisonEpsilon = 0.000001;

  final RichTextColorContrast _contrast;

  @override
  Color resolveReadableForeground({
    required Color requested,
    required Color background,
    required Color fallback,
    required double minimumContrast,
  }) {
    _validateMinimumContrast(minimumContrast);
    _requireOpaqueBackground(background);

    final requestedVisible = _contrast.composite(requested, background);
    final requestedContrast = _contrast.contrastRatio(
      requestedVisible,
      background,
    );
    if (_meetsMinimum(requestedContrast, minimumContrast)) {
      return requested;
    }

    final backgroundHct = Hct.fromInt(background.toARGB32());
    final requestedHct = Hct.fromInt(requestedVisible.toARGB32());
    final fallbackVisible = _contrast.composite(fallback, background);
    final fallbackHct = Hct.fromInt(fallbackVisible.toARGB32());
    final targetTones = <double>[
      Contrast.lighter(tone: backgroundHct.tone, ratio: minimumContrast),
      Contrast.darker(tone: backgroundHct.tone, ratio: minimumContrast),
    ];
    final candidates = <_ReadableToneCandidate>[];
    var bestCandidateContrast = requestedContrast;

    for (final targetTone in targetTones) {
      if (targetTone < 0 || targetTone > 100) {
        continue;
      }
      final candidateHct = Hct.from(
        requestedHct.hue,
        requestedHct.chroma,
        targetTone,
      );
      final candidate = Color(candidateHct.toInt());
      final candidateContrast = _contrast.contrastRatio(candidate, background);
      if (candidateContrast > bestCandidateContrast) {
        bestCandidateContrast = candidateContrast;
      }
      if (!_meetsMinimum(candidateContrast, minimumContrast)) {
        continue;
      }
      candidates.add(
        _ReadableToneCandidate(
          color: candidate,
          requestedToneDelta: (candidateHct.tone - requestedHct.tone).abs(),
          fallbackToneDelta: (candidateHct.tone - fallbackHct.tone).abs(),
        ),
      );
    }

    if (candidates.isNotEmpty) {
      candidates.sort(_compareCandidates);
      return candidates.first.color;
    }

    final fallbackContrast = _contrast.contrastRatio(
      fallbackVisible,
      background,
    );
    if (_meetsMinimum(fallbackContrast, minimumContrast)) {
      return fallback;
    }
    throw RichTextToneResolutionFailure(
      minimumContrast: minimumContrast,
      bestCandidateContrast: bestCandidateContrast,
      fallbackContrast: fallbackContrast,
    );
  }

  int _compareCandidates(
    _ReadableToneCandidate first,
    _ReadableToneCandidate second,
  ) {
    final requestedDelta = first.requestedToneDelta - second.requestedToneDelta;
    if (requestedDelta.abs() > _comparisonEpsilon) {
      return requestedDelta < 0 ? -1 : 1;
    }
    final fallbackDelta = first.fallbackToneDelta - second.fallbackToneDelta;
    if (fallbackDelta.abs() > _comparisonEpsilon) {
      return fallbackDelta < 0 ? -1 : 1;
    }
    return first.color.toARGB32().compareTo(second.color.toARGB32());
  }

  bool _meetsMinimum(double actual, double minimum) {
    return actual >= minimum;
  }

  void _validateMinimumContrast(double minimumContrast) {
    if (!minimumContrast.isFinite ||
        minimumContrast < 1 ||
        minimumContrast > 21) {
      throw ArgumentError.value(
        minimumContrast,
        'minimumContrast',
        'Must be finite and between 1 and 21.',
      );
    }
  }

  void _requireOpaqueBackground(Color background) {
    if ((background.toARGB32() >>> 24) != 0xFF) {
      throw ArgumentError.value(
        background,
        'background',
        'Resolve the reading surface to an opaque color first.',
      );
    }
  }
}

final class _ReadableToneCandidate {
  const _ReadableToneCandidate({
    required this.color,
    required this.requestedToneDelta,
    required this.fallbackToneDelta,
  });

  final Color color;
  final double requestedToneDelta;
  final double fallbackToneDelta;
}
