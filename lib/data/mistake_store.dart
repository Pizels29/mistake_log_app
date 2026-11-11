import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:hive_flutter/hive_flutter.dart';

import '../models/mistake_class.dart';
import '../models/mistake.dart';

class MistakeStore {
  static const reviewInterval = Duration(days: 7);

  MistakeStore(this._box, this._classesBox);

  final Box<Map> _box;
  final Box<Map> _classesBox;

  late final ValueListenable<Box<Map>> _changes = _box.listenable();
  late final ValueListenable<Box<Map>> _classesChanges = _classesBox
      .listenable();

  ValueListenable<Box<Map>> get changes => _changes;
  ValueListenable<Box<Map>> get classesChanges => _classesChanges;

  static const unassignedClassId = 'unassigned';
  static const _defaultClasses = [
    MistakeClass(id: 'precalculus', name: 'Precalculus'),
    MistakeClass(id: 'physics', name: 'Physics'),
    MistakeClass(id: 'csa', name: 'Computer Science A'),
    MistakeClass(id: 'english', name: 'English'),
    MistakeClass(id: unassignedClassId, name: 'Unassigned'),
  ];

  Future<void> initialize() async {
    if (_classesBox.isEmpty) {
      for (final entry in _defaultClasses) {
        await _classesBox.put(entry.id, entry.toMap());
      }
    } else if (!_classesBox.containsKey(unassignedClassId)) {
      final unassigned = _defaultClasses.last;
      await _classesBox.put(unassigned.id, unassigned.toMap());
    }

    for (final entry in _box.toMap().entries) {
      final map = Map<dynamic, dynamic>.from(entry.value);
      var changed = false;
      if (map['classId'] == null && map['subject'] != null) {
        map['classId'] = map.remove('subject');
        changed = true;
      }
      if (map['reviewed'] == true && map['reviewedAt'] == null) {
        map['reviewedAt'] = DateTime.now().toIso8601String();
        changed = true;
      }
      if (changed) {
        await _box.put(entry.key, map);
      }
    }
  }

  List<MistakeClass> get classes =>
      _classesBox.values.map(MistakeClass.fromMap).toList()..sort((a, b) {
        if (a.id == unassignedClassId) return 1;
        if (b.id == unassignedClassId) return -1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

  List<Mistake> get all =>
      _box.values.map(Mistake.fromMap).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<void> add(Mistake mistake) => _box.put(mistake.id, mistake.toMap());

  Future<void> save(Mistake mistake) => add(mistake);

  Future<void> setReviewed(
    Mistake mistake,
    bool reviewed, {
    DateTime? now,
  }) async {
    await _box.put(
      mistake.id,
      Mistake(
        id: mistake.id,
        classId: mistake.classId,
        description: mistake.description,
        createdAt: mistake.createdAt,
        reviewed: reviewed,
        reviewedAt: reviewed ? (now ?? DateTime.now()) : null,
        photoBytes: mistake.photoBytes,
        tags: mistake.tags,
      ).toMap(),
    );
  }

  Future<void> refreshDueReviews({DateTime? now}) async {
    final currentTime = now ?? DateTime.now();
    for (final mistake in all) {
      final reviewedAt = mistake.reviewedAt;
      if (mistake.reviewed &&
          reviewedAt != null &&
          !reviewedAt.add(reviewInterval).isAfter(currentTime)) {
        await _box.put(
          mistake.id,
          Mistake(
            id: mistake.id,
            classId: mistake.classId,
            description: mistake.description,
            createdAt: mistake.createdAt,
            reviewed: false,
            photoBytes: mistake.photoBytes,
            tags: mistake.tags,
          ).toMap(),
        );
      }
    }
  }

  Future<void> deleteMistake(String id) => _box.delete(id);

  Future<void> addClass(MistakeClass mistakeClass) async {
    _validateClassName(mistakeClass.name);
    await _classesBox.put(mistakeClass.id, mistakeClass.toMap());
  }

  Future<void> renameClass(MistakeClass mistakeClass, String name) async {
    if (mistakeClass.id == unassignedClassId) {
      throw StateError('The Unassigned class cannot be renamed.');
    }
    _validateClassName(name, excludingId: mistakeClass.id);
    await _classesBox.put(
      mistakeClass.id,
      MistakeClass(id: mistakeClass.id, name: name.trim()).toMap(),
    );
  }

  Future<void> removeClass(MistakeClass mistakeClass) async {
    if (mistakeClass.id == unassignedClassId) {
      throw StateError('The Unassigned class cannot be removed.');
    }
    for (final mistake in all.where(
      (entry) => entry.classId == mistakeClass.id,
    )) {
      await _box.put(
        mistake.id,
        Mistake(
          id: mistake.id,
          classId: unassignedClassId,
          description: mistake.description,
          createdAt: mistake.createdAt,
          reviewed: mistake.reviewed,
          reviewedAt: mistake.reviewedAt,
          photoBytes: mistake.photoBytes,
          tags: mistake.tags,
        ).toMap(),
      );
    }
    await _classesBox.delete(mistakeClass.id);
  }

  void _validateClassName(String name, {String? excludingId}) {
    final normalized = name.trim().toLowerCase();
    if (normalized.isEmpty) {
      throw ArgumentError('Class name cannot be empty.');
    }
    if (classes.any(
      (entry) =>
          entry.id != excludingId &&
          entry.name.trim().toLowerCase() == normalized,
    )) {
      throw ArgumentError('A class with that name already exists.');
    }
  }
}
