import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/posting/domain/services/new_thread_response_parser.dart';

void main() {
  const parser = NewThreadResponseParser();

  group('NewThreadResponseParser success', () {
    test('parses tid+pid with post_newthread_succeed', () {
      final result = parser.parse(<String, dynamic>{
        'Variables': <String, dynamic>{
          'tid': '999001',
          'pid': '888001',
        },
        'Message': <String, dynamic>{
          'messageval': 'post_newthread_succeed',
          'messagestr': '主题已发布',
        },
      });

      expect(result.success, isTrue);
      expect(result.result?.tid, '999001');
      expect(result.result?.pid, '888001');
      expect(result.result?.message, '主题已发布');
    });

    test('parses tid+pid even when Message node is absent', () {
      final result = parser.parse(<String, dynamic>{
        'Variables': <String, dynamic>{
          'tid': '999002',
          'pid': '888002',
        },
      });

      expect(result.success, isTrue);
      expect(result.result?.tid, '999002');
    });

    test('parses JSON string body', () {
      final result = parser.parse(
        jsonEncode(<String, dynamic>{
          'Variables': <String, dynamic>{
            'tid': '999003',
            'pid': '888003',
          },
          'Message': <String, dynamic>{
            'messageval': 'post_newthread_succeed',
          },
        }),
      );

      expect(result.success, isTrue);
      expect(result.result?.tid, '999003');
    });
  });

  group('NewThreadResponseParser failure', () {
    test('post_type_isnull is mapped to failure with code', () {
      final result = parser.parse(<String, dynamic>{
        'Variables': <String, dynamic>{},
        'Message': <String, dynamic>{
          'messageval': 'post_type_isnull',
          'messagestr': '请选择主题分类',
        },
      });

      expect(result.success, isFalse);
      expect(result.code, 'post_type_isnull');
      expect(result.message, '请选择主题分类');
    });

    test('post_flood_ctrl is mapped to failure', () {
      final result = parser.parse(<String, dynamic>{
        'Message': <String, dynamic>{
          'messageval': 'post_flood_ctrl',
          'messagestr': '发帖间隔过短',
        },
      });
      expect(result.success, isFalse);
      expect(result.code, 'post_flood_ctrl');
    });

    test('postperm_login_nopermission is mapped to failure', () {
      final result = parser.parse(<String, dynamic>{
        'Message': <String, dynamic>{
          'messageval': 'postperm_login_nopermission',
          'messagestr': '请登录后再发帖',
        },
      });
      expect(result.success, isFalse);
      expect(result.code, 'postperm_login_nopermission');
    });

    test('missing tid even with succeed-like messageval is treated as failure',
        () {
      final result = parser.parse(<String, dynamic>{
        'Variables': <String, dynamic>{},
        'Message': <String, dynamic>{
          'messageval': 'post_newthread_succeed',
          'messagestr': '主题已发布',
        },
      });

      expect(result.success, isFalse);
      expect(result.code, 'post_newthread_succeed');
    });

    test('empty body falls back to failure with default message', () {
      final result = parser.parse(null);
      expect(result.success, isFalse);
      expect(result.message, '发帖结果未知');
    });
  });
}
