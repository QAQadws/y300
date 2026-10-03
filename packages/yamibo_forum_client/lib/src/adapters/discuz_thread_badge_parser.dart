import 'package:html/dom.dart' as dom;

import '../contracts/forum_thread_badge.dart';
import '../parsing/loose_json.dart';

/// Shares marker interpretation between forum and user-directory summaries.
abstract final class DiscuzThreadBadgeParser {
  /// Reads every marker from a touch-template topic title in source order.
  static List<ForumThreadBadge> fromHtml(dom.Element? titleBlock) {
    final badges = <ForumThreadBadge>[];
    for (final marker
        in titleBlock?.querySelectorAll('.micon') ?? <dom.Element>[]) {
      final label = marker.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (label.isEmpty) continue;
      final kind = marker.classes.contains('lock')
          ? ForumThreadBadgeKind.closed
          : marker.classes.contains('top')
          ? ForumThreadBadgeKind.sticky
          : marker.classes.contains('digest')
          ? ForumThreadBadgeKind.digest
          : ForumThreadBadgeKind.fromSourceLabel(label);
      badges.add(ForumThreadBadge(kind: kind, sourceLabel: label));
    }
    return List.unmodifiable(badges);
  }

  /// Reads independent markers from typed Discuz API fields.
  static List<ForumThreadBadge> fromApi(JsonMap fields) {
    final badges = <ForumThreadBadge>[];
    void add(ForumThreadBadgeKind kind) {
      badges.add(ForumThreadBadge(kind: kind, sourceLabel: ''));
    }

    // Moved topics can have folder=lock while closed contains a redirect TID.
    final closed = LooseJson.integer(fields['closed']);
    if (fields['closed'] == true ||
        closed == 1 ||
        (closed <= 1 && LooseJson.string(fields['folder']) == 'lock')) {
      add(ForumThreadBadgeKind.closed);
    } else {
      final special = switch (LooseJson.integer(fields['special'])) {
        1 => ForumThreadBadgeKind.poll,
        2 => ForumThreadBadgeKind.trade,
        3 => ForumThreadBadgeKind.reward,
        4 => ForumThreadBadgeKind.activity,
        5 => ForumThreadBadgeKind.debate,
        _ => null,
      };
      if (special != null) add(special);
    }
    if (LooseJson.integer(fields['attachment']) == 2) {
      add(ForumThreadBadgeKind.image);
    }
    final displayOrder = LooseJson.integer(fields['displayorder']);
    if (displayOrder >= 1 && displayOrder <= 4) {
      add(ForumThreadBadgeKind.sticky);
    }
    if (LooseJson.integer(fields['digest']) > 0) {
      add(ForumThreadBadgeKind.digest);
    }

    final label = LooseJson.string(fields['badgeLabel']).trim();
    if (label.isNotEmpty) {
      final kind = ForumThreadBadgeKind.fromSourceLabel(label);
      final marker = ForumThreadBadge(kind: kind, sourceLabel: label);
      final matching = badges.indexWhere((badge) => badge.kind == kind);
      if (matching < 0) {
        badges.add(marker);
      } else {
        badges[matching] = marker;
      }
    }
    return List.unmodifiable(badges);
  }
}
