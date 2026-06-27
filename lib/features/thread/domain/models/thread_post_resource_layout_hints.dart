import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';

enum ThreadPostResourceLayoutHintSource {
  htmlAttribute,
  cachedDimension,
  contentDefault,
}

class ThreadPostResourceDimension {
  const ThreadPostResourceDimension({
    required this.width,
    required this.height,
  });

  final double width;
  final double height;

  bool get isValid =>
      width.isFinite && height.isFinite && width > 0 && height > 0;

  double get aspectRatio => width / height;
}

class ThreadPostBlockImageLayoutHint {
  const ThreadPostBlockImageLayoutHint({
    required this.aspectRatio,
    required this.source,
    required this.lockForCurrentBuild,
  });

  final double aspectRatio;
  final ThreadPostResourceLayoutHintSource source;
  final bool lockForCurrentBuild;

  String get signature =>
      '${aspectRatio.toStringAsFixed(6)}|${source.name}|$lockForCurrentBuild';
}

class ThreadPostInlineImageLayoutHint {
  const ThreadPostInlineImageLayoutHint({
    required this.width,
    required this.height,
    required this.source,
    required this.lockForCurrentBuild,
  });

  final double width;
  final double height;
  final ThreadPostResourceLayoutHintSource source;
  final bool lockForCurrentBuild;

  ThreadPostResourceDimension get dimension =>
      ThreadPostResourceDimension(width: width, height: height);

  String get signature =>
      '${width.toStringAsFixed(3)}x${height.toStringAsFixed(3)}|${source.name}|$lockForCurrentBuild';
}

class ThreadPostResourceLayoutHints {
  const ThreadPostResourceLayoutHints({
    this.blockImages = const <String, ThreadPostBlockImageLayoutHint>{},
    this.inlineImages = const <String, ThreadPostInlineImageLayoutHint>{},
  });

  static const empty = ThreadPostResourceLayoutHints();

  final Map<String, ThreadPostBlockImageLayoutHint> blockImages;
  final Map<String, ThreadPostInlineImageLayoutHint> inlineImages;

  ThreadPostBlockImageLayoutHint? blockImage(ThreadPostImageBlock image) {
    return blockImages[blockImageKey(image)];
  }

  ThreadPostInlineImageLayoutHint? inlineImage(ThreadPostInlineImage image) {
    return inlineImages[inlineImageKey(image)];
  }

  String get signature {
    if (blockImages.isEmpty && inlineImages.isEmpty) {
      return 'empty';
    }
    final parts = <String>[
      for (final entry in _sortedBlockImageEntries())
        'b:${entry.key}:${entry.value.signature}',
      for (final entry in _sortedInlineImageEntries())
        'i:${entry.key}:${entry.value.signature}',
    ];
    return parts.join(';');
  }

  static String blockImageKey(ThreadPostImageBlock image) {
    final anchorId = image.anchorId.trim();
    if (anchorId.isNotEmpty) {
      return 'anchor:$anchorId';
    }
    return 'block:${image.index}|${image.url}|${image.rawUrl}';
  }

  static String inlineImageKey(ThreadPostInlineImage image) {
    final width = image.originalWidth;
    final height = image.originalHeight;
    return 'inline:${image.url}|${image.rawUrl}|$width|$height';
  }

  List<MapEntry<String, ThreadPostBlockImageLayoutHint>>
  _sortedBlockImageEntries() {
    final entries = blockImages.entries.toList();
    entries.sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }

  List<MapEntry<String, ThreadPostInlineImageLayoutHint>>
  _sortedInlineImageEntries() {
    final entries = inlineImages.entries.toList();
    entries.sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }
}
