import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_asset_factory.dart';

void main() {
  test('keeps migrated source identity when legacy locators are cleared', () {
    final asset = LibraryCoverAssetFactory.preferred(
      ownerType: 'comic',
      ownerId: 'comic-1',
      sourceRevision: 3,
    );

    expect(asset, isNotNull);
    expect(asset!.assetId, 'comic/comic-1/source');
    expect(asset.revision, 3);
    expect(asset.kind, LibraryCoverAssetKind.source);
    expect(asset.sourceUrl, isNull);
    expect(asset.legacyLocalPath, isNull);
  });

  test('does not invent a source asset without revision or locator', () {
    final asset = LibraryCoverAssetFactory.preferred(
      ownerType: 'novel',
      ownerId: 'novel-1',
    );

    expect(asset, isNull);
  });
}
