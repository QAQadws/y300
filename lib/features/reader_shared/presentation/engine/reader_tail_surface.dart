import 'dart:async';

import 'package:flutter/material.dart';

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

  String get indicatorLabel => '末尾内容';

  bool get hasAdvance => false;

  Widget buildPaged(BuildContext context, ReaderTailActions actions);

  Widget buildVertical(BuildContext context, ReaderTailActions actions);

  Widget buildAdvance(BuildContext context, ReaderTailActions actions) {
    return const Center(child: Text('继续'));
  }

  FutureOr<void> onVisible();

  FutureOr<void> onRetry();

  FutureOr<void> onAdvance();

  void dispose() {}
}
