enum YamiboRequestKind {
  api,
  html,
  resource,
  imageProbe,
}

class YamiboRequestContext {
  const YamiboRequestContext({
    required this.kind,
    required this.operation,
    this.module,
    this.pageKind,
    this.silent = false,
  });

  final YamiboRequestKind kind;
  final String operation;
  final String? module;
  final String? pageKind;
  final bool silent;
}
