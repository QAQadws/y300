import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart'
    as forum_adapters;
import 'package:y300/features/forum/data/providers/forum_display_repository_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('production forum display provider remains HTML-first', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final repository = container.read(forumDisplayRepositoryProvider);

    expect(repository, isA<forum_adapters.ForumDisplayHtmlRepository>());
  });
}
