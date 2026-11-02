part of 'forum_body_emphasis_line_layout.dart';

/// Immutable plan only: actual font keys, per-size scaling, geometry and draw
/// input. Holds no cache, native layout/picture handle or owner callback.
final class ForumBodyEmphasisLineMetrics {
  ForumBodyEmphasisLineMetrics._({
    required this.input,
    required this.baseRequest,
    required this.requestWidth,
    required this.textScaler,
    required this.baseOffset,
    required this.fontBounds,
    required this.width,
    required this.height,
    required this.alphabeticBaseline,
    required this.pictureInput,
    required Object baseKey,
    required List<Object> markKeys,
    required List<ForumBodyEmphasisMarkInput> markInputs,
    required List<int> unitMarks,
    required List<ForumBodyEmphasisLineMark> marks,
  }) : _baseKey = baseKey,
       _markKeys = UnmodifiableListView(markKeys),
       _markInputs = UnmodifiableListView(markInputs),
       _unitMarks = UnmodifiableListView(unitMarks),
       marks = UnmodifiableListView(marks);
  static const revision = 1;
  final ForumBodyEmphasisTextInput input;
  final ForumBodyTextRequest baseRequest;
  final double requestWidth;
  final TextScaler textScaler;
  Map<double, double> get effectiveScales => (textScaler as _LineScaler).values;
  final Offset baseOffset;
  final Rect fontBounds;
  final double width;
  final double height;
  final double alphabeticBaseline;
  final List<ForumBodyEmphasisLineMark> marks;

  /// A numeric draw specification, not an acquired/recorded picture or source
  /// authority. Page admission may include it without producing any drawing.
  final ForumBodyTextPictureInput pictureInput;
  final Object _baseKey;
  final List<Object> _markKeys;
  final List<ForumBodyEmphasisMarkInput> _markInputs;
  final List<int> _unitMarks;

  /// Temporary native fonts needed for measurement/visible qualification.
  /// Final visible retention consists of the base plus pictureInput instead.
  Iterable<ForumBodyNativeRequestSlot> get nativeFootprint sync* {
    yield (
      request: baseRequest,
      width: requestWidth,
      minimumLineCount: input.content.projection.text.isEmpty ? 0 : 1,
    );
    for (final mark in _markInputs) {
      yield (
        request: ForumBodyEmphasisMarkRequest(mark),
        width: requestWidth,
        minimumLineCount: 1,
      );
    }
  }
}

/// Uses the exact same native measurement and placement transaction as visible
/// preparation, but retires font leases and returns numbers without recording.
final class ForumBodyEmphasisLineMetricsPreparation {
  ForumBodyEmphasisLineMetricsPreparation({
    required ForumBodyEmphasisTextInput input,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    ForumBodyTextRequest? baseRequest,
    double width = 16384,
    TextScaler textScaler = TextScaler.noScaling,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _work = ForumBodyEmphasisLinePreparation._work(
         input: input,
         cache: cache,
         ensureOwner: ensureOwner,
         baseRequest: baseRequest,
         width: width,
         textScaler: textScaler,
         measureOnly: true,
         additionalOwnedLeases: additionalOwnedLeases,
       );
  final ForumBodyEmphasisLinePreparation _work;
  bool get isReady => _work.isReady;
  bool get cacheMiss => _work.cacheMiss;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases =>
      _work.nativeLeases;
  ForumBodyEmphasisLineStep advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) => _work.advance(maxParts: maxParts, cachedOnly: cachedOnly);
  ForumBodyEmphasisLineMetrics takeMetrics() => _work._takeMetrics();
  void close() => _work.close();
}
