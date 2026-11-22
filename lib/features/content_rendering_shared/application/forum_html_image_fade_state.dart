/// Remembers which images have presented a frame in a single body.
final class ForumHtmlImageFadeState {
  final _presentedImages = <Object>{};

  bool hasPresented(Object identity) => _presentedImages.contains(identity);

  void markPresented(Object identity) {
    _presentedImages.add(identity);
  }
}
