import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/tags/data/providers/tag_providers.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('production Tag directory provider remains desktop HTML-first', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final client = container.read(yamiboForumClientProvider);
    final repository = container.read(forumTagDirectoryRepositoryProvider);

    expect(repository, same(client.forumTagDirectory));
    expect(
      repository.capabilities.supports(
        ForumTagDirectoryCapability.stableTagIdentity,
      ),
      isTrue,
    );
  });
}
