import 'complex_slice.dart';

final class HtmlComplexFitResult {
  const HtmlComplexFitResult({
    required this.slice,
    required this.measuredHeight,
    required this.probeCount,
    required this.cacheHitCount,
    required this.fits,
    required this.exhaustedAtom,
    required this.requiresFreshPage,
    required this.budgetExceeded,
    this.oversizedMinimumFragment = false,
  }) : assert(measuredHeight >= 0),
       assert(probeCount >= 0),
       assert(cacheHitCount >= 0);

  final HtmlComplexSlice slice;

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

  /// Search was limited by probes, candidate size or the grapheme window.
  final bool budgetExceeded;

  /// A fresh-page indivisible minimum used the finite exceptional size limit.
  final bool oversizedMinimumFragment;
}
