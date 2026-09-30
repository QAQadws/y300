import 'dart:convert';

import 'package:html/parser.dart' as html;

import '../contracts/data_command_contract.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/user_blog_media.dart';
import '../contracts/user_blog_operations.dart';
import '../network/forum_multipart.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_transport.dart';
import 'discuz_blog_editor_media.dart';
import 'discuz_blog_mutation_session.dart';

/// Album upload and receipt binding on the existing shared transport.
final class DiscuzBlogImageUpload {
  /// Shares the journal's actor boundary and optional multipart transport.
  const DiscuzBlogImageUpload(this.boundary, this.multipart);

  /// Existing journal session boundary.
  final DiscuzBlogMutationSession boundary;

  /// Host-owned streamed multipart transport.
  final ForumMultipartClient? multipart;

  /// Sends one source-validated image; all failures after send are uncertain.
  Future<DataCommandResult<UserBlogUploadedImage>> upload(
    UserBlogImageUploadSubmission submission,
    DiscuzBlogEditorMedia media,
    UserBlogTarget target,
  ) async {
    final transport = multipart;
    if (transport == null) return const DataCommandUnsupported();
    if (!boundary.currentActor(submission.actorUserId) ||
        submission.actorUserId != media.uid ||
        target.actorUserId != media.uid) {
      return _notSent(
        'blog_image_actor_changed',
        DataCommandFailureKind.unauthenticated,
      );
    }
    if (submission.cancellation?.isCancelled ?? false) {
      return _notSent('blog_image_cancelled', DataCommandFailureKind.cancelled);
    }
    final content = submission.content;
    final name = content.fileName.trim();
    final extension = name.split('.').last.toLowerCase();
    final mime = content.mimeType.trim().toLowerCase();
    const mimeTypes = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'bmp': 'image/bmp',
      'webp': 'image/webp',
    };
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        RegExp(r'[\\/\x00-\x1F\x7F]').hasMatch(name) ||
        mimeTypes[extension] != mime ||
        content.contentLength <= 0 ||
        !media.limits.extensionRules.any(
          (rule) => rule.extension == extension,
        ) ||
        (media.limits.maximumBytes != null &&
            content.contentLength > media.limits.maximumBytes!)) {
      return _notSent('blog_image_content_invalid');
    }
    final ForumTransportResult<ForumMultipartResponse> result;
    try {
      result = await transport.sendMultipart(
        ForumMultipartRequest(
          uri: media.uploadUri,
          context: const ForumRequestContext(
            operation: 'blog.image.upload',
            module: 'blog',
            silent: true,
          ),
          headers: boundary.profiles
              .resolve(
                ForumRequestProfileKind.desktopHtml,
                referer: boundary.config.siteOrigin.resolve(
                  'home.php?mod=spacecp&ac=blog&mobile=no',
                ),
              )
              .headers,
          fields: {'uid': media.uid, 'hash': media.hash},
          followRedirects: false,
          file: ForumMultipartFile(
            fieldName: 'Filedata',
            fileName: name,
            contentType: mime,
            contentLength: content.contentLength,
            openRead: content.openRead,
          ),
          cancellation: submission.cancellation,
          onSendProgress: (sent, total) {
            if (total > 0 &&
                boundary.currentActor(media.uid) &&
                !(submission.cancellation?.isCancelled ?? false)) {
              submission.onProgress?.call((sent / total).clamp(0, 1));
            }
          },
        ),
      );
    } catch (_) {
      return _unknown(
        'blog_image_transport_failed',
        DataCommandFailureKind.network,
      );
    }
    if (!boundary.currentActor(media.uid) ||
        (submission.cancellation?.isCancelled ?? false)) {
      return _unknown(
        'blog_image_interrupted',
        DataCommandFailureKind.cancelled,
      );
    }
    if (result case ForumTransportError<ForumMultipartResponse>()) {
      return _unknown(
        'blog_image_transport_failed',
        DataCommandFailureKind.network,
      );
    }
    final response =
        (result as ForumTransportSuccess<ForumMultipartResponse>).response;
    if (response.statusCode != 200 || response.uri != media.uploadUri) {
      return _unknown('blog_image_response_unconfirmed');
    }
    try {
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        return _unknown('blog_image_response_unconfirmed');
      }
      final id = data['picid']?.toString() ?? '';
      if (id == '0' &&
          data['url']?.toString() == '0' &&
          data['bigimg']?.toString() == '0') {
        return DataCommandRejected(
          _failure('blog_image_rejected', DataCommandFailureKind.server),
        );
      }
      final thumbnail = _imageUri(data['url']);
      final original = _imageUri(data['bigimg']);
      if (!RegExp(r'^[1-9]\d*$').hasMatch(id) ||
          thumbnail == null ||
          original == null) {
        return _unknown('blog_image_response_unconfirmed');
      }
      // The web editor inserts bigimg. blog_post uses pic_get(..., 0), whose
      // fifth argument disables thumbnails, when matching submitted picture IDs.
      return DataCommandApplied(
        UserBlogUploadedImage(
          picId: id,
          imageUri: original,
          originalImageUri: original,
          token: _UploadedImageProof(this, target, id, original, original),
        ),
      );
    } on FormatException {
      return _unknown('blog_image_response_unconfirmed');
    }
  }

  Uri? _imageUri(Object? value) {
    if (value is! String || value.trim().isEmpty || value == '0') return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    final resolved = boundary.config.siteOrigin.resolveUri(uri);
    if (!{'http', 'https'}.contains(resolved.scheme) ||
        resolved.host.isEmpty ||
        resolved.userInfo.isNotEmpty ||
        resolved.fragment.isNotEmpty) {
      return null;
    }
    return resolved;
  }

  /// The default album is where this uploader stores pictures. Read all needed
  /// pages before declaring a hint missing; a draft URL never proves ownership.
  Future<DataReadResult<UserBlogDraftImageRestoration, Object?>> restore(
    UserBlogEditorPreparation preparation,
    List<UserBlogDraftImageReference> images,
    ForumRequestCancellation? cancellation,
  ) async {
    final expected = <String, Uri>{};
    for (final image in images) {
      if (!RegExp(r'^[1-9]\d*$').hasMatch(image.picId) ||
          _imageUri(image.originalUri.toString()) != image.originalUri ||
          expected.containsKey(image.picId)) {
        return _restoreFailure('blog_draft_image_hint_invalid');
      }
      expected[image.picId] = image.originalUri;
    }
    final restored = <String, UserBlogUploadedImage>{};
    final seen = <String, Uri>{};
    var lastPage = 1;
    for (
      var page = 1;
      page <= lastPage && restored.length < expected.length;
      page++
    ) {
      final uri = boundary.config.siteOrigin
          .resolve('home.php')
          .replace(
            queryParameters: {
              'mod': 'misc',
              'ac': 'ajax',
              'op': 'album',
              'id': '0',
              'page': '$page',
              'mobile': 'no',
            },
          );
      final source = await boundary.read(
        uri,
        actor: preparation.target.actorUserId,
        referer: boundary.config.siteOrigin.resolve(
          'home.php?mod=spacecp&ac=blog&mobile=no',
        ),
        operation: 'blog.draft.images',
        profile: ForumRequestProfileKind.desktopHtml,
        cancellation: cancellation,
        requireExactUri: true,
      );
      if (source.failureOrNull case final failure?) return failure.retype();
      try {
        final document = html.parse(source.dataOrNull!);
        final tables = document.querySelectorAll('table.imgl');
        if (tables.length != 1) {
          throw const FormatException('album_table_missing');
        }
        for (final cell in tables.single.querySelectorAll('td[id]')) {
          final match = RegExp(r'^image_td_([1-9]\d*)$').firstMatch(cell.id);
          final nodes = cell.querySelectorAll('img');
          if (match == null || nodes.length != 1) {
            throw const FormatException('album_image_invalid');
          }
          final handler = nodes.single.attributes['onclick'] ?? '';
          final call = RegExp(
            r'''^\s*insertImage\(['"]([^'"]+)['"]\);?\s*$''',
          ).firstMatch(handler);
          final original = call == null ? null : _imageUri(call.group(1));
          if (original == null) {
            throw const FormatException('album_image_invalid');
          }
          final id = match.group(1)!;
          if (seen.containsKey(id)) {
            throw const FormatException('album_image_conflict');
          }
          seen[id] = original;
          if (expected[id] == original) {
            restored[id] = UserBlogUploadedImage(
              picId: id,
              imageUri: original,
              originalImageUri: original,
              token: _UploadedImageProof(
                this,
                preparation.target,
                id,
                original,
                original,
              ),
            );
          }
        }
        for (final link in document.querySelectorAll('.pgs a[href]')) {
          final target = uri.resolve(link.attributes['href']!);
          final query = target.queryParameters;
          if (!boundary.sameSite(target) ||
              target.path != uri.path ||
              query['mod'] != 'misc' ||
              query['ac'] != 'ajax' ||
              query['op'] != 'album' ||
              query['id'] != '0') {
            throw const FormatException('album_pagination_invalid');
          }
          final number = int.tryParse(query['page'] ?? '1');
          if (number == null || number < 1 || number > 10000) {
            throw const FormatException('album_pagination_invalid');
          }
          if (number > lastPage) lastPage = number;
        }
      } on FormatException {
        return _restoreFailure('blog_draft_album_invalid');
      }
    }
    return DataReadSuccess(
      data: UserBlogDraftImageRestoration(
        images: List.unmodifiable(restored.values),
        missingPicIds: Set.unmodifiable(
          expected.keys.toSet().difference(restored.keys.toSet()),
        ),
      ),
      capabilities: null,
      metadata: const DataReadMetadata.network(),
    );
  }

  /// Retains proof across fresh preparation, but never across target or actor.
  Map<String, String> bindingFields(UserBlogEditorSubmission submission) {
    final sources = html
        .parseFragment(submission.bodyHtml)
        .querySelectorAll('img[src]')
        .map(
          (image) =>
              boundary.config.siteOrigin.resolve(image.attributes['src']!),
        )
        .toSet();
    final fields = <String, String>{};
    for (final image in submission.uploadedImages) {
      final proof = image.token;
      if (proof is! _UploadedImageProof ||
          !identical(proof.owner, this) ||
          proof.target != submission.preparation.target ||
          proof.picId != image.picId ||
          proof.image != image.imageUri ||
          proof.original != image.originalImageUri) {
        throw const FormatException('blog_image_receipt_invalid');
      }
      // Discuz appends every bound picture absent from the body. Binding only
      // current embeds prevents deleted pictures from reappearing after save.
      if (sources.contains(image.imageUri)) {
        fields['picids[${image.picId}]'] = image.picId;
      }
    }
    if (fields.isNotEmpty) fields['savealbumid'] = '0';
    return fields;
  }
}

DataReadFailure<UserBlogDraftImageRestoration, Object?> _restoreFailure(
  String code,
) => DataReadFailure(
  kind: DataReadFailureKind.parse,
  code: code,
  diagnosticMessage: code,
);

final class _UploadedImageProof implements UserBlogUploadedImageToken {
  const _UploadedImageProof(
    this.owner,
    this.target,
    this.picId,
    this.image,
    this.original,
  );
  final DiscuzBlogImageUpload owner;
  final UserBlogTarget target;
  final String picId;
  final Uri image;
  final Uri original;
}

DataCommandFailure _failure(String code, DataCommandFailureKind kind) =>
    DataCommandFailure(
      kind: kind,
      retryPolicy: DataCommandRetryPolicy.explicitOnly,
      code: code,
      diagnosticMessage: code,
    );
DataCommandNotSent<UserBlogUploadedImage> _notSent(
  String code, [
  DataCommandFailureKind kind = DataCommandFailureKind.validation,
]) => DataCommandNotSent(_failure(code, kind));
DataCommandOutcomeUnknown<UserBlogUploadedImage> _unknown(
  String code, [
  DataCommandFailureKind kind = DataCommandFailureKind.parse,
]) => DataCommandOutcomeUnknown(_failure(code, kind));
