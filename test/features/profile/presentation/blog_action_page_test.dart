import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_action_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import '../../../test_support/localized_test_app.dart';
import '../test_support/blog_operation_fixture.dart';

void main() {
  for (final action in blogManagementActions) {
    testWidgets('$action waits for preparation and explicit confirmation', (
      tester,
    ) async {
      final service = BlogOperationFixture();
      final host = await _open(tester, service, action: action);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('blog-action-submit')))
            .onPressed,
        isNull,
      );
      expect(service.submissions, isEmpty);
      service.prepared();
      await tester.pumpAndSettle();
      expect(service.submissions, isEmpty);
      await tester.tap(find.byKey(const Key('blog-action-submit')));
      await tester.pump();
      expect(service.submissions, hasLength(1));
      expect(host.container.read(blogMutationBusProvider).last, isNull);
      service.applied();
      await tester.pumpAndSettle();
      expect(find.byType(BlogActionPage), findsNothing);
      expect((await host.receipt)?.target, blogActionTarget(action));
      expect(host.container.read(blogMutationBusProvider).last?.blogId, '11');
    });
  }

  testWidgets('rejection requires new read and another explicit confirm', (
    tester,
  ) async {
    final service = BlogOperationFixture(autoPrepare: true);
    final host = await _open(tester, service);
    await tester.tap(find.byKey(const Key('blog-action-submit')));
    await tester.pump();
    service.submissions.last.result.complete(
      const DataCommandRejected(blogActionWriteFailure),
    );
    await tester.pumpAndSettle();
    expect(find.text(blogActionWriteFailure.diagnosticMessage), findsNothing);
    expect(host.container.read(blogMutationBusProvider).last, isNull);
    await tester.tap(find.byKey(const Key('blog-action-retry')));
    await tester.pumpAndSettle();
    expect(service.preparations, hasLength(2));
    expect(service.submissions, hasLength(1));
    await tester.tap(find.byKey(const Key('blog-action-submit')));
    await tester.pump();
    service.applied();
    await tester.pumpAndSettle();
    expect(await host.receipt, isNotNull);
  });

  testWidgets('unknown outcome has no retry and publishes no mutation', (
    tester,
  ) async {
    final service = BlogOperationFixture(autoPrepare: true);
    final host = await _open(tester, service);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(BlogActionPage)),
    );
    await tester.tap(find.byKey(const Key('blog-action-submit')));
    await tester.pump();
    service.submissions.last.result.complete(
      const DataCommandOutcomeUnknown(blogActionWriteFailure),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.profileBlogActionOutcomeUnknown), findsOneWidget);
    expect(find.byKey(const Key('blog-action-submit')), findsNothing);
    expect(find.byKey(const Key('blog-action-retry')), findsNothing);
    expect(find.byKey(const Key('blog-action-open-web')), findsNothing);
    expect(host.container.read(blogMutationBusProvider).last, isNull);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(await host.receipt, isNull);
  });

  for (final submitting in [false, true]) {
    testWidgets(
      'leaving during ${submitting ? 'POST' : 'GET'} ignores late result',
      (tester) async {
        final service = BlogOperationFixture(autoPrepare: submitting);
        final host = await _open(tester, service);
        if (submitting) {
          await tester.tap(find.byKey(const Key('blog-action-submit')));
          await tester.pump();
        }
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(await host.receipt, isNull);
        final token = submitting
            ? service.submissions.last.cancellation
            : service.preparations.last.cancellation;
        expect(token!.isCancelled, isTrue);
        if (submitting) {
          service.applied();
        } else {
          service.prepared();
        }
        await tester.pumpAndSettle();
        expect(host.container.read(blogMutationBusProvider).last, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('changing account invalidates pending confirmation permanently', (
    tester,
  ) async {
    final service = BlogOperationFixture();
    final host = await _open(tester, service);
    host.changeActor('202');
    await tester.pump();
    host.changeActor('101');
    await tester.pump();
    service.prepared();
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(BlogActionPage)),
    );
    expect(find.text(l10n.forumWebViewAccountChanged), findsOneWidget);
    expect(find.byKey(const Key('blog-action-submit')), findsNothing);
    expect(service.submissions, isEmpty);
  });

  for (final family in AppThemeFamily.values) {
    for (final brightness in Brightness.values) {
      testWidgets('confirmation fits $family $brightness with large text', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(300, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final service = BlogOperationFixture();
        await _open(
          tester,
          service,
          theme: AppTheme.build(family: family, brightness: brightness),
          largeReducedMotion: true,
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
        service.prepared();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const Key('blog-action-submit')));
        await tester.tap(find.byKey(const Key('blog-action-submit')));
        await tester.pump();
        service.applied();
        await tester.pumpAndSettle();
        expect(find.byType(BlogActionPage), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Future<_Host> _open(
  WidgetTester tester,
  BlogOperationFixture service, {
  UserBlogAction action = UserBlogAction.delete,
  ThemeData? theme,
  bool largeReducedMotion = false,
}) async {
  final host = _Host(service);
  addTearDown(host.container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: host.container,
      child: LocalizedTestApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: largeReducedMotion,
            textScaler: TextScaler.linear(largeReducedMotion ? 2 : 1),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open-action'),
              onPressed: () {
                host.receipt = Navigator.of(context).push<UserBlogReceipt>(
                  MaterialPageRoute(
                    builder: (_) =>
                        BlogActionPage(target: blogActionTarget(action)),
                  ),
                );
              },
              child: const Text('fixture open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-action')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  if (service.autoPrepare) await tester.pumpAndSettle();
  return host;
}

final class _Host {
  _Host(this.service)
    : container = ProviderContainer(
        overrides: [
          blogAccountIdProvider.overrideWithValue('101'),
          userBlogOperationsProvider.overrideWithValue(service),
        ],
      );
  final BlogOperationFixture service;
  final ProviderContainer container;
  late Future<UserBlogReceipt?> receipt;
  void changeActor(String? actor) => container.updateOverrides([
    blogAccountIdProvider.overrideWithValue(actor),
    userBlogOperationsProvider.overrideWithValue(service),
  ]);
}
