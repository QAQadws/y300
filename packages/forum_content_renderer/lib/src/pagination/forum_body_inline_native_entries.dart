import 'package:flutter/painting.dart';

import '../paragraph/forum_body_native_request.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import 'forum_body_text_page_content.dart';

/// Pure request identities for the one paragraph currently being composed.
/// This is not a cache or a proof of readable ownership. Published pages retain
/// only numeric fragments; this index retires with the active composer input.
final class ForumBodyInlineNativeEntries {
  ForumBodyInlineNativeEntries._(this._input, this._parents, this._atoms);
  final ForumBodyInlinePageContent _input;
  final List<ForumBodyNativeInputCost> _parents;
  final List<List<ForumBodyNativeInputCost>> _atoms;

  Iterable<Object> inRange(int start, int end) =>
      costsInRange(start, end).map((cost) => cost.identity);

  Iterable<ForumBodyNativeInputCost> costsInRange(int start, int end) sync* {
    // Reuse the authoritative legal atom/range checks and indexed boundaries.
    _input.nativeHandleCountInRange(start, end);
    yield* _parents;
    final ranges = _input.content.projection.atoms;
    var low = 0, high = ranges.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (ranges[mid].displayEndUtf16 <= start) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    for (
      var i = low;
      i < ranges.length && ranges[i].displayStartUtf16 < end;
      i++
    ) {
      yield* _atoms[i];
    }
  }
}

/// Uses the SAME request/key validation as visible aggregate admission. Each
/// unit inspects one request or seals one atom; no native work is performed.
/// The caller owns the parent lease until transfer to the existing composer.
final class ForumBodyInlineNativeEntriesPreparation {
  ForumBodyInlineNativeEntriesPreparation({
    required ForumBodyInlinePageContent input,
    required ForumBodyInlineParagraphLease parent,
    required ForumBodyParagraphCache cache,
    required TextScaler textScaler,
    required void Function() ensureOwner,
  }) : _input = input,
       _parent = (
         identity: parent.nativeInputIdentity,
         estimatedBytes: parent.nativeLayoutEstimatedBytes,
       ),
       _cache = cache,
       _scaler = textScaler,
       _ensureOwner = ensureOwner {
    if (!cache.ownsLease(parent) || !identical(input.content, parent.content)) {
      throw ArgumentError('Foreign inline native entry input');
    }
    _parentsReady = input.fontFrames == null;
  }
  ForumBodyInlinePageContent? _input;
  ForumBodyNativeInputCost? _parent;
  List<ForumBodyNativeInputCost>? _parentCosts;
  bool _parentsReady = false;
  ForumBodyParagraphCache? _cache;
  TextScaler? _scaler;
  void Function()? _ensureOwner;
  List<List<ForumBodyNativeInputCost>> _atoms = [];
  Iterator<ForumBodyNativeBudgetSlot>? _requests;
  ForumBodyParagraphBudgetProbe? _probe;
  bool _ready = false;
  bool _closed = false;
  bool _operating = false;
  bool get isReady => _ready && !_closed;

  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Native entry preparation is reentrant');
    _operating = true;
    try {
      _guard();
      var used = 0;
      while (!_ready && used < maxParts) {
        if (!_parentsReady) {
          final probe = _probe ??= _cache!.createBudgetProbe(
            captureInputEstimates: true,
          );
          final requests = _requests ??=
              _input!.fontFrames!.paintReference.nativeFootprint.iterator;
          if (requests.moveNext()) {
            final slot = requests.current;
            slot.request.includeBudget(
              probe,
              width: slot.width,
              textScaler: _input!.fontFrames!.textScaler,
              minimumLineCount: slot.minimumLineCount,
            );
          } else {
            _parentCosts = [_parent!, ...probe.snapshotNativeEstimates()];
            probe.close();
            _probe = null;
            _requests = null;
            _parentsReady = true;
          }
        } else if (_atoms.length == _input!.rubyAtoms.length) {
          _ready = true;
        } else {
          final requests = _requests ??=
              _input!.rubyAtoms[_atoms.length].nativeBudgetFootprint.iterator;
          final probe = _probe ??= _cache!.createBudgetProbe(
            captureInputEstimates: true,
          );
          if (requests.moveNext()) {
            final slot = requests.current;
            slot.request.includeBudget(
              probe,
              width: slot.width,
              minimumLineCount: slot.minimumLineCount,
              textScaler: _scaler!,
            );
            _guard();
          } else {
            _atoms.add(probe.snapshotNativeEstimates());
            probe.close();
            _probe = null;
            _requests = null;
          }
        }
        used++;
        _guard();
      }
      return used;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  ForumBodyInlineNativeEntries take() {
    if (_operating) throw StateError('Native entry preparation is reentrant');
    _operating = true;
    try {
      _guard();
      if (!_ready) throw StateError('Native entry preparation is incomplete');
      final result = ForumBodyInlineNativeEntries._(
        _input!,
        _parentCosts ?? [_parent!],
        _atoms,
      );
      _atoms = [];
      close();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_closed) throw StateError('Native entry preparation is retired');
    _ensureOwner!();
    if (_closed || _cache!.isClosed) {
      throw StateError('Native entry owner is retired');
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _probe?.close();
    _probe = null;
    _requests = null;
    _input = null;
    _parent = null;
    _parentCosts = null;
    _cache = null;
    _scaler = null;
    _ensureOwner = null;
    _atoms = [];
  }
}
