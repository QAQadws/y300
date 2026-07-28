import 'dart:async';

import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

/// Actions exposed to a tail surface without leaking reader implementation
/// details into the business module that renders it.
class ReaderTailActions {
  const ReaderTailActions({required this.onRetry, required this.onAdvance});

  final VoidCallback onRetry;
  final VoidCallback onAdvance;
}

/// Neutral non-image content attached to one reader owner.
///
/// The surface owns its loading/error/content UI. The reader only decides
/// where it belongs in the sequence and when to invoke lifecycle callbacks.
abstract interface class ReaderTailSurface {
  String get id;

  String indicatorLabel(BuildContext context) =>
      AppLocalizations.of(context).readerTailContent;

  bool get hasAdvance => false;

  /// Whether the current tail state has enough information to start adjacent
  /// lookahead. Vertical tails can keep this false until the user explicitly
  /// expands them; paged tails usually become ready after their first load.
  bool get isAdjacentPreloadReady => false;

  /// Number of lazily-built items contributed to the vertical reader stream.
  /// A regular tail is one item; a large tail can expose a sliver-like item
  /// sequence without nesting another scrollable viewport.
  int get verticalItemCount => 1;

  Widget buildPaged(BuildContext context, ReaderTailActions actions);

  Widget buildVertical(BuildContext context, ReaderTailActions actions);

  Widget buildVerticalItem(
    BuildContext context,
    ReaderTailActions actions,
    int index,
  ) {
    if (index != 0) {
      throw RangeError.index(index, this, 'index');
    }
    return buildVertical(context, actions);
  }

  Widget buildAdvance(BuildContext context, ReaderTailActions actions) {
    return Center(child: Text(AppLocalizations.of(context).readerContinue));
  }

  FutureOr<void> onVisible();

  /// Vertical tails can require an explicit action before loading. The
  /// default keeps the Phase 3 contract a no-op for ordinary tails.
  FutureOr<void> onVerticalVisible() {}

  FutureOr<void> onRetry();

  FutureOr<void> onAdvance();

  void dispose() {}
}
