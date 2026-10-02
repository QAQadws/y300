import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../client/forum_client_config.dart';
import '../contracts/data_command_contract.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/private_message_batch_command.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';

/// Discuz's desktop compose form and single-request direct-message batch.
final class DiscuzPrivateMessageBatchCommand
    implements
        ForumPrivateMessageBatchCommand,
        ForumPrivateMessageBatchPreparationRepository {
  /// Creates an adapter on the existing authenticated Host transport.
  const DiscuzPrivateMessageBatchCommand({
    required this.config,
    required this.network,
    required this.profiles,
  });

  /// Managed forum origin.
  final ForumClientConfig config;

  /// Shared transport, including Cookie, WAF and cancellation handling.
  final ForumClientNetwork network;

  /// Desktop request identity resolver.
  final ForumRequestProfileResolver profiles;

  Uri get _composeUri =>
      config.siteOrigin.resolve('home.php?mod=spacecp&ac=pm');

  @override
  Future<
    DataReadResult<
      ForumPrivateMessageBatchPreparation,
      ForumPrivateMessageBatchCapabilities
    >
  >
  prepare(ForumPrivateMessageBatchPreparationRequest request) async {
    if (request.cancellation?.isCancelled ?? false) {
      return _readFailure('request_cancelled', DataReadFailureKind.cancelled);
    }
    final ForumTransportResult<ForumResponse<Object?>> result;
    try {
      result = await network.send(
        ForumRequest(
          method: ForumRequestMethod.get,
          uri: _composeUri,
          context: const ForumRequestContext(
            operation: 'private_message.batch.prepare',
            pageKind: 'profile.private_messages',
          ),
          headers: profiles
              .resolve(ForumRequestProfileKind.desktopHtml)
              .headers,
          followRedirects: false,
          cancellation: request.cancellation,
        ),
      );
    } on Object {
      return _readFailure(
        'private_message_batch_prepare_failed',
        DataReadFailureKind.network,
      );
    }
    if (request.cancellation?.isCancelled ?? false) {
      return _readFailure('request_cancelled', DataReadFailureKind.cancelled);
    }
    if (result case ForumTransportError(:final failure)) {
      return _readFailure(
        'private_message_batch_prepare_failed',
        toReadFailureKind(failure.kind),
      );
    }
    final response =
        (result as ForumTransportSuccess<ForumResponse<Object?>>).response;
    if (response.statusCode == 401 || response.statusCode == 403) {
      return _readFailure(
        'private_message_batch_session_unavailable',
        DataReadFailureKind.unauthorized,
      );
    }
    if (response.statusCode != 200 ||
        response.uri != _composeUri ||
        response.body is! String ||
        (response.body! as String).length > 1048576) {
      return _readFailure(
        'private_message_batch_form_unrecognized',
        DataReadFailureKind.parse,
      );
    }
    final document = html.parse(response.body! as String);
    final forms = document
        .querySelectorAll('form')
        .where((form) => form.querySelector('[name="pmsubmit"]') != null)
        .toList();
    if (forms.length != 1) {
      return _readFailure(
        'private_message_batch_form_unavailable',
        DataReadFailureKind.business,
      );
    }
    final form = forms.single;
    final action = Uri.tryParse(form.attributes['action'] ?? '');
    final resolved = action == null ? null : _composeUri.resolveUri(action);
    final hash = _field(form, 'formhash');
    final type = _field(form, 'type');
    if (form.attributes['method']?.toLowerCase() != 'post' ||
        resolved == null ||
        !_validAction(resolved) ||
        _field(form, 'pmsubmit') != 'true' ||
        hash == null ||
        !RegExp(r'^[a-zA-Z0-9]{8}$').hasMatch(hash) ||
        form.querySelectorAll('[name="type"]').length > 1 ||
        (type != null && type != '0') ||
        form.querySelectorAll('input[name="username"]').length != 1 ||
        form.querySelectorAll('textarea[name="message"]').length != 1 ||
        form.querySelector(
              '[name="seccodeverify"], [name="secanswer"], [name="subject"]',
            ) !=
            null ||
        form
            .querySelectorAll(
              '[name="touid"], [name="pmid"], [name="plid"], [name="uid"], [name="users[]"]',
            )
            .isNotEmpty) {
      return _readFailure(
        'private_message_batch_form_unrecognized',
        DataReadFailureKind.parse,
      );
    }
    return DataReadSuccess(
      data: ForumPrivateMessageBatchPreparation(
        token: _PreparedForm(resolved, hash),
      ),
      capabilities: ForumPrivateMessageBatchCapabilities(
        values: DataCapabilitySet.supported(
          ForumPrivateMessageBatchCapability.values,
        ),
      ),
      metadata: const DataReadMetadata.network(),
    );
  }

  bool _validAction(Uri uri) {
    if (uri.scheme != config.siteOrigin.scheme ||
        uri.host != config.siteOrigin.host ||
        uri.port != config.siteOrigin.port ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.path != _composeUri.path) {
      return false;
    }
    final query = uri.queryParametersAll;
    if (query.values.any((values) => values.length != 1) ||
        query.keys.any(
          (key) => !const {'mod', 'ac', 'op', 'touid', 'pmid'}.contains(key),
        )) {
      return false;
    }
    return uri.queryParameters['mod'] == 'spacecp' &&
        uri.queryParameters['ac'] == 'pm' &&
        uri.queryParameters['op'] == 'send' &&
        const {null, '', '0'}.contains(uri.queryParameters['touid']) &&
        const {null, '', '0'}.contains(uri.queryParameters['pmid']);
  }

  @override
  Future<DataCommandResult<ForumPrivateMessageBatchReceipt>> execute(
    ForumPrivateMessageBatchSubmission submission,
  ) async {
    final usernames = <String>[];
    for (final value in submission.usernames) {
      final username = value.trim();
      if (username.isEmpty ||
          username.length > 256 ||
          RegExp(r'[,\x00-\x1f\x7f]').hasMatch(value)) {
        return _notSent(
          'private_message_batch_input_invalid',
          DataCommandFailureKind.validation,
        );
      }
      if (!usernames.contains(username)) usernames.add(username);
    }
    if (usernames.isEmpty ||
        usernames.length > 20 ||
        submission.message.trim().isEmpty) {
      return _notSent(
        'private_message_batch_input_invalid',
        DataCommandFailureKind.validation,
      );
    }
    // Never accept a caller's previously prepared token: every click obtains
    // the current session's form before the one permitted write dispatch.
    final preparation = await prepare(
      ForumPrivateMessageBatchPreparationRequest(
        cancellation: submission.cancellation,
      ),
    );
    if (preparation case DataReadFailure(:final kind, :final code)) {
      return _notSent(
        code ?? 'private_message_batch_prepare_failed',
        _commandKind(kind),
      );
    }
    if (submission.cancellation?.isCancelled ?? false) {
      return _notSent('request_cancelled', DataCommandFailureKind.cancelled);
    }
    final token = preparation.dataOrNull!.token as _PreparedForm;
    final uri = token._action.replace(
      queryParameters: {
        ...token._action.queryParameters,
        'inajax': '1',
        'ajaxdata': 'json',
      },
    );
    final ForumTransportResult<ForumResponse<Object?>> result;
    try {
      result = await network.send(
        ForumRequest(
          method: ForumRequestMethod.post,
          uri: uri,
          context: const ForumRequestContext(
            operation: 'private_message.batch.submit',
            pageKind: 'profile.private_messages',
          ),
          headers: {
            ...profiles
                .resolve(
                  ForumRequestProfileKind.desktopHtml,
                  referer: _composeUri,
                )
                .headers,
            'Accept': 'application/json',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: ForumFormFields([
            MapEntry('formhash', token._formhash),
            const MapEntry('pmsubmit', 'true'),
            const MapEntry('type', '0'),
            MapEntry(
              'referer',
              config.siteOrigin.resolve('home.php?mod=space&do=pm').toString(),
            ),
            for (final username in usernames) MapEntry('users[]', username),
            MapEntry('message', submission.message),
          ]),
          followRedirects: false,
          cancellation: submission.cancellation,
        ),
      );
    } on Object {
      return _unknown();
    }
    if (result is ForumTransportError<ForumResponse<Object?>>) {
      return _unknown();
    }
    final response =
        (result as ForumTransportSuccess<ForumResponse<Object?>>).response;
    if (response.statusCode != 200 ||
        response.uri != uri ||
        response.body is! String ||
        (response.body! as String).length > 131072) {
      return _unknown();
    }
    final contentTypes = response.headers.entries
        .where((entry) => entry.key.toLowerCase() == 'content-type')
        .expand((entry) => entry.value)
        .toList();
    if (contentTypes.isNotEmpty &&
        !contentTypes.every(
          (value) =>
              value.split(';').first.trim().toLowerCase() == 'application/json',
        )) {
      return _unknown();
    }
    final Object? payload;
    try {
      if (!_hasUniqueJsonKeys(response.body! as String)) return _unknown();
      payload = jsonDecode(response.body! as String);
    } on FormatException {
      return _unknown();
    }
    if (payload is! Map<String, Object?> ||
        payload.length != 2 ||
        payload['message'] is! String ||
        !payload.containsKey('data')) {
      return _unknown();
    }
    final data = payload['data'];
    if (data is Map<String, Object?> &&
        data.length == 2 &&
        data['succeed'] is int &&
        data['users'] is String) {
      final accepted = data['succeed']! as int;
      final excludedText = data['users']! as String;
      final excluded = excludedText.isEmpty
          ? <String>[]
          : excludedText.split(',');
      if (accepted < 1 ||
          accepted > usernames.length ||
          excluded.toSet().length != excluded.length ||
          excluded.any((name) => !usernames.contains(name)) ||
          accepted + excluded.length != usernames.length) {
        return _unknown();
      }
      // Positive succeed is emitted only after UCenter returned a positive
      // message ID. Its count precedes UCenter's additional blacklist filter.
      return DataCommandApplied(
        ForumPrivateMessageBatchReceipt(
          usernames: usernames,
          serverReportedAcceptedCount: accepted,
          excludedUsernames: excluded,
        ),
      );
    }
    final emptyData =
        (data is Map<Object?, Object?> && data.isEmpty) ||
        (data is List<Object?> && data.isEmpty);
    final rejection = emptyData
        ? _rejection(payload['message']! as String)
        : null;
    if (rejection != null) return DataCommandRejected(rejection);
    return _unknown();
  }
}

// jsonDecode discards duplicate keys. Check the bounded token structure first
// so contradictory receipt fields cannot be hidden by last-value-wins parsing.
// Full JSON syntax is still validated by jsonDecode immediately afterwards.
bool _hasUniqueJsonKeys(String source) {
  final objects = <Set<String>>[];
  var depth = 0;
  var fields = 0;
  var index = 0;
  while (index < source.length) {
    final char = source[index++];
    if (char == '{' || char == '[') {
      if (++depth > 8) return false;
      if (char == '{') objects.add(<String>{});
    } else if (char == '}' || char == ']') {
      if (--depth < 0) return false;
      if (char == '}') {
        if (objects.isEmpty) return false;
        objects.removeLast();
      }
    } else if (char == '"') {
      final start = index - 1;
      var closed = false;
      while (index < source.length) {
        final current = source[index++];
        if (current == r'\') {
          index++;
        } else if (current == '"') {
          closed = true;
          break;
        }
      }
      if (!closed) return false;
      final end = index;
      while (index < source.length &&
          const [9, 10, 13, 32].contains(source.codeUnitAt(index))) {
        index++;
      }
      if (index < source.length && source[index] == ':') {
        final key = jsonDecode(source.substring(start, end));
        if (key is! String ||
            objects.isEmpty ||
            ++fields > 128 ||
            !objects.last.add(key)) {
          return false;
        }
      }
    }
  }
  return depth == 0 && objects.isEmpty;
}

final class _PreparedForm implements ForumPrivateMessageBatchPreparationToken {
  const _PreparedForm(this._action, this._formhash);
  final Uri _action;
  final String _formhash;
}

String? _field(Element form, String name) {
  final fields = form.querySelectorAll('input[name="$name"]');
  return fields.length == 1 ? fields.single.attributes['value'] : null;
}

DataReadFailure<
  ForumPrivateMessageBatchPreparation,
  ForumPrivateMessageBatchCapabilities
>
_readFailure(String code, DataReadFailureKind kind) =>
    DataReadFailure(kind: kind, code: code, diagnosticMessage: code);

DataCommandFailureKind _commandKind(DataReadFailureKind kind) => switch (kind) {
  DataReadFailureKind.cancelled => DataCommandFailureKind.cancelled,
  DataReadFailureKind.unauthorized => DataCommandFailureKind.unauthenticated,
  DataReadFailureKind.network => DataCommandFailureKind.network,
  DataReadFailureKind.timeout => DataCommandFailureKind.timeout,
  DataReadFailureKind.server => DataCommandFailureKind.server,
  DataReadFailureKind.parse => DataCommandFailureKind.parse,
  DataReadFailureKind.business => DataCommandFailureKind.permissionDenied,
  _ => DataCommandFailureKind.unknown,
};

DataCommandFailure _failure(String code, DataCommandFailureKind kind) =>
    DataCommandFailure(
      kind: kind,
      retryPolicy: DataCommandRetryPolicy.explicitOnly,
      code: code,
      diagnosticMessage: code,
    );

DataCommandNotSent<ForumPrivateMessageBatchReceipt> _notSent(
  String code,
  DataCommandFailureKind kind,
) => DataCommandNotSent(_failure(code, kind));

DataCommandOutcomeUnknown<ForumPrivateMessageBatchReceipt> _unknown() =>
    DataCommandOutcomeUnknown(
      _failure(
        'private_message_batch_success_unproved',
        DataCommandFailureKind.unknown,
      ),
    );

DataCommandFailure? _rejection(String markup) {
  final message = html.parseFragment(markup).text?.trim() ?? '';
  final code = _knownRejections[message];
  if (code == null) return null;
  final kind = switch (code) {
    'to_login' ||
    'login_before_enter_home' => DataCommandFailureKind.unauthenticated,
    'submit_invalid' => DataCommandFailureKind.staleFormhash,
    'no_privilege_sendpm' ||
    'is_blacklist' ||
    'message_can_not_send_onlyfriend' =>
      DataCommandFailureKind.permissionDenied,
    _ => DataCommandFailureKind.validation,
  };
  return _failure(code, kind);
}

// ajaxdata=json carries translated text, not messageval. Only exact known
// server rejections are classified; unknown/localized text remains uncertain.
const _knownRejections = <String, String>{
  '您需要先登录才能继续本操作': 'to_login',
  '请先登录后才能继续浏览': 'login_before_enter_home',
  '抱歉，您的请求来路不正确或表单验证串不符，无法提交': 'submit_invalid',
  '抱歉，您目前没有权限发短消息，点击这里查看权限': 'no_privilege_sendpm',
  '抱歉，受对方的隐私设置影响，您目前没有权限进行本操作': 'is_blacklist',
  '抱歉，该用户只接收好友发送的短消息': 'message_can_not_send_onlyfriend',
  '抱歉，不能发送空消息': 'unable_to_send_air_news',
  '抱歉，用户不存在或被冻结，请检查用户名是否正确': 'message_bad_touser',
  '不能给自己发送短消息': 'message_can_not_send_to_self',
  '发送失败，您当前超出了24小时内两人会话的上限': 'message_can_not_send_1',
  '两次发送短消息太快，请稍候再发送': 'message_can_not_send_2',
  '抱歉，您不能给非好友批量发送短消息': 'message_can_not_send_3',
  '抱歉，您目前还不能使用发送短消息功能': 'message_can_not_send_4',
  '您超出了24小时内群聊会话的上限': 'message_can_not_send_5',
  '对方屏蔽了您的短消息': 'message_can_not_send_6',
  '超过了群聊人数上限': 'message_can_not_send_7',
  '抱歉，您不能给自己发短消息': 'message_can_not_send_8',
  '收件人为空或对方屏蔽了您的短消息': 'message_can_not_send_9',
  '发起群聊人数不能小于两人': 'message_can_not_send_10',
  '该会话不存在': 'message_can_not_send_11',
  '抱歉，您没有权限操作': 'message_can_not_send_12',
  '这不是群聊消息': 'message_can_not_send_13',
  '这不是私人消息': 'message_can_not_send_14',
  '数据有误': 'message_can_not_send_15',
  '您超出了24小时内发短消息数量的上限': 'message_can_not_send_16',
  '抱歉，发送短消息失败': 'message_can_not_send',
};
