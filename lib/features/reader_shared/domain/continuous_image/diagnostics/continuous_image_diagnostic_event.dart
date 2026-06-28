enum ContinuousImageDiagnosticEventType {
  imageItemBuilt,
  imagePlaceholderLaidOut,
  imageDecodeResolved,
  imageDimensionPersisted,
  imageAspectRatioApplied,
  imageAspectRatioDeferredAboveViewport,
  imageOpened,
  extentRecorded,
  scrollOffsetCompensated,
  activeImageChanged,
  prefetchScheduled,
  prefetchCancelled,
  prefetchCompleted,
}

class ContinuousImageDiagnosticEvent {
  const ContinuousImageDiagnosticEvent({
    required this.time,
    required this.type,
    required this.itemId,
    required this.ownerId,
    required this.index,
    this.source,
    this.aspectRatio,
    this.width,
    this.height,
    this.message = '',
  });

  final DateTime time;
  final ContinuousImageDiagnosticEventType type;
  final String itemId;
  final String ownerId;
  final int index;
  final String? source;
  final double? aspectRatio;
  final int? width;
  final int? height;
  final String message;

  String toLogFields() {
    final fields = <String>[
      'continuous=${type.name}',
      'owner=$ownerId',
      'item=$itemId',
      'index=$index',
      if (source?.trim().isNotEmpty == true) 'source=$source',
      if (aspectRatio != null) 'ratio=${aspectRatio!.toStringAsFixed(4)}',
      if (width != null && height != null) 'size=${width}x$height',
      if (message.trim().isNotEmpty) message,
    ];
    return fields.join(' ');
  }
}
