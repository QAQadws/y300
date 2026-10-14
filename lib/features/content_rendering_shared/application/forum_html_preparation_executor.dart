import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import '../domain/models/forum_html_reader_preferences.dart';
import '../presentation/contracts/forum_html_render_preparer.dart';
import 'forum_html_render_preparer.dart';

final class ForumHtmlPreparationRequest {
  const ForumHtmlPreparationRequest({
    required this.html,
    required this.preferences,
    required this.theme,
    required this.sourceId,
    required this.threadId,
    required this.imageCacheOwnerId,
    required this.preparer,
  });

  final String html;
  final ForumHtmlReaderPreferences preferences;
  final ForumHtmlThemeContext theme;
  final String sourceId;
  final String? threadId;
  final String? imageCacheOwnerId;
  final ForumHtmlRenderPreparer preparer;

  Object get identity => (
    html,
    preparer.preparationPreferencesIdentity(preferences),
    theme.signature,
    sourceId,
    threadId,
    imageCacheOwnerId,
    preparer,
  );

  ForumHtmlPreparedRenderDocument prepareSynchronously() => preparer.prepare(
    html: html,
    preferences: preferences,
    theme: theme,
    sourceId: sourceId,
    threadId: threadId,
    imageCacheOwnerId: imageCacheOwnerId,
  );

  ForumHtmlBackgroundPreparationInput? get backgroundInput {
    final candidate = preparer;
    if (candidate is! DefaultForumHtmlRenderPreparer ||
        !candidate.supportsBackgroundPreparation) {
      return null;
    }
    return ForumHtmlBackgroundPreparationInput(
      html: html,
      preferences: preferences,
      theme: theme,
      sourceId: sourceId,
      threadId: threadId,
      imageCacheOwnerId: imageCacheOwnerId,
      enablePlainTextLinks: candidate.enablePlainTextLinks,
      enableSafeDisplayPlanning: candidate.enableSafeDisplayPlanning,
    );
  }
}

/// No facade, service, provider, context or callback crosses the worker boundary.
final class ForumHtmlBackgroundPreparationInput {
  const ForumHtmlBackgroundPreparationInput({
    required this.html,
    required this.preferences,
    required this.theme,
    required this.sourceId,
    required this.threadId,
    required this.imageCacheOwnerId,
    required this.enablePlainTextLinks,
    this.enableSafeDisplayPlanning = false,
  });

  final String html;
  final ForumHtmlReaderPreferences preferences;
  final ForumHtmlThemeContext theme;
  final String sourceId;
  final String? threadId;
  final String? imageCacheOwnerId;
  final bool enablePlainTextLinks;
  final bool enableSafeDisplayPlanning;

  ForumHtmlPreparedRenderDocument prepare() =>
      DefaultForumHtmlRenderPreparer(
        enablePlainTextLinks: enablePlainTextLinks,
        enableSafeDisplayPlanning: enableSafeDisplayPlanning,
      ).prepare(
        html: html,
        preferences: preferences,
        theme: theme,
        sourceId: sourceId,
        threadId: threadId,
        imageCacheOwnerId: imageCacheOwnerId,
      );
}

typedef ForumHtmlPreparationWorker =
    Future<ForumHtmlPreparedRenderDocument> Function(
      ForumHtmlBackgroundPreparationInput input,
    );

Future<ForumHtmlPreparedRenderDocument> _runPreparationWorker(
  ForumHtmlBackgroundPreparationInput input,
) => Isolate.run(input.prepare, debugName: 'forum-body-preparation');

/// Bounds admitted work; completed documents belong only to mounted consumers.
class ForumHtmlPreparationExecutor extends ChangeNotifier {
  ForumHtmlPreparationExecutor({
    this.codeUnitThreshold = 32 * 1024,
    this.maxConcurrent = 1,
    this.maxQueued = 16,
    this.maxQueuedCodeUnits = 512 * 1024,
    ForumHtmlPreparationWorker worker = _runPreparationWorker,
  }) : assert(codeUnitThreshold >= 0),
       assert(maxConcurrent > 0),
       assert(maxQueued >= 0),
       assert(maxQueuedCodeUnits >= 0),
       _worker = worker;

  // Application runtime scope. Leases retire inputs on unmount/owner changes;
  // this executor never retains a completed cache or a queue of rejected jobs.
  static final shared = ForumHtmlPreparationExecutor();

  final int codeUnitThreshold;
  final int maxConcurrent;
  final int maxQueued;
  final int maxQueuedCodeUnits;
  final ForumHtmlPreparationWorker _worker;
  final _entries = <Object, _PreparationEntry>{};
  final _queue = Queue<_PreparationEntry>();
  int _active = 0;
  int _queuedCodeUnits = 0;
  bool _closed = false;
  bool _notificationScheduled = false;

  int get activeCount => _active;
  int get queuedCount => _queue.length;
  int get queuedCodeUnits => _queuedCodeUnits;

  bool usesBackground(ForumHtmlPreparationRequest request) =>
      request.html.length >= codeUnitThreshold &&
      request.backgroundInput != null;

  /// Null applies backpressure. The mounted caller retains its own input and
  /// listens for capacity, without synchronously preparing it or adding a job.
  ForumHtmlPreparationLease? tryAcquire(ForumHtmlPreparationRequest request) {
    if (_closed) throw StateError('Preparation executor is closed');
    final identity = request.identity;
    final existing = _entries[identity];
    if (existing != null) {
      existing.consumers++;
      return ForumHtmlPreparationLease._(this, existing);
    }
    final input = request.backgroundInput;
    if (input == null) throw ArgumentError('Unsupported background preparer');
    final canStart = _active < maxConcurrent;
    if (!canStart &&
        (_queue.length >= maxQueued ||
            _queuedCodeUnits + input.html.length > maxQueuedCodeUnits)) {
      return null;
    }
    final entry = _PreparationEntry(identity, input);
    _entries[identity] = entry;
    if (canStart) {
      _start(entry);
    } else {
      _queue.add(entry);
      _queuedCodeUnits += input.html.length;
    }
    return ForumHtmlPreparationLease._(this, entry);
  }

  void _start(_PreparationEntry entry) {
    entry.started = true;
    _active++;
    Future<ForumHtmlPreparedRenderDocument>.sync(() => _worker(entry.input))
        .then(
          (document) => entry.completer.complete(document),
          onError: (Object error, StackTrace stack) =>
              entry.completer.completeError(error, stack),
        )
        .whenComplete(() {
          _active--;
          if (identical(_entries[entry.identity], entry)) {
            _entries.remove(entry.identity);
          }
          while (!_closed && _active < maxConcurrent && _queue.isNotEmpty) {
            final next = _queue.removeFirst();
            _queuedCodeUnits -= next.input.html.length;
            _start(next);
          }
          _capacityChanged();
        });
  }

  void _release(_PreparationEntry entry) {
    entry.consumers--;
    if (entry.consumers != 0 || entry.started) return;
    if (_queue.remove(entry)) {
      _queuedCodeUnits -= entry.input.html.length;
      _entries.remove(entry.identity);
      entry.completer.complete(null);
      _capacityChanged();
    }
  }

  void _capacityChanged() {
    if (_closed || _notificationScheduled) return;
    _notificationScheduled = true;
    scheduleMicrotask(() {
      _notificationScheduled = false;
      if (!_closed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _closed = true;
    for (final entry in _queue) {
      _entries.remove(entry.identity);
      entry.completer.complete(null);
    }
    _queue.clear();
    _queuedCodeUnits = 0;
    // Already-running isolates remain counted until their real completion.
    super.dispose();
  }
}

final class ForumHtmlPreparationLease {
  ForumHtmlPreparationLease._(this._executor, this._entry);
  final ForumHtmlPreparationExecutor _executor;
  final _PreparationEntry _entry;
  bool _released = false;

  Future<ForumHtmlPreparedRenderDocument?> get future =>
      _entry.completer.future;

  void release() {
    if (_released) return;
    _released = true;
    _executor._release(_entry);
  }
}

final class _PreparationEntry {
  _PreparationEntry(this.identity, this.input);
  final Object identity;
  final ForumHtmlBackgroundPreparationInput input;
  final completer = Completer<ForumHtmlPreparedRenderDocument?>();
  int consumers = 1;
  bool started = false;
}
