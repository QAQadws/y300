import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/data/repositories/package_composer_unused_image_repository.dart';
import 'package:y300/features/composer_shared/domain/models/composer_unused_image_models.dart';

void main() {
  test(
    'directory projection preserves thumbnail referer and delete proof',
    () async {
      final token = _DirectoryToken();
      final directory = _DirectoryRepository(token);
      final command = _DeleteCommand();
      final repository = PackageComposerUnusedImageRepository(
        directory: directory,
        deleteCommand: command,
      );

      final loaded = await repository.loadUnusedImages();
      final image =
          (loaded as ApiSuccess<List<ComposerUnusedImage>>).data.single;
      expect(image.aid, '50001');
      expect(image.thumbnailRefererUri.queryParameters['action'], 'imagelist');

      final deleted = await repository.deleteUnusedImage('50001');
      expect(
        (deleted as ApiSuccess<ComposerUnusedImageDeleteResult>).data.deleted,
        isTrue,
      );
      expect(identical(command.lastRequest?.directoryToken, token), isTrue);
    },
  );

  test(
    'delete fails before transport when no loaded directory proves aid',
    () async {
      final command = _DeleteCommand();
      final repository = PackageComposerUnusedImageRepository(
        directory: _DirectoryRepository(_DirectoryToken()),
        deleteCommand: command,
      );

      final result = await repository.deleteUnusedImage('50001');

      expect(result, isA<ApiFailure<ComposerUnusedImageDeleteResult>>());
      expect(result.errorOrNull?.code, 'unused_attachment_proof_missing');
      expect(command.lastRequest, isNull);
    },
  );
}

final class _DirectoryToken
    implements ForumUnusedImageAttachmentDirectoryToken {}

final class _DirectoryRepository
    implements ForumUnusedImageAttachmentDirectoryRepository {
  const _DirectoryRepository(this.token);

  final ForumUnusedImageAttachmentDirectoryToken token;

  @override
  ForumUnusedImageAttachmentCapabilities get capabilities =>
      ForumUnusedImageAttachmentCapabilities(
        values: DataCapabilitySet.supported(
          ForumUnusedImageAttachmentCapability.values,
        ),
      );

  @override
  Future<
    DataReadResult<
      ForumUnusedImageAttachmentDirectory,
      ForumUnusedImageAttachmentCapabilities
    >
  >
  load(
    ForumUnusedImageAttachmentDirectoryRequest request,
  ) async => DataReadSuccess(
    data: ForumUnusedImageAttachmentDirectory(
      items: <ForumUnusedImageAttachment>[
        ForumUnusedImageAttachment(
          aid: '50001',
          thumbnail: ForumResourceReference(
            uri: Uri.parse(
              'https://bbs.example.test/forum.php?mod=image&aid=50001',
            ),
            referer: Uri.parse(
              'https://bbs.example.test/forum.php?mod=ajax&action=imagelist&posttime=0',
            ),
            kind: ForumResourceKind.image,
            origin: ForumResourceOrigin.sameSite,
          ),
          fileName: 'fixture.jpg',
        ),
      ],
      token: token,
    ),
    capabilities: capabilities,
    metadata: const DataReadMetadata.network(),
  );
}

final class _DeleteCommand implements ForumUnusedImageAttachmentDeleteCommand {
  DeleteUnusedImageAttachmentRequest? lastRequest;

  @override
  Future<DataCommandResult<ForumImageAttachmentDeleteReceipt>> execute(
    DeleteUnusedImageAttachmentRequest request,
  ) async {
    lastRequest = request;
    return DataCommandApplied(
      ForumImageAttachmentDeleteReceipt(aid: request.aid, deletedCount: 1),
    );
  }
}
