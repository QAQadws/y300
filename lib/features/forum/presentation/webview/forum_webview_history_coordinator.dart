import 'dart:async';

import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/thread/domain/services/forum_thread_url_parser.dart';

typedef ForumWebViewHistoryCommit =
    FutureOr<void> Function(ForumWebViewHistoryCandidate candidate);

typedef ForumWebViewHistoryCommitFailure =
    void Function(
      ForumWebViewHistoryCandidate candidate,
      Object error,
      StackTrace stackTrace,
    );

enum ForumWebViewHistorySkipReason {
  disposed,
  missingNavigation,
  staleGeneration,
  mismatchedNavigation,
  missingFinalUri,
  nonThreadDocument,
  missingPostProof,
  duplicateTarget,
}

typedef ForumWebViewHistorySkip =
    void Function(ForumWebViewHistorySkipReason reason);

class ForumWebViewHistoryCandidate {
  const ForumWebViewHistoryCandidate({
    required this.tid,
    required this.finalUri,
    required this.document,
    this.forumName,
  });

  final String tid;
  final Uri finalUri;
  final ForumThreadDocumentSnapshot document;
  final String? forumName;
}

class ForumWebViewHistoryCoordinator {
  ForumWebViewHistoryCoordinator({
    required ForumWebViewHistoryCommit onCommit,
    ForumWebViewHistoryCommitFailure? onCommitFailure,
    ForumWebViewHistorySkip? onSkip,
    ForumThreadUrlParser urlParser = const ForumThreadUrlParser(),
  }) : _onCommit = onCommit,
       _onCommitFailure = onCommitFailure,
       _onSkip = onSkip,
       _urlParser = urlParser;

  final ForumWebViewHistoryCommit _onCommit;
  final ForumWebViewHistoryCommitFailure? _onCommitFailure;
  final ForumWebViewHistorySkip? _onSkip;
  final ForumThreadUrlParser _urlParser;

  bool _supportsPageCommitVisible = false;
  bool _disposed = false;
  int _currentGeneration = 0;
  String? _lastCommittedTid;
  _PendingForumWebViewNavigation? _pending;

  void configure({required bool supportsPageCommitVisible}) {
    if (_disposed) {
      return;
    }
    _supportsPageCommitVisible = supportsPageCommitVisible;
  }

  void onPageStarted({required int generation, required Uri uri}) {
    if (_disposed) {
      return;
    }
    _currentGeneration = generation;
    _pending = _PendingForumWebViewNavigation(
      generation: generation,
      startedUri: uri,
    );
  }

  Future<void> onPageCommitVisible({
    required int generation,
    required Uri uri,
  }) async {
    final pending = _currentPending(generation, uri);
    if (pending == null || !_supportsPageCommitVisible) {
      return;
    }
    pending.isVisible = true;
    await _tryResolve(pending);
  }

  Future<void> onPageFinished({
    required int generation,
    required Uri finalUri,
    required ForumThreadDocumentSnapshot? document,
    String? forumName,
  }) async {
    final pending = _currentPending(generation, finalUri);
    if (pending == null) {
      return;
    }
    pending
      ..finalUri = finalUri
      ..document = document
      ..forumName = forumName
      ..isMetadataReady = true;
    if (!_supportsPageCommitVisible) {
      pending.isVisible = true;
    }
    await _tryResolve(pending);
  }

  void dispose() {
    _disposed = true;
    _pending = null;
  }

  _PendingForumWebViewNavigation? _currentPending(
    int generation,
    Uri eventUri,
  ) {
    final pending = _pending;
    if (_disposed) {
      _skip(ForumWebViewHistorySkipReason.disposed);
      return null;
    }
    if (pending == null) {
      _skip(ForumWebViewHistorySkipReason.missingNavigation);
      return null;
    }
    if (generation != _currentGeneration || generation != pending.generation) {
      _skip(ForumWebViewHistorySkipReason.staleGeneration);
      return null;
    }
    if (!_belongsToNavigation(pending.startedUri, eventUri)) {
      _skip(ForumWebViewHistorySkipReason.mismatchedNavigation);
      return null;
    }
    return pending;
  }

  Future<void> _tryResolve(_PendingForumWebViewNavigation pending) async {
    if (_disposed ||
        pending.isResolved ||
        pending.generation != _currentGeneration ||
        !pending.isVisible ||
        !pending.isMetadataReady) {
      return;
    }

    pending.isResolved = true;
    final finalUri = pending.finalUri;
    if (finalUri == null) {
      _skip(ForumWebViewHistorySkipReason.missingFinalUri);
      return;
    }
    final tid = _urlParser.extractTid(finalUri.toString());
    if (tid == null) {
      _lastCommittedTid = null;
      _skip(ForumWebViewHistorySkipReason.nonThreadDocument);
      return;
    }

    final document = pending.document;
    if (document == null || !document.hasPostProof) {
      _skip(ForumWebViewHistorySkipReason.missingPostProof);
      return;
    }
    if (_lastCommittedTid == tid) {
      _skip(ForumWebViewHistorySkipReason.duplicateTarget);
      return;
    }

    _lastCommittedTid = tid;
    final candidate = ForumWebViewHistoryCandidate(
      tid: tid,
      finalUri: finalUri,
      document: document,
      forumName: pending.forumName,
    );
    try {
      await _onCommit(candidate);
    } catch (error, stackTrace) {
      _onCommitFailure?.call(candidate, error, stackTrace);
    }
  }

  void _skip(ForumWebViewHistorySkipReason reason) {
    _onSkip?.call(reason);
  }

  bool _belongsToNavigation(Uri startedUri, Uri eventUri) {
    if (startedUri.replace(fragment: '').toString() ==
        eventUri.replace(fragment: '').toString()) {
      return true;
    }
    final startedTid =
        _urlParser.extractTid(startedUri.toString()) ??
        _rawPositiveInteger(startedUri.query, 'ptid');
    final eventTid = _urlParser.extractTid(eventUri.toString());
    return startedTid != null && startedTid == eventTid;
  }

  String? _rawPositiveInteger(String rawQuery, String key) {
    final normalizedKey = key.toLowerCase();
    for (final segment in rawQuery.split(RegExp(r'[&;]'))) {
      final separator = segment.indexOf('=');
      if (separator <= 0 ||
          segment.substring(0, separator).trim().toLowerCase() !=
              normalizedKey) {
        continue;
      }
      final value = segment.substring(separator + 1).trim();
      if (RegExp(r'^\d+$').hasMatch(value) && value != '0') {
        return BigInt.tryParse(value)?.toString();
      }
    }
    return null;
  }
}

class _PendingForumWebViewNavigation {
  _PendingForumWebViewNavigation({
    required this.generation,
    required this.startedUri,
  });

  final int generation;
  final Uri startedUri;
  Uri? finalUri;
  ForumThreadDocumentSnapshot? document;
  String? forumName;
  bool isVisible = false;
  bool isMetadataReady = false;
  bool isResolved = false;
}
