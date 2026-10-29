import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_exceptions.dart';
import 'config.dart';

/// Токен доступа, который подставляется в заголовок `Authorization`.
///
/// Возвращается функцией, а не значением, чтобы токен можно было обновить
/// на лету, не пересобирая клиент.
typedef TokenProvider = String? Function();

/// Создаёт настроенный клиент Dio.
///
/// Общие настройки и интерсепторы вынесены сюда, чтобы репозитории
/// занимались только предметной областью.
Dio buildDio(
    {TokenProvider? tokenProvider,
    Future<bool> Function()? refreshTokens,
    Future<void> Function()? onSessionExpired}) {
  final dio = Dio(
    BaseOptions(
      // Web resolves /api against the deployment origin. Native test adapters
      // require an absolute URI even when they never open a network connection.
      baseUrl: kIsWeb || Uri.parse(apiBaseUrl).hasScheme
          ? apiBaseUrl
          : Uri(scheme: 'http', host: 'localhost')
              .resolve(apiBaseUrl)
              .toString(),
      connectTimeout: Duration(seconds: connectTimeoutSeconds),
      receiveTimeout: Duration(seconds: receiveTimeoutSeconds),
      headers: {'Content-Type': 'application/json'},
      // Не бросать исключение на кодах 4xx — разберём их сами.
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = tokenProvider?.call();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        if (kDebugMode) {
          debugPrint('[API] → ${options.method} ${options.uri}');
        }
        return handler.next(options);
      },
      onResponse: (response, handler) {
        final status = response.statusCode ?? 0;
        if (kDebugMode) {
          debugPrint('[API] ← $status ${response.requestOptions.uri}');
        }
        if (status >= 400) {
          // Просто написать `throw mapHttpError(...)` нельзя: dio перехватит
          // любое исключение из интерсептора и завернёт его в DioException
          // с типом unknown, а наше ValidationException окажется спрятан
          // внутри поля error. Поэтому отправляем ответ по ветке ошибок сами,
          // приложив уже разобранное исключение.
          return handler.reject(
            DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
              error: mapHttpError(status, response.data),
            ),
            true,
          );
        }
        return handler.next(response);
      },
      onError: (error, handler) async {
        final request = error.requestOptions;
        final isAuth = request.path.startsWith('/auth/');
        if (error.response?.statusCode == 401 &&
            !isAuth &&
            refreshTokens != null) {
          if (request.extra['authRetried'] == true) {
            await onSessionExpired?.call();
          } else {
            final current = tokenProvider?.call();
            final alreadyRefreshed = current != null &&
                request.headers['Authorization'] != 'Bearer $current';
            if (alreadyRefreshed || await refreshTokens()) {
              request.extra['authRetried'] = true;
              request.headers['Authorization'] =
                  'Bearer ${tokenProvider?.call()}';
              try {
                final response = await dio.fetch<dynamic>(request);
                return handler.resolve(response);
              } on DioException catch (retryError) {
                return handler.next(retryError);
              }
            }
          }
        }
        // Сюда приходят сетевые сбои, таймауты, коды 5xx
        // и всё, что отклонил обработчик выше.
        if (kDebugMode) {
          debugPrint(
            '[API] ${error.requestOptions.method} ${error.requestOptions.uri} → ${error.response?.statusCode ?? 'нет ответа'}: ${error.type}',
          );
        }
        return handler.next(error);
      },
    ),
  );

  return dio;
}

/// Выполняет операцию чтения с автоматическим повтором при сетевом сбое.
///
/// Повторяются только операции чтения: повторять создание записи нельзя,
/// иначе на сервере появятся дубликаты. При каждой попытке пауза растёт
/// экспоненциально.
Future<T> withRetry<T>(
  Future<T> Function() action, {
  int maxAttempts = maxReadRetries,
  Duration baseDelay = const Duration(milliseconds: retryBaseDelayMs),
}) async {
  var attempt = 0;
  while (true) {
    attempt++;
    try {
      return await action();
    } on DioException catch (e) {
      // `guard` внутри действия уже превратил DioException в исключение
      // предметной области, поэтому здесь разбираем оба вида.
      final error = mapDioError(e);
      if (!_isRetryable(error) || attempt >= maxAttempts) rethrow;
      if (kDebugMode) {
        debugPrint('[API] повтор $attempt из $maxAttempts после сетевого сбоя');
      }
      await Future<void>.delayed(baseDelay * (1 << (attempt - 1)));
    } on NetworkException {
      // Сетевой сбой после разбора в `guard`: повторяем.
      if (attempt >= maxAttempts) rethrow;
      if (kDebugMode) {
        debugPrint('[API] повтор $attempt из $maxAttempts после сетевого сбоя');
      }
      await Future<void>.delayed(baseDelay * (1 << (attempt - 1)));
    }
  }
}

/// Повторять имеет смысл только сетевые сбои.
///
/// Ошибки 4xx и 5xx повторять бессмысленно: сервер ответил, и ответ
/// будет тем же. Повторять создание записи тоже нельзя — на сервере
/// появятся дубликаты.
bool _isRetryable(ApiException error) => error is NetworkException;
