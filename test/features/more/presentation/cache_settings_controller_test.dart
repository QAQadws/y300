import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/more/data/more_settings_repository.dart';
import 'package:y300/features/more/presentation/cache_settings_controller.dart';

void main() {
  test('loads default/effective directory from repository', () async {
    final container = ProviderContainer(
      overrides: [
        moreSettingsRepositoryProvider.overrideWithValue(
          _FakeMoreSettingsRepository(
            defaultDir: 'C:/default-cache',
            customDir: null,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final state = await container.read(cacheSettingsControllerProvider.future);
    expect(state.defaultDirectory, 'C:/default-cache');
    expect(state.customDirectory, isNull);
    expect(state.effectiveDirectory, 'C:/default-cache');
  });

  test('choose custom directory updates effective directory', () async {
    final repo = _FakeMoreSettingsRepository(
      defaultDir: 'C:/default-cache',
      customDir: null,
      pickedDir: 'D:/comic-cache',
    );
    final container = ProviderContainer(
      overrides: [
        moreSettingsRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    await container.read(cacheSettingsControllerProvider.future);
    await container.read(cacheSettingsControllerProvider.notifier).chooseCustomDirectory();

    final value = container.read(cacheSettingsControllerProvider).value!;
    expect(value.customDirectory, 'D:/comic-cache');
    expect(value.effectiveDirectory, 'D:/comic-cache');
  });

  test('restore default clears custom directory', () async {
    final repo = _FakeMoreSettingsRepository(
      defaultDir: 'C:/default-cache',
      customDir: 'D:/comic-cache',
    );
    final container = ProviderContainer(
      overrides: [
        moreSettingsRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    await container.read(cacheSettingsControllerProvider.future);
    await container.read(cacheSettingsControllerProvider.notifier).restoreDefaultDirectory();

    final value = container.read(cacheSettingsControllerProvider).value!;
    expect(value.customDirectory, isNull);
    expect(value.effectiveDirectory, 'C:/default-cache');
  });
}

class _FakeMoreSettingsRepository implements MoreSettingsRepository {
  _FakeMoreSettingsRepository({
    required String defaultDir,
    String? customDir,
    String? pickedDir,
  })  : _defaultDir = defaultDir,
        _customDir = customDir,
        _pickedDir = pickedDir;

  final String _defaultDir;
  String? _customDir;
  final String? _pickedDir;

  @override
  Future<String> getDefaultCacheDirectory() async => _defaultDir;

  @override
  Future<String?> getCustomCacheDirectory() async => _customDir;

  @override
  Future<String?> pickDirectory() async => _pickedDir;

  @override
  Future<void> setCustomCacheDirectory(String? path) async {
    _customDir = path;
  }
}

