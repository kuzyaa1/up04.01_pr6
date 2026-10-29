import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../state/session.dart';
import '../widgets/state_views.dart';
import '../models/booking.dart';
import '../models/client.dart';
import '../models/equipment.dart';
import '../models/photographer.dart';
import '../models/studio_hall.dart';
import '../repositories/booking_repository.dart';
import '../repositories/client_repository.dart';
import '../repositories/equipment_repository.dart';
import '../repositories/hall_repository.dart';
import '../repositories/photographer_repository.dart';

class EntityDetailScreen extends StatefulWidget {
  final String collection;
  final int id;
  const EntityDetailScreen(
      {super.key, required this.collection, required this.id});
  @override
  State<EntityDetailScreen> createState() => _EntityDetailScreenState();
}

class _EntityDetailScreenState extends State<EntityDetailScreen> {
  late Future<Map<String, String>?> _details = _load();
  Future<Map<String, String>?> _load() async {
    final halls = context.read<HallRepository>();
    final clients = context.read<ClientRepository>();
    final photographers = context.read<PhotographerRepository>();
    final equipment = context.read<EquipmentRepository>();
    final bookings = context.read<BookingRepository>();
    final Object? record = switch (widget.collection) {
      'halls' => await halls.findById(widget.id),
      'clients' => await clients.findById(widget.id),
      'photographers' => await photographers.findById(widget.id),
      'equipment' => await equipment.findById(widget.id),
      'bookings' => await bookings.findById(widget.id),
      _ => null,
    };
    if (record == null) return null;
    final hallNames = {
      for (final h in await halls.all(includeDeleted: true)) h.id: h.name
    };
    final photographerNames = {
      for (final p in await photographers.all(includeDeleted: true))
        p.id: p.fullName
    };
    final equipmentNames = {
      for (final e in await equipment.all(includeDeleted: true)) e.id: e.name
    };
    String names(List<int> ids, Map<int, String> options) =>
        ids.map((id) => options[id] ?? '#$id').join(', ');
    final rows = <String, String>{'Номер записи': '${widget.id}'};
    switch (record) {
      case Booking b:
        rows.addAll({
          'Клиент': b.clientName,
          'Почта для связи': b.email,
          'Код бронирования': b.accessCode,
          'Зал': hallNames[b.hallId] ?? '#${b.hallId}',
          'Фотографы': names(b.photographerIds, photographerNames),
          'Дата съёмки': b.date.toIso8601String().split('T').first,
          'Длительность': '${b.durationHours} ч',
          'Участников': '${b.participants}',
          'Тип съёмки': b.shootingType,
          'Комментарий': b.comment,
          'Состояние': b.isDeleted ? 'Удалено' : 'Активно'
        });
      case Client c:
        rows.addAll({
          'Имя клиента': c.name,
          'Email': c.email,
          'Телефон': c.phone,
          'Тип клиента': c.clientType,
          'Компания': c.company,
          'Номер абонемента': c.cardNumber,
          'Дата выдачи': c.cardIssuedAt,
          'Действует до': c.cardExpiresAt,
          'Пожелания и заметки': c.notes,
          'Состояние': c.isDeleted ? 'Удалено' : 'Активно'
        });
      case StudioHall h:
        rows.addAll({
          'Название зала': h.name,
          'Код зала': h.code,
          'Стиль': h.style,
          'Вместимость': '${h.capacity} чел.',
          'Цена за час': '${h.hourlyRate} ₽',
          'Оборудование': names(h.equipmentIds, equipmentNames),
          'Бронирования': h.bookingIds.map((id) => '#$id').join(', '),
          'Состояние': h.isDeleted ? 'Удалено' : 'Активно'
        });
      case Photographer p:
        rows.addAll({
          'Фотограф': p.fullName,
          'Специализация': p.specialization,
          'Стаж': '${p.experienceYears} лет',
          'Ставка за час': '${p.hourlyRate} ₽',
          'Работает в залах': names(p.hallIds, hallNames),
          'О себе': p.bio,
          'Бронирования': p.bookingIds.map((id) => '#$id').join(', '),
          'Состояние': p.isDeleted ? 'Удалено' : 'Активно'
        });
      case Equipment e:
        rows.addAll({
          'Название': e.name,
          'Категория': e.category,
          'Производитель': e.manufacturer,
          'Зал': hallNames[e.hallId] ?? '#${e.hallId}',
          'Количество': '${e.quantity} шт.',
          'Цена за день': '${e.pricePerDay} ₽',
          'Состояние': e.isDeleted ? 'Удалено' : 'Активно'
        });
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Карточка записи'),
            leading: BackButton(
                onPressed: () => context.go('/${widget.collection}'))),
        body: FutureBuilder<Map<String, String>?>(
            future: _details,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return ErrorView(
                  message: 'Не удалось загрузить запись. Проверьте соединение.',
                  onRetry: () => setState(() => _details = _load()),
                );
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data;
              if (rows == null) {
                return const Center(child: Text('Запись не найдена'));
              }
              return Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            for (final entry in rows.entries)
                              ListTile(
                                  title: Text(entry.key),
                                  subtitle: SelectableText(
                                      entry.value.isEmpty ? '—' : entry.value)),
                            const SizedBox(height: 16),
                            if (context
                                .watch<SessionStore>()
                                .permissions
                                .canManageEntity(widget.collection))
                              FilledButton.icon(
                                  onPressed: () => context.go(
                                      '/${widget.collection}/${widget.id}/edit'),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Редактировать')),
                          ])));
            }),
      );
}
