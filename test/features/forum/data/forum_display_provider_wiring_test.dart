import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/forum/data/providers/forum_display_repository_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('production forum display provider remains HTML-first', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final client = container.read(yamiboForumClientProvider);
    final repository = container.read(forumDisplayRepositoryProvider);

    expect(repository, same(client.forumDisplay));
    expect(
      repository.capabilities.supports(ForumDisplayCapability.filters),
      isTrue,
    );
    expect(
      repository.capabilities.paginationPrecision,
      PaginationPrecision.exact,
    );
  });
}
