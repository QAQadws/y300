class ShelfCategoryAssignResult {
  const ShelfCategoryAssignResult({
    required this.assignedWorkIds,
    required this.failedWorkIds,
    required this.targetCategoryId,
  });

  final List<String> assignedWorkIds;
  final List<String> failedWorkIds;
  final String targetCategoryId;

  bool get hasFailure => failedWorkIds.isNotEmpty;
}

abstract class ShelfCategoryAssignUseCase {
  Future<ShelfCategoryAssignResult> assign({
    required Set<String> workIds,
    required String sourceCategoryId,
    required String targetCategoryId,
  });
}
