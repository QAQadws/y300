import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';

import '../domain/models/forum_html_reader_preferences.dart';
import '../presentation/contracts/forum_html_render_preparer.dart';
import 'forum_html_render_preparer.dart';
import 'forum_preparation_scheduler.dart';

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

  ForumHtmlPreparationRequest withPreparer(ForumHtmlRenderPreparer preparer) =>
      ForumHtmlPreparationRequest(
        html: html,
        preferences: preferences,
        theme: theme,
        sourceId: sourceId,
        threadId: threadId,
        imageCacheOwnerId: imageCacheOwnerId,
        preparer: preparer,
      );

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
      contentImageKind: candidate.contentImageKind,
      enablePlainTextLinks: candidate.enablePlainTextLinks,
      enableSafeDisplayPlanning: candidate.enableSafeDisplayPlanning,
      safeDisplayPlanningCodeUnitBudget:
          candidate.safeDisplayPlanningCodeUnitBudget,
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
    this.contentImageKind = ForumImageKind.threadInline,
    required this.enablePlainTextLinks,
    this.enableSafeDisplayPlanning = false,
    this.safeDisplayPlanningCodeUnitBudget,
  });

  final String html;
  final ForumHtmlReaderPreferences preferences;
  final ForumHtmlThemeContext theme;
  final String sourceId;
  final String? threadId;
  final String? imageCacheOwnerId;
  final ForumImageKind contentImageKind;
  final bool enablePlainTextLinks;
  final bool enableSafeDisplayPlanning;
  final int? safeDisplayPlanningCodeUnitBudget;

  ForumHtmlPreparedRenderDocument prepare() =>
      DefaultForumHtmlRenderPreparer(
        contentImageKind: contentImageKind,
        enablePlainTextLinks: enablePlainTextLinks,
        enableSafeDisplayPlanning: enableSafeDisplayPlanning,
        safeDisplayPlanningCodeUnitBudget: safeDisplayPlanningCodeUnitBudget,
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

/// HTML preparation facade over shared data-only admission.
class ForumHtmlPreparationExecutor extends ChangeNotifier {
  ForumHtmlPreparationExecutor({
    int codeUnitThreshold = 32 * 1024,
    int maxConcurrent = 1,
    int maxQueued = 16,
    int maxQueuedCodeUnits = 512 * 1024,
    ForumHtmlPreparationWorker worker = _runPreparationWorker,
  }) : this._(
         codeUnitThreshold,
         ForumPreparationScheduler(
           maxConcurrent: maxConcurrent,
           maxQueued: maxQueued,
           maxQueuedCodeUnits: maxQueuedCodeUnits,
         ),
         true,
         worker,
       );

  ForumHtmlPreparationExecutor.withScheduler({
    required ForumPreparationScheduler scheduler,
    int codeUnitThreshold = 32 * 1024,
    ForumHtmlPreparationWorker worker = _runPreparationWorker,
  }) : this._(codeUnitThreshold, scheduler, false, worker);

  ForumHtmlPreparationExecutor._(
    this.codeUnitThreshold,
    this._scheduler,
    this._ownsScheduler,
    this._worker,
  ) : assert(codeUnitThreshold >= 0) {
    _scope = _scheduler.createScope();
    _scheduler.addListener(_capacityChanged);
  }

  static final shared = ForumHtmlPreparationExecutor.withScheduler(
    scheduler: ForumPreparationScheduler.shared,
  );
  final int codeUnitThreshold;
  final ForumPreparationScheduler _scheduler;
  final bool _ownsScheduler;
  final ForumHtmlPreparationWorker _worker;
  late final ForumPreparationScope _scope;
  bool _closed = false;
  int get maxConcurrent => _scheduler.maxConcurrent;
  int get maxQueued => _scheduler.maxQueued;
  int get maxQueuedCodeUnits => _scheduler.maxQueuedCodeUnits;
  int get activeCount => _scheduler.activeCount;
  int get queuedCount => _scheduler.queuedCount;
  int get queuedCodeUnits => _scheduler.queuedCodeUnits;

  bool usesBackground(ForumHtmlPreparationRequest request) =>
      request.html.length >= codeUnitThreshold &&
      request.backgroundInput != null;

  ForumHtmlPreparationLease? tryAcquire(ForumHtmlPreparationRequest request) {
    if (_closed) throw StateError('Preparation executor is closed');
    final input = request.backgroundInput;
    if (input == null) throw ArgumentError('Unsupported background preparer');
    final worker = _worker;
    final lease = _scope.tryAcquire<ForumHtmlPreparedRenderDocument>(
      identity: (request.identity, worker),
      codeUnits: input.html.length,
      work: () => worker(input),
    );
    return lease == null ? null : ForumHtmlPreparationLease._(lease);
  }

  void _capacityChanged() {
    if (!_closed) notifyListeners();
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _scheduler.removeListener(_capacityChanged);
    _scope.close();
    if (_ownsScheduler) _scheduler.dispose();
    super.dispose();
  }
}

final class ForumHtmlPreparationLease
    implements ForumPreparationWorkLease<ForumHtmlPreparedRenderDocument> {
  ForumHtmlPreparationLease._(this._lease);
  final ForumPreparationLease<ForumHtmlPreparedRenderDocument> _lease;
  @override
  Future<ForumHtmlPreparedRenderDocument?> get future => _lease.future;
  @override
  void release() => _lease.release();
}
