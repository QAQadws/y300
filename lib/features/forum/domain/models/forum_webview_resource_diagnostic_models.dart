enum ForumWebViewResourceKind {
  smiley,
  attachment,
  staticAsset,
  other,
}

class ForumWebViewResourceDiagnosticEvent {
  const ForumWebViewResourceDiagnosticEvent({
    required this.uri,
    required this.kind,
    required this.isMainFrame,
    this.statusCode,
    this.errorDescription,
  });

  final Uri uri;
  final ForumWebViewResourceKind kind;
  final int? statusCode;
  final String? errorDescription;
  final bool isMainFrame;
}
