import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/core/preferences/preference_key.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/profile/data/daily_sign_in_storage.dart';
import 'package:y300/features/profile/data/providers/daily_sign_in_providers.dart';
import 'package:y300/features/profile/data/providers/daily_sign_in_storage_providers.dart';
import 'package:y300/features/profile/presentation/daily_auto_sign_in_toggle.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../support/forum_auth_test_support.dart';
import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('automatic sign-in toggle defaults on and persists per account', (
    tester,
  ) async {
    final preferences = _MemoryPreferencesStore();
    final session = YamiboSessionStore()..saveExtracted(_session('654321'));
    final repository = _SignRepository();
    final command = _SignCommand();
    await _pump(
      tester,
      repository: repository,
      command: command,
      preferences: preferences,
      store: session,
    );

    final toggle = find.byKey(const Key('daily-auto-sign-in-toggle'));
    expect(tester.widget<Switch>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isFalse);
    final previousAccountToggle = tester.widget<Switch>(toggle).onChanged!;
    expect(
      await SharedPreferencesDailyAutoSignInSettings(
        preferences,
      ).isEnabled('654321'),
      isFalse,
    );
    expect(
      await SharedPreferencesDailyAutoSignInSettings(
        preferences,
      ).isEnabled('777777'),
      isTrue,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DailyAutoSignInToggle)),
    );
    session.saveExtracted(_session('777777'));
    container
        .read(authSessionControllerProvider.notifier)
        .acceptSession(
          const ForumSessionIdentity(
            userId: '777777',
            username: 'second-member',
          ),
        );
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isTrue);
    previousAccountToggle(false);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(repository.queries, isEmpty);
    expect(command.requests, isEmpty);
  });

  testWidgets('automatic toggle rolls back and explains a failed save', (
    tester,
  ) async {
    final preferences = _MemoryPreferencesStore()..failWrites = true;
    final repository = _SignRepository();
    final command = _SignCommand();
    await _pump(
      tester,
      repository: repository,
      command: command,
      preferences: preferences,
    );
    final toggle = find.byKey(const Key('daily-auto-sign-in-toggle'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(DailyAutoSignInToggle)),
    );
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(tester.widget<Switch>(toggle).onChanged, isNull);
    expect(find.text(l10n.dailyAutoSignInStorageUnavailable), findsOneWidget);
    expect(repository.queries, isEmpty);
    expect(command.requests, isEmpty);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required ForumDailySignInRepository repository,
  required ForumDailySignInCommand command,
  required _MemoryPreferencesStore preferences,
  YamiboSessionStore? store,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...forumAuthOverrides(const _AuthRepository()),
        dailySignInAttemptLedgerProvider.overrideWithValue(
          SharedPreferencesDailySignInAttemptLedger(preferences),
        ),
        dailyAutoSignInSettingsProvider.overrideWithValue(
          SharedPreferencesDailyAutoSignInSettings(preferences),
        ),
        dailySignInRepositoryProvider.overrideWithValue(repository),
        dailySignInCommandProvider.overrideWithValue(command),
        if (store != null) yamiboSessionStoreProvider.overrideWithValue(store),
      ],
      child: const LocalizedTestApp(
        home: Scaffold(body: DailyAutoSignInToggle()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _SignRepository implements ForumDailySignInRepository {
  final List<ForumDailySignInQuery> queries = [];

  @override
  ForumDailySignInSourceCapabilities get capabilities =>
      ForumDailySignInSourceCapabilities(
        values: DataCapabilitySet.supported(
          ForumDailySignInReadCapability.values,
        ),
      );

  @override
  Future<
    DataReadResult<ForumDailySignInSnapshot, ForumDailySignInReadCapabilities>
  >
  load(ForumDailySignInQuery query) async {
    queries.add(query);
    throw StateError('Displaying or changing the toggle must not read status');
  }
}

class _SignCommand implements ForumDailySignInCommand {
  final List<ForumDailySignInRequest> requests = [];

  @override
  ForumDailySignInCommandCapabilities get capabilities =>
      ForumDailySignInCommandCapabilities(
        values: DataCapabilitySet.supported(
          ForumDailySignInCommandCapability.values,
        ),
      );

  @override
  Future<DataCommandResult<ForumDailySignInReceipt>> execute(
    ForumDailySignInRequest request,
  ) async {
    requests.add(request);
    throw StateError('Displaying or changing the toggle must not submit');
  }
}

YamiboSessionSnapshot _session(String uid) => YamiboSessionSnapshot(
  isLoggedIn: true,
  uid: uid,
  username: 'sample-member',
  formhash: '',
  updatedAt: DateTime(2026, 1, 1),
  source: 'test',
);

class _AuthRepository implements AuthRepository {
  const _AuthRepository();

  @override
  Future<ApiResult<SessionInfo>> refreshSession() async => const ApiSuccess(
    SessionInfo(
      uid: '654321',
      username: 'sample-member',
      formhash: 'fh',
      isLoggedIn: true,
    ),
  );

  @override
  Future<ApiResult<bool>> verifyAuthByForumIndex() async =>
      const ApiSuccess<bool>(true);

  @override
  Future<ApiResult<SessionInfo>> login({
    required String username,
    required String password,
    String questionId = '0',
    String answer = '',
  }) async => refreshSession();

  @override
  Future<void> logout() async {}
}

final class _MemoryPreferencesStore implements PreferencesStore {
  final Map<String, Object> values = {};
  bool failWrites = false;

  @override
  Future<T?> read<T extends Object>(PreferenceKey<T> key) async {
    final value = values[key.name];
    return value is T ? value : null;
  }

  @override
  Future<bool> contains<T extends Object>(PreferenceKey<T> key) async =>
      values.containsKey(key.name);

  @override
  Future<void> write<T extends Object>(PreferenceKey<T> key, T value) async {
    if (failWrites) throw StateError('synthetic write failure');
    values[key.name] = value;
  }

  @override
  Future<void> remove<T extends Object>(PreferenceKey<T> key) async {
    values.remove(key.name);
  }
}
