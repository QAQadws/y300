/// Internal native resource shared by the reading owner's single cache budget.
/// Typed leases expose each layout's own paint/hit contract to consumers.
abstract interface class ForumBodyNativeParagraphLayout {
  bool get isDisposed;
  int get lineCount;
  void dispose();
}
