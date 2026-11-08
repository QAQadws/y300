import 'dart:async';

import 'package:flutter/widgets.dart';

import '../contracts/forum_html_display_image.dart';
import '../contracts/forum_html_image_host.dart';
import '../contracts/forum_html_image_predecode_host.dart';
import 'forum_html_image_viewport_coordinator.dart';

typedef ForumHtmlImageDimensions = ({Size size, ForumHtmlImageLayout layout});

/// One mounted image's resource lifetime. Geometry and frame scheduling stay
/// in the Widget; admission and actual I/O capacity stay in the viewport.
/// No Context, render object or prepared document is stored here.
final class ForumHtmlImageBinding {
  ForumHtmlImageBinding({
    required ForumHtmlImageHost host,
    required ForumHtmlDisplayImage image,
    required Object observationIdentity,
    ForumHtmlImageViewportCoordinator? viewport,
  }) : _host = host,
       _image = image,
       _viewport = viewport {
    _attachViewport(observationIdentity);
  }

  ForumHtmlImageHost _host;
  ForumHtmlDisplayImage _image;
  ForumHtmlImageViewportCoordinator? _viewport;
  ForumHtmlImageViewportHandle? _handle;
  Object _sourceEpoch = Object();
  Object _displayEpoch = Object();
  bool _closed = false;
  bool _firstFrameRendered = false;
  bool _inlineDisplaySettled = false;
  bool _keepsImageMounted = false;
  int _retryToken = 0;
  int _pendingDimensions = 0;
  bool _dimensionRetryUsed = false;
  ForumHtmlImageDimensionPriority _dimensionPriority =
      ForumHtmlImageDimensionPriority.background;
  _ImagePreparation? _preparation;

  ForumHtmlImageViewportHandle? get viewportHandle => _handle;
  bool get firstFrameRendered => _firstFrameRendered;
  bool get inlineDisplaySettled => _inlineDisplaySettled;
  int get retryToken => _retryToken;
  bool get hasPendingDimensions => _pendingDimensions > 0;
  bool get canDisplay =>
      !_closed &&
      (_handle == null || (_handle!.isActive && _keepsImageMounted));

  ForumHtmlImageDisplayLease get displayLease =>
      ForumHtmlImageDisplayLease._(this, _displayEpoch);

  /// Returns whether source-owned geometry needs to be rebuilt. Replacing only
  /// a viewport retires displayed callbacks, but keeps valid dimension reads.
  bool update({
    required ForumHtmlImageHost host,
    required ForumHtmlDisplayImage image,
    required Object observationIdentity,
    ForumHtmlImageViewportCoordinator? viewport,
  }) {
    if (_closed) throw StateError('Image binding is closed');
    final sourceChanged =
        !identical(_host, host) ||
        _image.identity != image.identity ||
        _image.htmlSize != image.htmlSize ||
        _image.isSticker != image.isSticker;
    if (!identical(_viewport, viewport)) {
      _detachViewport();
      _viewport = viewport;
      _retireDisplay();
      cancelPreparation();
      _attachViewport(observationIdentity);
    }
    _handle?.configureObservation(observationIdentity);
    _host = host;
    _image = image;
    if (sourceChanged) {
      _sourceEpoch = Object();
      _retireDisplay();
      _inlineDisplaySettled = false;
      _pendingDimensions = 0;
      _dimensionRetryUsed = false;
      _dimensionPriority = ForumHtmlImageDimensionPriority.background;
      cancelPreparation();
      _handle?.reportLoadStarted();
    }
    return sourceChanged;
  }

  void _attachViewport(Object observationIdentity) {
    _handle = _viewport?.register(observationIdentity: observationIdentity);
    _keepsImageMounted = _handle?.value.keepsImageMounted ?? false;
    _handle?.addListener(_onModeChanged);
  }

  void _detachViewport() {
    _handle?.removeListener(_onModeChanged);
    _handle?.dispose();
    _handle = null;
  }

  void _onModeChanged() {
    final mode = _handle!.value;
    if (mode.keepsImageMounted != _keepsImageMounted) {
      _keepsImageMounted = mode.keepsImageMounted;
      _retireDisplay();
    }
    if (_preparation?.work.mode != mode) cancelPreparation();
  }

  void _retireDisplay() {
    _displayEpoch = Object();
    _firstFrameRendered = false;
  }

  bool _acceptsDisplay(Object epoch) =>
      canDisplay && identical(epoch, _displayEpoch);

  bool reportFirstFrame(ForumHtmlImageDisplayLease lease) {
    if (!identical(lease._binding, this) || !lease.isActive) return false;
    _firstFrameRendered = true;
    _inlineDisplaySettled = true;
    return true;
  }

  void reportFailure(ForumHtmlImageDisplayLease lease) {
    if (!identical(lease._binding, this) || !lease.isActive) return;
    _firstFrameRendered = false;
    _inlineDisplaySettled = true;
    _handle?.reportImageFailed();
  }

  void retry() {
    if (_closed) return;
    _retireDisplay();
    _retryToken++;
    _handle?.reportLoadStarted();
  }

  void reportPaintedFrame() {
    if (canDisplay && _firstFrameRendered) _handle?.reportFramePainted();
  }

  void reportRetainAdmission(bool? canRetain) {
    if (canDisplay && _firstFrameRendered) {
      _handle?.reportFirstFrameRendered(canRetain: canRetain);
    }
  }

  void configureWork({required Size displaySize, required double pixelRatio}) {
    if (_closed) return;
    _handle?.configureWork(
      identity: (_host, _image.identity, displaySize.width, pixelRatio),
      canPredecode:
          _host is ForumHtmlImagePredecodeHost &&
          displaySize.width.isFinite &&
          displaySize.width > 0,
    );
  }

  bool get canPromoteDimensions =>
      !_closed &&
      _handle != null &&
      _handle!.isActive &&
      _handle!.value != ForumHtmlImageViewportMode.dormant &&
      _host is ForumHtmlImageDimensionPriorityHost &&
      !_image.isSticker &&
      _image.htmlSize == null &&
      !(_dimensionRetryUsed && _pendingDimensions == 0);

  ForumHtmlImageDimensionPriority? takeDimensionPromotion() {
    if (!canPromoteDimensions) return null;
    final priority = _handle!.value == ForumHtmlImageViewportMode.display
        ? ForumHtmlImageDimensionPriority.visible
        : ForumHtmlImageDimensionPriority.nearby;
    if (_pendingDimensions > 0) {
      if (priority.index <= _dimensionPriority.index) return null;
    } else {
      if (_dimensionRetryUsed) return null;
      _dimensionRetryUsed = true;
    }
    if (priority.index > _dimensionPriority.index) {
      _dimensionPriority = priority;
    }
    return priority;
  }

  Future<ForumHtmlImageDimensionResult> loadDimensions({
    ForumHtmlImageDimensionPriority? priority,
  }) async {
    final epoch = _sourceEpoch;
    final host = _host;
    final image = _image;
    ForumHtmlImageDimensions? dimensions;
    if (_closed) return ForumHtmlImageDimensionResult._(this, epoch, null);
    _pendingDimensions++;
    try {
      dimensions =
          priority != null && host is ForumHtmlImageDimensionPriorityHost
          ? await (host as ForumHtmlImageDimensionPriorityHost)
                .loadDimensionsWithPriority(image, priority: priority)
          : await host.loadDimensions(image);
    } catch (_) {
      // Metadata is optional; a miss remains eligible for the bounded retry.
    } finally {
      if (!_closed && identical(epoch, _sourceEpoch)) _pendingDimensions--;
    }
    return ForumHtmlImageDimensionResult._(this, epoch, dimensions);
  }

  void prepareImage({
    required BuildContext context,
    required Size displaySize,
    required double pixelRatio,
  }) {
    final handle = _handle;
    if (_closed || handle == null) return;
    final identity = (
      _host,
      _image.identity,
      handle.value,
      displaySize.width,
      pixelRatio,
    );
    if (_preparation?.identity == identity) return;
    cancelPreparation();
    final work = handle.tryBeginWork();
    if (work == null) return;
    final preparation = _ImagePreparation(
      identity,
      work,
      _host,
      _image,
      displaySize,
      handle.maxDecodedBytes,
    );
    _preparation = preparation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_closed &&
          context.mounted &&
          work.isActive &&
          identical(_preparation, preparation)) {
        unawaited(_prepare(context, preparation));
      } else {
        work.complete(ForumHtmlImagePreparationOutcome.cancelled);
      }
    });
  }

  Future<void> _prepare(
    BuildContext context,
    _ImagePreparation preparation,
  ) async {
    var outcome = ForumHtmlImagePreparationOutcome.failed;
    try {
      final host = preparation.host;
      if (preparation.work.mode == ForumHtmlImageViewportMode.predecode &&
          host is ForumHtmlImagePredecodeHost) {
        outcome = await (host as ForumHtmlImagePredecodeHost).predecodeImage(
          image: preparation.image,
          context: context,
          displaySize: preparation.displaySize,
          scope: preparation.work,
          maxDecodedBytes: preparation.maxDecodedBytes,
        );
      } else {
        await host.prefetchDisk(preparation.image, scope: preparation.work);
        outcome = ForumHtmlImagePreparationOutcome.diskOnly;
      }
    } catch (_) {
      // Optional preparation never takes over display's failure/retry surface.
    } finally {
      preparation.work.complete(outcome);
    }
  }

  void cancelPreparation() {
    _preparation?.work.cancel();
    _preparation = null;
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _sourceEpoch = Object();
    _retireDisplay();
    _pendingDimensions = 0;
    cancelPreparation();
    _detachViewport();
    _viewport = null;
  }
}

final class ForumHtmlImageDisplayLease {
  const ForumHtmlImageDisplayLease._(this._binding, this._epoch);
  final ForumHtmlImageBinding _binding;
  final Object _epoch;
  bool get isActive => _binding._acceptsDisplay(_epoch);
}

final class ForumHtmlImageDimensionResult {
  const ForumHtmlImageDimensionResult._(
    this._binding,
    this._epoch,
    this.dimensions,
  );
  final ForumHtmlImageBinding _binding;
  final Object _epoch;
  final ForumHtmlImageDimensions? dimensions;
  bool get isCurrent =>
      !_binding._closed && identical(_binding._sourceEpoch, _epoch);
}

final class _ImagePreparation {
  const _ImagePreparation(
    this.identity,
    this.work,
    this.host,
    this.image,
    this.displaySize,
    this.maxDecodedBytes,
  );
  final Object identity;
  final ForumHtmlImageViewportWork work;
  final ForumHtmlImageHost host;
  final ForumHtmlDisplayImage image;
  final Size displaySize;
  final int maxDecodedBytes;
}
