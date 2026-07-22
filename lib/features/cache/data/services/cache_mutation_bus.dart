import 'dart:async';

import 'package:y300/features/cache/domain/models/cache_capacity_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';

final class CacheMutationBus
    implements CacheMutationReporter, CacheMutationSource {
  CacheMutationBus();

  final StreamController<CacheNamespace> _controller =
      StreamController<CacheNamespace>.broadcast(sync: true);
  bool _disposed = false;

  @override
  Stream<CacheNamespace> get mutations => _controller.stream;

  @override
  void reportMutation(CacheNamespace namespace) {
    if (!_disposed) {
      _controller.add(namespace);
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _controller.close();
  }
}
