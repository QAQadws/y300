import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/repositories/file_font_library_repository.dart';
import '../data/services/file_picker_font_import_picker.dart';
import '../data/services/flutter_font_runtime_loader.dart';
import '../domain/repositories/font_library_repository.dart';
import '../domain/repositories/font_library_storage_usage.dart';
import '../domain/services/font_import_picker.dart';
import '../domain/services/font_runtime_loader.dart';
import 'font_library_service.dart';

final _fileFontLibraryRepositoryProvider = Provider<FileFontLibraryRepository>((
  ref,
) {
  final repository = FileFontLibraryRepository(
    directoryProvider: () async => Directory(
      p.join((await getApplicationSupportDirectory()).path, 'fonts'),
    ),
  );
  ref.onDispose(() => unawaited(repository.dispose()));
  return repository;
});

final fontLibraryRepositoryProvider = Provider<FontLibraryRepository>(
  (ref) => ref.watch(_fileFontLibraryRepositoryProvider),
);

final fontLibraryStorageUsageProvider = Provider<FontLibraryStorageUsage>(
  (ref) => ref.watch(_fileFontLibraryRepositoryProvider),
);

final fontRuntimeLoaderProvider = Provider<FontRuntimeLoader>(
  (ref) => FlutterFontRuntimeLoader(),
);

final fontLibraryServiceProvider = Provider<FontLibraryService>((ref) {
  final service = FontLibraryService(
    repository: ref.watch(fontLibraryRepositoryProvider),
    runtimeLoader: ref.watch(fontRuntimeLoaderProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final fontImportPickerProvider = Provider<FontImportPicker>(
  (ref) => FilePickerFontImportPicker(),
);
