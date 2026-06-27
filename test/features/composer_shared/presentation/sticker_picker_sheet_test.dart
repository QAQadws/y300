import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/cache/domain/image_cache_keys.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/composer_shared/data/composer_providers.dart';
import 'package:y300/features/composer_shared/data/sticker_picker_preferences_repository.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/widgets/sticker_picker_sheet.dart';

void main() {
  testWidgets('StickerPickerSheet shows loading state', (tester) async {
    final completer = Completer<List<StickerGroup>>();
    await tester.pumpWidget(_buildSheet(loadGroups: () => completer.future));

    expect(
      find.byKey(const Key('reply-sticker-picker-loading')),
      findsOneWidget,
    );
  });

  testWidgets('StickerPickerSheet shows error state', (tester) async {
    await tester.pumpWidget(
      _buildSheet(
        loadGroups: () async {
          throw StateError('boom');
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reply-sticker-picker-error')), findsOneWidget);
  });

  testWidgets('StickerPickerSheet shows empty state', (tester) async {
    await tester.pumpWidget(_buildSheet(loadGroups: () async => const []));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reply-sticker-picker-empty')), findsOneWidget);
    expect(find.text('需要联网加载表情包'), findsOneWidget);
  });

  testWidgets('StickerPickerSheet shows groups and returns selected sticker', (
    tester,
  ) async {
    StickerItem? selected;
    final preferencesRepository = _FakeStickerPickerPreferencesRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stickerGroupsProvider.overrideWith((_) async => _groups),
          stickerPickerPreferencesRepositoryProvider.overrideWithValue(
            preferencesRepository,
          ),
          stickerPickerLastGroupIdProvider.overrideWith((ref) {
            return ref
                .read(stickerPickerPreferencesRepositoryProvider)
                .loadLastGroupId();
          }),
          imageCacheServiceProvider.overrideWithValue(
            _FailingImageCacheService(),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: StickerPickerSheet())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('reply-sticker-group-tab-bugcat')),
      findsOneWidget,
    );
    expect(find.text('貓貓蟲'), findsOneWidget);
    expect(find.text('{:9_656:}'), findsNothing);
    expect(
      find.byKey(const Key('reply-sticker-item-{:9_656:}')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stickerGroupsProvider.overrideWith((_) async => _groups),
          stickerPickerPreferencesRepositoryProvider.overrideWithValue(
            preferencesRepository,
          ),
          stickerPickerLastGroupIdProvider.overrideWith((ref) {
            return ref
                .read(stickerPickerPreferencesRepositoryProvider)
                .loadLastGroupId();
          }),
          imageCacheServiceProvider.overrideWithValue(
            _FailingImageCacheService(),
          ),
        ],
        child: MaterialApp(
          home: _PickerLauncher(
            onSelected: (sticker) {
              selected = sticker;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-sticker-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reply-sticker-item-{:9_656:}')));
    await tester.pumpAndSettle();

    expect(selected?.code, '{:9_656:}');
  });

  testWidgets('StickerPickerSheet restores and saves selected group', (
    tester,
  ) async {
    final preferencesRepository = _FakeStickerPickerPreferencesRepository(
      lastGroupId: 'azukisan',
    );
    await tester.pumpWidget(
      _buildSheet(
        loadGroups: () async => _groups,
        preferencesRepository: preferencesRepository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reply-sticker-item-{:6_1:}')), findsOneWidget);
    expect(find.byKey(const Key('reply-sticker-item-{:9_656:}')), findsNothing);

    await tester.tap(find.byKey(const Key('reply-sticker-group-tab-bugcat')));
    await tester.pumpAndSettle();

    expect(preferencesRepository.lastGroupId, 'bugcat');
  });
}

final _groups = [
  StickerGroup(
    id: 'bugcat',
    title: '貓貓蟲',
    stickers: [_sticker(code: '{:9_656:}', imagePath: 'bugcat/Capoo16.gif')],
  ),
  StickerGroup(
    id: 'azukisan',
    title: '小豆泥',
    stickers: [_sticker(code: '{:6_1:}', imagePath: 'azukisan/1.gif')],
  ),
];

StickerItem _sticker({required String code, required String imagePath}) {
  return StickerItem(
    code: code,
    rawCodePattern: code,
    imagePath: imagePath,
    imageUrl: 'https://bbs.yamibo.com/static/image/smiley/$imagePath',
    cacheKey: ImageCacheKeys.remoteSmiley(imagePath),
  );
}

Widget _buildSheet({
  required Future<List<StickerGroup>> Function() loadGroups,
  StickerPickerPreferencesRepository? preferencesRepository,
}) {
  final resolvedPreferencesRepository =
      preferencesRepository ?? _FakeStickerPickerPreferencesRepository();
  return ProviderScope(
    overrides: [
      stickerGroupsProvider.overrideWith((_) => loadGroups()),
      stickerPickerPreferencesRepositoryProvider.overrideWithValue(
        resolvedPreferencesRepository,
      ),
      stickerPickerLastGroupIdProvider.overrideWith((ref) {
        return ref
            .read(stickerPickerPreferencesRepositoryProvider)
            .loadLastGroupId();
      }),
      imageCacheServiceProvider.overrideWithValue(_FailingImageCacheService()),
    ],
    child: const MaterialApp(home: Scaffold(body: StickerPickerSheet())),
  );
}

class _FailingImageCacheService implements ImageCacheService {
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult.failed;
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult.failed;
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    return 0;
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<void> clearUnprotected() async {}
}

class _PickerLauncher extends StatelessWidget {
  const _PickerLauncher({required this.onSelected});

  final ValueChanged<StickerItem> onSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FilledButton(
        key: const Key('open-sticker-picker'),
        onPressed: () async {
          final sticker = await showModalBottomSheet<StickerItem>(
            context: context,
            builder: (_) => const StickerPickerSheet(),
          );
          if (sticker != null) {
            onSelected(sticker);
          }
        },
        child: const Text('open'),
      ),
    );
  }
}

class _FakeStickerPickerPreferencesRepository
    implements StickerPickerPreferencesRepository {
  _FakeStickerPickerPreferencesRepository({this.lastGroupId});

  String? lastGroupId;

  @override
  Future<String?> loadLastGroupId() async {
    return lastGroupId;
  }

  @override
  Future<void> saveLastGroupId(String groupId) async {
    lastGroupId = groupId;
  }
}
