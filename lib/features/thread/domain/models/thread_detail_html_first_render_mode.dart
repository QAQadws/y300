enum ThreadDetailHtmlFirstRenderMode {
  legacy,
  htmlFirst;

  bool get isHtmlFirst => this == ThreadDetailHtmlFirstRenderMode.htmlFirst;
}
