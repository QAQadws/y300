import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/preferences/preferences_providers.dart';
import 'package:y300/features/thread/data/repositories/shared_preferences_thread_quick_scroll_repository.dart';
import 'package:y300/features/thread/domain/repositories/thread_quick_scroll_preferences_repository.dart';

final threadQuickScrollPreferencesRepositoryProvider =
    Provider<ThreadQuickScrollPreferencesRepository>((ref) {
      return SharedPreferencesThreadQuickScrollRepository(
        ref.watch(preferencesStoreProvider),
      );
    });
