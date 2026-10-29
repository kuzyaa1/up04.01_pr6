import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_studio_portal/data/seed_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:photo_studio_portal/models/booking.dart';
import 'package:photo_studio_portal/repositories/booking_repository.dart';
import 'package:photo_studio_portal/repositories/persistent_booking_repository.dart';
import 'package:photo_studio_portal/repositories/photo_studio_repositories.dart';
import 'package:photo_studio_portal/screens/booking_form_screen.dart';
import 'package:photo_studio_portal/state/catalog_notifier.dart';
import 'package:photo_studio_portal/state/session.dart';
import 'package:photo_studio_portal/widgets/entity_form.dart';

class CapturingBookings extends PersistentBookingRepository {
  CapturingBookings(super.prefs);
  Booking? submitted;
  @override
  Future<Booking> save(Booking booking) async {
    submitted = booking;
    return booking;
  }
}

void main() {
  for (final hallId in [1, 17]) {
    testWidgets('клиент выбирает фотографа и бронирует зал $hallId',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final local = PhotoStudioRepositories(prefs);
      final bookings = CapturingBookings(prefs);
      final session = SessionStore()
        ..setUser(const AppUser(
            id: 4,
            clientId: 1,
            username: 'client',
            fullName: 'Мой профиль',
            email: 'own@example.com',
            role: 'client'));
      final catalog = CatalogNotifier(
          halls: local.halls,
          photographers: local.photographers,
          clients: local.clients,
          bookings: local.bookings,
          equipment: local.equipment,
          includeClients: false);
      await catalog.load();
      final router = GoRouter(initialLocation: '/new', routes: [
        GoRoute(
            path: '/new',
            builder: (_, __) =>
                BookingFormScreen(selfService: true, initialHallId: hallId)),
        GoRoute(
            path: '/my-bookings',
            builder: (_, __) => const Scaffold(
                body: Text('Мои бронирования после сохранения'))),
      ]);
      await tester.pumpWidget(MultiProvider(providers: [
        ChangeNotifierProvider<SessionStore>.value(value: session),
        ChangeNotifierProvider<CatalogNotifier>.value(value: catalog),
        Provider<BookingRepository>.value(value: bookings),
      ], child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();
      final form = tester.state<EntityFormState>(find.byType(EntityForm));
      final specs = tester.widget<EntityForm>(find.byType(EntityForm)).fields;
      expect(specs.any((f) => f.name == 'clientId'), isFalse);
      expect(specs.any((f) => f.name == 'accessCode'), isFalse);
      expect(form.number('hallId'), hallId);
      expect(form.string('email'), 'own@example.com');
      final photographer = catalog.photographers
          .firstWhere((p) => p.hallIds.isEmpty || p.hallIds.contains(hallId));
      final chip = find.widgetWithText(FilterChip, photographer.fullName);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(form.selection('photographerIds'), [photographer.id]);
      form.setValue('date', '2099-01-15');
      await tester.pumpAndSettle();
      final submit = find.widgetWithText(FilledButton, 'Создать бронирование');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(bookings.submitted, isNotNull);
      expect(bookings.submitted!.clientId, 1);
      expect(bookings.submitted!.clientName, 'Мой профиль');
      expect(bookings.submitted!.hallId, hallId);
      expect(bookings.submitted!.photographerIds, [photographer.id]);
      expect(bookings.submitted!.accessCode, isEmpty);
      expect(router.routeInformationProvider.value.uri.path, '/my-bookings');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      session.dispose();
      catalog.dispose();
    });
  }
  test('каждый демонстрационный зал имеет назначенного фотографа', () {
    for (final hall in seedHalls) {
      expect(
          seedPhotographers
              .any((p) => p.hallIds.isEmpty || p.hallIds.contains(hall.id)),
          isTrue,
          reason: hall.name);
    }
    final fixtures =
        jsonDecode(File('server/seed-pr3.json').readAsStringSync()) as Map;
    for (final hall in fixtures['halls'] as List) {
      expect(
          (fixtures['photographers'] as List).any((p) =>
              (p['hallIds'] as List).isEmpty ||
              (p['hallIds'] as List).contains(hall['id'])),
          isTrue,
          reason: '${hall['name']}');
    }
  });
  testWidgets('пустой выбор имеет пояснение и не перекрывает подпись',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EntityForm(
      formKey: GlobalKey<FormState>(),
      fields: const [
        FieldSpec(
            name: 'photographerIds',
            label: 'Фотографы',
            type: FieldType.multiselect,
            emptyMessage: 'Для этого зала пока не назначены фотографы')
      ],
      onSubmit: () {},
      onCancel: () {},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Для этого зала пока не назначены фотографы'),
        findsOneWidget);
    final decoration =
        tester.widget<InputDecorator>(find.byType(InputDecorator));
    expect(decoration.decoration.floatingLabelBehavior,
        FloatingLabelBehavior.always);
    expect(tester.takeException(), isNull);
  });
}
