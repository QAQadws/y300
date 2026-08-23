import 'package:y300/core/network/api_result.dart';

abstract interface class FormhashProvider {
  Future<ApiResult<String>> loadFormhash({bool preferProfile = false});
}
