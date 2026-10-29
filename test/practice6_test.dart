import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:photo_studio_portal/core/permissions.dart';
import 'package:photo_studio_portal/core/validators.dart';
import 'package:photo_studio_portal/models/studio_hall.dart';
import 'package:photo_studio_portal/models/hall_query.dart';
import 'package:photo_studio_portal/models/page_result.dart';
import 'package:photo_studio_portal/models/booking_query.dart';
import 'package:photo_studio_portal/models/client_query.dart';
import 'package:photo_studio_portal/models/equipment_query.dart';
import 'package:photo_studio_portal/models/photographer_query.dart';
import 'package:photo_studio_portal/repositories/photo_studio_repositories.dart';
import 'package:photo_studio_portal/repositories/in_memory_hall_repository.dart';
import 'package:photo_studio_portal/repositories/hall_repository.dart';
import 'package:photo_studio_portal/repositories/client_repository.dart';
import 'package:photo_studio_portal/repositories/photographer_repository.dart';
import 'package:photo_studio_portal/repositories/equipment_repository.dart';
import 'package:photo_studio_portal/repositories/booking_repository.dart';
import 'package:photo_studio_portal/screens/home_screen.dart';
import 'package:photo_studio_portal/screens/hall_list_screen.dart';
import 'package:photo_studio_portal/screens/client_list_screen.dart';
import 'package:photo_studio_portal/screens/booking_list_screen.dart';
import 'package:photo_studio_portal/screens/equipment_list_screen.dart';
import 'package:photo_studio_portal/screens/photographer_list_screen.dart';
import 'package:photo_studio_portal/screens/hall_form_screen.dart';
import 'package:photo_studio_portal/screens/client_form_screen.dart';
import 'package:photo_studio_portal/screens/booking_form_screen.dart';
import 'package:photo_studio_portal/screens/equipment_form_screen.dart';
import 'package:photo_studio_portal/screens/photographer_form_screen.dart';
import 'package:photo_studio_portal/screens/login_screen.dart';
import 'package:photo_studio_portal/screens/register_screen.dart';
import 'package:photo_studio_portal/state/catalog_notifier.dart';
import 'package:photo_studio_portal/state/catalog_notifiers.dart';
import 'package:photo_studio_portal/state/list_notifiers.dart';
import 'package:photo_studio_portal/state/session.dart';
import 'package:photo_studio_portal/widgets/entity_table.dart';
import 'package:photo_studio_portal/widgets/responsive.dart';
import 'package:photo_studio_portal/widgets/state_views.dart';

class ControlledHalls extends InMemoryHallRepository {
  ControlledHalls(super.prefs);
  Completer<PageResult<StudioHall>>? pending;
  bool offline = false;
  @override
  Future<PageResult<StudioHall>> find(HallQuery query,
      {CancelToken? cancelToken}) {
    if (pending != null) return pending!.future;
    if (offline) return Future.error(Exception('Нет связи с сервером'));
    return super.find(query, cancelToken: cancelToken);
  }
}

Future<void> mount(WidgetTester tester, Widget child,
    {HallRepository? hallRepository, String role = 'admin'}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final repos = PhotoStudioRepositories(prefs);
  final session = SessionStore()
    ..setUser(AppUser(
        id: 1,
        username: role,
        fullName: 'Пользователь фотостудии',
        email: 'demo@example.com',
        role: role));
  final halls = hallRepository ?? repos.halls;
  await tester.pumpWidget(MultiProvider(providers: [
    ChangeNotifierProvider(create: (_) => session),
    Provider<HallRepository>.value(value: halls),
    Provider<ClientRepository>.value(value: repos.clients),
    Provider<BookingRepository>.value(value: repos.bookings),
    Provider<PhotographerRepository>.value(value: repos.photographers),
    Provider<EquipmentRepository>.value(value: repos.equipment),
    ChangeNotifierProvider(create: (_) => HallListNotifier(halls)),
    ChangeNotifierProvider(create: (_) => ClientListNotifier(repos.clients)),
    ChangeNotifierProvider(create: (_) => BookingListNotifier(repos.bookings)),
    ChangeNotifierProvider(
        create: (_) => EquipmentListNotifier(repos.equipment)),
    ChangeNotifierProvider(
        create: (_) => PhotographerListNotifier(repos.photographers)),
    ChangeNotifierProvider(
        create: (_) => CatalogNotifier(
            halls: repos.halls,
            photographers: repos.photographers,
            clients: repos.clients,
            bookings: repos.bookings,
            equipment: repos.equipment)
          ..load()),
  ], child: MaterialApp(home: child)));
}

void main() {
  test('пустое название зала отклоняется',
      () => expect(V.required()('  '), isNotNull));
  test('название зала принимается', () => expect(V.required()('Лофт'), isNull));
  test('вместимость должна быть положительной',
      () => expect(V.positive()('0'), isNotNull));
  test('почта клиента проверяется',
      () => expect(V.email()('photo@studio.ru'), isNull));
  test('неполный JSON зала не вызывает исключение', () {
    final hall = StudioHall.fromJson({'id': 12});
    expect(hall.name, isEmpty);
    expect(hall.equipmentIds, isEmpty);
  });
  test('числа из JSON преобразуются безопасно', () {
    expect(StudioHall.fromJson({'id': '12', 'capacity': '6'}).capacity, 6);
  });
  test(
      'менеджер не изменяет залы',
      () => expect(const Permissions(UserRole.manager).canManageEntity('halls'),
          isFalse));
  test('клиент может создать свою бронь',
      () => expect(const Permissions(UserRole.client).canBookOwn, isTrue));

  final screens = <String, Widget>{
    'главная': const HomeScreen(),
    'залы': const HallListScreen(query: HallQuery()),
    'клиенты': const ClientListScreen(query: ClientQuery()),
    'брони': const BookingListScreen(query: BookingQuery()),
    'оборудование': const EquipmentListScreen(query: EquipmentQuery()),
    'фотографы': const PhotographerListScreen(query: PhotographerQuery()),
    'форма зала': const HallFormScreen(),
    'форма клиента': const ClientFormScreen(),
    'форма брони': const BookingFormScreen(),
    'форма оборудования': const EquipmentFormScreen(),
    'форма фотографа': const PhotographerFormScreen(),
    'вход': const LoginScreen(),
    'регистрация': const RegisterScreen(),
  };
  for (final width in [360.0, 768.0, 1280.0, 1920.0]) {
    for (final screen in screens.entries) {
      testWidgets('${screen.key}: ширина $width без переполнений',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await mount(tester, screen.value);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (screen.key == 'залы') {
          expect(find.byType(EntityTable<StudioHall>),
              width >= 1000 ? findsOneWidget : findsNothing);
          expect(find.byType(NavigationBar),
              width == 360 ? findsOneWidget : findsNothing);
          expect(find.byType(NavigationRail),
              width >= 768 ? findsOneWidget : findsNothing);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  testWidgets('изменение ширины сохраняет выбранную запись', (tester) async {
    await mount(tester, const HallListScreen(query: HallQuery()));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(HallListScreen));
    context.read<HallListNotifier>().toggle(1);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    expect(context.read<HallListNotifier>().selected, contains(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('виден индикатор незавершённого запроса', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = ControlledHalls(await SharedPreferences.getInstance())
      ..pending = Completer();
    await mount(tester, const HallListScreen(query: HallQuery()),
        hallRepository: repo);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repo.pending!.complete(PageResult.empty());
    await tester.pumpAndSettle();
  });
  testWidgets('пустой ответ показывает пояснение', (tester) async {
    await mount(tester,
        const HallListScreen(query: HallQuery(search: 'несуществующийзал')));
    await tester.pumpAndSettle();
    expect(find.byType(EmptyView), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
  testWidgets('ошибка сети и повтор восстанавливают список без перезагрузки',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = ControlledHalls(await SharedPreferences.getInstance())
      ..offline = true;
    await mount(tester, const HallListScreen(query: HallQuery()),
        hallRepository: repo);
    await tester.pumpAndSettle();
    expect(find.byType(ErrorView), findsOneWidget);
    repo.offline = false;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorView), findsNothing);
    expect(find.byType(ResponsiveRecordTile), findsWidgets);
  });
  testWidgets('пустая форма входа не отправляется', (tester) async {
    await mount(tester, const LoginScreen());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
    await tester.pump();
    expect(find.text('Укажите пароль'), findsOneWidget);
  });
  testWidgets('клиент не видит создание зала', (tester) async {
    await mount(tester, const HallListScreen(query: HallQuery()),
        role: 'client');
    await tester.pumpAndSettle();
    expect(find.text('Новый зал'), findsNothing);
    expect(find.byTooltip('Редактировать'), findsNothing);
    expect(find.byTooltip('Забронировать зал'), findsWidgets);
  });
}
