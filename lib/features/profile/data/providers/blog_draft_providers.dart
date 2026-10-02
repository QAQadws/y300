import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/composer_shared/data/local/composer_draft_database_manager.dart';
import 'package:y300/features/profile/data/local/blog_draft_database.dart';
import 'package:y300/features/profile/data/repositories/sqflite_blog_draft_repository.dart';
import 'package:y300/features/profile/domain/repositories/blog_draft_repository.dart';

final blogDraftDatabaseManagerProvider = Provider<ComposerDraftDatabaseManager>(
  (ref) {
    final manager = ComposerDraftDatabaseManager(
      databaseName: BlogDraftDatabase.name,
      opener: (name) => BlogDraftDatabase.open(databaseName: name),
    );
    ref.onDispose(() => unawaited(manager.dispose()));
    return manager;
  },
);

final blogDraftRepositoryProvider = Provider<BlogDraftRepository>(
  (ref) => SqfliteBlogDraftRepository(
    databaseProvider: ref.watch(blogDraftDatabaseManagerProvider).open,
  ),
);
