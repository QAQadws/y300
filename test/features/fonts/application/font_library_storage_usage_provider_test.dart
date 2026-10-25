import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/fonts/application/font_library_providers.dart';

void main() {
  test('repository and usage views share the same private store owner', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      identical(
        container.read(fontLibraryRepositoryProvider),
        container.read(fontLibraryStorageUsageProvider),
      ),
      isTrue,
    );
  });
}
