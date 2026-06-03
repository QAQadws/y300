import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_host_controller.dart';

final shelfSelectionHostControllerProvider =
    Provider<ShelfSelectionHostController>((ref) {
  final controller = ShelfSelectionHostController();
  ref.onDispose(controller.dispose);
  return controller;
});
