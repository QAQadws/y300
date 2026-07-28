enum ForumShellMode {
  webview,
  native;

  /// The parser-backed forum surface is the default for new installations.
  static const ForumShellMode defaultMode = ForumShellMode.native;
}
