import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/thread/data/repositories/discuz_post_edit_repository.dart';
import 'package:y300/features/thread/data/services/post_edit_form_parser.dart';
import 'package:y300/features/thread/data/services/post_edit_remote_data_source.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/repositories/post_edit_repository.dart';
import 'package:y300/features/thread/domain/services/post_edit_baseline_fingerprint_service.dart';
import 'package:y300/features/thread/domain/services/post_edit_native_capability_classifier.dart';

final postEditRemoteDataSourceProvider = Provider<PostEditRemoteDataSource>((
  ref,
) {
  return DiscuzPostEditRemoteDataSource(
    gateway: ref.watch(yamiboHttpGatewayProvider),
  );
});

final postEditFormParserProvider = Provider<PostEditFormParser>((ref) {
  return PostEditFormParser(
    fingerprintService: ref.watch(postEditBaselineFingerprintServiceProvider),
  );
});

final postEditRepositoryProvider = Provider<PostEditRepository>((ref) {
  return DiscuzPostEditRepository(
    remoteDataSource: ref.watch(postEditRemoteDataSourceProvider),
    formParser: ref.watch(postEditFormParserProvider),
    capabilityClassifier: ref.watch(postEditNativeCapabilityClassifierProvider),
  );
});

final postEditPreparationProvider = FutureProvider.autoDispose
    .family<PostEditPreparation, PostEditTarget>((ref, target) async {
      final result = await ref
          .watch(postEditRepositoryProvider)
          .loadForm(target);
      return result.when(
        success: (preparation) => preparation,
        failure: (error) => throw error,
      );
    });
