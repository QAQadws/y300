import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/data/local_library_state_repository.dart';

/// 统一状态仓储 Provider。
final libraryStateRepositoryProvider = Provider<LibraryStateRepository>((ref) {
  return LocalLibraryStateRepository(ComicLocalDb.open());
});

