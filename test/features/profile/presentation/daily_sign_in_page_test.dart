import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/core/preferences/preference_key.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/profile/data/daily_sign_in_storage.dart';
import 'package:y300/features/profile/data/providers/daily_sign_in_providers.dart';
import 'package:y300/features/profile/data/providers/daily_sign_in_storage_providers.dart';
import 'package:y300/features/profile/presentation/daily_sign_in_controller.dart';
import 'package:y300/features/profile/presentation/daily_sign_in_page.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../support/forum_auth_test_support.dart';
import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('signed state and ordered statistics never expose submit', (
    tester,
  ) async {
    final repository = _SignRepository(
      (query, _) async => _success(query.userId, ForumDailySignInStatus.signed),
    );
    final command = _SignCommand((_, _) async => _unknown);
    await _pump(tester, repository: repository, command: command);

    final l10n = _l10n(tester);
    expect(find.text(l10n.dailySignInSigned), findsOneWidget);
    expect(find.text('连续天数'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byKey(const Key('daily-sign-in-submit')), findsNothing);
    expect(command.requests, isEmpty);
  });

  testWidgets('reopening the native panel rereads network status', (
    tester,
  ) async {
    final repository = _SignRepository(
      (query, call) async => _success(
        query.userId,
        call == 0
            ? ForumDailySignInStatus.unsigned
            : ForumDailySignInStatus.signed,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        ...forumAuthOverrides(const _AuthRepository()),
        ..._storageOverrides(_MemoryPreferencesStore()),
        dailySignInRepositoryProvider.overrideWithValue(repository),
        dailySignInCommandProvider.overrideWithValue(
          _SignCommand((_, _) async => _unknown),
        ),
      ],
    );
    addTearDown(container.dispose);
    Future<void> show(Widget home) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: LocalizedTestApp(home: home),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(const DailySignInPage());
    expect(find.text(_l10n(tester).dailySignInUnsigned), findsOneWidget);
    await show(const Scaffold(body: SizedBox()));
    await show(const DailySignInPage());
    expect(find.text(_l10n(tester).dailySignInSigned), findsOneWidget);
    expect(repository.queries, hasLength(2));
  });

  testWidgets(
    'panel entry shares an in-flight read and refresh stays read-only',
    (tester) async {
      final pending = Completer<_ReadResult>();
      final repository = _SignRepository(
        (query, call) => call == 0
            ? pending.future
            : Future.value(
                _success(query.userId, ForumDailySignInStatus.signed),
              ),
      );
      final command = _SignCommand((_, _) async => _unknown);
      await _pump(
        tester,
        repository: repository,
        command: command,
        settle: false,
      );
      await tester.pump();
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DailySignInPage)),
      );
      final controller = container.read(dailySignInControllerProvider.notifier);
      final firstRefresh = controller.refresh();
      final secondRefresh = controller.refresh();
      expect(repository.queries, hasLength(1));
      expect(find.byKey(const Key('daily-sign-in-progress')), findsOneWidget);

      pending.complete(_success('654321', ForumDailySignInStatus.unsigned));
      await Future.wait([firstRefresh, secondRefresh]);
      await tester.pumpAndSettle();
      expect(find.text(_l10n(tester).dailySignInUnsigned), findsOneWidget);
      expect(repository.queries, hasLength(1));
      expect(command.requests, isEmpty);

      await tester.tap(find.byKey(const Key('daily-sign-in-refresh')));
      await tester.pumpAndSettle();
      expect(find.text(_l10n(tester).dailySignInSigned), findsOneWidget);
      expect(repository.queries, hasLength(2));
      expect(command.requests, isEmpty);
    },
  );

  testWidgets('mounted panel rereads after logout and same-account login', (
    tester,
  ) async {
    final store = YamiboSessionStore()..saveExtracted(_session('654321'));
    final repository = _SignRepository(
      (query, call) async => _success(
        query.userId,
        call == 0
            ? ForumDailySignInStatus.unsigned
            : ForumDailySignInStatus.signed,
      ),
    );
    final command = _SignCommand((_, _) async => _unknown);
    await _pump(tester, repository: repository, command: command, store: store);
    expect(repository.queries, hasLength(1));
    expect(find.text(_l10n(tester).dailySignInUnsigned), findsOneWidget);

    store.clear();
    await tester.pumpAndSettle();
    expect(find.text(_l10n(tester).dailySignInLoginRequired), findsOneWidget);
    expect(find.byKey(const Key('daily-sign-in-status')), findsNothing);
    expect(repository.queries, hasLength(1));

    store.saveExtracted(_session('654321'));
    await tester.pumpAndSettle();
    expect(find.text(_l10n(tester).dailySignInSigned), findsOneWidget);
    expect(find.byKey(const Key('daily-sign-in-progress')), findsNothing);
    expect(repository.queries.map((query) => query.userId), [
      '654321',
      '654321',
    ]);
    expect(command.requests, isEmpty);
  });

  testWidgets('concurrent manual triggers make one command and verify read', (
    tester,
  ) async {
    final repository = _SignRepository(
      (query, call) async => _success(
        query.userId,
        call == 0
            ? ForumDailySignInStatus.unsigned
            : ForumDailySignInStatus.signed,
      ),
    );
    final pending = Completer<DataCommandResult<ForumDailySignInReceipt>>();
    final command = _SignCommand((_, _) => pending.future);
    await _pump(tester, repository: repository, command: command);

    await tester.tap(find.byKey(const Key('daily-sign-in-submit')));
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DailySignInPage)),
    );
    unawaited(container.read(dailySignInControllerProvider.notifier).submit());
    expect(command.requests, hasLength(1));
    expect(command.requests.single.expectedForumDay, '20260925');
    expect(find.byKey(const Key('daily-sign-in-submit')), findsNothing);

    pending.complete(_unknown);
    await tester.pumpAndSettle();
    expect(repository.queries, hasLength(2));
    expect(command.requests, hasLength(1));
    expect(find.text(_l10n(tester).dailySignInSigned), findsOneWidget);
    expect(
      find.text(_l10n(tester).dailySignInUnknownButSigned),
      findsOneWidget,
    );
    expect(find.text(_l10n(tester).dailySignInApplied), findsNothing);
  });

  testWidgets('unknown result requires explicit confirmation for a retry', (
    tester,
  ) async {
    final repository = _SignRepository(
      (query, _) async =>
          _success(query.userId, ForumDailySignInStatus.unsigned),
    );
    final command = _SignCommand((_, _) async => _unknown);
    await _pump(tester, repository: repository, command: command);

    await tester.tap(find.byKey(const Key('daily-sign-in-submit')));
    await tester.pumpAndSettle();
    expect(command.requests, hasLength(1));
    expect(command.requests.single.expectedForumDay, '20260925');
    expect(find.text(_l10n(tester).dailySignInOutcomeUnknown), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DailySignInPage)),
    );
    await container.read(dailySignInControllerProvider.notifier).submit();
    expect(command.requests, hasLength(1));

    await tester.tap(find.byKey(const Key('daily-sign-in-submit')));
    await tester.pumpAndSettle();
    expect(find.text(_l10n(tester).dailySignInRetryTitle), findsOneWidget);
    await tester.tap(find.text(_l10n(tester).commonCancel));
    await tester.pumpAndSettle();
    expect(command.requests, hasLength(1));

    await tester.tap(find.byKey(const Key('daily-sign-in-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('daily-sign-in-confirm-retry')));
    await tester.pumpAndSettle();
    expect(command.requests, hasLength(2));
    expect(repository.queries, hasLength(3));
  });

  testWidgets('forum day change does not silently clear an unknown send', (
    tester,
  ) async {
    final repository = _SignRepository(
      (query, call) async => _success(
        query.userId,
        ForumDailySignInStatus.unsigned,
        forumDay: call == 0 ? '20260925' : '20260926',
      ),
    );
    final command = _SignCommand((_, _) async => _unknown);
    await _pump(tester, repository: repository, command: command);

    await tester.tap(find.byKey(const Key('daily-sign-in-submit')));
    await tester.pumpAndSettle();
    expect(command.requests, hasLength(1));
    expect(find.text(_l10n(tester).dailySignInOutcomeUnknown), findsOneWidget);
    expect(find.text(_l10n(tester).dailySignInRetryUnknown), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DailySignInPage)),
    );
    await container.read(dailySignInControllerProvider.notifier).submit();
    expect(command.requests, hasLength(1));
  });

  testWidgets('day change during preparation reports no submission', (
    tester,
  ) async {
    final repository = _SignRepository(
      (query, call) async => _success(
        query.userId,
        ForumDailySignInStatus.unsigned,
        forumDay: call == 0 ? '20260925' : '20260926',
      ),
    );
    final command = _SignCommand(
      (_, _) async => const DataCommandNotSent(
        DataCommandFailure(
          kind: DataCommandFailureKind.validation,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'daily_sign_in_forum_day_changed',
          diagnosticMessage: 'daily_sign_in_forum_day_changed',
        ),
      ),
    );
    await _pump(tester, repository: repository, command: command);

    await tester.tap(find.byKey(const Key('daily-sign-in-submit')));
    await tester.pumpAndSettle();
    expect(find.text(_l10n(tester).dailySignInDayChanged), findsOneWidget);
    expect(find.text(_l10n(tester).dailySignInUnsigned), findsOneWidget);
    expect(command.requests, hasLength(1));
  });

  testWidgets('failed explicit retry keeps the earlier unknown guard', (
    tester,
  ) async {
    final repository = _SignRepository(
      (query, call) async => _success(
        query.userId,
        ForumDailySignInStatus.unsigned,
        forumDay: call == 0 ? '20260925' : '20260926',
      ),
    );
    final command = _SignCommand(
      (_, call) async => call == 0
          ? _unknown
          : const DataCommandNotSent(
              DataCommandFailure(
                kind: DataCommandFailureKind.validation,
                retryPolicy: DataCommandRetryPolicy.explicitOnly,
                code: 'daily_sign_in_forum_day_changed',
                diagnosticMessage: 'daily_sign_in_forum_day_changed',
              ),
            ),
    );
    await _pump(tester, repository: repository, command: command);

    await tester.tap(find.byKey(const Key('daily-sign-in-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('daily-sign-in-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('daily-sign-in-confirm-retry')));
    await tester.pumpAndSettle();
    expect(command.requests, hasLength(2));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DailySignInPage)),
    );
    await container.read(dailySignInControllerProvider.notifier).submit();
    expect(command.requests, hasLength(2));
    expect(find.text(_l10n(tester).dailySignInRetryUnknown), findsOneWidget);
  });

  testWidgets('session change hides a late old-account sign read', (
    tester,
  ) async {
    final store = YamiboSessionStore()..saveExtracted(_session('654321'));
    final oldRead = Completer<_ReadResult>();
    final repository = _SignRepository((query, _) {
      if (query.userId == '654321') return oldRead.future;
      return Future.value(
        _success(query.userId, ForumDailySignInStatus.signed),
      );
    });
    await _pump(
      tester,
      repository: repository,
      command: _SignCommand((_, _) async => _unknown),
      store: store,
      settle: false,
    );
    await tester.pump();
    await tester.pump();
    expect(repository.queries, hasLength(1));
    expect(repository.queries.single.userId, '654321');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DailySignInPage)),
    );

    store.saveExtracted(_session('777777'));
    container
        .read(authSessionControllerProvider.notifier)
        .acceptSession(
          const ForumSessionIdentity(
            userId: '777777',
            username: 'second-member',
          ),
        );
    await tester.pumpAndSettle();
    expect(repository.queries.last.userId, '777777');
    expect(repository.queries, hasLength(2));
    expect(find.text(_l10n(tester).dailySignInSigned), findsOneWidget);

    oldRead.complete(_success('654321', ForumDailySignInStatus.unsigned));
    await tester.pumpAndSettle();
    expect(find.text(_l10n(tester).dailySignInSigned), findsOneWidget);
    expect(find.text(_l10n(tester).dailySignInUnsigned), findsNothing);
    expect(repository.queries, hasLength(2));
  });

  testWidgets('session change discards a late old-account command', (
    tester,
  ) async {
    final store = YamiboSessionStore()..saveExtracted(_session('654321'));
    final repository = _SignRepository(
      (query, _) async => _success(
        query.userId,
        query.userId == '654321'
            ? ForumDailySignInStatus.unsigned
            : ForumDailySignInStatus.signed,
      ),
    );
    final oldCommand = Completer<DataCommandResult<ForumDailySignInReceipt>>();
    final command = _SignCommand((_, _) => oldCommand.future);
    await _pump(tester, repository: repository, command: command, store: store);

    await tester.tap(find.byKey(const Key('daily-sign-in-submit')));
    await tester.pump();
    expect(command.requests, hasLength(1));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DailySignInPage)),
    );

    store.saveExtracted(_session('777777'));
    container
        .read(authSessionControllerProvider.notifier)
        .acceptSession(
          const ForumSessionIdentity(
            userId: '777777',
            username: 'second-member',
          ),
        );
    await tester.pumpAndSettle();
    expect(find.text(_l10n(tester).dailySignInSigned), findsOneWidget);
    expect(find.byKey(const Key('daily-sign-in-submitting')), findsNothing);

    oldCommand.complete(_unknown);
    await tester.pumpAndSettle();
    expect(find.text(_l10n(tester).dailySignInSigned), findsOneWidget);
    expect(
      find.byKey(const Key('daily-sign-in-command-message')),
      findsNothing,
    );
    expect(command.requests, hasLength(1));
  });

  testWidgets('same account relogin waits for prior command and keeps guard', (
    tester,
  ) async {
    final store = YamiboSessionStore()..saveExtracted(_session('654321'));
    final repository = _SignRepository(
      (query, _) async =>
          _success(query.userId, ForumDailySignInStatus.unsigned),
    );
    final oldCommand = Completer<DataCommandResult<ForumDailySignInReceipt>>();
    final command = _SignCommand((_, _) => oldCommand.future);
    await _pump(tester, repository: repository, command: command, store: store);

    await tester.tap(find.byKey(const Key('daily-sign-in-submit')));
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DailySignInPage)),
    );
    store.clear();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('daily-sign-in-submit')), findsNothing);

    store.saveExtracted(_session('654321'));
    await tester.pump();
    await tester.pump();
    expect(command.requests, hasLength(1));
    expect(find.byKey(const Key('daily-sign-in-submit')), findsNothing);

    oldCommand.complete(_unknown);
    await tester.pumpAndSettle();
    expect(find.text(_l10n(tester).dailySignInRetryUnknown), findsOneWidget);
    await container.read(dailySignInControllerProvider.notifier).submit();
    expect(command.requests, hasLength(1));
  });

  testWidgets('parse failure offers only the canonical forum page', (
    tester,
  ) async {
    final opened = <ForumWebViewLaunchConfig>[];
    final repository = _SignRepository(
      (_, _) async => const DataReadFailure(
        kind: DataReadFailureKind.parse,
        diagnosticMessage: 'synthetic_structure_change',
      ),
    );
    await _pump(
      tester,
      repository: repository,
      command: _SignCommand((_, _) async => _unknown),
      routeFactory: (config) {
        opened.add(config);
        return MaterialPageRoute<Object?>(
          builder: (_) => const Scaffold(body: Text('managed forum')),
        );
      },
    );
    expect(find.byKey(const Key('daily-sign-in-submit')), findsNothing);
    await tester.tap(find.byKey(const Key('daily-sign-in-web-fallback')));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
    expect(opened.single.initialUri.path, '/plugin.php');
    expect(opened.single.initialUri.queryParameters, {
      'id': 'zqlj_sign',
      'mobile': '2',
    });
  });

  testWidgets('sign panel fits 300dp with enlarged text', (tester) async {
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _SignRepository(
      (query, _) async =>
          _success(query.userId, ForumDailySignInStatus.unsigned),
    );
    await _pump(
      tester,
      repository: repository,
      command: _SignCommand((_, _) async => _unknown),
      textScaler: const TextScaler.linear(1.6),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('daily-sign-in-submit')), findsOneWidget);
    expect(find.byKey(const Key('daily-auto-sign-in-toggle')), findsOneWidget);
  });

  testWidgets('automatic sign-in toggle defaults on and persists per account', (
    tester,
  ) async {
    final preferences = _MemoryPreferencesStore();
    final session = YamiboSessionStore()..saveExtracted(_session('654321'));
    final repository = _SignRepository(
      (query, _) async =>
          _success(query.userId, ForumDailySignInStatus.unsigned),
    );
    await _pump(
      tester,
      repository: repository,
      command: _SignCommand((_, _) async => _unknown),
      preferences: preferences,
      store: session,
    );

    final toggle = find.byKey(const Key('daily-auto-sign-in-toggle'));
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
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
      tester.element(find.byType(DailySignInPage)),
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
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });

  testWidgets('pending checkpoint after restart explains same-day pause', (
    tester,
  ) async {
    final preferences = _MemoryPreferencesStore();
    await SharedPreferencesDailySignInAttemptLedger(
      preferences,
    ).reserve(userId: '654321', forumDay: '20260925');
    final repository = _SignRepository(
      (query, _) async =>
          _success(query.userId, ForumDailySignInStatus.unsigned),
    );
    final command = _SignCommand((_, _) async => _unknown);
    await _pump(
      tester,
      repository: repository,
      command: command,
      preferences: preferences,
    );

    expect(
      find.text(_l10n(tester).dailyAutoSignInPendingToday),
      findsOneWidget,
    );
    expect(find.text(_l10n(tester).dailySignInRetryUnknown), findsOneWidget);
    expect(command.requests, isEmpty);
  });

  testWidgets('previous-day unknown shows automatic pause and manual retry', (
    tester,
  ) async {
    final preferences = _MemoryPreferencesStore();
    final ledger = SharedPreferencesDailySignInAttemptLedger(preferences);
    final reservation = await ledger.reserve(
      userId: '654321',
      forumDay: '20260925',
    );
    await ledger.markUnknown(reservation!);
    final repository = _SignRepository(
      (query, _) async => _success(
        query.userId,
        ForumDailySignInStatus.unsigned,
        forumDay: '20260926',
      ),
    );
    await _pump(
      tester,
      repository: repository,
      command: _SignCommand((_, _) async => _unknown),
      preferences: preferences,
    );

    expect(
      find.text(_l10n(tester).dailyAutoSignInPausedPreviousDay),
      findsOneWidget,
    );
    expect(find.byKey(const Key('daily-sign-in-submit')), findsOneWidget);
    expect(find.text(_l10n(tester).dailySignInRetryUnknown), findsOneWidget);
  });

  testWidgets(
    'storage failure disables submission but preserves read-only refresh',
    (tester) async {
      final preferences = _MemoryPreferencesStore()..failReads = true;
      final repository = _SignRepository(
        (query, _) async =>
            _success(query.userId, ForumDailySignInStatus.unsigned),
      );
      final command = _SignCommand((_, _) async => _unknown);
      await _pump(
        tester,
        repository: repository,
        command: command,
        preferences: preferences,
      );

      expect(
        find.text(_l10n(tester).dailyAutoSignInStorageUnavailable),
        findsOneWidget,
      );
      expect(find.byKey(const Key('daily-sign-in-submit')), findsNothing);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('daily-auto-sign-in-toggle')),
            )
            .onChanged,
        isNull,
      );
      await tester.tap(find.byKey(const Key('daily-sign-in-refresh')));
      await tester.pumpAndSettle();
      expect(repository.queries, hasLength(2));
      expect(command.requests, isEmpty);
    },
  );
}

typedef _ReadResult =
    DataReadResult<ForumDailySignInSnapshot, ForumDailySignInReadCapabilities>;

_ReadResult _success(
  String uid,
  ForumDailySignInStatus status, {
  String forumDay = '20260925',
}) => DataReadSuccess(
  data: ForumDailySignInSnapshot(
    userId: uid,
    forumDay: forumDay,
    status: status,
    statistics: const [
      ForumDailySignInStatistic(label: '连续天数', value: '3'),
      ForumDailySignInStatistic(label: '累计天数', value: '8'),
    ],
  ),
  capabilities: ForumDailySignInReadCapabilities(
    values: DataCapabilitySet.supported(ForumDailySignInReadCapability.values),
  ),
  metadata: const DataReadMetadata.network(),
);

const _unknown = DataCommandOutcomeUnknown<ForumDailySignInReceipt>(
  DataCommandFailure(
    kind: DataCommandFailureKind.parse,
    retryPolicy: DataCommandRetryPolicy.explicitOnly,
    code: 'daily_sign_in_response_unconfirmed',
    diagnosticMessage: 'daily_sign_in_response_unconfirmed',
  ),
);

class _SignRepository implements ForumDailySignInRepository {
  _SignRepository(this.onLoad);

  final Future<_ReadResult> Function(ForumDailySignInQuery, int) onLoad;
  final List<ForumDailySignInQuery> queries = [];

  @override
  ForumDailySignInSourceCapabilities get capabilities =>
      ForumDailySignInSourceCapabilities(
        values: DataCapabilitySet.supported(
          ForumDailySignInReadCapability.values,
        ),
      );

  @override
  Future<_ReadResult> load(ForumDailySignInQuery query) {
    final call = queries.length;
    queries.add(query);
    return onLoad(query, call);
  }
}

class _SignCommand implements ForumDailySignInCommand {
  _SignCommand(this.onExecute);

  final Future<DataCommandResult<ForumDailySignInReceipt>> Function(
    ForumDailySignInRequest,
    int,
  )
  onExecute;
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
    final call = requests.length;
    requests.add(request);
    final authorize = request.beforeSend;
    if (authorize == null) {
      throw StateError('A production sign-in request must have a send gate');
    }
    final authorization = await authorize(
      ForumDailySignInPreparedAttempt(
        userId: request.userId,
        forumDay: request.expectedForumDay ?? '20260925',
      ),
    );
    if (authorization != ForumDailySignInSendAuthorization.allow) {
      return const DataCommandNotSent(
        DataCommandFailure(
          kind: DataCommandFailureKind.validation,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'daily_sign_in_send_suppressed',
          diagnosticMessage: 'daily_sign_in_send_suppressed',
        ),
      );
    }
    return onExecute(request, call);
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required ForumDailySignInRepository repository,
  required ForumDailySignInCommand command,
  YamiboSessionStore? store,
  ForumWebViewRouteFactory? routeFactory,
  TextScaler textScaler = TextScaler.noScaling,
  _MemoryPreferencesStore? preferences,
  bool settle = true,
}) async {
  final storage = preferences ?? _MemoryPreferencesStore();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...forumAuthOverrides(const _AuthRepository()),
        ..._storageOverrides(storage),
        dailySignInRepositoryProvider.overrideWithValue(repository),
        dailySignInCommandProvider.overrideWithValue(command),
        if (store != null) yamiboSessionStoreProvider.overrideWithValue(store),
        if (routeFactory != null)
          forumWebViewRouteFactoryProvider.overrideWithValue(routeFactory),
      ],
      child: LocalizedTestApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: const DailySignInPage(),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(DailySignInPage)));

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

List<Override> _storageOverrides(_MemoryPreferencesStore store) => [
  dailySignInAttemptLedgerProvider.overrideWithValue(
    SharedPreferencesDailySignInAttemptLedger(store),
  ),
  dailyAutoSignInSettingsProvider.overrideWithValue(
    SharedPreferencesDailyAutoSignInSettings(store),
  ),
];

final class _MemoryPreferencesStore implements PreferencesStore {
  final Map<String, Object> values = {};
  bool failReads = false;

  @override
  Future<T?> read<T extends Object>(PreferenceKey<T> key) async {
    if (failReads) throw StateError('synthetic read failure');
    final value = values[key.name];
    return value is T ? value : null;
  }

  @override
  Future<bool> contains<T extends Object>(PreferenceKey<T> key) async {
    if (failReads) throw StateError('synthetic read failure');
    return values.containsKey(key.name);
  }

  @override
  Future<void> write<T extends Object>(PreferenceKey<T> key, T value) async {
    values[key.name] = value;
  }

  @override
  Future<void> remove<T extends Object>(PreferenceKey<T> key) async {
    values.remove(key.name);
  }
}
