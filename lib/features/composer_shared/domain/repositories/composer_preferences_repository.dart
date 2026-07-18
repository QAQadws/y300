import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';

abstract interface class ComposerPreferencesRepository {
  Future<ComposerPreferences> load();

  Future<void> save(ComposerPreferences preferences);
}
