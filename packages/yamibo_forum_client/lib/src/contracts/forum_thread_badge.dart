/// Source-neutral meanings of the status markers advertised for a topic.
enum ForumThreadBadgeKind {
  /// A closed-topic marker advertised by the source.
  closed,

  /// A poll topic.
  poll,

  /// A trade topic.
  trade,

  /// A reward topic.
  reward,

  /// An activity topic.
  activity,

  /// A debate topic.
  debate,

  /// An image marker advertised by the source.
  image,

  /// A sticky topic.
  sticky,

  /// A digest topic.
  digest,

  /// An advertised marker whose meaning is not recognized.
  unknown;

  /// Recognizes legacy source labels while preserving unknown marker wording.
  static ForumThreadBadgeKind fromSourceLabel(String label) =>
      switch (label.trim().toLowerCase()) {
        '关闭' ||
        '关闭的主题' ||
        '關閉' ||
        '關閉的主題' ||
        'closed' ||
        'closed thread' ||
        'locked' => ForumThreadBadgeKind.closed,
        '投票' || 'poll' => ForumThreadBadgeKind.poll,
        '商品' || 'trade' => ForumThreadBadgeKind.trade,
        '悬赏' || '懸賞' || 'reward' => ForumThreadBadgeKind.reward,
        '活动' || '活動' || 'activity' => ForumThreadBadgeKind.activity,
        '辩论' || '辯論' || 'debate' => ForumThreadBadgeKind.debate,
        '图' || '圖' || 'image' => ForumThreadBadgeKind.image,
        '置顶' || '置頂' || 'sticky' || 'pinned' => ForumThreadBadgeKind.sticky,
        '精华' || '精華' || 'digest' => ForumThreadBadgeKind.digest,
        _ => ForumThreadBadgeKind.unknown,
      };
}

/// One topic marker, independent of other markers and the topic's title.
final class ForumThreadBadge {
  /// Creates a source marker.
  const ForumThreadBadge({required this.kind, required this.sourceLabel});

  /// Source-neutral marker meaning.
  final ForumThreadBadgeKind kind;

  /// Original source wording, or empty when an API supplies only typed fields.
  final String sourceLabel;
}
