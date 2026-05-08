import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/tags/domain/forum_tag_models.dart';

abstract class ForumTagRepository {
  Future<ForumTagLookup> loadLookup();
}

class AssetForumTagRepository implements ForumTagRepository {
  const AssetForumTagRepository({
    AssetBundle? bundle,
    this.assetPath = 'assets/tag.json',
  }) : _bundle = bundle;

  final AssetBundle? _bundle;
  final String assetPath;

  @override
  Future<ForumTagLookup> loadLookup() async {
    final raw = await (_bundle ?? rootBundle).loadString(assetPath);
    final decoded = jsonDecode(raw);
    final boards = ParseUtils.asList(decoded)
        .map((item) => ForumBoardTagSet.fromJson(ParseUtils.asMap(item)))
        .toList(growable: false);
    return ForumTagLookup(boards);
  }
}
