import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:home_widget/home_widget.dart';

import '../models/mistake.dart';

class DailyMistakeWidget {
  static const _appGroupId = 'group.com.example.mistakeLogApp';
  static const _cycleKey = 'mistake_cycle_order';
  static const _itemsKey = 'mistake_cycle';
  static const _anchorKey = 'mistake_cycle_anchor';
  static const _androidWidgetName =
      'com.example.mistake_log_app.MistakeWidgetProvider';
  static const _iosWidgetName = 'MistakeLogWidget';

  static Future<void>? _initialization;

  static Future<void> initialize() => _initialization ??= _initialize();

  static Future<void> _initialize() async {
    final success = await HomeWidget.setAppGroupId(_appGroupId);
    if (success == false) {
      throw StateError('Could not configure shared home-screen widget data.');
    }
  }

  static Future<void> sync(
    List<Mistake> mistakes,
    Map<String, String> classNames,
  ) async {
    await initialize();

    final eligible = mistakes.where((mistake) => !mistake.reviewed).toList();
    final eligibleById = {for (final mistake in eligible) mistake.id: mistake};
    final storedCycle = await HomeWidget.getWidgetData<String>(_cycleKey);
    final storedAnchor = await HomeWidget.getWidgetData<String>(_anchorKey);
    final previousOrder = storedCycle == null
        ? <String>[]
        : (jsonDecode(storedCycle) as List<dynamic>).cast<String>();
    final order = [...previousOrder];
    final hadExistingOrder = order.isNotEmpty;

    order.removeWhere((id) => !eligibleById.containsKey(id));
    final newIds = eligibleById.keys.where((id) => !order.contains(id)).toList()
      ..shuffle(Random());
    order.addAll(newIds);

    final today = _dateOnly(DateTime.now());
    final anchor = storedAnchor == null || !hadExistingOrder
        ? today
        : _dateOnly(DateTime.parse(storedAnchor));
    final cycleAnchor = anchor.isAfter(today) ? today : anchor;
    for (final id in previousOrder.where(
      (id) => !eligibleById.containsKey(id),
    )) {
      await _clearPhoto(id);
    }
    for (final mistake in eligible.where(
      (mistake) => mistake.photoBytes == null,
    )) {
      await _clearPhoto(mistake.id);
    }
    final items = [
      for (final id in order)
        if (eligibleById[id] case final mistake?) ...[
          {
            'id': id,
            'description': mistake.description,
            'className': classNames[mistake.classId] ?? 'Unassigned',
            'tags': mistake.tags.join(' · '),
            if (mistake.photoBytes != null)
              'photoPath': await _savePhoto(id, mistake.photoBytes!),
          },
        ],
    ];

    await _save(_cycleKey, jsonEncode(order));
    await _save(_itemsKey, jsonEncode(items));
    await _save(_anchorKey, _formatDate(cycleAnchor));
    final updated = await HomeWidget.updateWidget(
      qualifiedAndroidName: _androidWidgetName,
      iOSName: _iosWidgetName,
    );
    if (updated == false) {
      throw StateError('Could not refresh the home-screen mistake widget.');
    }
  }

  static Future<void> _save(String key, String value) async {
    final saved = await HomeWidget.saveWidgetData<String>(key, value);
    if (saved == false) {
      throw StateError('Could not save home-screen widget data.');
    }
  }

  static Future<String> _savePhoto(String id, Uint8List bytes) async {
    final key = _photoKey(id);
    return HomeWidget.saveFile(key, bytes, extension: 'jpg');
  }

  static Future<void> _clearPhoto(String id) async {
    final cleared = await HomeWidget.saveWidgetData<String>(
      _photoKey(id),
      null,
    );
    if (cleared == false) {
      throw StateError('Could not clear a removed widget photo.');
    }
  }

  static String _photoKey(String id) =>
      'mistake_photo_${base64Url.encode(utf8.encode(id)).replaceAll('=', '')}';

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
