import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/tags/data/providers/tag_providers.dart';
import 'package:y300/features/tags/domain/models/forum_tag_directory_models.dart';
import 'package:y300/features/tags/domain/repositories/forum_tag_directory_repository.dart';

class YamiboTagThreadPageArgs {
  const YamiboTagThreadPageArgs({
    required this.tagId,
    this.page = 1,
    this.title = '',
  });

  final String tagId;
  final int page;
  final String title;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is YamiboTagThreadPageArgs &&
        other.tagId == tagId &&
        other.page == page &&
        other.title == title;
  }

  @override
  int get hashCode => Object.hash(tagId, page, title);
}

class YamiboTagThreadPageState {
  const YamiboTagThreadPageState({
    required this.tagId,
    required this.page,
    required this.title,
    required this.isLoadingPage,
    this.data,
    this.capabilities,
    this.metadata,
    this.errorMessage,
  });

  final String tagId;
  final int page;
  final String title;
  final bool isLoadingPage;
  final ForumTagDirectoryData? data;
  final ForumTagDirectoryReadCapabilities? capabilities;
  final DataReadMetadata? metadata;
  final String? errorMessage;

  YamiboTagThreadPageState copyWith({
    String? tagId,
    int? page,
    String? title,
    bool? isLoadingPage,
    ForumTagDirectoryData? data,
    ForumTagDirectoryReadCapabilities? capabilities,
    DataReadMetadata? metadata,
    String? errorMessage,
    bool clearError = false,
  }) {
    return YamiboTagThreadPageState(
      tagId: tagId ?? this.tagId,
      page: page ?? this.page,
      title: title ?? this.title,
      isLoadingPage: isLoadingPage ?? this.isLoadingPage,
      data: data ?? this.data,
      capabilities: capabilities ?? this.capabilities,
      metadata: metadata ?? this.metadata,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  factory YamiboTagThreadPageState.initial(YamiboTagThreadPageArgs args) {
    return YamiboTagThreadPageState(
      tagId: args.tagId,
      page: args.page,
      title: args.title,
      isLoadingPage: false,
    );
  }
}

final yamiboTagThreadPageControllerProvider = AsyncNotifierProvider.autoDispose
    .family<
      YamiboTagThreadPageController,
      YamiboTagThreadPageState,
      YamiboTagThreadPageArgs
    >((args) => YamiboTagThreadPageController(args));

class YamiboTagThreadPageController
    extends AsyncNotifier<YamiboTagThreadPageState> {
  YamiboTagThreadPageController(this._args);

  final YamiboTagThreadPageArgs _args;

  @override
  FutureOr<YamiboTagThreadPageState> build() {
    return _load(
      ForumTagDirectoryQuery(tagId: _args.tagId, page: _args.page),
      previous: null,
      cachePolicy: CacheLoadPolicy.cacheFirst,
    );
  }

  Future<void> refresh() async {
    final current = state.value ?? YamiboTagThreadPageState.initial(_args);
    final query = ForumTagDirectoryQuery(
      tagId: current.tagId,
      page: current.data?.pagination.currentPage ?? current.page,
    );
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _load(
        query,
        previous: current,
        cachePolicy: CacheLoadPolicy.networkFirst,
      ),
    );
  }

  Future<void> loadPage(int page) async {
    final current = state.value ?? YamiboTagThreadPageState.initial(_args);
    final pagination = current.data?.pagination;
    final currentPage = pagination?.currentPage ?? current.page;
    final lastPage = pagination?.totalPages;
    if (current.isLoadingPage ||
        page < 1 ||
        page == pagination?.currentPage ||
        (lastPage != null && page > lastPage) ||
        (pagination?.hasNext == false && page > currentPage) ||
        (pagination?.hasPrevious == false && page < currentPage)) {
      return;
    }
    state = AsyncData(current.copyWith(isLoadingPage: true, clearError: true));
    final next = await _load(
      ForumTagDirectoryQuery(tagId: current.tagId, page: page),
      previous: current,
      cachePolicy: CacheLoadPolicy.cacheFirst,
    );
    state = AsyncData(next);
  }

  Future<YamiboTagThreadPageState> _load(
    ForumTagDirectoryQuery query, {
    required YamiboTagThreadPageState? previous,
    required CacheLoadPolicy cachePolicy,
  }) async {
    final result = await ref
        .read(forumTagDirectoryRepositoryProvider)
        .load(query, cachePolicy: cachePolicy);
    if (result case DataReadSuccess<
      ForumTagDirectoryData,
      ForumTagDirectoryReadCapabilities
    >(
      :final data,
      :final capabilities,
      :final metadata,
    )) {
      return YamiboTagThreadPageState(
        tagId: data.tag.id,
        page: data.pagination.currentPage,
        title: data.tag.name ?? _args.title,
        isLoadingPage: false,
        data: data,
        capabilities: capabilities,
        metadata: metadata,
      );
    }
    final failure = result.failureOrNull!;
    return (previous ?? YamiboTagThreadPageState.initial(_args)).copyWith(
      isLoadingPage: false,
      errorMessage: failure.diagnosticMessage,
    );
  }
}
