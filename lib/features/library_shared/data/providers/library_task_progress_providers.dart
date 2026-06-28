import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';

final libraryTaskProgressHubProvider = Provider<LibraryTaskProgressHub>((ref) {
  final hub = DefaultLibraryTaskProgressHub();
  ref.onDispose(hub.dispose);
  return hub;
});
