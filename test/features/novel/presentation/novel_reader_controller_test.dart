import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_rich_block_text.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/domain/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_episode_open_policy.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_update_service.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_position.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_transition_state.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_bootstrap_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_document_build_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_progress_committer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_supplemental_hydration_service.dart';

void main() {
  test('NovelReaderViewState derives episode boundaries', () {
    final episodes = _episodes();

    final first = _viewState(
      episodes: episodes,
      currentEpisode: episodes.first,
    );
    expect(first.currentEpisodeIndex, 0);
    expect(first.previousEpisode, isNull);
    expect(first.nextEpisode?.episodeId, episodes[1].episodeId);
    expect(first.hasPreviousEpisode, isFalse);
    expect(first.hasNextEpisode, isTrue);

    final middle = _viewState(episodes: episodes, currentEpisode: episodes[1]);
    expect(middle.currentEpisodeIndex, 1);
    expect(middle.previousEpisode?.episodeId, episodes.first.episodeId);
    expect(middle.nextEpisode?.episodeId, episodes.last.episodeId);
    expect(middle.hasPreviousEpisode, isTrue);
    expect(middle.hasNextEpisode, isTrue);

    final last = _viewState(episodes: episodes, currentEpisode: episodes.last);
    expect(last.currentEpisodeIndex, 2);
    expect(last.previousEpisode?.episodeId, episodes[1].episodeId);
    expect(last.nextEpisode, isNull);
    expect(last.hasPreviousEpisode, isTrue);
    expect(last.hasNextEpisode, isFalse);
  });

  test('NovelReaderController loads readingProgress into state', () async {
    final progress = NovelReadingProgress(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5002',
      scrollOffset: 88,
      updatedAt: DateTime(2026, 6, 1),
      anchorFormatVersion: 37,
      anchorTextIdentity: '  unsupported identity  ',
      isProgressPercentValid: false,
    );
    final repository = _ControllerNovelRepository(readingProgress: progress);
    final container = _buildContainer(repository: repository);
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5002',
    );
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    final state = await container.read(
      novelReaderControllerProvider(args).future,
    );

    expect(state.readingProgress?.episodeId, 'novel:49:100:5002');
    expect(state.currentOffset, 88);
    expect(state.progressSnapshot.anchorFormatVersion, 37);
    expect(
      state.progressSnapshot.anchorTextIdentity,
      '  unsupported identity  ',
    );
    expect(state.progressSnapshot.isProgressPercentValid, isFalse);
  });

  test(
    'NovelReaderController exposes the persisted paged preference as effective mode',
    () async {
      final repository = _ControllerNovelRepository(
        preferences: NovelReaderPreferences.defaults().copyWith(
          flowMode: NovelReaderFlowMode.pagedRtl,
        ),
      );
      final container = _buildContainer(repository: repository);
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);

      final state = await container.read(
        novelReaderControllerProvider(args).future,
      );

      expect(state.persistedPreferences.flowMode, NovelReaderFlowMode.pagedRtl);
      expect(state.effectivePreferences.flowMode, NovelReaderFlowMode.pagedRtl);
      expect(state.progressSnapshot.flowMode, NovelReaderFlowMode.pagedRtl);
    },
  );

  test(
    'NovelReaderController exposes paged LTR for new-reader defaults',
    () async {
      final repository = _ControllerNovelRepository(
        preferences: NovelReaderPreferences.defaults(),
      );
      final container = _buildContainer(repository: repository);
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);

      final state = await container.read(
        novelReaderControllerProvider(args).future,
      );

      expect(state.persistedPreferences.flowMode, NovelReaderFlowMode.pagedLtr);
      expect(state.effectivePreferences.flowMode, NovelReaderFlowMode.pagedLtr);
      expect(state.progressSnapshot.flowMode, NovelReaderFlowMode.pagedLtr);
    },
  );

  test(
    'NovelReaderController previewPreferences only updates effective state',
    () async {
      final repository = _ControllerNovelRepository();
      final container = _buildContainer(repository: repository);
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);

      final initial = await container.read(provider.future);
      final next = initial.persistedPreferences.copyWith(
        themePreset: NovelReaderThemePreset.sepia,
        flowMode: NovelReaderFlowMode.pagedLtr,
      );

      container.read(provider.notifier).previewPreferences(next);
      final state = container.read(provider).value!;

      expect(state.persistedPreferences, initial.persistedPreferences);
      expect(state.effectivePreferences, next);
      expect(state.progressSnapshot.flowMode, NovelReaderFlowMode.vertical);
      expect(repository.latestPreferences, isNull);
      expect(repository.upsertPreferencesCallCount, 0);
    },
  );

  test(
    'NovelReaderController commitPreferences persists once and syncs state',
    () async {
      final repository = _ControllerNovelRepository();
      final container = _buildContainer(repository: repository);
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);

      final initial = await container.read(provider.future);
      final next = initial.persistedPreferences.copyWith(
        themePreset: NovelReaderThemePreset.dark,
      );

      container.read(provider.notifier).previewPreferences(next);
      await container.read(provider.notifier).commitPreferences(next);
      final state = container.read(provider).value!;

      expect(repository.latestPreferences, next);
      expect(repository.upsertPreferencesCallCount, 1);
      expect(state.persistedPreferences, next);
      expect(state.effectivePreferences, next);
    },
  );

  test(
    'NovelReaderController revertPreferencePreview rolls back effective state',
    () async {
      final repository = _ControllerNovelRepository();
      final container = _buildContainer(repository: repository);
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);

      final initial = await container.read(provider.future);
      final next = initial.persistedPreferences.copyWith(
        flowMode: NovelReaderFlowMode.pagedLtr,
      );

      container.read(provider.notifier).previewPreferences(next);
      container.read(provider.notifier).revertPreferencePreview();
      final state = container.read(provider).value!;

      expect(state.persistedPreferences, initial.persistedPreferences);
      expect(state.effectivePreferences, initial.persistedPreferences);
      expect(
        state.progressSnapshot.flowMode,
        initial.persistedPreferences.flowMode,
      );
      expect(repository.upsertPreferencesCallCount, 0);
    },
  );

  test('late preference save preserves a newer preview and progress', () async {
    final repository = _ControllerNovelRepository();
    final preferencesRepository = _DelayedPreferencesRepository(repository);
    final container = _buildContainer(
      repository: repository,
      preferencesRepository: preferencesRepository,
    );
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);
    final initial = await container.read(provider.future);
    final controller = container.read(provider.notifier);
    final first = initial.preferences.copyWith(fontSize: 20);
    final latest = first.copyWith(fontSize: 24);
    controller.previewPreferences(first);
    final commit = controller.commitPreferences(first);
    controller.previewPreferences(latest);
    preferencesRepository.saveGate.complete();
    await commit;

    final state = container.read(provider).value!;
    expect(state.persistedPreferences, first);
    expect(state.effectivePreferences, latest);
    expect(state.progressSnapshot, initial.progressSnapshot);
    expect(state.document, initial.document);
  });

  test(
    'preference save finishing after disposal does not use disposed ref',
    () async {
      final repository = _ControllerNovelRepository();
      final preferencesRepository = _DelayedPreferencesRepository(repository);
      final container = _buildContainer(
        repository: repository,
        preferencesRepository: preferencesRepository,
      );
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      final subscription = _keepReaderAlive(container, args);
      final initial = await container.read(provider.future);
      final next = initial.preferences.copyWith(fontSize: 24);
      final commit = container.read(provider.notifier).commitPreferences(next);
      subscription.close();
      container.dispose();
      preferencesRepository.saveGate.complete();

      await expectLater(commit, completes);
      expect(repository.latestPreferences, next);
    },
  );

  test('an old save cannot mutate a rebuilt reader generation', () async {
    final repository = _ControllerNovelRepository();
    final preferencesRepository = _DelayedPreferencesRepository(repository);
    final container = _buildContainer(
      repository: repository,
      preferencesRepository: preferencesRepository,
    );
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);
    final initial = await container.read(provider.future);
    final first = initial.preferences.copyWith(fontSize: 20);
    final commit = container.read(provider.notifier).commitPreferences(first);
    container.invalidate(provider);
    final rebuilt = await container.read(provider.future);
    final latest = rebuilt.preferences.copyWith(fontSize: 24);
    container.read(provider.notifier).previewPreferences(latest);
    preferencesRepository.saveGate.complete();
    await commit;

    final state = container.read(provider).value!;
    expect(state.persistedPreferences, rebuilt.persistedPreferences);
    expect(state.effectivePreferences, latest);
    expect(state.document, rebuilt.document);
    expect(state.progressSnapshot, rebuilt.progressSnapshot);
  });

  test(
    'equal baseline is saved when an old write finished after rebuild',
    () async {
      final repository = _ControllerNovelRepository();
      final preferencesRepository = _DelayedPreferencesRepository(repository);
      final container = _buildContainer(
        repository: repository,
        preferencesRepository: preferencesRepository,
      );
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);
      final initial = await container.read(provider.future);
      final oldCommit = container
          .read(provider.notifier)
          .commitPreferences(initial.preferences.copyWith(fontSize: 20));
      container.invalidate(provider);
      final rebuilt = await container.read(provider.future);
      preferencesRepository.saveGate.complete();
      await oldCommit;
      expect(repository.preferences, isNot(rebuilt.persistedPreferences));

      await container
          .read(provider.notifier)
          .commitPreferences(rebuilt.persistedPreferences);
      expect(repository.preferences, rebuilt.persistedPreferences);
      expect(repository.upsertPreferencesCallCount, 2);
      await container
          .read(provider.notifier)
          .commitPreferences(rebuilt.persistedPreferences);
      expect(repository.upsertPreferencesCallCount, 2);
    },
  );

  for (final returnToOriginal in [false, true]) {
    test(
      returnToOriginal
          ? 'late converted document cannot replace a new session of the same episode'
          : 'late converted document cannot replace the next episode',
      () async {
        final repository = _ControllerNovelRepository();
        final bootstrap = _SequenceNovelReaderBootstrapService();
        bootstrap.completeAt(
          0,
          _criticalBootstrap(episodeId: 'novel:49:100:5001'),
        );
        final container = _buildContainer(
          repository: repository,
          bootstrapService: bootstrap,
        );
        addTearDown(container.dispose);
        const args = NovelReaderArgs(
          novelId: 'novel:49:100',
          episodeId: 'novel:49:100:5001',
        );
        final provider = novelReaderControllerProvider(args);
        final subscription = _keepReaderAlive(container, args);
        addTearDown(subscription.close);
        final initial = await container.read(provider.future);
        final controller = container.read(provider.notifier);
        final next = initial.preferences.copyWith(
          conversionMode: NovelReaderConversionMode.toTraditional,
        );
        controller.previewPreferences(next);
        final commit = controller.commitPreferences(next);
        await Future<void>.delayed(Duration.zero);
        expect(bootstrap.contexts, hasLength(2));
        expect(
          bootstrap.contexts[1].requestedEpisodeId,
          initial.currentEpisode.episodeId,
        );
        final transition = controller.openEpisodeFromCatalog(
          'novel:49:100:5002',
        );
        bootstrap.completeAt(
          2,
          _criticalBootstrap(
            episodeId: 'novel:49:100:5002',
            paragraphText: '第二章当前正文。',
            preferences: next,
          ),
        );
        expect(await transition, isTrue);
        if (returnToOriginal) {
          final returnTransition = controller.openEpisodeFromCatalog(
            'novel:49:100:5001',
          );
          bootstrap.completeAt(
            3,
            _criticalBootstrap(
              episodeId: 'novel:49:100:5001',
              paragraphText: '第一章新会话正文。',
              preferences: next,
            ),
          );
          expect(await returnTransition, isTrue);
        }
        final current = container.read(provider).value!;
        bootstrap.completeAt(
          1,
          _criticalBootstrap(
            episodeId: 'novel:49:100:5001',
            paragraphText: '迟到的旧转换正文。',
            preferences: next,
          ),
        );
        await commit;

        final state = container.read(provider).value!;
        expect(state.currentEpisode, current.currentEpisode);
        expect(state.currentContent, current.currentContent);
        expect(state.document, current.document);
        expect(state.progressSnapshot, current.progressSnapshot);
      },
    );
  }

  test(
    'NovelReaderController preview and commit are no-op for equal preferences',
    () async {
      final repository = _ControllerNovelRepository();
      final container = _buildContainer(repository: repository);
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);

      final initial = await container.read(provider.future);

      container
          .read(provider.notifier)
          .previewPreferences(initial.effectivePreferences);
      await container
          .read(provider.notifier)
          .commitPreferences(initial.persistedPreferences);
      final state = container.read(provider).value!;

      expect(state.persistedPreferences, initial.persistedPreferences);
      expect(state.effectivePreferences, initial.effectivePreferences);
      expect(repository.upsertPreferencesCallCount, 0);
    },
  );

  test(
    'NovelReaderController saveCurrentProgressNow flushes and syncs readingProgress',
    () async {
      final repository = _ControllerNovelRepository();
      final progressCommitter = _FakeNovelReaderProgressCommitter();
      final container = _buildContainer(
        repository: repository,
        progressCommitter: progressCommitter,
      );
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);

      await container.read(provider.future);
      const snapshot = NovelReaderProgressSnapshot(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
        flowMode: NovelReaderFlowMode.vertical,
        scrollOffset: 42,
        pageIndex: 0,
        progressPercent: 0.5,
        anchorFormatVersion: 37,
        anchorTextIdentity: '  unsupported identity  ',
      );

      await container.read(provider.notifier).saveCurrentProgressNow(snapshot);

      final state = container.read(provider).value!;
      expect(progressCommitter.flushCallCount, 1);
      expect(progressCommitter.latestFlushedSnapshot, snapshot);
      expect(state.progressSnapshot, snapshot);
      expect(state.currentOffset, 42);
      expect(state.readingProgress?.episodeId, 'novel:49:100:5001');
      expect(state.readingProgress?.scrollOffset, 42);
      expect(state.readingProgress?.anchorFormatVersion, 37);
      expect(
        state.readingProgress?.anchorTextIdentity,
        '  unsupported identity  ',
      );
      expect(state.readingProgress?.isProgressPercentValid, isNull);
    },
  );

  test(
    'progress flush rejects a snapshot from another novel or episode',
    () async {
      final repository = _ControllerNovelRepository();
      final committer = _FakeNovelReaderProgressCommitter();
      final container = _buildContainer(
        repository: repository,
        progressCommitter: committer,
      );
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);
      await container.read(provider.future);
      await Future<void>.delayed(Duration.zero);
      final initial = container.read(provider).value!;
      for (final identity in [
        (novelId: 'another-novel', episodeId: 'novel:49:100:5001'),
        (novelId: 'novel:49:100', episodeId: 'novel:49:100:5002'),
      ]) {
        await container
            .read(provider.notifier)
            .saveCurrentProgressNow(
              NovelReaderProgressSnapshot(
                novelId: identity.novelId,
                episodeId: identity.episodeId,
                flowMode: NovelReaderFlowMode.vertical,
                scrollOffset: 42,
                pageIndex: 0,
                progressPercent: 0.5,
              ),
            );
      }
      expect(committer.flushCallCount, 0);
      expect(container.read(provider).value, same(initial));
    },
  );

  for (final retirement in [
    'chapter',
    'return',
    'refresh',
    'refreshed',
    'dispose',
  ]) {
    test(
      'a started progress flush does not project after $retirement',
      () async {
        final initialProgress = NovelReadingProgress(
          novelId: 'novel:49:100',
          episodeId: 'novel:49:100:5001',
          scrollOffset: 7,
          updatedAt: DateTime(2026, 6, 1),
        );
        final repository = _ControllerNovelRepository(
          readingProgress: initialProgress,
        );
        final committer = _GatedProgressCommitter(repository);
        final bootstrap = retirement == 'refresh'
            ? _SequenceNovelReaderBootstrapService()
            : null;
        bootstrap?.completeAt(
          0,
          _criticalBootstrap(
            episodeId: 'novel:49:100:5001',
            readingProgress: initialProgress,
            preferences: repository.preferences,
          ),
        );
        final container = _buildContainer(
          repository: repository,
          progressCommitter: committer,
          bootstrapService: bootstrap,
        );
        var disposed = false;
        addTearDown(() {
          if (!disposed) container.dispose();
        });
        const args = NovelReaderArgs(
          novelId: 'novel:49:100',
          episodeId: 'novel:49:100:5001',
        );
        final provider = novelReaderControllerProvider(args);
        final subscription = _keepReaderAlive(container, args);
        addTearDown(() {
          if (!disposed) subscription.close();
        });
        await container.read(provider.future);
        final controller = container.read(provider.notifier);
        const snapshot = NovelReaderProgressSnapshot(
          novelId: 'novel:49:100',
          episodeId: 'novel:49:100:5001',
          flowMode: NovelReaderFlowMode.vertical,
          scrollOffset: 42,
          pageIndex: 0,
          progressPercent: 0.5,
        );
        final oldFlush = controller.saveCurrentProgressNow(snapshot);
        expect(committer.flushCallCount, 1);
        expect(container.read(provider).value!.currentOffset, 42);

        if (retirement == 'refresh') {
          container.invalidate(provider);
          final reloaded = container.read(provider.future);
          expect(container.read(provider.notifier), same(controller));
          expect(container.read(provider).isLoading, isTrue);
          await controller.saveCurrentProgressNow(snapshot);
          expect(
            committer.flushCallCount,
            1,
            reason: 'Loading has no active progress surface.',
          );
          committer.gate.complete();
          await oldFlush;
          expect(container.read(provider).isLoading, isTrue);
          bootstrap!.completeAt(
            1,
            _criticalBootstrap(
              episodeId: 'novel:49:100:5001',
              readingProgress: initialProgress,
              preferences: repository.preferences,
            ),
          );
          final fresh = await reloaded;
          expect(fresh.currentOffset, 7);
          expect(fresh.readingProgress, same(initialProgress));
        } else if (retirement == 'dispose') {
          container.dispose();
          disposed = true;
          committer.gate.complete();
          await oldFlush;
        } else if (retirement == 'refreshed') {
          container.invalidate(provider);
          await container.read(provider.future);
          expect(container.read(provider.notifier), same(controller));
          await Future<void>.delayed(Duration.zero);
          final fresh = container.read(provider).value!;
          expect(fresh.currentOffset, 7);
          committer.gate.complete();
          await oldFlush;
          final after = container.read(provider).value!;
          expect(after.progressSnapshot, fresh.progressSnapshot);
          expect(after.currentOffset, fresh.currentOffset);
          expect(after.readingProgress, same(fresh.readingProgress));
        } else {
          expect(await controller.openEpisode('novel:49:100:5002'), isTrue);
          if (retirement == 'return') {
            expect(await controller.openEpisode('novel:49:100:5001'), isTrue);
          }
          await Future<void>.delayed(Duration.zero);
          final fresh = container.read(provider).value!;
          committer.gate.complete();
          await oldFlush;
          final after = container.read(provider).value!;
          expect(
            after.currentEpisode.episodeId,
            fresh.currentEpisode.episodeId,
          );
          expect(after.progressSnapshot, fresh.progressSnapshot);
          expect(after.currentOffset, fresh.currentOffset);
          expect(after.readingProgress, same(fresh.readingProgress));
        }
        // Cancellation retires UI ownership, not the already issued local write.
        expect(committer.committed, [snapshot]);
        expect(repository.readingProgress!.scrollOffset, 42);
      },
    );
  }

  for (final dispose in [false, true]) {
    for (final fail in [false, true]) {
      test(
        'late chapter ${fail ? 'failure' : 'success'} is retired by ${dispose ? 'dispose' : 'same-notifier refresh'}',
        () async {
          final repository = _ControllerNovelRepository();
          final bootstrap = _SequenceNovelReaderBootstrapService();
          bootstrap.completeAt(
            0,
            _criticalBootstrap(episodeId: 'novel:49:100:5001'),
          );
          final container = _buildContainer(
            repository: repository,
            bootstrapService: bootstrap,
          );
          var disposed = false;
          addTearDown(() {
            if (!disposed) container.dispose();
          });
          const args = NovelReaderArgs(
            novelId: 'novel:49:100',
            episodeId: 'novel:49:100:5001',
          );
          final provider = novelReaderControllerProvider(args);
          final subscription = _keepReaderAlive(container, args);
          addTearDown(() {
            if (!disposed) subscription.close();
          });
          await container.read(provider.future);
          final controller = container.read(provider.notifier);
          final oldTransition = controller.openEpisode('novel:49:100:5002');
          expect(bootstrap.contexts, hasLength(2));
          expect(
            container.read(provider).value!.transition!.targetEpisodeId,
            'novel:49:100:5002',
          );
          NovelReaderViewState? fresh;
          if (dispose) {
            container.dispose();
            disposed = true;
          } else {
            bootstrap.completeAt(
              2,
              _criticalBootstrap(episodeId: 'novel:49:100:5001'),
            );
            container.invalidate(provider);
            await container.read(provider.future);
            expect(container.read(provider.notifier), same(controller));
            await Future<void>.delayed(Duration.zero);
            fresh = container.read(provider).value!;
            expect(fresh.transition, isNull);
          }
          if (fail) {
            bootstrap.failAt(1, StateError('retired chapter load failed'));
          } else {
            bootstrap.completeAt(
              1,
              _criticalBootstrap(episodeId: 'novel:49:100:5002'),
            );
          }
          expect(await oldTransition, isFalse);
          if (!dispose) {
            expect(container.read(provider).value, same(fresh));
            expect(
              container.read(provider).value!.currentEpisode.episodeId,
              'novel:49:100:5001',
            );
          }
        },
      );
    }
  }

  for (final dispose in [false, true]) {
    for (final fail in [false, true]) {
      test(
        'error-view update ${fail ? 'failure' : 'success'} is retired by ${dispose ? 'dispose' : 'same-notifier refresh'}',
        () async {
          final bootstrap = _SequenceNovelReaderBootstrapService();
          bootstrap.failAt(0, StateError('initial chapter unavailable'));
          final updates = _GatedNovelChapterUpdateService();
          final container = _buildContainer(
            repository: _ControllerNovelRepository(),
            bootstrapService: bootstrap,
            chapterUpdateService: updates,
          );
          var disposed = false;
          addTearDown(() {
            if (!disposed) container.dispose();
          });
          const args = NovelReaderArgs(
            novelId: 'novel:49:100',
            episodeId: 'novel:49:100:5001',
          );
          final provider = novelReaderControllerProvider(args);
          final subscription = _keepReaderAlive(container, args);
          addTearDown(() {
            if (!disposed) subscription.close();
          });
          await expectLater(container.read(provider.future), throwsStateError);
          expect(container.read(provider).hasError, isTrue);
          final controller = container.read(provider.notifier);
          final oldUpdate = controller.updateWork();
          expect(updates.started, 1);
          expect(container.read(provider).isLoading, isTrue);
          expect(bootstrap.contexts, hasLength(1));
          NovelReaderViewState? fresh;
          if (dispose) {
            container.dispose();
            disposed = true;
          } else {
            bootstrap.completeAt(
              1,
              _criticalBootstrap(episodeId: 'novel:49:100:5001'),
            );
            container.invalidate(provider);
            await container.read(provider.future);
            expect(container.read(provider.notifier), same(controller));
            await Future<void>.delayed(Duration.zero);
            fresh = container.read(provider).value!;
          }
          updates.complete(fail: fail);
          expect(await oldUpdate, isFalse);
          expect(
            bootstrap.contexts,
            hasLength(dispose ? 1 : 2),
            reason: 'A retired update must not start another bootstrap.',
          );
          if (!dispose) {
            expect(container.read(provider).value, same(fresh));
            expect(container.read(provider).hasError, isFalse);
          }
        },
      );
    }
  }

  for (final fail in [false, true]) {
    test(
      'active error-view update preserves its ${fail ? 'failure' : 'success'} result',
      () async {
        final bootstrap = _SequenceNovelReaderBootstrapService();
        bootstrap.failAt(0, StateError('initial chapter unavailable'));
        bootstrap.completeAt(
          1,
          _criticalBootstrap(episodeId: 'novel:49:100:5001'),
        );
        final updates = _GatedNovelChapterUpdateService();
        final container = _buildContainer(
          repository: _ControllerNovelRepository(),
          bootstrapService: bootstrap,
          chapterUpdateService: updates,
        );
        addTearDown(container.dispose);
        const args = NovelReaderArgs(
          novelId: 'novel:49:100',
          episodeId: 'novel:49:100:5001',
        );
        final provider = novelReaderControllerProvider(args);
        final subscription = _keepReaderAlive(container, args);
        addTearDown(subscription.close);
        await expectLater(container.read(provider.future), throwsStateError);
        final update = container.read(provider.notifier).updateWork();
        expect(container.read(provider).isLoading, isTrue);
        updates.complete(fail: fail);
        expect(await update, !fail);
        expect(bootstrap.contexts, hasLength(fail ? 1 : 2));
        if (fail) {
          expect(container.read(provider).error, isA<StateError>());
        } else {
          expect(
            container.read(provider).value!.currentEpisode.episodeId,
            'novel:49:100:5001',
          );
          expect(container.read(provider).hasError, isFalse);
        }
      },
    );
  }

  test(
    'NovelReaderController onScrollOffsetChanged schedules progress update',
    () async {
      final repository = _ControllerNovelRepository();
      final progressCommitter = _FakeNovelReaderProgressCommitter();
      final container = _buildContainer(
        repository: repository,
        progressCommitter: progressCommitter,
      );
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);

      await container.read(provider.future);
      await container
          .read(provider.notifier)
          .onScrollOffsetChanged(24, maxScrollExtent: 120);

      final state = container.read(provider).value!;
      expect(state.currentOffset, 24);
      expect(state.progressSnapshot.scrollOffset, 24);
      expect(progressCommitter.scheduleCallCount, 1);
      expect(progressCommitter.flushCallCount, 0);
      expect(repository.readingProgress, isNull);
    },
  );

  test(
    'NovelReaderController persists only the reported paged position',
    () async {
      final repository = _ControllerNovelRepository(
        preferences: NovelReaderPreferences.defaults().copyWith(
          flowMode: NovelReaderFlowMode.pagedLtr,
        ),
      );
      final progressCommitter = _FakeNovelReaderProgressCommitter();
      final container = _buildContainer(
        repository: repository,
        progressCommitter: progressCommitter,
      );
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);

      final provider = novelReaderControllerProvider(args);
      await container.read(provider.future);
      container
          .read(provider.notifier)
          .onPagedPositionChanged(
            const NovelReaderPaginationPosition(
              episodeId: 'novel:49:100:5001',
              paginationKey: 'layout-v1',
              pageIndex: 2,
              pageCount: 5,
              anchor: NovelReaderTextAnchor(
                episodeId: 'novel:49:100:5001',
                nodeId: 'node-2',
                textOffset: 14,
                formatVersion: 1,
                textIdentity: 'semantic-text-v1',
              ),
            ),
          );

      final state = container.read(provider).value!;
      expect(state.progressSnapshot.pageIndex, 2);
      expect(state.progressSnapshot.pageCount, 5);
      expect(state.progressSnapshot.paginationKey, 'layout-v1');
      expect(state.progressSnapshot.anchorNodeId, 'node-2');
      expect(state.progressSnapshot.anchorTextOffset, 14);
      expect(state.progressSnapshot.anchorFormatVersion, 1);
      expect(state.progressSnapshot.anchorTextIdentity, 'semantic-text-v1');
      expect(state.progressSnapshot.progressPercent, 0.4);
      expect(state.progressSnapshot.isProgressPercentValid, isTrue);
      expect(progressCommitter.scheduleCallCount, 1);
    },
  );

  test(
    'progress committer persists metadata-only changes and deduplicates repeats',
    () async {
      final repository = _ControllerNovelRepository();
      final committer = DefaultNovelReaderProgressCommitter(
        repository: repository,
      );
      addTearDown(committer.cancel);
      const baseline = NovelReaderProgressSnapshot(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
        flowMode: NovelReaderFlowMode.pagedLtr,
        scrollOffset: 0,
        pageIndex: 2,
        anchorNodeId: 'node-2',
        anchorTextOffset: 14,
        anchorFormatVersion: 37,
        anchorTextIdentity: '  unsupported identity  ',
        progressPercent: 0.4,
      );
      for (final changed in <NovelReaderProgressSnapshot>[
        baseline.copyWith(anchorFormatVersion: 1),
        baseline.copyWith(anchorTextIdentity: 'semantic-text-v1'),
        baseline.copyWith(isProgressPercentValid: false),
      ]) {
        await committer.flush(baseline);
        final savesBeforeChange = repository.savedProgressEpisodeIds.length;
        await committer.flush(changed);
        await committer.flush(changed.copyWith());

        expect(
          repository.savedProgressEpisodeIds.length,
          savesBeforeChange + 1,
        );
        expect(
          repository.readingProgress?.anchorFormatVersion,
          changed.anchorFormatVersion,
        );
        expect(
          repository.readingProgress?.anchorTextIdentity,
          changed.anchorTextIdentity,
        );
        expect(
          repository.readingProgress?.isProgressPercentValid,
          changed.isProgressPercentValid,
        );
      }
    },
  );

  for (final version in [0, 1, 37]) {
    test(
      'passive compatibility restore version $version preserves the row until user confirmation',
      () async {
        final original = NovelReadingProgress(
          novelId: 'novel:49:100',
          episodeId: 'novel:49:100:5001',
          scrollOffset: 0,
          updatedAt: DateTime(2026, 10, 4),
          flowMode: NovelReaderFlowMode.pagedLtr,
          pageIndex: 8,
          pageCount: 10,
          anchorNodeId: 'node-8',
          anchorTextOffset: 777,
          anchorFormatVersion: version,
          anchorTextIdentity: version == 0 ? null : '  old identity  ',
          paginationKey: 'old-layout',
          progressPercent: 0.8,
          isProgressPercentValid: true,
        );
        final repository = _ControllerNovelRepository(
          preferences: NovelReaderPreferences.defaults().copyWith(
            flowMode: NovelReaderFlowMode.pagedLtr,
          ),
          readingProgress: original,
        );
        final committer = DefaultNovelReaderProgressCommitter(
          repository: repository,
        );
        final container = _buildContainer(
          repository: repository,
          progressCommitter: committer,
        );
        addTearDown(container.dispose);
        const args = NovelReaderArgs(
          novelId: 'novel:49:100',
          episodeId: 'novel:49:100:5001',
        );
        final provider = novelReaderControllerProvider(args);
        final subscription = _keepReaderAlive(container, args);
        addTearDown(subscription.close);
        final loaded = await container.read(provider.future);
        final controller = container.read(provider.notifier);
        // Exit can precede the first surface report, so it is protected too.
        await controller.saveCurrentProgressNow(loaded.progressSnapshot);
        for (final isFinal in [false, true]) {
          controller.onPagedPositionChanged(
            NovelReaderPaginationPosition(
              episodeId: args.episodeId,
              paginationKey: 'new-layout',
              pageIndex: 1,
              pageCount: isFinal ? 5 : 2,
              isPageCountFinal: isFinal,
              isReadOnlyCompatibilityRestore: true,
              anchor: NovelReaderTextAnchor(
                episodeId: args.episodeId,
                nodeId: 'new-node',
                textOffset: 10,
                formatVersion: 1,
                textIdentity: 'new exact text',
              ),
            ),
          );
          final restored = container.read(provider).value!.progressSnapshot;
          expect(restored, loaded.progressSnapshot);
          await controller.saveCurrentProgressNow(restored);
        }
        expect(repository.savedProgressEpisodeIds, isEmpty);
        expect(repository.readingProgress, same(original));
        expect(container.read(provider).value!.readingProgress, same(original));

        controller.onPagedPositionChanged(
          NovelReaderPaginationPosition(
            episodeId: args.episodeId,
            paginationKey: 'new-layout',
            pageIndex: 2,
            pageCount: 5,
            anchor: NovelReaderTextAnchor(
              episodeId: args.episodeId,
              nodeId: 'new-node',
              textOffset: 20,
              formatVersion: 1,
              textIdentity: 'new exact text',
            ),
          ),
        );
        await controller.saveCurrentProgressNow(
          container.read(provider).value!.progressSnapshot,
        );
        expect(repository.savedProgressEpisodeIds, [args.episodeId]);
        expect(repository.readingProgress?.anchorFormatVersion, 1);
        expect(
          repository.readingProgress?.anchorTextIdentity,
          'new exact text',
        );
        expect(repository.readingProgress?.anchorTextOffset, 20);
        expect(repository.readingProgress?.progressPercent, 0.4);
      },
    );
  }

  test(
    'a new paged chapter saves its first visible position without a page turn',
    () async {
      final repository = _ControllerNovelRepository(
        preferences: NovelReaderPreferences.defaults().copyWith(
          flowMode: NovelReaderFlowMode.pagedLtr,
        ),
      );
      final committer = DefaultNovelReaderProgressCommitter(
        repository: repository,
      );
      final container = _buildContainer(
        repository: repository,
        progressCommitter: committer,
      );
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);
      final loaded = await container.read(provider.future);
      final controller = container.read(provider.notifier);
      await controller.saveCurrentProgressNow(loaded.progressSnapshot);
      expect(repository.savedProgressEpisodeIds, isEmpty);
      controller.onPagedPositionChanged(
        const NovelReaderPaginationPosition(
          episodeId: 'novel:49:100:5001',
          paginationKey: 'new-layout',
          pageIndex: 0,
          pageCount: 2,
          isReadOnlyCompatibilityRestore: true,
          anchor: NovelReaderTextAnchor(
            episodeId: 'novel:49:100:5001',
            nodeId: 'node-0',
            formatVersion: 1,
            textIdentity: 'first text',
          ),
        ),
      );
      await controller.saveCurrentProgressNow(
        container.read(provider).value!.progressSnapshot,
      );
      expect(repository.savedProgressEpisodeIds, [args.episodeId]);
      expect(repository.readingProgress?.anchorFormatVersion, 1);
      expect(repository.readingProgress?.pageIndex, 0);
    },
  );

  test(
    'explicit paged fromBeginning commits its first reported position',
    () async {
      final repository = _ControllerNovelRepository(
        preferences: NovelReaderPreferences.defaults().copyWith(
          flowMode: NovelReaderFlowMode.pagedLtr,
        ),
      );
      final committer = _FakeNovelReaderProgressCommitter();
      final container = _buildContainer(
        repository: repository,
        progressCommitter: committer,
      );
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
        openPolicy: NovelEpisodeOpenPolicy.startAtBeginning,
      );
      final provider = novelReaderControllerProvider(args);
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);
      await container.read(provider.future);
      container
          .read(provider.notifier)
          .onPagedPositionChanged(
            const NovelReaderPaginationPosition(
              episodeId: 'novel:49:100:5001',
              paginationKey: 'new-layout',
              pageIndex: 0,
              pageCount: 2,
              isReadOnlyCompatibilityRestore: true,
              anchor: NovelReaderTextAnchor(
                episodeId: 'novel:49:100:5001',
                nodeId: 'node-0',
                formatVersion: 1,
                textIdentity: 'first text',
              ),
            ),
          );
      await Future<void>.delayed(Duration.zero);
      expect(committer.flushCallCount, 1);
      expect(committer.latestFlushedSnapshot?.anchorFormatVersion, 1);
      expect(committer.latestFlushedSnapshot?.pageIndex, 0);
    },
  );

  test(
    'a newly reported partial position reopens without the previous valid percent',
    () async {
      final repository = _ControllerNovelRepository(
        preferences: NovelReaderPreferences.defaults().copyWith(
          flowMode: NovelReaderFlowMode.pagedLtr,
        ),
        readingProgress: NovelReadingProgress(
          novelId: 'novel:49:100',
          episodeId: 'novel:49:100:5001',
          scrollOffset: 0,
          updatedAt: DateTime(2026, 10, 4),
          flowMode: NovelReaderFlowMode.pagedLtr,
          pageIndex: 8,
          pageCount: 10,
          anchorNodeId: 'node-8',
          anchorFormatVersion: 1,
          anchorTextIdentity: 'semantic-text-v1',
          progressPercent: 0.8,
          isProgressPercentValid: true,
        ),
      );
      final committer = DefaultNovelReaderProgressCommitter(
        repository: repository,
      );
      final container = _buildContainer(
        repository: repository,
        progressCommitter: committer,
      );
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);
      final loaded = await container.read(provider.future);
      expect(loaded.progressSnapshot.progressPercent, 0.8);
      expect(loaded.progressSnapshot.isProgressPercentValid, isTrue);

      final controller = container.read(provider.notifier);
      controller.onPagedPositionChanged(
        const NovelReaderPaginationPosition(
          episodeId: 'novel:49:100:5001',
          paginationKey: 'layout-v1',
          pageIndex: 1,
          pageCount: 2,
          isPageCountFinal: false,
          anchor: NovelReaderTextAnchor(
            episodeId: 'novel:49:100:5001',
            nodeId: 'node-2',
            textOffset: 14,
            formatVersion: 1,
            textIdentity: 'semantic-text-v1',
          ),
        ),
      );
      final partial = container.read(provider).value!.progressSnapshot;
      expect(partial.progressPercent, 0);
      expect(partial.isProgressPercentValid, isFalse);
      expect(partial.pageCount, isNull);
      await controller.saveCurrentProgressNow(partial);
      expect(repository.readingProgress?.isProgressPercentValid, isFalse);
      expect(repository.readingProgress?.progressPercent, 0);

      final reopened = _buildContainer(repository: repository);
      addTearDown(reopened.dispose);
      final reopenedSubscription = _keepReaderAlive(reopened, args);
      addTearDown(reopenedSubscription.close);
      final restored = await reopened.read(provider.future);
      expect(restored.progressSnapshot.anchorFormatVersion, 1);
      expect(restored.progressSnapshot.anchorTextIdentity, 'semantic-text-v1');
      expect(restored.progressSnapshot.anchorTextOffset, 14);
      expect(restored.progressSnapshot.progressPercent, 0);
      expect(restored.progressSnapshot.isProgressPercentValid, isFalse);
      expect(restored.progressSnapshot.pageCount, isNull);
    },
  );

  test('NovelReaderController dispose cancels progress committer', () async {
    final repository = _ControllerNovelRepository();
    final progressCommitter = _FakeNovelReaderProgressCommitter();
    final container = _buildContainer(
      repository: repository,
      progressCommitter: progressCommitter,
    );
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final subscription = _keepReaderAlive(container, args);

    await container.read(novelReaderControllerProvider(args).future);
    subscription.close();
    container.dispose();

    expect(progressCommitter.cancelCallCount, 1);
  });

  test(
    'openEpisodeFromCatalog always starts the target chapter at the beginning',
    () async {
      final targetProgress = NovelReadingProgress(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5002',
        scrollOffset: 88,
        updatedAt: DateTime(2026, 6, 1),
      );
      final repository = _ControllerNovelRepository(
        readingProgress: targetProgress,
      );
      final container = _buildContainer(repository: repository);
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);

      final initial = await container.read(provider.future);
      expect(initial.currentEpisode.episodeId, 'novel:49:100:5001');
      expect(initial.currentOffset, 0);

      final controller = container.read(provider.notifier);
      await controller.saveCurrentOffsetNow(12);
      await controller.openEpisodeFromCatalog('novel:49:100:5002');

      final state = await container.read(provider.future);
      expect(state.currentEpisode.episodeId, 'novel:49:100:5002');
      expect(state.currentOffset, 0);
      expect(repository.savedProgressEpisodeIds, contains('novel:49:100:5001'));
    },
  );

  test(
    'chapter transition never inherits the source pagination page',
    () async {
      final repository = _ControllerNovelRepository(
        preferences: NovelReaderPreferences.defaults().copyWith(
          flowMode: NovelReaderFlowMode.pagedLtr,
        ),
      );
      final container = _buildContainer(repository: repository);
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);

      await container.read(provider.future);
      final controller = container.read(provider.notifier);
      controller.onPagedPositionChanged(
        const NovelReaderPaginationPosition(
          episodeId: 'novel:49:100:5001',
          paginationKey: 'source-layout',
          pageIndex: 4,
          pageCount: 6,
          anchor: NovelReaderTextAnchor(
            episodeId: 'novel:49:100:5001',
            nodeId: 'source-node',
          ),
        ),
      );
      await controller.saveCurrentProgressNow(
        container.read(provider).value!.progressSnapshot,
      );

      await controller.openEpisodeFromCatalog('novel:49:100:5002');
      final target = container.read(provider).value!;
      expect(target.currentEpisode.episodeId, 'novel:49:100:5002');
      expect(target.progressSnapshot.pageIndex, 0);
      expect(target.progressSnapshot.pageCount, isNull);
      expect(target.progressSnapshot.paginationKey, isNull);
      expect(target.progressSnapshot.anchorNodeId, isNull);
    },
  );

  test(
    'initial start policy ignores the matching persisted progress',
    () async {
      final repository = _ControllerNovelRepository(
        readingProgress: NovelReadingProgress(
          novelId: 'novel:49:100',
          episodeId: 'novel:49:100:5002',
          scrollOffset: 320,
          updatedAt: DateTime(2026, 7, 21),
          progressPercent: 0.75,
        ),
      );
      final progressCommitter = _FakeNovelReaderProgressCommitter();
      final container = _buildContainer(
        repository: repository,
        progressCommitter: progressCommitter,
      );
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5002',
        openPolicy: NovelEpisodeOpenPolicy.startAtBeginning,
      );
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);

      final state = await container.read(
        novelReaderControllerProvider(args).future,
      );

      expect(state.progressSnapshot.scrollOffset, 0);
      expect(state.progressSnapshot.progressPercent, 0);
      expect(progressCommitter.flushCallCount, 0);

      await container
          .read(novelReaderControllerProvider(args).notifier)
          .onVerticalContentReady('novel:49:100:5002');

      expect(progressCommitter.flushCallCount, 1);
      expect(
        progressCommitter.latestFlushedSnapshot?.episodeId,
        args.episodeId,
      );
      expect(progressCommitter.latestFlushedSnapshot?.progressPercent, 0);
    },
  );

  test(
    'initial build publishes critical state before supplemental completes',
    () async {
      final repository = _ControllerNovelRepository();
      final bootstrapService = _ControlledNovelReaderBootstrapService(
        initialCritical: _criticalBootstrap(episodeId: 'novel:49:100:5001'),
      );
      final hydrationService =
          _ControlledNovelReaderSupplementalHydrationService();
      final container = _buildContainer(
        repository: repository,
        bootstrapService: bootstrapService,
        supplementalHydrationService: hydrationService,
      );
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);

      final state = await container.read(provider.future);

      expect(state.currentEpisode.episodeId, 'novel:49:100:5001');
      expect(state.isHydratingSupplemental, isTrue);
      expect(state.novel, isNull);
      expect(state.bookmarks, isEmpty);

      hydrationService.completeInitialBookmarks(
        _supplementalBookmarks(episodeId: 'novel:49:100:5001'),
      );
      await Future<void>.delayed(Duration.zero);
      var hydrated = container.read(provider).value!;
      expect(hydrated.bookmarks, isNotEmpty);
      expect(hydrated.currentEpisodeBookmarks, isNotEmpty);
      expect(hydrated.novel, isNull);

      hydrationService.completeInitialNovel(_supplementalNovel());
      await Future<void>.delayed(Duration.zero);

      hydrated = container.read(provider).value!;
      expect(hydrated.isHydratingSupplemental, isFalse);
      expect(hydrated.novel?.title, '测试小说');
    },
  );

  test(
    'openEpisodeFromCatalog keeps old content and sets switching transition before critical resolves',
    () async {
      final repository = _ControllerNovelRepository();
      final bootstrapService = _ControlledNovelReaderBootstrapService(
        initialCritical: _criticalBootstrap(episodeId: 'novel:49:100:5001'),
      );
      final hydrationService =
          _ControlledNovelReaderSupplementalHydrationService();
      final container = _buildContainer(
        repository: repository,
        bootstrapService: bootstrapService,
        supplementalHydrationService: hydrationService,
      );
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);

      await container.read(provider.future);
      hydrationService.completeInitialBookmarks(
        _supplementalBookmarks(episodeId: 'novel:49:100:5001'),
      );
      hydrationService.completeInitialNovel(_supplementalNovel());
      await Future<void>.delayed(Duration.zero);

      final future = container
          .read(provider.notifier)
          .openEpisodeFromCatalog('novel:49:100:5002');
      final transitioning = container.read(provider).value!;

      expect(container.read(provider).isLoading, isFalse);
      expect(transitioning.currentEpisode.episodeId, 'novel:49:100:5001');
      expect(
        transitioning.transition?.kind,
        NovelReaderTransitionKind.switchingEpisode,
      );
      expect(transitioning.transition?.targetEpisodeId, 'novel:49:100:5002');

      bootstrapService.completeEpisodeCritical(
        'novel:49:100:5002',
        _criticalBootstrap(
          episodeId: 'novel:49:100:5002',
          paragraphText: '第二章正文。',
        ),
      );
      final didSucceed = await future;

      expect(didSucceed, isTrue);
      final switched = container.read(provider).value!;
      expect(switched.currentEpisode.episodeId, 'novel:49:100:5002');
      expect(switched.transition, isNull);
      expect(switched.searchKeyword, isEmpty);
      expect(switched.searchResults, isEmpty);
      expect(switched.currentSearchIndex, -1);
      expect(switched.isHydratingSupplemental, isTrue);
    },
  );

  test(
    'openEpisodeFromCatalog failure keeps old chapter and clears transition',
    () async {
      final repository = _ControllerNovelRepository();
      final bootstrapService = _ControlledNovelReaderBootstrapService(
        initialCritical: _criticalBootstrap(episodeId: 'novel:49:100:5001'),
      );
      bootstrapService.failEpisodeCritical(
        'novel:49:100:5002',
        StateError('critical failed'),
      );
      final container = _buildContainer(
        repository: repository,
        bootstrapService: bootstrapService,
      );
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);

      await container.read(provider.future);

      final didSucceed = await container
          .read(provider.notifier)
          .openEpisodeFromCatalog('novel:49:100:5002');

      expect(didSucceed, isFalse);
      final state = container.read(provider).value!;
      expect(state.currentEpisode.episodeId, 'novel:49:100:5001');
      expect(state.transition, isNull);
    },
  );

  test('stale supplemental does not override newer chapter state', () async {
    final repository = _ControllerNovelRepository();
    final bootstrapService = _ControlledNovelReaderBootstrapService(
      initialCritical: _criticalBootstrap(episodeId: 'novel:49:100:5001'),
    );
    final hydrationService =
        _ControlledNovelReaderSupplementalHydrationService();
    final container = _buildContainer(
      repository: repository,
      bootstrapService: bootstrapService,
      supplementalHydrationService: hydrationService,
    );
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    await container.read(provider.future);

    final switchFuture = container
        .read(provider.notifier)
        .openEpisodeFromCatalog('novel:49:100:5002');
    bootstrapService.completeEpisodeCritical(
      'novel:49:100:5002',
      _criticalBootstrap(
        episodeId: 'novel:49:100:5002',
        paragraphText: '第二章正文。',
      ),
    );
    await switchFuture;

    hydrationService.completeInitialBookmarks(
      _supplementalBookmarks(episodeId: 'novel:49:100:5001'),
    );
    hydrationService.completeInitialNovel(
      _supplementalNovel(novelTitle: '旧章节小说'),
    );
    await Future<void>.delayed(Duration.zero);

    final state = container.read(provider).value!;
    expect(state.currentEpisode.episodeId, 'novel:49:100:5002');
    expect(state.novel, isNull);
  });

  test('supplemental phase failure does not block later phases', () async {
    final repository = _ControllerNovelRepository();
    final bootstrapService = _ControlledNovelReaderBootstrapService(
      initialCritical: _criticalBootstrap(episodeId: 'novel:49:100:5001'),
    );
    final hydrationService =
        _ControlledNovelReaderSupplementalHydrationService();
    hydrationService.failInitialBookmarks(StateError('bookmark failed'));
    final container = _buildContainer(
      repository: repository,
      bootstrapService: bootstrapService,
      supplementalHydrationService: hydrationService,
    );
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    await container.read(provider.future);
    hydrationService.completeInitialNovel(_supplementalNovel());
    await Future<void>.delayed(Duration.zero);

    final state = container.read(provider).value!;
    expect(state.bookmarks, isEmpty);
    expect(state.novel?.title, '测试小说');
    expect(state.isHydratingSupplemental, isFalse);
  });

  test('updateWork failure keeps old content and avoids AsyncError', () async {
    final repository = _ControllerNovelRepository();
    final updateService = _RecordingNovelChapterUpdateService();
    final bootstrapService = _ControlledNovelReaderBootstrapService(
      initialCritical: _criticalBootstrap(episodeId: 'novel:49:100:5001'),
    );
    bootstrapService.failEpisodeCritical(
      'novel:49:100:5001',
      StateError('refresh failed'),
    );
    final container = _buildContainer(
      repository: repository,
      bootstrapService: bootstrapService,
      chapterUpdateService: updateService,
    );
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    await container.read(provider.future);

    final didSucceed = await container.read(provider.notifier).updateWork();

    expect(didSucceed, isFalse);
    expect(updateService.novelIds, <String>['novel:49:100']);
    expect(container.read(provider).hasError, isFalse);
    final state = container.read(provider).value!;
    expect(state.currentEpisode.episodeId, 'novel:49:100:5001');
    expect(state.transition, isNull);
  });

  test('searchInCurrentChapter updates search results and selection', () async {
    final repository = _ControllerNovelRepository();
    repository.contentsByEpisodeId['novel:49:100:5001'] = _content(
      'novel:49:100:5001',
      '关键词在这里。关键词再次出现。',
    );
    final container = _buildContainer(repository: repository);
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    await container.read(provider.future);
    container.read(provider.notifier).searchInCurrentChapter('关键词');
    final state = container.read(provider).value!;

    expect(state.searchResults, hasLength(2));
    expect(state.currentSearchIndex, 0);
    container
        .read(provider.notifier)
        .selectSearchResult(state.searchResults.last.resultId);
    expect(container.read(provider).value!.currentSearchIndex, 1);
  });

  test('bookmark actions persist and reload state', () async {
    final repository = _ControllerNovelRepository();
    final container = _buildContainer(repository: repository);
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    await container.read(provider.future);
    await container.read(provider.notifier).toggleCurrentEpisodeBookmark();
    expect(container.read(provider).value!.hasCurrentEpisodeBookmark, isTrue);

    await container
        .read(provider.notifier)
        .addBookmarkAtCurrentPosition(
          const NovelReaderTextAnchor(
            episodeId: 'novel:49:100:5001',
            nodeId: 'node-0',
          ),
        );
    var state = container.read(provider).value!;
    expect(state.currentEpisodeBookmarks.length, 2);

    final positionBookmark = state.currentEpisodeBookmarks.firstWhere(
      (bookmark) => bookmark.bookmarkId.startsWith('reader-bookmark:'),
    );
    await container
        .read(provider.notifier)
        .removeBookmark(positionBookmark.bookmarkId);
    state = container.read(provider).value!;
    expect(state.currentEpisodeBookmarks.length, 1);
  });

  test(
    'bookmark snippets use exact rune coordinates and preserve whole graphemes',
    () async {
      const family = '👩‍👩‍👧‍👦';
      final repository = _ControllerNovelRepository();
      repository.contentsByEpisodeId['novel:49:100:5001'] = _content(
        'novel:49:100:5001',
        '  😀前文$family'
            '后文${'正文' * 30}',
      );
      final container = _buildContainer(repository: repository);
      addTearDown(container.dispose);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      final subscription = _keepReaderAlive(container, args);
      addTearDown(subscription.close);
      final loaded = await container.read(provider.future);
      final block = loaded.document.blocks.first;
      final text = block.novelPlainText;
      final familyStart = text.indexOf(family);
      expect(familyStart, greaterThanOrEqualTo(0));
      final anchor = NovelReaderTextAnchor(
        episodeId: args.episodeId,
        nodeId: block.anchorId,
        textOffset: text.substring(0, familyStart).runes.length + 2,
        formatVersion: 1,
        textIdentity: NovelReaderAnchorFormat.textIdentity(text),
      );
      final controller = container.read(provider.notifier);
      void expectPreservedAnchor(NovelReaderTextAnchor expected) {
        final actual = repository.bookmarks.last.anchor;
        expect(actual.episodeId, expected.episodeId);
        expect(actual.nodeId, expected.nodeId);
        expect(actual.textOffset, expected.textOffset);
        expect(actual.formatVersion, expected.formatVersion);
        expect(actual.textIdentity, expected.textIdentity);
        expect(actual.pageIndex, expected.pageIndex);
        expect(actual.scrollOffset, expected.scrollOffset);
        expect(actual.progressPercent, expected.progressPercent);
        expect(actual.isProgressPercentValid, expected.isProgressPercentValid);
      }

      await controller.addBookmarkAtCurrentPosition(anchor);
      expect(repository.bookmarks.last.snippet, contains(family));
      expect(repository.bookmarks.last.snippet, isNot(contains('😀前文')));
      expectPreservedAnchor(anchor);
      for (final unknown in [
        anchor.copyWith(formatVersion: 37),
        anchor.copyWith(textIdentity: 'different source text'),
      ]) {
        await controller.addBookmarkAtCurrentPosition(unknown);
        expect(repository.bookmarks.last.snippet, startsWith('😀前文'));
        expectPreservedAnchor(unknown);
      }
    },
  );
}

ProviderSubscription<AsyncValue<NovelReaderViewState>> _keepReaderAlive(
  ProviderContainer container,
  NovelReaderArgs args,
) {
  return container.listen<AsyncValue<NovelReaderViewState>>(
    novelReaderControllerProvider(args),
    (_, _) {},
  );
}

ProviderContainer _buildContainer({
  required _ControllerNovelRepository repository,
  NovelReaderPreferencesRepository? preferencesRepository,
  LibraryStateRepository? stateRepository,
  NovelReaderBootstrapService? bootstrapService,
  NovelReaderSupplementalHydrationService? supplementalHydrationService,
  NovelReaderDocumentBuildService? documentBuildService,
  NovelReaderProgressCommitter? progressCommitter,
  NovelChapterUpdateService? chapterUpdateService,
}) {
  return ProviderContainer(
    overrides: [
      novelRepositoryProvider.overrideWithValue(repository),
      novelReaderPreferencesRepositoryProvider.overrideWithValue(
        preferencesRepository ??
            _ControllerNovelReaderPreferencesRepository(repository),
      ),
      novelChapterUpdateServiceProvider.overrideWithValue(
        chapterUpdateService ?? _RecordingNovelChapterUpdateService(),
      ),
      libraryStateRepositoryProvider.overrideWithValue(
        stateRepository ?? _MemoryLibraryStateRepository(),
      ),
      if (bootstrapService != null)
        novelReaderBootstrapServiceProvider.overrideWithValue(bootstrapService),
      if (supplementalHydrationService != null)
        novelReaderSupplementalHydrationServiceProvider.overrideWithValue(
          supplementalHydrationService,
        ),
      if (documentBuildService != null)
        novelReaderDocumentBuildServiceProvider.overrideWithValue(
          documentBuildService,
        ),
      if (progressCommitter != null)
        novelReaderProgressCommitterProvider.overrideWithValue(
          progressCommitter,
        ),
    ],
  );
}

class _RecordingNovelChapterUpdateService implements NovelChapterUpdateService {
  final List<String> novelIds = <String>[];

  @override
  Future<NovelChapterSyncResult> update(
    String novelId, {
    NovelChapterUpdateIntent intent = NovelChapterUpdateIntent.normal,
  }) async {
    novelIds.add(novelId);
    return NovelChapterSyncResult(
      mode: NovelChapterSyncMode.incremental,
      fetchedPages: 1,
      insertedCount: 0,
      updatedCount: 1,
      totalCount: 2,
      checkpoint: NovelChapterSyncCheckpoint(
        novelId: novelId,
        publisherId: '406769',
        lastCompletedAuthorPage: 1,
        lastSeenPid: '5002',
        completedAt: DateTime(2026, 7, 14),
      ),
    );
  }
}

NovelReaderViewState _viewState({
  required List<NovelEpisodeItem> episodes,
  required NovelEpisodeItem currentEpisode,
}) {
  return NovelReaderViewState(
    novel: null,
    episodes: episodes,
    currentEpisode: currentEpisode,
    currentContent: _content(currentEpisode.episodeId, '正文。'),
    document: _document(currentEpisode.episodeId),
    persistedPreferences: NovelReaderPreferences.defaults(),
    effectivePreferences: NovelReaderPreferences.defaults(),
    readingProgress: null,
    progressSnapshot: const NovelReaderProgressSnapshot(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
      flowMode: NovelReaderFlowMode.vertical,
      scrollOffset: 0,
      pageIndex: 0,
      progressPercent: 0,
    ),
    currentOffset: 0,
  );
}

class _MemoryLibraryStateRepository implements LibraryStateRepository {
  final Map<String, LibraryEpisodeState> _episodeStates =
      <String, LibraryEpisodeState>{};

  @override
  Future<void> upsertEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
    required String workId,
    bool? isRead,
    bool? isDownloaded,
    bool? isBookmarked,
    DateTime? readAt,
    DateTime? downloadedAt,
  }) async {
    final old = _episodeStates[episodeId];
    _episodeStates[episodeId] = LibraryEpisodeState(
      moduleKey: moduleKey,
      episodeId: episodeId,
      workId: workId,
      isRead: isRead ?? old?.isRead ?? false,
      isDownloaded: isDownloaded ?? old?.isDownloaded ?? false,
      isBookmarked: isBookmarked ?? old?.isBookmarked ?? false,
      readAt: isRead == false ? null : readAt ?? old?.readAt,
      downloadedAt: isDownloaded == false
          ? null
          : downloadedAt ?? old?.downloadedAt,
    );
  }

  @override
  Future<LibraryEpisodeState?> getEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
  }) async {
    final state = _episodeStates[episodeId];
    return state?.moduleKey == moduleKey ? state : null;
  }

  @override
  Future<void> upsertWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
    String? lastReadEpisodeId,
    DateTime? lastReadAt,
    DateTime? checkUpdatedAt,
    DateTime? fetchedUpdatedAt,
    String? introText,
  }) async {}

  @override
  Future<LibraryWorkState?> getWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return null;
  }

  @override
  Future<int> countUnreadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return 0;
  }

  @override
  Future<int> countReadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return 0;
  }

  @override
  Future<int> countDownloadedEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return _episodeStates.values
        .where(
          (state) =>
              state.moduleKey == moduleKey &&
              state.workId == workId &&
              state.isDownloaded,
        )
        .length;
  }

  @override
  Future<void> setWorksReadState({
    required LibraryModuleKey moduleKey,
    required Set<String> workIds,
    required bool isRead,
    DateTime? readAt,
  }) async {}

  @override
  Future<void> purgeWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    _episodeStates.removeWhere(
      (_, state) => state.moduleKey == moduleKey && state.workId == workId,
    );
  }

  @override
  Future<void> upsertDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode displayMode,
    required int gridColumns,
  }) async {}

  @override
  Future<LibraryModuleDisplaySettings> getDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode defaultDisplayMode,
  }) async {
    return LibraryModuleDisplaySettings(
      moduleKey: moduleKey,
      displayMode: defaultDisplayMode,
      gridColumns: 3,
      updatedAt: DateTime(2026, 6, 8),
    );
  }

  @override
  Future<String> createTag({required String name}) async => 'tag';

  @override
  Future<List<LibraryTag>> getTags() async => const <LibraryTag>[];

  @override
  Future<void> renameTag({
    required String tagId,
    required String newName,
  }) async {}

  @override
  Future<void> deleteTag({required String tagId}) async {}

  @override
  Future<void> bindTagToWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<void> unbindTagFromWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<List<LibraryTag>> getWorkTags({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return const <LibraryTag>[];
  }

  @override
  Future<bool> hasAnyTag({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return false;
  }
}

class _ControllerNovelRepository implements NovelRepository {
  _ControllerNovelRepository({
    this.readingProgress,
    NovelReaderPreferences? preferences,
  }) : preferences =
           preferences ??
           NovelReaderPreferences.defaults().copyWith(
             flowMode: NovelReaderFlowMode.vertical,
           ) {
    contentsByEpisodeId = <String, NovelChapterContent>{
      for (final episode in episodes)
        episode.episodeId: _content(
          episode.episodeId,
          '${episode.episodeTitle}正文。',
        ),
    };
  }

  final episodes = _episodes();
  late final Map<String, NovelChapterContent> contentsByEpisodeId;
  NovelReadingProgress? readingProgress;
  NovelReaderPreferences preferences;
  NovelReaderPreferences? latestPreferences;
  int upsertPreferencesCallCount = 0;
  final savedProgressEpisodeIds = <String>[];
  final bookmarks = <NovelReaderBookmark>[];

  @override
  Future<String> createCategory({required String name}) async => 'default';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<NovelShelfCategory>> getCategories() async {
    return const <NovelShelfCategory>[];
  }

  @override
  Future<NovelChapterContent?> getChapterContent({
    required String episodeId,
  }) async {
    return contentsByEpisodeId[episodeId];
  }

  @override
  Future<NovelItem?> getDetail({required String novelId}) async {
    return NovelItem(
      novelId: novelId,
      sourceTid: '100',
      sourceFid: '49',
      title: '测试小说',
      updatedAt: DateTime(2026, 1, 1),
      episodeCount: episodes.length,
    );
  }

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async {
    return descending ? episodes.reversed.toList(growable: false) : episodes;
  }

  @override
  Future<NovelReadingProgress?> getReadingProgress({
    required String novelId,
  }) async {
    return readingProgress;
  }

  @override
  Future<List<NovelItem>> getShelfItems({String categoryId = 'default'}) async {
    return const <NovelItem>[];
  }

  @override
  Future<void> moveNovelToCategory({
    required String novelId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<void> purgeWork({required String novelId}) async {}

  @override
  Future<void> removeFromShelf({required String novelId}) async {}

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {}

  @override
  Future<void> saveReadingProgress({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
    NovelReaderFlowMode flowMode = NovelReaderFlowMode.vertical,
    int pageIndex = 0,
    int? pageCount,
    String? anchorNodeId,
    int anchorTextOffset = 0,
    int anchorFormatVersion = 0,
    String? anchorTextIdentity,
    String? paginationKey,
    double progressPercent = 0,
    bool? isProgressPercentValid,
  }) async {
    savedProgressEpisodeIds.add(episodeId);
    readingProgress = NovelReadingProgress(
      novelId: novelId,
      episodeId: episodeId,
      scrollOffset: scrollOffset,
      updatedAt: DateTime(2026, 6, 8),
      flowMode: flowMode,
      pageIndex: pageIndex,
      pageCount: pageCount,
      anchorNodeId: anchorNodeId,
      anchorTextOffset: anchorTextOffset,
      anchorFormatVersion: anchorFormatVersion,
      anchorTextIdentity: anchorTextIdentity,
      paginationKey: paginationKey,
      progressPercent: progressPercent,
      isProgressPercentValid: isProgressPercentValid,
    );
  }

  @override
  Future<void> addReaderBookmark({
    required NovelReaderBookmark bookmark,
  }) async {
    bookmarks.removeWhere((item) => item.bookmarkId == bookmark.bookmarkId);
    bookmarks.add(bookmark);
  }

  @override
  Future<List<NovelReaderBookmark>> listReaderBookmarks({
    required String novelId,
  }) async {
    return bookmarks.where((bookmark) => bookmark.novelId == novelId).toList();
  }

  @override
  Future<void> removeReaderBookmark({required String bookmarkId}) async {
    bookmarks.removeWhere((bookmark) => bookmark.bookmarkId == bookmarkId);
  }

  @override
  Future<void> toggleEpisodeBookmark({
    required String novelId,
    required String episodeId,
    required bool isBookmarked,
  }) async {
    bookmarks.removeWhere(
      (bookmark) => bookmark.bookmarkId == 'episode-bookmark:$episodeId',
    );
    if (isBookmarked) {
      bookmarks.add(
        NovelReaderBookmark(
          bookmarkId: 'episode-bookmark:$episodeId',
          novelId: novelId,
          episodeId: episodeId,
          anchor: NovelReaderTextAnchor(episodeId: episodeId),
          title: episodeId,
          snippet: '章节书签',
          createdAt: DateTime(2026, 6, 8),
          updatedAt: DateTime(2026, 6, 8),
        ),
      );
    }
  }
}

class _ControllerNovelReaderPreferencesRepository
    implements NovelReaderPreferencesRepository {
  const _ControllerNovelReaderPreferencesRepository(this.repository);

  final _ControllerNovelRepository repository;

  @override
  Future<NovelReaderPreferences> load() async => repository.preferences;

  @override
  Future<void> save(NovelReaderPreferences preferences) async {
    repository.upsertPreferencesCallCount += 1;
    repository.latestPreferences = preferences;
    repository.preferences = preferences;
  }
}

class _DelayedPreferencesRepository
    implements NovelReaderPreferencesRepository {
  _DelayedPreferencesRepository(this.repository);

  final _ControllerNovelRepository repository;
  final saveGate = Completer<void>();

  @override
  Future<NovelReaderPreferences> load() async => repository.preferences;

  @override
  Future<void> save(NovelReaderPreferences preferences) async {
    repository.upsertPreferencesCallCount += 1;
    await saveGate.future;
    repository.latestPreferences = preferences;
    repository.preferences = preferences;
  }
}

class _SequenceNovelReaderBootstrapService
    implements NovelReaderBootstrapService {
  final contexts = <NovelReaderLoadContext>[];
  final _sequence = _HydrationSequence<NovelReaderCriticalBootstrap>();

  @override
  Future<NovelReaderCriticalBootstrap> loadCritical(
    NovelReaderLoadContext context,
  ) {
    contexts.add(context);
    return _sequence.take();
  }

  void completeAt(int index, NovelReaderCriticalBootstrap value) {
    _sequence.completeAt(index, value);
  }

  void failAt(int index, Object error) {
    _sequence.completeErrorAt(index, error);
  }
}

class _ControlledNovelReaderBootstrapService
    implements NovelReaderBootstrapService {
  _ControlledNovelReaderBootstrapService({
    required NovelReaderCriticalBootstrap initialCritical,
  }) : _initialCritical = initialCritical;

  final NovelReaderCriticalBootstrap _initialCritical;
  bool _hasServedInitialCritical = false;
  final Map<String, Completer<NovelReaderCriticalBootstrap>>
  _criticalCompleters = <String, Completer<NovelReaderCriticalBootstrap>>{};
  final Map<String, Object> _criticalFailures = <String, Object>{};

  @override
  Future<NovelReaderCriticalBootstrap> loadCritical(
    NovelReaderLoadContext context,
  ) {
    if (!_hasServedInitialCritical &&
        context.requestedEpisodeId ==
            _initialCritical.currentEpisode.episodeId) {
      _hasServedInitialCritical = true;
      return Future<NovelReaderCriticalBootstrap>.value(_initialCritical);
    }
    final failure = _criticalFailures[context.requestedEpisodeId];
    if (failure != null) {
      return Future<NovelReaderCriticalBootstrap>.error(failure);
    }
    final completer = _criticalCompleters.putIfAbsent(
      context.requestedEpisodeId,
      Completer<NovelReaderCriticalBootstrap>.new,
    );
    return completer.future;
  }

  void completeEpisodeCritical(
    String episodeId,
    NovelReaderCriticalBootstrap value,
  ) {
    _criticalCompleters.putIfAbsent(
      episodeId,
      Completer<NovelReaderCriticalBootstrap>.new,
    );
    final completer = _criticalCompleters[episodeId]!;
    if (!completer.isCompleted) {
      completer.complete(value);
    }
  }

  void failEpisodeCritical(String episodeId, Object error) {
    _criticalFailures[episodeId] = error;
  }
}

List<NovelEpisodeItem> _episodes() {
  return const <NovelEpisodeItem>[
    NovelEpisodeItem(
      episodeId: 'novel:49:100:5001',
      novelId: 'novel:49:100',
      sourceTid: '100',
      sourcePid: '5001',
      sourcePage: 1,
      episodeTitle: '第1章',
      orderIndex: 0,
      datelineText: '2026-05-03',
    ),
    NovelEpisodeItem(
      episodeId: 'novel:49:100:5002',
      novelId: 'novel:49:100',
      sourceTid: '100',
      sourcePid: '5002',
      sourcePage: 1,
      episodeTitle: '第2章',
      orderIndex: 1,
      datelineText: '2026-05-04',
    ),
    NovelEpisodeItem(
      episodeId: 'novel:49:100:5003',
      novelId: 'novel:49:100',
      sourceTid: '100',
      sourcePid: '5003',
      sourcePage: 1,
      episodeTitle: '第3章',
      orderIndex: 2,
      datelineText: '2026-05-05',
    ),
  ];
}

NovelChapterContent _content(String episodeId, String text) {
  return NovelChapterContent(
    episodeId: episodeId,
    rawHtml: '<p>$text</p>',
    plainText: text,
    paragraphs: <String>[text],
  );
}

NovelReaderDocument _document(String episodeId) {
  return NovelReaderDocument(
    episodeId: episodeId,
    rawHtmlHash: 'test',
    body: const RichDocument(
      blocks: <RichBlock>[
        RichTextBlock(
          anchorId: 'node-0',
          runs: <RichRun>[RichRun(text: '正文。')],
        ),
      ],
    ),
    plainText: '正文。',
    wordCount: 3,
  );
}

NovelReaderCriticalBootstrap _criticalBootstrap({
  required String episodeId,
  String paragraphText = '正文。',
  NovelReaderPreferences? preferences,
  NovelReadingProgress? readingProgress,
}) {
  final resolvedPreferences = preferences ?? NovelReaderPreferences.defaults();
  final progress = const NovelReaderProgressPolicy().fromReadingProgress(
    novelId: 'novel:49:100',
    episodeId: episodeId,
    flowMode: resolvedPreferences.flowMode,
    progress: readingProgress,
  );
  final episode = _episodes().firstWhere((item) => item.episodeId == episodeId);
  return NovelReaderCriticalBootstrap(
    episodes: _episodes(),
    currentEpisode: episode,
    currentContent: _content(episodeId, paragraphText),
    document: NovelReaderDocument(
      episodeId: episodeId,
      rawHtmlHash: 'test-$episodeId',
      body: RichDocument(
        blocks: <RichBlock>[
          RichTextBlock(
            anchorId: 'node-0',
            runs: <RichRun>[RichRun(text: paragraphText)],
          ),
        ],
      ),
      plainText: paragraphText,
      wordCount: paragraphText.length,
    ),
    persistedPreferences: resolvedPreferences,
    effectivePreferences: resolvedPreferences,
    readingProgress: readingProgress,
    progressSnapshot: progress,
    currentOffset: progress.scrollOffset,
  );
}

List<NovelReaderBookmark> _supplementalBookmarks({required String episodeId}) {
  return <NovelReaderBookmark>[
    NovelReaderBookmark(
      bookmarkId: 'episode-bookmark:$episodeId',
      novelId: 'novel:49:100',
      episodeId: episodeId,
      anchor: NovelReaderTextAnchor(episodeId: episodeId),
      title: '章节书签',
      snippet: '章节书签',
      createdAt: DateTime(2026, 6, 8),
      updatedAt: DateTime(2026, 6, 8),
    ),
  ];
}

NovelItem _supplementalNovel({String novelTitle = '测试小说'}) {
  return NovelItem(
    novelId: 'novel:49:100',
    sourceTid: '100',
    sourceFid: '49',
    title: novelTitle,
    updatedAt: DateTime(2026, 1, 1),
    episodeCount: _episodes().length,
  );
}

class _ControlledNovelReaderSupplementalHydrationService
    implements NovelReaderSupplementalHydrationService {
  final _HydrationSequence<List<NovelReaderBookmark>> _bookmarkSequence =
      _HydrationSequence<List<NovelReaderBookmark>>();
  final _HydrationSequence<NovelItem?> _novelSequence =
      _HydrationSequence<NovelItem?>();

  @override
  Future<List<NovelReaderBookmark>> loadBookmarks({required String novelId}) {
    return _bookmarkSequence.take();
  }

  @override
  Future<NovelItem?> loadNovel({required String novelId}) {
    return _novelSequence.take();
  }

  void completeInitialBookmarks(List<NovelReaderBookmark> value) {
    _bookmarkSequence.completeAt(0, value);
  }

  void failInitialBookmarks(Object error) {
    _bookmarkSequence.completeErrorAt(0, error);
  }

  void completeInitialNovel(NovelItem? value) {
    _novelSequence.completeAt(0, value);
  }
}

class _FakeNovelReaderProgressCommitter
    implements NovelReaderProgressCommitter {
  int scheduleCallCount = 0;
  int flushCallCount = 0;
  int cancelCallCount = 0;
  NovelReaderProgressSnapshot? latestScheduledSnapshot;
  NovelReaderProgressSnapshot? latestFlushedSnapshot;

  @override
  void cancel() {
    cancelCallCount += 1;
  }

  @override
  Future<void> flush(NovelReaderProgressSnapshot snapshot) async {
    flushCallCount += 1;
    latestFlushedSnapshot = snapshot;
  }

  @override
  void schedule(NovelReaderProgressSnapshot snapshot) {
    scheduleCallCount += 1;
    latestScheduledSnapshot = snapshot;
  }
}

class _GatedProgressCommitter extends _FakeNovelReaderProgressCommitter {
  _GatedProgressCommitter(this.repository);

  final _ControllerNovelRepository repository;
  final gate = Completer<void>();
  final committed = <NovelReaderProgressSnapshot>[];

  @override
  Future<void> flush(NovelReaderProgressSnapshot snapshot) async {
    flushCallCount += 1;
    latestFlushedSnapshot = snapshot;
    await gate.future;
    await repository.saveReadingProgress(
      novelId: snapshot.novelId,
      episodeId: snapshot.episodeId,
      scrollOffset: snapshot.scrollOffset,
      flowMode: snapshot.flowMode,
      pageIndex: snapshot.pageIndex,
      pageCount: snapshot.pageCount,
      anchorNodeId: snapshot.anchorNodeId,
      anchorTextOffset: snapshot.anchorTextOffset,
      anchorFormatVersion: snapshot.anchorFormatVersion,
      anchorTextIdentity: snapshot.anchorTextIdentity,
      paginationKey: snapshot.paginationKey,
      progressPercent: snapshot.progressPercent,
      isProgressPercentValid: snapshot.isProgressPercentValid,
    );
    committed.add(snapshot);
  }
}

class _GatedNovelChapterUpdateService
    extends _RecordingNovelChapterUpdateService {
  final gate = Completer<void>();
  int started = 0;

  @override
  Future<NovelChapterSyncResult> update(
    String novelId, {
    NovelChapterUpdateIntent intent = NovelChapterUpdateIntent.normal,
  }) async {
    started += 1;
    await gate.future;
    return super.update(novelId, intent: intent);
  }

  void complete({required bool fail}) {
    if (fail) {
      gate.completeError(StateError('controlled work update failure'));
    } else {
      gate.complete();
    }
  }
}

class _HydrationSequence<T> {
  final List<_PendingHydrationOutcome<T>?> _pendingOutcomes =
      <_PendingHydrationOutcome<T>?>[];
  final List<Completer<T>?> _completers = <Completer<T>?>[];
  int _nextTakeIndex = 0;

  Future<T> take() {
    final index = _nextTakeIndex++;
    _ensureIndex(index);
    final pendingOutcome = _pendingOutcomes[index];
    if (pendingOutcome != null) {
      return pendingOutcome.toFuture();
    }
    final completer = Completer<T>();
    _completers[index] = completer;
    return completer.future;
  }

  void completeAt(int index, T value) {
    _ensureIndex(index);
    final completer = _completers[index];
    if (completer != null && !completer.isCompleted) {
      completer.complete(value);
      return;
    }
    _pendingOutcomes[index] = _PendingHydrationValue<T>(value);
  }

  void completeErrorAt(int index, Object error) {
    _ensureIndex(index);
    final completer = _completers[index];
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
      return;
    }
    _pendingOutcomes[index] = _PendingHydrationError<T>(error);
  }

  void _ensureIndex(int index) {
    while (_pendingOutcomes.length <= index) {
      _pendingOutcomes.add(null);
      _completers.add(null);
    }
  }
}

abstract class _PendingHydrationOutcome<T> {
  Future<T> toFuture();
}

class _PendingHydrationValue<T> implements _PendingHydrationOutcome<T> {
  _PendingHydrationValue(this.value);

  final T value;

  @override
  Future<T> toFuture() {
    return Future<T>.value(value);
  }
}

class _PendingHydrationError<T> implements _PendingHydrationOutcome<T> {
  _PendingHydrationError(this.error);

  final Object error;

  @override
  Future<T> toFuture() {
    return Future<T>.error(error);
  }
}
