import 'package:flutter/foundation.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_slice.dart';

@immutable
final class NovelReaderComplexHtmlFitResult {
  const NovelReaderComplexHtmlFitResult({
    required this.slice,
    required this.measuredHeight,
    required this.probeCount,
    required this.cacheHitCount,
    required this.fits,
    required this.exhaustedAtom,
    required this.requiresFreshPage,
    required this.budgetExceeded,
  }) : assert(measuredHeight >= 0),
       assert(probeCount >= 0),
       assert(cacheHitCount >= 0);

  final NovelReaderComplexHtmlSlice slice;

  /// Height of the complete measured candidate, including any page buffer.
  final double measuredHeight;

  /// Number of calls made to the measurement session for this search.
  final int probeCount;

  /// Number of local or measurement-session cache hits.
  final int cacheHitCount;
  final bool fits;
  final bool exhaustedAtom;

  /// The caller must flush its current page before appending [slice].
  final bool requiresFreshPage;

  /// The best verified result was returned after the hard probe limit.
  final bool budgetExceeded;
}
