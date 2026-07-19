import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/app_update/data/providers/app_update_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('update providers reuse one coordinator and an isolated Dio client', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final firstCoordinator = container.read(appUpdatePromptCoordinatorProvider);
    final secondCoordinator = container.read(
      appUpdatePromptCoordinatorProvider,
    );
    final firstDio = container.read(appUpdateDioProvider);
    final secondDio = container.read(appUpdateDioProvider);
    final headerNames = firstDio.options.headers.keys
        .map((key) => key.toLowerCase())
        .toSet();
    final interceptorNames = firstDio.interceptors
        .map((interceptor) => interceptor.runtimeType.toString().toLowerCase())
        .toList();

    expect(identical(firstCoordinator, secondCoordinator), isTrue);
    expect(identical(firstDio, secondDio), isTrue);
    expect(headerNames, isNot(contains('cookie')));
    expect(headerNames, isNot(contains('authorization')));
    expect(
      interceptorNames.where(
        (name) => name.contains('cookie') || name.contains('auth'),
      ),
      isEmpty,
    );
  });
}
