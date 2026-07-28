import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';

typedef SelectionHostAsyncVoidCallback = Future<void> Function();
typedef SelectionHostLoadCategoriesCallback =
    Future<List<LibraryCategory>> Function();
typedef SelectionHostCreateCategoryCallback =
    Future<String> Function(String name);
typedef SelectionHostRunActionCallback =
    Future<SelectionActionOutcome> Function(
      SelectionActionExecutionRequest request,
    );

class ShelfSelectionHostDelegate {
  const ShelfSelectionHostDelegate({
    required this.exitSelection,
    required this.selectAllVisible,
    required this.invertVisible,
    required this.loadAvailableCategories,
    required this.createCategory,
    required this.runSelectionAction,
    required this.refreshAfterAction,
  });

  final SelectionHostAsyncVoidCallback exitSelection;
  final SelectionHostAsyncVoidCallback selectAllVisible;
  final SelectionHostAsyncVoidCallback invertVisible;
  final SelectionHostLoadCategoriesCallback loadAvailableCategories;
  final SelectionHostCreateCategoryCallback createCategory;
  final SelectionHostRunActionCallback runSelectionAction;
  final SelectionHostAsyncVoidCallback refreshAfterAction;
}

class ShelfSelectionHostState {
  const ShelfSelectionHostState({
    required this.ownerToken,
    required this.moduleKey,
    required this.activeCategoryId,
    required this.selectedCount,
    required this.selectionActions,
  });

  final Object ownerToken;
  final LibraryModuleKey moduleKey;
  final String activeCategoryId;
  final int selectedCount;
  final List<SelectionAction> selectionActions;

  ShelfSelectionHostState copyWith({
    String? activeCategoryId,
    int? selectedCount,
    List<SelectionAction>? selectionActions,
  }) {
    return ShelfSelectionHostState(
      ownerToken: ownerToken,
      moduleKey: moduleKey,
      activeCategoryId: activeCategoryId ?? this.activeCategoryId,
      selectedCount: selectedCount ?? this.selectedCount,
      selectionActions: selectionActions ?? this.selectionActions,
    );
  }
}

class ShelfSelectionHostController extends ChangeNotifier {
  ShelfSelectionHostState? _state;
  ShelfSelectionHostDelegate? _delegate;
  Set<String> _selectedWorkIds = <String>{};
  var _disposed = false;

  ShelfSelectionHostState? get state => _state;

  bool get isActive => !_disposed && _state != null && _delegate != null;

  Set<String> get selectedWorkIds =>
      UnmodifiableSetView<String>(_selectedWorkIds);

  void activate({
    required Object ownerToken,
    required LibraryModuleKey moduleKey,
    required String activeCategoryId,
    required int selectedCount,
    required Set<String> selectedWorkIds,
    required List<SelectionAction> selectionActions,
    required ShelfSelectionHostDelegate delegate,
  }) {
    if (_disposed) {
      return;
    }
    _delegate = delegate;
    _selectedWorkIds = Set<String>.of(selectedWorkIds);
    _state = ShelfSelectionHostState(
      ownerToken: ownerToken,
      moduleKey: moduleKey,
      activeCategoryId: activeCategoryId,
      selectedCount: selectedCount,
      selectionActions: List<SelectionAction>.unmodifiable(selectionActions),
    );
    notifyListeners();
  }

  void update({
    required Object ownerToken,
    required String activeCategoryId,
    required int selectedCount,
    required Set<String> selectedWorkIds,
    required List<SelectionAction> selectionActions,
  }) {
    if (_disposed) {
      return;
    }
    final current = _state;
    if (current == null || !identical(current.ownerToken, ownerToken)) {
      return;
    }
    _selectedWorkIds = Set<String>.of(selectedWorkIds);
    _state = current.copyWith(
      activeCategoryId: activeCategoryId,
      selectedCount: selectedCount,
      selectionActions: List<SelectionAction>.unmodifiable(selectionActions),
    );
    notifyListeners();
  }

  void deactivate(Object ownerToken) {
    if (_disposed) {
      return;
    }
    final current = _state;
    if (current == null || !identical(current.ownerToken, ownerToken)) {
      return;
    }
    _delegate = null;
    _state = null;
    _selectedWorkIds = <String>{};
    notifyListeners();
  }

  Future<void> exitSelection() async {
    final delegate = _requireDelegate();
    final ownerToken = _requireState().ownerToken;
    await delegate.exitSelection();
    deactivate(ownerToken);
  }

  Future<void> selectAllVisible() async {
    final delegate = _requireDelegate();
    await delegate.selectAllVisible();
  }

  Future<void> invertVisible() async {
    final delegate = _requireDelegate();
    await delegate.invertVisible();
  }

  Future<List<LibraryCategory>> loadAvailableCategories() async {
    final delegate = _requireDelegate();
    return delegate.loadAvailableCategories();
  }

  Future<String> createCategory(String name) async {
    final delegate = _requireDelegate();
    return delegate.createCategory(name);
  }

  Future<SelectionActionOutcome> executeAction({
    required String actionId,
    String? targetCategoryId,
  }) async {
    final delegate = _requireDelegate();
    final current = _requireState();
    final ownerToken = current.ownerToken;
    final request = SelectionActionExecutionRequest(
      actionId: actionId,
      workIds: Set<String>.of(_selectedWorkIds),
      activeCategoryId: current.activeCategoryId,
      targetCategoryId: targetCategoryId,
    );
    final result = await delegate.runSelectionAction(request);
    if (!result.changed) {
      return result;
    }
    await delegate.refreshAfterAction();
    await delegate.exitSelection();
    deactivate(ownerToken);
    return result;
  }

  ShelfSelectionHostState _requireState() {
    final current = _state;
    if (current == null) {
      throw StateError('No active shelf selection');
    }
    return current;
  }

  ShelfSelectionHostDelegate _requireDelegate() {
    final delegate = _delegate;
    if (delegate == null) {
      throw StateError('No active shelf selection');
    }
    return delegate;
  }

  @override
  void dispose() {
    _disposed = true;
    _delegate = null;
    _state = null;
    _selectedWorkIds = <String>{};
    super.dispose();
  }
}
