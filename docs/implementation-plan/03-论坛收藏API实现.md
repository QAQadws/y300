# 阶段 3：论坛收藏 API 实现

**预计时间：3–4 小时**

## 1. 需求

用户在论坛模块浏览帖子时，点击"收藏"按钮，调用 Discuz API 将帖子加入收藏。

### API 信息

- **端点**：`https://bbs.yamibo.com/api/mobile/index.php`
- **参数**：
  - `module=favthread`
  - `version=4`
- **POST body** (form-urlencoded)：
  ```
  formhash=<formhash>
  id=<tid 帖子ID>
  favoritesubmit=1
  ```

### 参考实现

`lib/features/reply/data/discuz_reply_api_repository.dart` — 同样的 API 模式（formhash + POST body + form-urlencoded）。

## 2. 设计

### 2.1 架构

```
┌──────────────────────────────────────┐
│  UI: FavoriteButton widget            │
│       (在帖子详情页/论坛页)            │
├──────────────────────────────────────┤
│  ForumFavoriteService (domain)        │
│       abstract class                  │
├──────────────────────────────────────┤
│  DiscuzForumFavoriteApiRepository     │
│       implements ForumFavoriteService │
│       (data layer)                    │
├──────────────────────────────────────┤
│  Existing: ProfileRepository          │
│       (提供 formhash)                 │
├──────────────────────────────────────┤
│  Existing: CookieStore                │
│       (提供 cookie)                   │
└──────────────────────────────────────┘
```

### 2.2 接口定义

**新文件：`lib/features/forum/domain/services/forum_favorite_service.dart`**

```dart
import 'package:y300/core/network/api_result.dart';

class ForumFavoriteResult {
  const ForumFavoriteResult({
    required this.success,
    required this.message,
  });

  final bool success;
  final String message;
}

abstract class ForumFavoriteService {
  /// 收藏一个帖子
  ///
  /// [tid] 帖子 ID
  /// 返回操作结果
  Future<ApiResult<ForumFavoriteResult>> addFavorite({
    required String tid,
  });

  /// 取消收藏
  ///
  /// [favid] 收藏记录的 ID（从收藏列表获取）
  Future<ApiResult<ForumFavoriteResult>> removeFavorite({
    required String favid,
  });
}
```

### 2.3 实现

**新文件：`lib/features/forum/data/discuz_forum_favorite_api_repository.dart`**

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/forum/domain/services/forum_favorite_service.dart';
import 'package:y300/features/profile/data/profile_repository.dart';

class DiscuzForumFavoriteApiRepository implements ForumFavoriteService {
  DiscuzForumFavoriteApiRepository({
    required ProfileRepository profileRepository,
    required CookieStore cookieStore,
    Dio? dio,
  }) : _profileRepository = profileRepository,
       _cookieStore = cookieStore,
       _dio = dio ?? Dio(BaseOptions(
         connectTimeout: AppConfig.connectTimeout,
         receiveTimeout: AppConfig.receiveTimeout,
       )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final cookieHeader = await _cookieStore.readCookieHeader(options.uri);
        if (cookieHeader != null && cookieHeader.isNotEmpty) {
          options.headers['cookie'] = cookieHeader;
        }
        handler.next(options);
      },
      onResponse: (response, handler) async {
        final setCookie = response.headers.map['set-cookie'] ?? <String>[];
        await _cookieStore.saveFromSetCookie(
          response.requestOptions.uri,
          setCookie,
        );
        handler.next(response);
      },
    ));
  }

  final ProfileRepository _profileRepository;
  final CookieStore _cookieStore;
  final Dio _dio;

  static const String _endpoint = 'api/mobile/index.php';
  static const String _module = 'favthread';
  static const String _version = '4';

  @override
  Future<ApiResult<ForumFavoriteResult>> addFavorite({
    required String tid,
  }) async {
    final trimmedTid = tid.trim();
    if (trimmedTid.isEmpty) {
      return const ApiFailure<ForumFavoriteResult>(
        ApiError(type: ApiErrorType.business, message: '帖子 ID 不能为空'),
      );
    }

    // 获取 formhash（复用 profile 模块的能力）
    final formhashResult = await _loadFormhash();
    if (formhashResult case ApiFailure<String>(:final error)) {
      return ApiFailure<ForumFavoriteResult>(error);
    }
    final formhash = (formhashResult as ApiSuccess<String>).data;

    final url = '${AppConfig.siteBaseUrl}/$_endpoint';

    try {
      final response = await _dio.post<dynamic>(
        url,
        queryParameters: const <String, String>{
          'module': _module,
          'version': _version,
        },
        data: <String, String>{
          'formhash': formhash,
          'id': trimmedTid,
          'favoritesubmit': '1',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: <String, String>{
            'referer': '${AppConfig.siteBaseUrl}/forum.php?mod=viewthread&tid=$trimmedTid&mobile=2',
            'accept': 'application/json, text/plain, */*',
          },
        ),
      );

      final parsed = _parseFavoriteResponse(response.data);
      if (parsed.success) {
        return ApiSuccess<ForumFavoriteResult>(
          ForumFavoriteResult(success: true, message: parsed.message),
        );
      } else {
        return ApiFailure<ForumFavoriteResult>(
          ApiError(
            type: ApiErrorType.business,
            message: parsed.message,
            code: parsed.code,
            raw: response.data,
            statusCode: response.statusCode,
          ),
        );
      }
    } on DioException catch (error) {
      return ApiFailure<ForumFavoriteResult>(
        ApiError(
          type: _mapDioErrorType(error),
          message: error.message ?? '网络异常',
          statusCode: error.response?.statusCode,
          raw: error.response?.data,
        ),
      );
    } catch (error) {
      return ApiFailure<ForumFavoriteResult>(
        ApiError(
          type: ApiErrorType.unknown,
          message: '收藏操作失败：$error',
          raw: error,
        ),
      );
    }
  }

  @override
  Future<ApiResult<ForumFavoriteResult>> removeFavorite({
    required String favid,
  }) async {
    final formhashResult = await _loadFormhash();
    if (formhashResult case ApiFailure<String>(:final error)) {
      return ApiFailure<ForumFavoriteResult>(error);
    }
    final formhash = (formhashResult as ApiSuccess<String>).data;

    final url = '${AppConfig.siteBaseUrl}/$_endpoint';

    try {
      final response = await _dio.post<dynamic>(
        url,
        queryParameters: const <String, String>{
          'module': _module,
          'version': _version,
        },
        data: <String, String>{
          'formhash': formhash,
          'favid': favid.trim(),
          'deletesubmit': 'true',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: <String, String>{
            'accept': 'application/json, text/plain, */*',
          },
        ),
      );
      // ... 类似的响应解析
    } on DioException catch (error) {
      // ... 错误处理
    } catch (error) {
      // ...
    }
  }

  Future<ApiResult<String>> _loadFormhash() async {
    final profile = await _profileRepository.getProfile();
    return profile.when(
      success: (data) {
        final formhash = data.formhash.trim();
        if (formhash.isEmpty) {
          return const ApiFailure<String>(
            ApiError(type: ApiErrorType.business, message: 'formhash 为空'),
          );
        }
        return ApiSuccess<String>(formhash);
      },
      failure: (error) => ApiFailure<String>(
        ApiError(
          type: error.type,
          message: '获取 formhash 失败：${error.message}',
          code: error.code,
        ),
      ),
    );
  }

  _FavoriteResponseParseResult _parseFavoriteResponse(dynamic data) {
    // 解析响应格式参考 Reply 模块：
    // {
    //   "Message": {
    //     "messagestr": "操作成功" / "已收藏该主题",
    //     "messageval": "..."
    //   }
    // }
    final root = _asJsonMap(data);
    final messageNode = ParseUtils.asMap(root['Message']);
    final message = ParseUtils.asString(
      messageNode['messagestr'],
      fallback: ParseUtils.asString(
        messageNode['messageval'],
        fallback: '操作结果未知',
      ),
    );
    final code = ParseUtils.asString(messageNode['messageval'], fallback: '');

    // Discuz 收藏成功的关键词检测
    final loweredCode = code.toLowerCase();
    final loweredMessage = message.toLowerCase();
    final success =
        loweredCode.contains('succeed') ||
        loweredCode.contains('success') ||
        loweredMessage.contains('成功') ||
        loweredMessage.contains('已收藏') ||
        loweredMessage.contains('已添加');

    return _FavoriteResponseParseResult(
      success: success,
      message: message,
      code: code,
    );
  }

  JsonMap _asJsonMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    if (data is String) {
      final decoded = jsonDecode(data);
      return ParseUtils.asMap(decoded);
    }
    return <String, dynamic>{};
  }

  ApiErrorType _mapDioErrorType(DioException error) {
    final statusCode = error.response?.statusCode;
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return ApiErrorType.timeout;
    }
    if (statusCode == 401 || statusCode == 403) {
      return ApiErrorType.unauthorized;
    }
    if (statusCode != null && statusCode >= 500) {
      return ApiErrorType.server;
    }
    return ApiErrorType.network;
  }
}

class _FavoriteResponseParseResult {
  const _FavoriteResponseParseResult({
    required this.success,
    required this.message,
    required this.code,
  });
  final bool success;
  final String message;
  final String code;
}
```

### 2.4 Provider 注册

**新文件或在 `lib/features/forum/data/forum_providers.dart` 中追加**

```dart
final forumFavoriteServiceProvider = Provider<ForumFavoriteService>((ref) {
  return DiscuzForumFavoriteApiRepository(
    profileRepository: ref.watch(profileRepositoryProvider),
    cookieStore: ref.watch(cookieStoreProvider),
  );
});
```

### 2.5 可选：常用论坛页 API

**补充 API**：`module=myfavforum&version=4` — 获取收藏的论坛版块列表。

此 API 已在 `FavoriteRepository.getFavoriteForums()` 中实现，无需新建。

## 3. 使用示例

```dart
// 在论坛帖子详情页
class ThreadDetailPage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ...
    return Scaffold(
      // ...
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final service = ref.read(forumFavoriteServiceProvider);
          final result = await service.addFavorite(tid: tid);
          result.when(
            success: (_) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('收藏成功')),
              );
              // 阶段 4 中会通过事件总线触发自动刷新
            },
            failure: (error) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('收藏失败：${error.message}')),
              );
            },
          );
        },
        child: const Icon(Icons.bookmark_add),
      ),
    );
  }
}
```

## 4. 文件变更清单

| 操作 | 文件 | 说明 |
|------|------|------|
| 新建 | `lib/features/forum/domain/services/forum_favorite_service.dart` | 接口 + 结果模型 |
| 新建 | `lib/features/forum/data/discuz_forum_favorite_api_repository.dart` | API 实现 |
| 修改 | `lib/features/forum/data/forum_providers.dart` | 注册 provider（若不存在则新建） |
| 修改 | `lib/features/thread/presentation/thread_detail_page.dart` | 集成收藏按钮 |

## 5. 验收标准

1. ✅ `addFavorite(tid:)` 能成功收藏帖子
2. ✅ 收藏失败时返回合理的错误消息
3. ✅ formhash 过期或为空时能正确处理
4. ✅ 网络异常时返回对应错误类型
5. ✅ 代码结构与 `DiscuzReplyApiRepository` 保持一致
6. ✅ Cookie 自动携带和更新
