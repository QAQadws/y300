import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/services/cache_mutation_bus.dart';

/// Leaf dependency shared by cache participants; never assembles participants.
final cacheMutationBusProvider = Provider<CacheMutationBus>((ref) {
  final bus = CacheMutationBus();
  ref.onDispose(() => unawaited(bus.dispose()));
  return bus;
});
