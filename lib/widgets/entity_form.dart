import 'package:flutter/material.dart';
import '../core/validators.dart';

enum FieldType {
  text,
  multiline,
  number,
  email,
  phone,
  date,
  dropdown,
  dropdownText,
  multiselect,
  switchField,
}

@immutable
class FieldSpec {
  final String name;
  final String label;
  final FieldType type;
  final Object? initialValue;
  final String? hint;
  final List<Validator> validators;
  final String? serverError;
  final List<DropdownEntry> options;
  final List<TextDropdownEntry> textOptions;
  final String? groupTitle;
  final double? width;

  final bool isWideList;
  final void Function(Object? value)? onChanged;
  const FieldSpec({
    required this.name,
    required this.label,
    this.type = FieldType.text,
    this.initialValue,
    this.hint,
    this.validators = const [],
    this.serverError,
    this.options = const [],
    this.textOptions = const [],
    this.groupTitle,
    this.width,
    this.isWideList = false,
    this.onChanged,
  });
  FieldSpec copyWith({Object? initialValue, String? serverError}) => FieldSpec(
        name: name,
        label: label,
        type: type,
        initialValue: initialValue ?? this.initialValue,
        hint: hint,
        validators: validators,
        serverError: serverError,
        options: options,
        textOptions: textOptions,
        groupTitle: groupTitle,
        width: width,
        isWideList: isWideList,
        onChanged: onChanged,
      );
}

@immutable
class DropdownEntry {
  final int value;
  final String label;
  const DropdownEntry(this.value, this.label);
}

@immutable
class TextDropdownEntry {
  final String value;
  final String label;
  const TextDropdownEntry(this.value, this.label);
}

class EntityForm extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final List<FieldSpec> fields;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;
  final String saveLabel;
  final String cancelLabel;
  final VoidCallback? onChanged;
  final VoidCallback? onRequestRebuild;
  final Map<String, String?> serverErrors;
  final int rebuildToken;
  final bool saving;
  const EntityForm({
    super.key,
    required this.formKey,
    required this.fields,
    required this.onSubmit,
    required this.onCancel,
    this.saveLabel = 'Сохранить',
    this.cancelLabel = 'Отмена',
    this.onChanged,
    this.onRequestRebuild,
    this.serverErrors = const {},
    this.rebuildToken = 0,
    this.saving = false,
  });
  @override
  State<EntityForm> createState() => EntityFormState();
}

class EntityFormState extends State<EntityForm> {
  final Map<String, Object?> _values = {};
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, GlobalKey<FormFieldState<Object?>>> _fieldKeys = {};
  final Set<String> _multiselectVisible = {};
  final Map<String, Object?> _rejectedValues = {};
  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      _initField(field);
    }
  }

  @override
  void didUpdateWidget(covariant EntityForm old) {
    super.didUpdateWidget(old);
    if (identical(old.fields, widget.fields) &&
        old.rebuildToken == widget.rebuildToken) {
      return;
    }
    final names = widget.fields.map((field) => field.name).toSet();
    for (final name in _controllers.keys.toList()) {
      if (names.contains(name)) continue;
      _controllers.remove(name)?.dispose();
      _values.remove(name);
      _fieldKeys.remove(name);
      _multiselectVisible.remove(name);
    }
    for (final field in widget.fields) {
      _initField(field);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _initField(FieldSpec field, {Object? fallback}) {
    if (_controllers.containsKey(field.name) ||
        _values.containsKey(field.name)) {
      return;
    }
    final initial = fallback ?? field.initialValue;
    if (field.type == FieldType.number) {
      final text = initial == null ? '' : '$initial';
      _controllers[field.name] = TextEditingController(text: text);
      _values[field.name] = int.tryParse(text) ?? 0;
    } else if (field.type == FieldType.text ||
        field.type == FieldType.multiline ||
        field.type == FieldType.email ||
        field.type == FieldType.phone ||
        field.type == FieldType.date) {
      _controllers[field.name] =
          TextEditingController(text: initial == null ? '' : '$initial');
      _values[field.name] = initial ?? '';
    } else if (field.type == FieldType.dropdownText) {
      _values[field.name] = initial as String?;
    } else if (field.type == FieldType.multiselect) {
      _values[field.name] =
          List<int>.from((initial as List?)?.cast<int>() ?? const []);
      _multiselectVisible.add(field.name);
    } else {
      _values[field.name] = initial;
    }
  }

  Object? value(String name) => _values[name];
  String text(String name) {
    final controller = _controllers[name];
    if (controller != null) return controller.text;
    final value = _values[name];
    if (value == null) return '';
    return '$value';
  }

  int number(String name) {
    final controller = _controllers[name];
    if (controller != null) return int.tryParse(controller.text.trim()) ?? 0;
    final value = _values[name];
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }

  List<int> selection(String name) =>
      List<int>.from((_values[name] as List?)?.cast<int>() ?? const []);
  String string(String name) => text(name).trim();
  void setValue(String name, Object? value) {
    setState(() {
      _values[name] = value;
      final controller = _controllers[name];
      if (controller != null) controller.text = value == null ? '' : '$value';
    });
    _updateFieldState(name, value);
  }

  void _updateFieldState(String name, Object? value) {
    final state = _fieldKeys[name]?.currentState;
    if (state is FormFieldState<List<int>>) {
      state.didChange(List<int>.from(value as List));
    }
  }

  FieldType fieldType(String name) => widget.fields
      .firstWhere((f) => f.name == name, orElse: () => widget.fields.first)
      .type;
  void _report(String name, Object? value, {bool fromController = false}) {
    setState(() {
      _values[name] = value;
      if (fromController) {
        final controller = _controllers[name];
        if (controller != null) controller.text = value == null ? '' : '$value';
      }
    });
    widget.onChanged?.call();
    _updateFieldState(name, value);
    widget.formKey.currentState?.validate();
  }

  void _clearServerError(String name) {
    if (widget.fields.any((f) => f.name == name && f.serverError != null)) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: widget.formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in _groupedFields()) ...[
                    _buildGroup(entry.key, entry.value),
                    const SizedBox(height: 16),
                  ],
                  const SizedBox(height: 12),
                  EntityFormActions(
                    onCancel: widget.onCancel,
                    onSave: widget.onSubmit,
                    saveLabel: widget.saveLabel,
                    cancelLabel: widget.cancelLabel,
                    saving: widget.saving,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  List<MapEntry<String?, List<FieldSpec>>> _groupedFields() {
    final groups = <String?, List<FieldSpec>>{};
    final order = <String?>[];
    for (final field in widget.fields) {
      if (!groups.containsKey(field.groupTitle)) {
        groups[field.groupTitle] = [];
        order.add(field.groupTitle);
      }
      groups[field.groupTitle]!.add(field);
    }
    return [
      for (final key in order)
        MapEntry<String?, List<FieldSpec>>(key, groups[key]!)
    ];
  }

  Widget _buildGroup(String? title, List<FieldSpec> fields) {
    final children = _buildRows(fields);
    if (title == null) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final child in children) child]);
    }
    return _FieldGroup(
      title: title,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  List<Widget> _buildRows(List<FieldSpec> fields) {
    if (fields.any((f) => f.type == FieldType.multiselect)) {
      final result = <Widget>[];
      final inline = <FieldSpec>[];
      void flushInline() {
        if (inline.isEmpty) return;
        result.add(_buildRow(List<FieldSpec>.of(inline)));
        result.add(const SizedBox(height: 16));
        inline.clear();
      }

      for (final field in fields) {
        if (field.width == null) {
          flushInline();
          result.add(_buildField(field));
          result.add(const SizedBox(height: 16));
        } else {
          inline.add(field);
        }
      }
      flushInline();
      if (result.isNotEmpty && result.last is SizedBox) result.removeLast();
      return result;
    }
    return [_buildRow(fields)];
  }

  Widget _buildRow(List<FieldSpec> fields) => LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final field in fields)
              SizedBox(
                width: (field.width ?? constraints.maxWidth)
                    .clamp(0.0, constraints.maxWidth),
                child: _buildField(field),
              ),
          ],
        ),
      );
  Widget _buildField(FieldSpec field) {
    final key = _fieldKeys.putIfAbsent(
        field.name, GlobalKey<FormFieldState<Object?>>.new);
    switch (field.type) {
      case FieldType.text:
      case FieldType.email:
      case FieldType.phone:
      case FieldType.date:
        return _textField(field, key);
      case FieldType.multiline:
        return _multilineField(field, key);
      case FieldType.number:
        return _numberField(field, key);
      case FieldType.dropdown:
        return _dropdownField(field, key);
      case FieldType.dropdownText:
        return _textDropdownField(field, key);
      case FieldType.multiselect:
        return _multiselectField(field, key);
      case FieldType.switchField:
        return _switchField(field);
    }
  }

  InputDecoration _decoration(FieldSpec field, {String? errorText}) =>
      InputDecoration(
        labelText: field.label,
        hintText: field.hint,
        border: const OutlineInputBorder(),
        errorText: errorText,
        errorMaxLines: 2,
      );
  String? _validate(FieldSpec field, String? value) {
    for (final validator in field.validators) {
      final error = validator(value);
      if (error != null) return error;
    }
    return _errorOf(field.name);
  }

  Widget _textField(FieldSpec field, GlobalKey<FormFieldState<Object?>> key) {
    final controller = _controllers[field.name]!;
    return TextFormField(
      controller: controller,
      key: key,
      keyboardType: switch (field.type) {
        FieldType.email => TextInputType.emailAddress,
        FieldType.phone => TextInputType.phone,
        _ => TextInputType.text,
      },
      decoration: _decoration(field, errorText: _errorOf(field.name)),
      validator: (value) => _validate(field, value),
      onChanged: (value) {
        _values[field.name] = value;
        _clearServerError(field.name);
        field.onChanged?.call(value);
        widget.onChanged?.call();
      },
    );
  }

  Widget _multilineField(
      FieldSpec field, GlobalKey<FormFieldState<Object?>> key) {
    final controller = _controllers[field.name]!;
    return TextFormField(
      controller: controller,
      key: key,
      maxLines: 3,
      minLines: 2,
      decoration: _decoration(field, errorText: _errorOf(field.name)),
      validator: (value) => _validate(field, value),
      onChanged: (value) {
        _values[field.name] = value;
        _clearServerError(field.name);
        field.onChanged?.call(value);
        widget.onChanged?.call();
      },
    );
  }

  Widget _numberField(FieldSpec field, GlobalKey<FormFieldState<Object?>> key) {
    final controller = _controllers[field.name]!;
    return TextFormField(
      controller: controller,
      key: key,
      keyboardType: TextInputType.number,
      decoration: _decoration(field, errorText: _errorOf(field.name)),
      validator: (value) => _validate(field, value),
      onChanged: (value) {
        _values[field.name] = int.tryParse(value.trim()) ?? 0;
        _clearServerError(field.name);
        field.onChanged?.call(value);
        widget.onChanged?.call();
      },
    );
  }

  Widget _dropdownField(
      FieldSpec field, GlobalKey<FormFieldState<Object?>> key) {
    final current = _values[field.name] as int?;
    final valid =
        current != null && field.options.any((o) => o.value == current)
            ? current
            : null;
    return DropdownButtonFormField<int>(
      key: key,
      value: valid,
      isExpanded: true,
      decoration: _decoration(field, errorText: _errorOf(field.name)),
      items: [
        for (final option in field.options)
          DropdownMenuItem(
            value: option.value,
            child: Text(option.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) {
        _values[field.name] = value;
        _clearServerError(field.name);
        field.onChanged?.call(value);
        widget.onChanged?.call();
      },
      validator: (value) => _validate(field, value == null ? '' : '$value'),
    );
  }

  Widget _textDropdownField(
      FieldSpec field, GlobalKey<FormFieldState<Object?>> key) {
    final current = _values[field.name] as String?;
    final valid = current != null &&
            field.textOptions.any((option) => option.value == current)
        ? current
        : null;
    return DropdownButtonFormField<String>(
      key: key,
      value: valid,
      isExpanded: true,
      decoration: _decoration(field, errorText: _errorOf(field.name)),
      items: [
        for (final option in field.textOptions)
          DropdownMenuItem(
            value: option.value,
            child: Text(option.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) {
        _values[field.name] = value;
        _clearServerError(field.name);
        field.onChanged?.call(value);
        widget.onChanged?.call();
      },
      validator: (value) => _validate(field, value ?? ''),
    );
  }

  Widget _multiselectField(
      FieldSpec field, GlobalKey<FormFieldState<Object?>> key) {
    final selected = selection(field.name);
    final expanded = _multiselectVisible.contains(field.name) ||
        field.isWideList ||
        _errorOf(field.name) != null;

    // Список доступных значений может быть длинным: показываем его
    // целиком только по запросу пользователя, иначе поле занимает
    // весь экран и следующие поля уезжают вниз.
    final options = field.options;
    const previewLimit = 8;
    final visibleOptions =
        expanded ? options : options.take(previewLimit).toList();
    final hiddenCount = options.length - visibleOptions.length;

    // Чипы доступных значений рисуются всегда: иначе выбрать ничего
    // невозможно — а множественный выбор без вариантов не работает.
    final chips = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in visibleOptions)
          FilterChip(
            label: Text(option.label),
            selected: selected.contains(option.value),
            onSelected: (_) {
              final next = [...selected];
              next.contains(option.value)
                  ? next.remove(option.value)
                  : next.add(option.value);
              _report(field.name, next);
            },
          ),
        if (hiddenCount > 0)
          ActionChip(
            label: Text('ещё $hiddenCount'),
            onPressed: () =>
                setState(() => _multiselectVisible.add(field.name)),
          ),
      ],
    );

    return FormField<List<int>>(
      key: key,
      initialValue: selected,
      validator: (value) {
        for (final validator in field.validators) {
          final error = validator(value?.isEmpty ?? true ? '' : 'ok');
          if (error != null) return error;
        }
        return _errorOf(field.name);
      },
      builder: (state) => InputDecorator(
        decoration: InputDecoration(
          labelText: field.label,
          helperText: field.hint,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          errorText: state.errorText ?? _errorOf(field.name),
          errorMaxLines: 2,
        ),
        isEmpty: selected.isEmpty,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Выбранные значения показываются сверху, чтобы их было видно
            // при свёрнутом списке вариантов.
            if (selected.isNotEmpty && !expanded)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final id in selected.take(4))
                      Builder(builder: (context) {
                        final option = field.options
                            .where((o) => o.value == id)
                            .firstOrNull;
                        return InputChip(
                          label: Text(option?.label ?? '#$id'),
                          onDeleted: () {
                            final next = selection(field.name)..remove(id);
                            _report(field.name, next);
                          },
                        );
                      }),
                    if (selected.length > 4)
                      ActionChip(
                        label: Text('ещё ${selected.length - 4}'),
                        onPressed: () =>
                            setState(() => _multiselectVisible.add(field.name)),
                      ),
                  ],
                ),
              ),
            chips,
            if (options.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('Нет доступных значений',
                    style: TextStyle(
                        color: Theme.of(context).hintColor, fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _switchField(FieldSpec field) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(field.label),
        value: _values[field.name] == true,
        onChanged: (value) => _report(field.name, value),
      );
  void rejectValue(String name) {
    _rejectedValues[name] = text(name);
  }

  String? _errorOf(String name) {
    for (final field in widget.fields) {
      if (field.name != name || field.serverError == null) continue;
      _rejectedValues.putIfAbsent(name, () => text(name));
      return _rejectedValues[name] == text(name) ? field.serverError : null;
    }
    _rejectedValues.remove(name);
    return null;
  }
}

class _FieldGroup extends StatelessWidget {
  final String title;
  final Widget child;
  const _FieldGroup({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.confirmation_number_outlined,
                  size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
}

class EntityFormActions extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final String saveLabel;
  final String cancelLabel;

  /// Идёт ли отправка формы: кнопка сохранения блокируется,
  /// чтобы повторное нажатие не создало вторую запись.
  final bool saving;

  const EntityFormActions({
    super.key,
    required this.onCancel,
    required this.onSave,
    this.saveLabel = 'Сохранить',
    this.cancelLabel = 'Отмена',
    this.saving = false,
  });

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.end,
        spacing: 12,
        children: [
          TextButton(onPressed: onCancel, child: Text(cancelLabel)),
          FilledButton(
            onPressed: saving ? null : onSave,
            child: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(saveLabel),
          ),
        ],
      );
}
