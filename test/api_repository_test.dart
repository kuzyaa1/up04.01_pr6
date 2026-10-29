import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_studio_portal/core/api_client.dart';
import 'package:photo_studio_portal/core/api_exceptions.dart';
import 'package:photo_studio_portal/core/config.dart';
import 'package:photo_studio_portal/models/hall_query.dart';
import 'package:photo_studio_portal/models/page_result.dart';
import 'package:photo_studio_portal/models/studio_hall.dart';
import 'package:photo_studio_portal/repositories/api_hall_repository.dart';

/// Подменённый обработчик запросов: отвечает заранее заданным ответом.
///
/// Репозиторий проверяется без реального сервера: достаточно подставить
/// нужный HTTP-ответ и посмотреть, как репозиторий его разбирает.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.responder);

  /// Возвращает ответ по запросу.
  final Future<ResponseBody> Function(RequestOptions options) responder;

  /// Все запросы, дошедшие до адаптера.
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

/// Тело ответа с кодом 200.
ResponseBody _ok(Object payload) => ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// Тело ответа с кодом ошибки.
ResponseBody _fail(int status, Object payload) => ResponseBody.fromString(
      jsonEncode(payload),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// Страница залов в формате сервера.
Map<String, dynamic> _page({
  List<Map<String, dynamic>>? items,
  int page = 1,
  int size = 10,
  int total = 1,
}) =>
    {
      'items': items ??
          [
            {
              'id': 1,
              'name': 'Белая циклорама',
              'code': 'A-01',
              'style': 'Циклорама',
              'capacity': 8,
              'hourlyRate': 2500,
              'description': 'Зал с белым фоном',
              'equipmentIds': [1, 2],
              'photographerIds': [3],
              'createdAt': '2026-08-01T09:00:00Z',
              'deletedAt': null,
            },
          ],
      'page': page,
      'size': size,
      'total': total,
      'totalPages': 1,
    };

/// Создаёт Dio с подменённым адаптером.
Dio _dioWith(_StubAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://localhost:8080/api',
      validateStatus: (status) => status != null && status < 500,
    ),
  );
  dio.httpClientAdapter = adapter;
  dio.interceptors.add(
    InterceptorsWrapper(
      onResponse: (response, handler) {
        final status = response.statusCode ?? 0;
        if (status >= 400) {
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
    ),
  );
  return dio;
}

void main() {
  group('ApiHallRepository', () {
    test('разбирает страницу залов с сервера', () async {
      final adapter = _StubAdapter((_) async => _ok(_page()));
      final repository = ApiHallRepository(_dioWith(adapter));

      final result = await repository.find(const HallQuery());

      expect(result.items, hasLength(1));
      expect(result.total, 1);
      expect(result.page, 1);
      final hall = result.items.first;
      expect(hall.id, 1);
      expect(hall.name, 'Белая циклорама');
      expect(hall.code, 'A-01');
      expect(hall.style, 'Циклорама');
      expect(hall.capacity, 8);
      expect(hall.hourlyRate, 2500);
      expect(hall.description, 'Зал с белым фоном');
      expect(hall.equipmentIds, [1, 2]);
    });

    test('поиск, фильтры и сортировка уходят на сервер', () async {
      final adapter = _StubAdapter((_) async => _ok(_page()));
      final repository = ApiHallRepository(_dioWith(adapter));

      await repository.find(
        const HallQuery(
          search: ' циклорама ',
          style: 'Циклорама',
          capacityFrom: 4,
          priceTo: 5000,
          sortField: 'capacity',
          sortAscending: false,
          page: 3,
          size: 25,
        ),
      );

      expect(adapter.requests, hasLength(1));
      final query = adapter.requests.single.queryParameters;
      expect(query['search'], 'циклорама');
      expect(query['style'], 'Циклорама');
      expect(query['capacityFrom'], 4);
      expect(query['priceTo'], 5000);
      expect(query['sort'], 'capacity,desc');
      expect(query['page'], 3);
      expect(query['size'], 25);
      // Пустые фильтры в адрес не попадают.
      expect(query.containsKey('priceFrom'), isFalse);
    });

    test('ошибка 422 разбирается в ValidationException с полями', () async {
      final adapter = _StubAdapter(
        (_) async => _fail(422, {
          'message': 'Ошибка валидации',
          'errors': {
            'code': 'Зал с таким кодом уже существует',
            'capacity': 'Вместимость — положительное целое число',
          },
        }),
      );
      final repository = ApiHallRepository(_dioWith(adapter));

      await expectLater(
        repository.create(
          const StudioHall(
            id: 0,
            name: 'Новый зал',
            code: 'A-01',
            style: 'Циклорама',
            capacity: 0,
            hourlyRate: 1000,
          ),
        ),
        throwsA(
          isA<ValidationException>()
              .having((e) => e.message, 'message', 'Ошибка валидации')
              .having(
                (e) => e.errors['code'],
                'errors[code]',
                'Зал с таким кодом уже существует',
              )
              .having(
                (e) => e.errors['capacity'],
                'errors[capacity]',
                'Вместимость — положительное целое число',
              ),
        ),
      );
    });

    test('недоступность сервера превращается в NetworkException', () async {
      final adapter = _StubAdapter(
        (_) async => throw DioException(
          requestOptions: RequestOptions(path: '/halls'),
          type: DioExceptionType.connectionError,
          error: 'connection refused',
        ),
      );
      final repository = ApiHallRepository(_dioWith(adapter));

      await expectLater(
        repository.find(const HallQuery()),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message.contains('CORS'),
            'подсказка про CORS',
            isTrue,
          ),
        ),
      );
    });

    test('конфликт 409 превращается в ConflictException', () async {
      final adapter = _StubAdapter(
        (_) async => _fail(
          409,
          {'message': 'На эту дату в зале уже есть активное бронирование'},
        ),
      );
      final repository = ApiHallRepository(_dioWith(adapter));

      await expectLater(
        repository.find(const HallQuery()),
        throwsA(
          isA<ConflictException>().having(
            (e) => e.message,
            'message',
            'На эту дату в зале уже есть активное бронирование',
          ),
        ),
      );
    });

    test('неизвестная запись даёт NotFoundException', () async {
      final adapter = _StubAdapter(
        (_) async => _fail(404, {'message': 'Объект не найден'}),
      );
      final repository = ApiHallRepository(_dioWith(adapter));

      await expectLater(
        repository.findById(999),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('создание отправляет тело запроса на сервер', () async {
      final adapter = _StubAdapter((_) async => _ok(_page()));
      final repository = ApiHallRepository(_dioWith(adapter));

      await repository.create(
        const StudioHall(
          id: 0,
          name: 'Новый зал',
          code: 'z-09',
          style: 'Лофт',
          capacity: 10,
          hourlyRate: 3000,
          description: 'Описание',
        ),
      );

      expect(adapter.requests, hasLength(1));
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/halls');
      final body = request.data as Map<String, dynamic>;
      expect(body['name'], 'Новый зал');
      expect(body['code'], 'Z-09');
      expect(body['capacity'], 10);
      expect(body['description'], 'Описание');
    });

    test('физическое удаление передаёт признак hard', () async {
      final adapter = _StubAdapter((_) async => _ok(_page()));
      final repository = ApiHallRepository(_dioWith(adapter));

      await repository.hardDelete(7);

      expect(adapter.requests.single.method, 'DELETE');
      expect(adapter.requests.single.queryParameters['hard'], 'true');
    });

    test('токен отмены передаётся в запрос', () async {
      final adapter = _StubAdapter((_) async => _ok(_page()));
      final repository = ApiHallRepository(_dioWith(adapter));

      final token = CancelToken();
      await repository.find(const HallQuery(), cancelToken: token);

      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.cancelToken, same(token));
    });

    test('запрос справочника не отменяется запросом списка', () async {
      // Репозиторий один на приложение, а экранов несколько. Если бы токен
      // отмены хранился в репозитории, запрос справочника отменялся бы
      // запросом списка — и справочники оставались бы пустыми.
      final adapter = _StubAdapter((_) async => _ok(_page()));
      final repository = ApiHallRepository(_dioWith(adapter));

      final listToken = CancelToken();
      final catalogToken = CancelToken();

      final listFuture =
          repository.find(const HallQuery(), cancelToken: listToken);
      final catalogFuture =
          repository.find(const HallQuery(), cancelToken: catalogToken);

      await Future.wait([listFuture, catalogFuture]);

      // Ни один запрос не отменён.
      expect(adapter.requests, hasLength(2));
      expect(listToken.isCancelled, isFalse);
      expect(catalogToken.isCancelled, isFalse);
    });
  });

  group('исключения предметной области', () {
    test('guard не выпускает наружу DioException', () async {
      await expectLater(
        guard(() async {
          throw DioException(
            requestOptions: RequestOptions(path: '/halls'),
            type: DioExceptionType.connectionTimeout,
          );
        }),
        throwsA(isA<NetworkException>()),
      );
    });

    test('ошибка 401 даёт UnauthorizedException', () {
      final error = mapHttpError(401, {'message': 'Требуется аутентификация'});
      expect(error, isA<UnauthorizedException>());
      expect(error.message, 'Требуется аутентификация');
    });

    test('ошибка 403 даёт ForbiddenException', () {
      expect(mapHttpError(403, null), isA<ForbiddenException>());
    });

    test('ошибка 5xx даёт ServerException', () {
      expect(mapHttpError(500, null), isA<ServerException>());
    });

    test('пустой ответ не приводит к падению при разборе', () async {
      final adapter = _StubAdapter((_) async => _ok(const <String, dynamic>{}));
      final repository = ApiHallRepository(_dioWith(adapter));

      final PageResult<StudioHall> result =
          await repository.find(const HallQuery());

      expect(result.items, isEmpty);
      expect(result.page, 1);
      expect(result.total, 0);
    });
  });

  group('адрес сервера', () {
    test('задаётся параметром сборки, а не константой', () {
      // Значение по умолчанию указывает на учебный сервер.
      expect(apiBaseUrl,
          const String.fromEnvironment('API_BASE_URL', defaultValue: '/api'));
    });
  });

  group('автоматический повтор', () {
    test('сетевой сбой повторяется и запрос в конце проходит', () async {
      var attempts = 0;
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080/api'));
      dio.httpClientAdapter = _StubAdapter((options) async {
        attempts++;
        if (attempts < 3) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        }
        return _ok(_page());
      });

      final result = await withRetry(
        () => guard(
          () => dio.get<Map<String, dynamic>>(
            '/halls',
          ),
        ),
        baseDelay: const Duration(milliseconds: 1),
      );

      expect(attempts, 3);
      expect(result.data?['items'], isNotEmpty);
    });

    test('после трёх неудачных попыток ошибка пробрасывается дальше', () async {
      var attempts = 0;
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080/api'));
      dio.httpClientAdapter = _StubAdapter((options) async {
        attempts++;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      });

      await expectLater(
        withRetry(
          () => guard(() => dio.get<Map<String, dynamic>>('/halls')),
          baseDelay: const Duration(milliseconds: 1),
        ),
        throwsA(isA<NetworkException>()),
      );
      expect(attempts, 3);
    });

    test('ошибка 422 не повторяется', () async {
      var attempts = 0;
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080/api'));
      dio.httpClientAdapter = _StubAdapter((options) async {
        attempts++;
        return _fail(422, {
          'message': 'Ошибка валидации',
          'errors': {'code': 'Занято'},
        });
      });

      await expectLater(
        withRetry(
          () => guard(() => dio.get<Map<String, dynamic>>('/halls')),
          baseDelay: const Duration(milliseconds: 1),
        ),
        throwsA(isA<ValidationException>()),
      );
      // Повторять проверку данных бессмысленно: ответ не изменится.
      expect(attempts, 1);
    });
  });
}
