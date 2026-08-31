import 'package:flutter/foundation.dart';
import 'package:y300/features/reader_shared/domain/rich_text/document/rich_document.dart';

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

@immutable
class ThreadPostBlockImageLayoutHint {
  const ThreadPostBlockImageLayoutHint({
    required this.aspectRatio,
    required this.source,
    required this.lockForCurrentBuild,
  });

  final double aspectRatio;
  final ThreadPostResourceLayoutHintSource source;
  final bool lockForCurrentBuild;

  /// Legacy string fingerprint — kept for backward compatibility.
  String get signature =>
      '${aspectRatio.toStringAsFixed(6)}|${source.name}|$lockForCurrentBuild';

  @override
  bool operator ==(Object other) =>
      other is ThreadPostBlockImageLayoutHint &&
      aspectRatio == other.aspectRatio &&
      source == other.source &&
      lockForCurrentBuild == other.lockForCurrentBuild;

  @override
  int get hashCode => Object.hash(aspectRatio, source, lockForCurrentBuild);
}

@immutable
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

  /// Legacy string fingerprint — kept for backward compatibility.
  String get signature =>
      '${width.toStringAsFixed(3)}x${height.toStringAsFixed(3)}|${source.name}|$lockForCurrentBuild';

  @override
  bool operator ==(Object other) =>
      other is ThreadPostInlineImageLayoutHint &&
      width == other.width &&
      height == other.height &&
      source == other.source &&
      lockForCurrentBuild == other.lockForCurrentBuild;

  @override
  int get hashCode => Object.hash(width, height, source, lockForCurrentBuild);
}

@immutable
class ThreadPostResourceLayoutHints {
  const ThreadPostResourceLayoutHints({
    this.blockImages = const <String, ThreadPostBlockImageLayoutHint>{},
    this.inlineImages = const <String, ThreadPostInlineImageLayoutHint>{},
  });

  static const empty = ThreadPostResourceLayoutHints();

  final Map<String, ThreadPostBlockImageLayoutHint> blockImages;
  final Map<String, ThreadPostInlineImageLayoutHint> inlineImages;

  ThreadPostBlockImageLayoutHint? blockImage(RichImageBlock image) {
    return blockImages[blockImageKey(image)];
  }

  ThreadPostInlineImageLayoutHint? inlineImage(RichInlineImage image) {
    return inlineImages[inlineImageKey(image)];
  }

  /// Legacy string fingerprint — kept for backward compatibility.
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

  static String blockImageKey(RichImageBlock image) {
    final anchorId = image.anchorId.trim();
    if (anchorId.isNotEmpty) {
      return 'anchor:$anchorId';
    }
    return 'block:${image.index}|${image.url}|${image.rawUrl}';
  }

  static String inlineImageKey(RichInlineImage image) {
    final width = image.originalWidth;
    final height = image.originalHeight;
    return 'inline:${image.url}|${image.rawUrl}|$width|$height';
  }

  @override
  bool operator ==(Object other) {
    if (other is! ThreadPostResourceLayoutHints) return false;
    if (blockImages.length != other.blockImages.length) return false;
    if (inlineImages.length != other.inlineImages.length) return false;
    for (final entry in blockImages.entries) {
      if (other.blockImages[entry.key] != entry.value) return false;
    }
    for (final entry in inlineImages.entries) {
      if (other.inlineImages[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([
    ...(_sortedBlockImageEntries().map((e) => Object.hash(e.key, e.value))),
    ...(_sortedInlineImageEntries().map((e) => Object.hash(e.key, e.value))),
  ]);

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
