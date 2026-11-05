/// Dispatches an authored URL with the lifetime of its visible native source.
typedef NovelReaderNativeLinkHandler = void Function(
  String url,
  bool Function() isCurrent,
);
