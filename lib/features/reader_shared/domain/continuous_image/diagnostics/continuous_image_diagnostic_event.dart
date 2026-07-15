enum ContinuousImageDiagnosticEventType {
  readerSessionCreated,
  initialRestoreStarted,
  initialRestoreCompleted,
  seekPreviewChanged,
  seekStarted,
  seekReached,
  seekSuperseded,
  seekFailed,
  pageChanged,
  zoomActivated,
  zoomDeactivated,
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
    this.readerKind,
    this.mode,
    this.generation,
    this.targetIndex,
    this.status,
    this.result,
    this.preloadKind,
    this.applied,
    this.elapsedMs,
    this.correctionDelta,
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
  final String? readerKind;
  final String? mode;
  final int? generation;
  final int? targetIndex;
  final String? status;
  final String? result;
  final String? preloadKind;
  final bool? applied;
  final int? elapsedMs;
  final double? correctionDelta;
  final String message;

  String toLogFields() {
    final fields = <String>[
      'continuous=${type.name}',
      'owner=$ownerId',
      'ownerId=$ownerId',
      'item=$itemId',
      'index=$index',
      'logicalIndex=$index',
      if (readerKind?.trim().isNotEmpty == true) 'readerKind=$readerKind',
      if (mode?.trim().isNotEmpty == true) 'mode=$mode',
      if (generation != null) 'generation=$generation',
      if (targetIndex != null) 'target=$targetIndex',
      if (status?.trim().isNotEmpty == true) 'status=$status',
      if (result?.trim().isNotEmpty == true) 'result=$result',
      if (preloadKind?.trim().isNotEmpty == true) 'kind=$preloadKind',
      if (applied != null) 'applied=$applied',
      if (elapsedMs != null) 'elapsedMs=$elapsedMs',
      if (correctionDelta != null)
        'correctionDelta=${correctionDelta!.toStringAsFixed(1)}',
      if (source?.trim().isNotEmpty == true) 'source=$source',
      if (aspectRatio != null) 'ratio=${aspectRatio!.toStringAsFixed(4)}',
      if (width != null && height != null) 'size=${width}x$height',
      if (message.trim().isNotEmpty) message,
    ];
    return fields.join(' ');
  }
}
