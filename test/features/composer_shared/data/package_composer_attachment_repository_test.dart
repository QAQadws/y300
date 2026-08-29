import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/data/repositories/package_composer_attachment_repository.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_failure_models.dart';

void main() {
  late MemoryFileSystem fileSystem;
  late _UploadToken token;
  late ForumImageAttachmentUploadPreparation preparation;

  setUp(() {
    fileSystem = MemoryFileSystem.test(style: FileSystemStyle.posix);
    token = _UploadToken();
    preparation = ForumImageAttachmentUploadPreparation(
      fid: '30',
      extensionRules: const <ForumImageAttachmentExtensionRule>[
        ForumImageAttachmentExtensionRule(extension: 'jpg'),
      ],
      token: token,
    );
  });

  test(
    'preparation maps unlimited quota without exposing protocol secrets',
    () async {
      final repository = PackageComposerAttachmentRepository(
        preparation: _PreparationRepository(preparation),
        command: _UploadCommand((_) async => const DataCommandUnsupported()),
        fileSystem: fileSystem,
      );

      final result = await repository.prepareUpload(fid: '30');
      final permission =
          (result as ApiSuccess<ComposerImageUploadPermission>).data;

      expect(permission.allowedExtensions, <String>{'jpg'});
      expect(permission.attachRemain.size, -1);
      expect(permission.attachRemain.count, -1);
      expect(permission.uid, isEmpty);
      expect(permission.uploadHash, isEmpty);
      expect(identical(permission.packagePreparation, preparation), isTrue);
    },
  );

  test(
    'confirmed package upload maps aid and consumes the local stream',
    () async {
      final file = fileSystem.file('/fixture.jpg');
      file.writeAsBytesSync(<int>[1, 2, 3]);
      ForumImageAttachmentUploadSubmission? captured;
      final repository = PackageComposerAttachmentRepository(
        preparation: _PreparationRepository(preparation),
        command: _UploadCommand((submission) async {
          captured = submission;
          expect(
            await submission.content
                .openRead()
                .expand((chunk) => chunk)
                .toList(),
            <int>[1, 2, 3],
          );
          return const DataCommandApplied(
            ForumImageAttachmentUploadReceipt(aid: '40001'),
          );
        }),
        fileSystem: fileSystem,
        now: () => DateTime.utc(2026, 8, 29),
      );
      final permission = ComposerImageUploadPermission(
        allowedExtensions: const <String>{'jpg'},
        attachRemain: const ComposerAttachRemain(size: -1, count: -1),
        packagePreparation: preparation,
      );

      final result = await repository.uploadImage(
        fid: '30',
        permission: permission,
        attachment: _attachment(file),
      );

      final uploaded = (result as ApiSuccess<ComposerUploadedImage>).data;
      expect(uploaded.aid, '40001');
      expect(captured?.content.contentLength, 3);
      expect(captured?.content.mimeType, 'image/jpeg');
    },
  );

  test(
    'precise package rejection remains a precise App failure code',
    () async {
      final file = fileSystem.file('/fixture.jpg');
      file.writeAsBytesSync(<int>[1]);
      final repository = PackageComposerAttachmentRepository(
        preparation: _PreparationRepository(preparation),
        command: _UploadCommand(
          (_) async => const DataCommandRejected(
            DataCommandFailure(
              kind: DataCommandFailureKind.validation,
              retryPolicy: DataCommandRetryPolicy.afterInputChange,
              code: 'attachment_dimensions_exceeded',
              diagnosticMessage: 'attachment_dimensions_exceeded',
            ),
          ),
        ),
        fileSystem: fileSystem,
      );

      final result = await repository.uploadImage(
        fid: '30',
        permission: ComposerImageUploadPermission(
          allowedExtensions: const <String>{'jpg'},
          attachRemain: const ComposerAttachRemain(size: -1, count: -1),
          packagePreparation: preparation,
        ),
        attachment: _attachment(file),
      );

      expect(result, isA<ApiFailure<ComposerUploadedImage>>());
      expect(
        result.errorOrNull?.code,
        ComposerImageUploadFailureCode.dimensionsExceeded.name,
      );
    },
  );
}

ComposerImageAttachment _attachment(File file) => ComposerImageAttachment(
  localId: 'local-1',
  localPath: file.path,
  fileName: 'fixture.jpg',
  mimeType: 'image/jpeg',
  order: 0,
  status: ComposerImageAttachmentStatus.local,
);

final class _UploadToken
    implements ForumImageAttachmentUploadPreparationToken {}

final class _PreparationRepository
    implements ForumImageAttachmentUploadPreparationRepository {
  const _PreparationRepository(this.preparation);

  final ForumImageAttachmentUploadPreparation preparation;

  @override
  ForumImageAttachmentUploadCapabilities get capabilities =>
      ForumImageAttachmentUploadCapabilities(
        values: DataCapabilitySet.supported(
          ForumImageAttachmentUploadCapability.values,
        ),
      );

  @override
  Future<
    DataReadResult<
      ForumImageAttachmentUploadPreparation,
      ForumImageAttachmentUploadCapabilities
    >
  >
  load(ForumImageAttachmentUploadPreparationRequest request) async =>
      DataReadSuccess(
        data: preparation,
        capabilities: capabilities,
        metadata: const DataReadMetadata.network(),
      );
}

final class _UploadCommand implements ForumImageAttachmentUploadCommand {
  const _UploadCommand(this.callback);

  final Future<DataCommandResult<ForumImageAttachmentUploadReceipt>> Function(
    ForumImageAttachmentUploadSubmission submission,
  )
  callback;

  @override
  ForumImageAttachmentUploadCapabilities get capabilities =>
      ForumImageAttachmentUploadCapabilities(
        values: DataCapabilitySet.supported(
          ForumImageAttachmentUploadCapability.values,
        ),
      );

  @override
  Future<DataCommandResult<ForumImageAttachmentUploadReceipt>> execute(
    ForumImageAttachmentUploadSubmission submission,
  ) => callback(submission);
}
