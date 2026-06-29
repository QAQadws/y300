class ForumHomeCarouselItem {
  const ForumHomeCarouselItem({
    required this.imageUrl,
    required this.targetUrl,
    this.aspectRatio,
  });

  final String imageUrl;
  final String targetUrl;
  final double? aspectRatio;

  ForumHomeCarouselItem copyWith({
    String? imageUrl,
    String? targetUrl,
    double? aspectRatio,
  }) {
    return ForumHomeCarouselItem(
      imageUrl: imageUrl ?? this.imageUrl,
      targetUrl: targetUrl ?? this.targetUrl,
      aspectRatio: aspectRatio ?? this.aspectRatio,
    );
  }
}

class ForumHomeChromeData {
  const ForumHomeChromeData({
    this.carouselItems = const <ForumHomeCarouselItem>[],
    this.favoriteForums = const <ForumHomeChromeForumItem>[],
  });

  final List<ForumHomeCarouselItem> carouselItems;
  final List<ForumHomeChromeForumItem> favoriteForums;

  static const empty = ForumHomeChromeData();

  ForumHomeChromeData copyWith({
    List<ForumHomeCarouselItem>? carouselItems,
    List<ForumHomeChromeForumItem>? favoriteForums,
  }) {
    return ForumHomeChromeData(
      carouselItems: carouselItems ?? this.carouselItems,
      favoriteForums: favoriteForums ?? this.favoriteForums,
    );
  }
}

class ForumHomeChromeForumItem {
  const ForumHomeChromeForumItem({
    required this.fid,
    required this.title,
    required this.description,
    required this.todayPosts,
  });

  final String fid;
  final String title;
  final String description;
  final int? todayPosts;
}
