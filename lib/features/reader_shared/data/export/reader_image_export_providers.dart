import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/reader_shared/data/export/default_reader_image_export_service.dart';
import 'package:y300/features/reader_shared/data/export/platform_reader_image_export_sink.dart';
import 'package:y300/features/reader_shared/domain/export/reader_image_export.dart';

final readerImageExportSinkProvider = Provider<ReaderImageExportSink>((ref) {
  return createPlatformReaderImageExportSink();
});

final readerImageExportServiceProvider = Provider<ReaderImageExportService>((
  ref,
) {
  return DefaultReaderImageExportService(
    imageCacheService: ref.watch(imageCacheServiceProvider),
    sink: ref.watch(readerImageExportSinkProvider),
  );
});
