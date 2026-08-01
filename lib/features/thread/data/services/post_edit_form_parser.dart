import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/thread/data/services/discuz_successful_control_extractor.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/services/post_edit_baseline_fingerprint_service.dart';

class PostEditFormParser {
  const PostEditFormParser({
    this.controlsExtractor = const DiscuzSuccessfulControlExtractor(),
    this.fingerprintService = const PostEditBaselineFingerprintService(),
  });

  final DiscuzSuccessfulControlExtractor controlsExtractor;
  final PostEditBaselineFingerprintService fingerprintService;

  PostEditFormParseResult parse(
    String html, {
    required PostEditTarget target,
    Uri? sourceUri,
  }) {
    final document = html_parser.parse(html);
    if (_looksLikeAuthenticationPage(document)) {
      return const PostEditFormParseResult.failure(
        PostEditFormParseFailureReason.authenticationRequired,
      );
    }
    if (_looksLikePermissionPage(document)) {
      return const PostEditFormParseResult.failure(
        PostEditFormParseFailureReason.permissionDenied,
      );
    }

    final forms = document.querySelectorAll('form#postform');
    if (forms.isEmpty) {
      return const PostEditFormParseResult.failure(
        PostEditFormParseFailureReason.missingForm,
      );
    }
    if (forms.length != 1) {
      return const PostEditFormParseResult.failure(
        PostEditFormParseFailureReason.duplicateForm,
      );
    }
    final form = forms.single;
    if ((form.attributes['method'] ?? '').toLowerCase() != 'post') {
      return const PostEditFormParseResult.failure(
        PostEditFormParseFailureReason.invalidMethod,
      );
    }
    final enctype = (form.attributes['enctype'] ?? '').toLowerCase();
    if (!enctype.startsWith('multipart/form-data')) {
      return const PostEditFormParseResult.failure(
        PostEditFormParseFailureReason.invalidEnctype,
      );
    }

    final source = sourceUri ?? target.editUri;
    final submitUri = _resolveSubmitUri(form, source);
    if (submitUri == null || !_isManagedEditSubmitUri(submitUri, target)) {
      return const PostEditFormParseResult.failure(
        PostEditFormParseFailureReason.invalidSubmitAction,
      );
    }

    final criticalNames = <String>[
      'formhash',
      'posttime',
      'fid',
      'tid',
      'pid',
      'page',
      'subject',
      'message',
    ];
    for (final name in criticalNames) {
      final controls = _controlsByName(form, name);
      if (controls.isEmpty) {
        return const PostEditFormParseResult.failure(
          PostEditFormParseFailureReason.missingCriticalControl,
        );
      }
      if (controls.length != 1) {
        return const PostEditFormParseResult.failure(
          PostEditFormParseFailureReason.duplicateCriticalControl,
        );
      }
    }

    final messageControl = _controlsByName(form, 'message').single;
    if (messageControl.localName != 'textarea' ||
        messageControl.id != 'needmessage') {
      return const PostEditFormParseResult.failure(
        PostEditFormParseFailureReason.contractChanged,
      );
    }
    final fieldValues = <String, String>{};
    for (final name in criticalNames) {
      fieldValues[name] = _controlValue(_controlsByName(form, name).single);
    }
    if (fieldValues['formhash']!.isEmpty ||
        fieldValues['posttime']!.isEmpty ||
        !_positiveInteger(fieldValues['fid']) ||
        !_positiveInteger(fieldValues['tid']) ||
        !_positiveInteger(fieldValues['pid']) ||
        !_positiveInteger(fieldValues['page'])) {
      return const PostEditFormParseResult.failure(
        PostEditFormParseFailureReason.contractChanged,
      );
    }
    if (fieldValues['fid'] != target.fid ||
        fieldValues['tid'] != target.tid ||
        fieldValues['pid'] != target.pid ||
        int.parse(fieldValues['page']!) != target.page) {
      return const PostEditFormParseResult.failure(
        PostEditFormParseFailureReason.targetMismatch,
      );
    }

    final extracted = controlsExtractor.extract(form);
    final externalControls = document
        .querySelectorAll('input, textarea, select')
        .where(
          (control) =>
              control.parent != null &&
              !form.contains(control) &&
              control.attributes['form'] == 'postform' &&
              (control.attributes['name']?.trim().isNotEmpty ?? false),
        )
        .isNotEmpty;
    final names = extracted.namedControlNames;
    final evidence = PostEditFormStructureEvidence(
      allNamedControlNamesInDomOrder: names,
      hasExternalFormOwnerControls: externalControls,
      hasUnsupportedControlType: extracted.hasUnsupportedControlType,
      hasRegularAttachments: document
          .querySelectorAll('#attlist li')
          .isNotEmpty,
      hasSpecialEditorMarker: _hasSpecialMarker(form),
      hasThreadSortMarker: _hasThreadSortMarker(form),
      hasPluginMarker: _hasPluginMarker(form),
      hasDestructiveField: _hasDestructiveField(form),
      hasAuditMarker: _hasAuditMarker(form),
    );

    final imagesResult = _parseImages(document, source);
    if (imagesResult == null) {
      return const PostEditFormParseResult.failure(
        PostEditFormParseFailureReason.malformedAttachment,
      );
    }
    final regularAttachments = _parseRegularAttachments(document);
    final rawMessage = fieldValues['message']!;
    final subject = fieldValues['subject']!;
    final fingerprint = fingerprintService.fingerprint(
      target: target,
      rawMessage: rawMessage,
      originalSubject: subject,
      successfulControls: extracted.fields,
      existingImages: imagesResult,
      regularAttachments: regularAttachments,
    );
    return PostEditFormParseResult.success(
      PostEditFormSnapshot(
        target: target,
        sourceUri: source,
        submitUri: submitUri,
        formHash: fieldValues['formhash']!,
        postTime: fieldValues['posttime']!,
        rawMessage: rawMessage,
        originalSubject: subject,
        successfulControls: extracted.fields,
        existingImages: imagesResult,
        regularAttachments: regularAttachments,
        structureEvidence: evidence,
        baselineFingerprint: fingerprint,
      ),
    );
  }

  Uri? _resolveSubmitUri(html_dom.Element form, Uri source) {
    final action = form.attributes['action']?.trim();
    if (action == null || action.isEmpty) {
      return null;
    }
    return Uri.tryParse(action).mapOrNull((uri) => source.resolveUri(uri));
  }

  bool _isManagedEditSubmitUri(Uri uri, PostEditTarget target) {
    if (uri.scheme.toLowerCase() != target.editUri.scheme.toLowerCase() ||
        uri.host.toLowerCase() != target.editUri.host.toLowerCase() ||
        uri.port != target.editUri.port ||
        uri.path.toLowerCase() != '/forum.php') {
      return false;
    }
    final query = uri.queryParametersAll;
    return _single(query, 'mod')?.toLowerCase() == 'post' &&
        _single(query, 'action')?.toLowerCase() == 'edit' &&
        _single(query, 'editsubmit')?.toLowerCase() == 'yes';
  }

  List<html_dom.Element> _controlsByName(html_dom.Element form, String name) {
    return form
        .querySelectorAll('input, textarea, select')
        .where((control) => control.attributes['name'] == name)
        .toList(growable: false);
  }

  String _controlValue(html_dom.Element control) {
    if (control.localName == 'textarea') {
      return control.text;
    }
    return control.attributes['value'] ?? '';
  }

  List<PostEditExistingImage>? _parseImages(
    html_dom.Document document,
    Uri source,
  ) {
    final images = <PostEditExistingImage>[];
    for (final marker in document.querySelectorAll('#imglist [aid]')) {
      final aid = marker.attributes['aid']?.trim() ?? '';
      if (!_positiveInteger(aid)) {
        return null;
      }
      final item = _nearestAncestor(marker, 'li') ?? marker;
      final image = item.querySelector('img[src]');
      final src = image?.attributes['src']?.trim() ?? '';
      if (src.isEmpty) {
        return null;
      }
      final description = item
          .querySelectorAll('input[name]')
          .map((input) => input)
          .firstWhere(
            (input) =>
                input.attributes['name']!.contains('attachnew[$aid]') &&
                input.attributes['name']!.toLowerCase().contains('description'),
            orElse: () => html_dom.Element.tag('input'),
          );
      images.add(
        PostEditExistingImage(
          aid: aid,
          imageUri: source.resolve(src),
          isAssociated: marker.attributes['up'] == '1',
          description: description.attributes['value'] ?? '',
          fileName: image?.attributes['alt'],
        ),
      );
    }
    return List.unmodifiable(images);
  }

  List<PostEditRegularAttachment> _parseRegularAttachments(
    html_dom.Document document,
  ) {
    return List.unmodifiable(
      document.querySelectorAll('#attlist li').map((item) {
        return PostEditRegularAttachment(
          aid: item.attributes['aid']?.trim() ?? item.id,
          fileName: item.attributes['data-filename'] ?? item.text.trim(),
        );
      }),
    );
  }

  bool _hasSpecialMarker(html_dom.Element form) {
    return form.querySelectorAll('[name]').any((control) {
      final name = control.attributes['name']!.toLowerCase();
      final value = _controlValue(control);
      return (name == 'special' && value.trim() != '0') ||
          name == 'specialextra' ||
          name.startsWith('poll') ||
          name.startsWith('trade') ||
          name.startsWith('reward') ||
          name.startsWith('activity') ||
          name.startsWith('debate') ||
          name.startsWith('rushreply') ||
          name.startsWith('replycredit') ||
          name.startsWith('cronpublish');
    });
  }

  bool _hasThreadSortMarker(html_dom.Element form) {
    return form.querySelectorAll('[name]').any((control) {
      final name = control.attributes['name']!.toLowerCase();
      final value = _controlValue(control);
      return (name == 'sortid' && value.trim() != '0') ||
          name.startsWith('typeoption[');
    });
  }

  bool _hasPluginMarker(html_dom.Element form) {
    return form.querySelectorAll('[name], [data-plugin], [id]').any((control) {
      final name = (control.attributes['name'] ?? '').toLowerCase();
      final id = (control.attributes['id'] ?? '').toLowerCase();
      return name.contains('plugin') ||
          name.startsWith('ext_') ||
          id.contains('plugin') ||
          control.attributes.containsKey('data-plugin');
    });
  }

  bool _hasDestructiveField(html_dom.Element form) {
    return form.querySelectorAll('[name]').any((control) {
      final name = control.attributes['name']!.toLowerCase();
      return name == 'delete' ||
          name == 'delattachop' ||
          name.startsWith('delete[') ||
          name.startsWith('delattachop[');
    });
  }

  bool _hasAuditMarker(html_dom.Element form) {
    return form.querySelectorAll('[name]').any((control) {
      final name = control.attributes['name']!.toLowerCase();
      return name == 'audit' || name.startsWith('audit[');
    });
  }

  bool _looksLikeAuthenticationPage(html_dom.Document document) {
    final body = document.body?.text.toLowerCase() ?? '';
    final title = document.querySelector('title')?.text.toLowerCase() ?? '';
    return document.querySelector('form#loginform, .loginbox') != null ||
        title.contains('login') ||
        title.contains('登录') ||
        body.contains('请先登录');
  }

  bool _looksLikePermissionPage(html_dom.Document document) {
    final body = document.body?.text.toLowerCase() ?? '';
    return body.contains('没有权限') ||
        body.contains('无权访问') ||
        body.contains('permission denied');
  }

  html_dom.Element? _nearestAncestor(
    html_dom.Element element,
    String localName,
  ) {
    var parent = element.parent;
    while (parent != null) {
      if (parent.localName == localName) {
        return parent;
      }
      parent = parent.parent;
    }
    return null;
  }

  String? _single(Map<String, List<String>> query, String name) {
    final values = query[name];
    if (values == null || values.length != 1) {
      return null;
    }
    final value = values.single.trim();
    return value.isEmpty ? null : value;
  }

  bool _positiveInteger(String? value) {
    return value != null && RegExp(r'^[1-9]\d*$').hasMatch(value);
  }
}

extension on Uri? {
  T? mapOrNull<T>(T Function(Uri value) transform) {
    final value = this;
    return value == null ? null : transform(value);
  }
}
