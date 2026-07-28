import 'dart:async';

import 'package:y300/features/comic/domain/models/comic_download_queue_models.dart';

abstract interface class ComicDownloadProgressObserver {
  Future<void> onImagesResolved(int totalImages);

  Future<void> onImageCompleted({
    required int completedImages,
    required int totalImages,
  });
}

final class ComicDownloadCancellationToken {
  bool _isCancellationRequested = false;

  bool get isCancellationRequested => _isCancellationRequested;

  void cancel() {
    _isCancellationRequested = true;
  }

  void throwIfCancellationRequested() {
    if (_isCancellationRequested) {
      throw const ComicDownloadCanceledException();
    }
  }
}

final class ComicDownloadCanceledException implements Exception {
  const ComicDownloadCanceledException();

  @override
  String toString() => 'ComicDownloadCanceledException';
}

final class ComicDownloadFailedException implements Exception {
  const ComicDownloadFailedException(this.code, {this.detail});

  final ComicDownloadFailureCode code;
  final Object? detail;

  @override
  String toString() => 'ComicDownloadFailedException(${code.name})';
}

abstract interface class ComicDownloadImageRequestGovernor {
  Future<void> waitForTurn();
}

abstract interface class ComicDownloadAvailabilityChecker {
  Future<bool> hasValidEpisodeDownload({
    required String comicId,
    required String episodeId,
  });
}

final class DefaultComicDownloadImageRequestGovernor
    implements ComicDownloadImageRequestGovernor {
  DefaultComicDownloadImageRequestGovernor({
    this.minimumInterval = const Duration(seconds: 1),
    DateTime Function()? nowProvider,
    Future<void> Function(Duration duration)? delay,
  }) : _nowProvider = nowProvider ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  final Duration minimumInterval;
  final DateTime Function() _nowProvider;
  final Future<void> Function(Duration duration) _delay;

  DateTime? _lastStartedAt;
  Future<void> _tail = Future<void>.value();

  @override
  Future<void> waitForTurn() {
    final turn = _tail.then((_) => _waitForTurn());
    _tail = turn.catchError((_) {});
    return turn;
  }

  Future<void> _waitForTurn() async {
    final lastStartedAt = _lastStartedAt;
    if (lastStartedAt != null) {
      final elapsed = _nowProvider().difference(lastStartedAt);
      final remaining = minimumInterval - elapsed;
      if (remaining > Duration.zero) {
        await _delay(remaining);
      }
    }
    _lastStartedAt = _nowProvider();
  }
}
