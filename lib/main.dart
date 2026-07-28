import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart' as date_symbol_data;
import 'package:y300/app/y300_app.dart';
import 'package:y300/core/media/global_image_cache_tuner.dart';
import 'package:y300/core/preferences/legacy_cache_root_preference_migrator.dart';
import 'package:y300/core/preferences/preferences_providers.dart';
import 'package:y300/core/preferences/preferences_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await date_symbol_data.initializeDateFormatting();
  // 配置运行时解码图片缓存预算（区别于磁盘缓存上限），让可见区与上下缓冲区的
  // 已解码 bitmap 常驻内存，避免来回滚动时反复重新解码。
  const PlatformImageCacheTuner().applyTo(PaintingBinding.instance.imageCache);
  final preferencesStore = SharedPreferencesStore();
  try {
    await LegacyCacheRootPreferenceMigrator(
      preferencesStore: preferencesStore,
    ).migrate();
  } catch (_) {
    // Cache-root retirement is retryable and must never block app startup.
  }
  runApp(
    ProviderScope(
      overrides: [preferencesStoreProvider.overrideWithValue(preferencesStore)],
      child: const Y300App(),
    ),
  );
}
