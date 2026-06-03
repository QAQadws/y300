enum ForumShellMode {
  webview,
  native,
}

extension ForumShellModeDisplay on ForumShellMode {
  String get displayLabel => switch (this) {
        ForumShellMode.webview => 'WebView 模式',
        ForumShellMode.native => '原生模式',
      };
}
