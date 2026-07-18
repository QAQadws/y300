import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/preferences/preferences_store.dart';

final preferencesStoreProvider = Provider<PreferencesStore>((ref) {
  return SharedPreferencesStore();
});
