enum ForumShellMode {
  webview,
  native;

  /// The parser-backed forum surface is the default for new installations.
  static const ForumShellMode defaultMode = ForumShellMode.native;
}

extension ForumShellModeDisplay on ForumShellMode {
  String get displayLabel => switch (this) {
    ForumShellMode.webview => 'WebView 模式',
    ForumShellMode.native => '解析模式',
  };
}
