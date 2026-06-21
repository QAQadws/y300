import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/tags/data/tag_providers.dart';
import 'package:y300/features/tags/domain/models/yamibo_tag_thread_page.dart';

class YamiboTagThreadPageArgs {
  const YamiboTagThreadPageArgs({required this.url, this.title = ''});

  final String url;
  final String title;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is YamiboTagThreadPageArgs &&
        other.url == url &&
        other.title == title;
  }

  @override
  int get hashCode => Object.hash(url, title);
}

class YamiboTagThreadPageState {
  const YamiboTagThreadPageState({
    required this.url,
    required this.title,
    required this.isLoadingPage,
    this.data,
    this.errorMessage,
  });

  final String url;
  final String title;
  final bool isLoadingPage;
  final YamiboTagThreadPageData? data;
  final String? errorMessage;

  YamiboTagThreadPageState copyWith({
    String? url,
    String? title,
    bool? isLoadingPage,
    YamiboTagThreadPageData? data,
    String? errorMessage,
    bool clearError = false,
  }) {
    return YamiboTagThreadPageState(
      url: url ?? this.url,
      title: title ?? this.title,
      isLoadingPage: isLoadingPage ?? this.isLoadingPage,
      data: data ?? this.data,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  factory YamiboTagThreadPageState.initial(YamiboTagThreadPageArgs args) {
    return YamiboTagThreadPageState(
      url: args.url,
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
    return _load(_args.url, previous: null);
  }

  Future<void> refresh() async {
    final current = state.value ?? YamiboTagThreadPageState.initial(_args);
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _load(current.data?.url ?? current.url, previous: current),
    );
  }

  Future<void> loadUrl(String url) async {
    final current = state.value ?? YamiboTagThreadPageState.initial(_args);
    if (current.isLoadingPage) {
      return;
    }
    state = AsyncData(current.copyWith(isLoadingPage: true, clearError: true));
    final next = await _load(url, previous: current);
    state = AsyncData(next);
  }

  Future<YamiboTagThreadPageState> _load(
    String url, {
    required YamiboTagThreadPageState? previous,
  }) async {
    final result = await ref
        .read(yamiboTagThreadPageRepositoryProvider)
        .load(url);
    if (result case ApiSuccess<YamiboTagThreadPageData>(:final data)) {
      return YamiboTagThreadPageState(
        url: data.url,
        title: data.tagName,
        isLoadingPage: false,
        data: data,
      );
    }
    final error = (result as ApiFailure<YamiboTagThreadPageData>).error;
    return (previous ?? YamiboTagThreadPageState.initial(_args)).copyWith(
      isLoadingPage: false,
      errorMessage: error.message,
    );
  }
}
