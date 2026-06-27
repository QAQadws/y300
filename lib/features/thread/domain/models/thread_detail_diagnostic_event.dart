enum ThreadDetailDiagnosticEventType {
  entryBuild,
  renderPlanCreate,
  scrollJump,
  scrollAnimate,
  targetPostScroll,
}

class ThreadDetailDiagnosticEvent {
  const ThreadDetailDiagnosticEvent({
    required this.time,
    required this.type,
    this.entryKey,
    this.pid,
    this.scrollOffset,
    required this.message,
  });

  final DateTime time;
  final ThreadDetailDiagnosticEventType type;
  final String? entryKey;
  final String? pid;
  final double? scrollOffset;
  final String message;

  String toLogLine() {
    final fields = <String>[
      time.toIso8601String(),
      type.name,
      if (entryKey?.trim().isNotEmpty == true) 'entry=$entryKey',
      if (pid?.trim().isNotEmpty == true) 'pid=$pid',
      if (scrollOffset != null) 'offset=${scrollOffset!.toStringAsFixed(1)}',
      message,
    ];
    return fields.join(' | ');
  }
}
