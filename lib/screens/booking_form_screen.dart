import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/form_outcome.dart';
import '../widgets/state_views.dart';
import '../core/validators.dart';
import '../models/booking.dart';
import '../models/photographer.dart';
import '../repositories/booking_repository.dart';
import '../state/catalog_notifier.dart';
import '../state/session.dart';
import '../widgets/dirty_guard.dart';
import '../widgets/entity_form.dart';

class BookingFormScreen extends StatefulWidget {
  final int? id;
  final bool selfService;
  final int? initialHallId;
  const BookingFormScreen(
      {super.key, this.id, this.selfService = false, this.initialHallId});
  bool get isEditing => id != null;
  @override
  State<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends State<BookingFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _entityFormKey = GlobalKey<EntityFormState>();
  Booking? _booking;

  final Map<String, String?> _serverErrors = {};
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  bool _dirty = false;
  int? _selectedHallId;
  int _revision = 0;
  String get _returnPath => widget.selfService ? '/my-bookings' : '/bookings';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final catalog = context.read<CatalogNotifier>();
      final repository = context.read<BookingRepository>();
      await catalog.load(force: true);
      if (catalog.error != null) throw StateError(catalog.error!);
      Booking? booking;
      if (widget.id != null) {
        booking = await repository.findById(widget.id!);
      }
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _selectedHallId = booking?.hallId ?? widget.initialHallId;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _loading = false;
      });
    }
  }

  List<FieldSpec> _fields(CatalogNotifier catalog) {
    final booking = _booking;
    return [
      if (!widget.selfService)
        FieldSpec(
          name: 'clientId',
          serverError: _serverErrors['clientId'],
          label: 'Клиент',
          type: FieldType.dropdown,
          initialValue: booking?.clientId,
          options: [
            for (final client in catalog.clients)
              DropdownEntry(client.id, '${client.name} — ${client.email}'),
          ],
          validators: [V.notNull('Выберите клиента')],
        ),
      FieldSpec(
        name: 'email',
        serverError: _serverErrors['email'],
        label: 'Почта для связи',
        type: FieldType.email,
        initialValue: booking?.email ??
            (widget.selfService
                ? context.read<SessionStore>().user?.email
                : null),
        validators: [V.required(), V.length(max: 254), V.email()],
        width: 320,
      ),
      FieldSpec(
        name: 'hallId',
        serverError: _serverErrors['hallId'],
        label: 'Зал студии',
        type: FieldType.dropdown,
        initialValue: _selectedHallId,
        hint: 'Связь «многие к одному»',
        options: [
          for (final hall in catalog.halls)
            DropdownEntry(hall.id,
                '${hall.name} — ${hall.hourlyRate} ₽/ч, до ${hall.capacity} чел.'),
        ],
        validators: [V.notNull('Выберите зал')],
        onChanged: (value) => _onHallChanged(value as int?),
      ),
      FieldSpec(
        name: 'photographerIds',
        serverError: _serverErrors['photographerIds'],
        label: 'Фотографы',
        type: FieldType.multiselect,
        initialValue: booking?.photographerIds ?? const [],
        hint:
            'Можно выбрать несколько фотографов, работающих в выбранном зале.',
        emptyMessage: 'Для этого зала пока не назначены фотографы. '
            'Выберите другой зал или обратитесь к администратору.',
        isWideList: true,
        options: [
          for (final photographer in _availablePhotographers(catalog))
            DropdownEntry(photographer.id, photographer.fullName),
        ],
        validators: [
          (value) => _availablePhotographers(catalog).isEmpty
              ? 'В выбранном зале нет назначенных фотографов'
              : value == null || value == ''
                  ? 'Выберите хотя бы одного фотографа'
                  : null
        ],
      ),
      FieldSpec(
        name: 'date',
        serverError: _serverErrors['date'],
        label: 'Дата съёмки (ГГГГ-ММ-ДД)',
        type: FieldType.date,
        initialValue: booking == null
            ? _dateText(DateTime.now().add(const Duration(days: 1)))
            : _dateText(booking.date),
        validators: [
          (value) => booking != null && value == _dateText(booking.date)
              ? V.date()(value)
              : V.notPast()(value)
        ],
        width: 300,
      ),
      if (!widget.selfService)
        FieldSpec(
          name: 'accessCode',
          serverError: _serverErrors['accessCode'],
          label: 'Код бронирования',
          type: FieldType.text,
          initialValue: booking?.accessCode,
          hint: 'Латиница, цифры и дефис, не короче 6 символов',
          validators: [V.required(), V.accessCode()],
          width: 320,
        ),
      FieldSpec(
        name: 'durationHours',
        serverError: _serverErrors['durationHours'],
        label: 'Длительность, ч',
        type: FieldType.number,
        initialValue: booking?.durationHours ?? 2,
        validators: [V.integer(min: 1, max: 24, label: 'Длительность')],
        width: 190,
      ),
      FieldSpec(
        name: 'participants',
        serverError: _serverErrors['participants'],
        label: 'Участников',
        type: FieldType.number,
        initialValue: booking?.participants ?? 1,
        validators: [V.positive(label: 'Количество участников')],
        width: 190,
      ),
      FieldSpec(
        name: 'shootingType',
        serverError: _serverErrors['shootingType'],
        label: 'Тип съёмки',
        type: FieldType.text,
        initialValue: booking?.shootingType ?? 'Портретная',
        validators: [V.required(), V.length(min: 3, max: 40)],
        width: 320,
      ),
      FieldSpec(
        name: 'comment',
        serverError: _serverErrors['comment'],
        label: 'Комментарий',
        type: FieldType.multiline,
        initialValue: booking?.comment ?? '',
        hint: 'Необязательно',
        validators: [V.length(max: 300)],
      ),
    ];
  }

  List<Photographer> _availablePhotographers(CatalogNotifier catalog) {
    final hallId = _selectedHallId;
    if (hallId == null) return catalog.photographers;
    return catalog.photographers
        .where((item) => item.hallIds.isEmpty || item.hallIds.contains(hallId))
        .toList();
  }

  void _onHallChanged(int? hallId) {
    final available = context
        .read<CatalogNotifier>()
        .photographers
        .where((item) =>
            hallId == null ||
            item.hallIds.isEmpty ||
            item.hallIds.contains(hallId))
        .map((item) => item.id)
        .toSet();
    final selected =
        _entityFormKey.currentState?.selection('photographerIds') ??
            _booking?.photographerIds ??
            const <int>[];
    final kept = selected.where(available.contains).toList();
    if (kept.length != selected.length) {
      _entityFormKey.currentState?.setValue('photographerIds', kept);
    }
    setState(() {
      _selectedHallId = hallId;
      _revision++;
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final form = _entityFormKey.currentState;
    if (form == null) return;
    final catalog = context.read<CatalogNotifier>();
    final self = widget.selfService ? context.read<SessionStore>().user : null;
    final clientId =
        widget.selfService ? (self?.clientId ?? 0) : form.number('clientId');
    final client =
        catalog.clients.where((item) => item.id == clientId).firstOrNull;
    if (_saving) return;

    setState(() {
      _saving = true;
      _serverErrors.clear();
      _revision++;
    });
    try {
      await context.read<BookingRepository>().save(Booking(
            id: _booking?.id ?? 0,
            clientName: self?.fullName ?? client?.name ?? 'Клиент #$clientId',
            clientId: clientId,
            email: form.string('email'),
            accessCode: form.string('accessCode'),
            hallId: form.number('hallId'),
            photographerIds: form.selection('photographerIds'),
            date: DateTime.tryParse(form.string('date')) ?? DateTime.now(),
            durationHours: form.number('durationHours'),
            participants: form.number('participants'),
            shootingType: form.string('shootingType'),
            comment: form.string('comment'),
            status: _booking?.status ?? 'active',
            deletedAt: _booking?.deletedAt,
          ));
      _dirty = false;
      await catalog.load(force: true);
      if (mounted) context.go(_returnPath);
    } on Object catch (error) {
      if (!mounted) return;
      final outcome = toFormOutcome(error);
      if (outcome is FormInvalid) {
        setState(() {
          _serverErrors
            ..clear()
            ..addAll(outcome.errors);
          _revision++;
        });
        _formKey.currentState?.validate();
      } else {
        showFormError(context, outcome);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _dateText(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  void _cancel() {
    context.go(_returnPath);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogNotifier>();
    return DirtyGuard(
      isDirty: () => _dirty,
      fallbackLocation: _returnPath,
      message:
          'Есть несохранённые изменения в бронировании. Выйти без сохранения?',
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => context.go(_returnPath)),
          title: Text(widget.isEditing
              ? 'Редактирование бронирования'
              : 'Новое бронирование'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? ErrorView(message: _loadError!, onRetry: _load)
                : widget.id != null && _booking == null
                    ? const Center(child: Text('Запись не найдена'))
                    : EntityForm(
                        key: _entityFormKey,
                        fields: _fields(catalog),
                        formKey: _formKey,
                        saving: _saving,
                        saveLabel: widget.isEditing
                            ? 'Сохранить изменения'
                            : 'Создать бронирование',
                        onSubmit: _save,
                        onCancel: _cancel,
                        onChanged: () => setState(() => _dirty = true),
                        rebuildToken: _revision,
                      ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
