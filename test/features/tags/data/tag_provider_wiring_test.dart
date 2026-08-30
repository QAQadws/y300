import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/tags/data/providers/tag_providers.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart'
    as forum_adapters;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('production Tag directory provider remains desktop HTML-first', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(forumTagDirectoryRepositoryProvider),
      isA<forum_adapters.DiscuzForumTagDirectoryRepository>(),
    );
  });
}
