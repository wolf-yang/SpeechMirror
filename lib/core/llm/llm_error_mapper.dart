import 'package:dio/dio.dart';

import 'llm_client.dart';

/// 将异常转换为用户可读短句（SnackBar / 内联错误）。
String mapLlmUserMessage(Object error) {
  if (error is LlmException) return error.message;
  if (error is DioException) {
    final code = error.response?.statusCode;
    if (code == 401) return '401：API Key 或 Base URL 可能不正确';
    if (code != null) return '请求失败（HTTP $code）';
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '请求超时，请检查网络或稍后再试';
      case DioExceptionType.connectionError:
        return '网络连接失败，请检查网络';
      default:
        break;
    }
    final m = error.message;
    if (m != null && m.isNotEmpty) return '网络异常：$m';
    return '网络异常';
  }
  return error.toString();
}
