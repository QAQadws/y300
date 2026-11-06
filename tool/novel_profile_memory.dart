import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';

/// Keeps the reader in the observed state until the Android host samples it.
final class NovelProfileMemory {
  NovelProfileMemory(this._emit) {
    registerExtension('ext.y300.profileMemoryAck', (_, parameters) async {
      final pending = _pending;
      final sampled = parameters['sampled'];
      if (pending == null ||
          pending.isCompleted ||
          parameters['sequence'] != '$_sequence' ||
          (sampled != 'true' && sampled != 'false')) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          '{"message":"Expected an acknowledgement for the active checkpoint"}',
        );
      }
      pending.complete(sampled == 'true');
      return ServiceExtensionResponse.result('{"acknowledged":true}');
    });
  }

  final void Function(Map<String, Object?>) _emit;
  Completer<bool>? _pending;
  int _sequence = 0;

  Future<void> checkpoint({
    required String phase,
    required String backend,
    required String fixture,
    int? run,
  }) async {
    if (_pending != null) throw StateError('Overlapping memory checkpoints');
    final isolateId = Service.getIsolateId(Isolate.current);
    if (isolateId == null) throw StateError('VM service isolate unavailable');
    final pending = _pending = Completer<bool>();
    try {
      _emit({
        'event': 'memory_checkpoint',
        'sequence': ++_sequence,
        'pid': pid,
        'isolateId': isolateId,
        'phase': phase,
        'backend': backend,
        'fixture': fixture,
        'run': ?run,
      });
      if (!await pending.future.timeout(const Duration(seconds: 30))) {
        throw StateError('Host memory sample failed');
      }
    } finally {
      _pending = null;
    }
  }
}
