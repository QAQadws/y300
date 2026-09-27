import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Scroll policy for a reversed conversation with a stable center message.
class ConversationScrollController extends ScrollController {
  ConversationScrollController() : super(keepScrollOffset: false);

  final _followingLatest = ValueNotifier(true);
  bool _latestScheduled = false;
  bool _disposed = false;

  ValueListenable<bool> get followingLatest => _followingLatest;

  void showLatest() {
    _followingLatest.value = true;
    if (_latestScheduled) return;
    _latestScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _latestScheduled = false;
      if (_disposed || !_followingLatest.value) return;
      for (final position in positions) {
        if (position.hasContentDimensions) {
          position.jumpTo(position.minScrollExtent);
        }
      }
    });
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _ConversationScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    followsLatest: () => _followingLatest.value,
    onFollowingChanged: (following) {
      if (!_disposed) _followingLatest.value = following;
    },
  );

  @override
  void dispose() {
    _disposed = true;
    _followingLatest.dispose();
    super.dispose();
  }
}

class _ConversationScrollPosition extends ScrollPositionWithSingleContext {
  _ConversationScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.followsLatest,
    required this.onFollowingChanged,
  }) : super(keepScrollOffset: false);

  final bool Function() followsLatest;
  final ValueChanged<bool> onFollowingChanged;
  bool _fitCheckScheduled = false;
  bool _disposed = false;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    // The first layout does not call correctForNewDimensions.
    if (!hasContentDimensions && followsLatest() && pixels != minScrollExtent) {
      correctPixels(minScrollExtent);
      return false;
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }

  @override
  bool correctForNewDimensions(
    ScrollMetrics oldPosition,
    ScrollMetrics newPosition,
  ) {
    final latestMoved =
        oldPosition.minScrollExtent != newPosition.minScrollExtent ||
        oldPosition.viewportDimension != newPosition.viewportDimension;
    // Lazy history estimates change while dragging. Correcting those offsets
    // would repeatedly pull a slow gesture back before it crosses 80 pixels.
    if (followsLatest() && latestMoved && !activity!.isScrolling) {
      // Correct during layout so keyboard and asynchronously sized HTML do not
      // leave the latest message outside the viewport for a frame.
      if (pixels != newPosition.minScrollExtent) {
        correctPixels(newPosition.minScrollExtent);
        return false;
      }
      return true;
    }
    return super.correctForNewDimensions(oldPosition, newPosition);
  }

  @override
  void applyNewDimensions() {
    super.applyNewDimensions();
    if (followsLatest() || _fitCheckScheduled) return;
    _fitCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitCheckScheduled = false;
      if (_disposed) return;
      // Read the final dimensions after the adaptive viewport has settled.
      // Layout corrections do not emit didUpdateScrollPositionBy.
      if (maxScrollExtent - minScrollExtent <= 0.01) {
        onFollowingChanged(true);
      }
    });
  }

  @override
  void didUpdateScrollPositionBy(double delta) {
    if (hasContentDimensions) {
      onFollowingChanged(pixels - minScrollExtent <= 80);
    }
    super.didUpdateScrollPositionBy(delta);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
