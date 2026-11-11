import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mistake_log/data/mistake_store.dart';
import 'package:mistake_log/models/mistake_class.dart';
import 'package:mistake_log/models/mistake.dart';

void main() {
  late Directory hiveDirectory;
  late Box<Map> box;
  late Box<Map> classesBox;
  late MistakeStore store;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('mistake-log-test-');
    Hive.init(hiveDirectory.path);
    box = await Hive.openBox<Map>('mistakes');
    classesBox = await Hive.openBox<Map>('classes');
    store = MistakeStore(box, classesBox);
  });

  setUp(() async {
    await box.clear();
    await classesBox.clear();
    await store.initialize();
  });

  tearDown(() async {
    await box.clear();
    await classesBox.clear();
  });

  tearDownAll(() async {
    await box.close();
    await classesBox.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('adds a tagged mistake and schedules its next review', () async {
    final chemistry = MistakeClass(id: 'chemistry', name: 'Chemistry');
    await store.addClass(chemistry);
    expect(store.classes.any((entry) => entry.id == chemistry.id), isTrue);
    await expectLater(
      store.addClass(const MistakeClass(id: 'chemistry-2', name: 'chemistry')),
      throwsArgumentError,
    );

    final mistake = Mistake(
      id: 'mistake-1',
      classId: 'precalculus',
      description: 'I forgot to distribute the negative sign.',
      createdAt: DateTime(2026, 11, 9),
      reviewed: false,
      tags: const ['conceptual', 'procedural'],
    );

    await store.add(mistake);

    expect(store.all, hasLength(1));
    expect(store.all.single.description, mistake.description);
    expect(store.all.single.classId, 'precalculus');
    expect(store.all.single.tags, ['conceptual', 'procedural']);

    final reviewedAt = DateTime(2026, 11, 9);
    await store.setReviewed(mistake, true, now: reviewedAt);

    expect(store.all.single.reviewed, isTrue);
    expect(store.all.single.reviewedAt, reviewedAt);
  });

  test(
    'classes can be added, renamed, and removed without losing mistakes',
    () async {
      final mistake = Mistake(
        id: 'mistake-1',
        classId: 'physics',
        description: 'Used the wrong direction for acceleration.',
        createdAt: DateTime(2026, 11, 9),
        reviewed: true,
        tags: const ['conceptual'],
      );
      await store.add(mistake);
      final physics = store.classes.singleWhere(
        (entry) => entry.id == 'physics',
      );

      await store.renameClass(physics, 'Mechanics');

      expect(
        store.classes.singleWhere((entry) => entry.id == 'physics').name,
        'Mechanics',
      );

      await store.removeClass(physics);

      expect(store.classes.any((entry) => entry.id == 'physics'), isFalse);
      expect(store.all.single.classId, MistakeStore.unassignedClassId);
      expect(store.all.single.description, mistake.description);
      expect(store.all.single.reviewed, isTrue);
      expect(store.all.single.tags, ['conceptual']);
    },
  );

  test('migrates existing subject values and adds default classes', () async {
    await box.put('legacy', {
      'id': 'legacy',
      'subject': 'csa',
      'description': 'Forgot a boundary condition.',
      'createdAt': DateTime(2026, 11, 9).toIso8601String(),
      'reviewed': false,
      'photoBytes': null,
    });
    await classesBox.clear();

    await store.initialize();

    expect(store.classes.map((entry) => entry.id), contains('csa'));
    expect(store.all.single.classId, 'csa');
    expect(store.all.single.tags, isEmpty);
    expect(box.get('legacy')!.containsKey('subject'), isFalse);
  });

  test('reviewed mistakes return to the log after seven days', () async {
    final mistake = Mistake(
      id: 'scheduled-mistake',
      classId: 'physics',
      description: 'Return after a week.',
      createdAt: DateTime(2026, 11, 9),
      reviewed: false,
      tags: const ['procedural'],
    );
    await store.add(mistake);
    final reviewedAt = DateTime(2026, 11, 9, 12);
    await store.setReviewed(mistake, true, now: reviewedAt);

    expect(store.all.single.reviewed, isTrue);
    expect(store.all.where((entry) => !entry.reviewed), isEmpty);
    await store.refreshDueReviews(
      now: reviewedAt.add(
        const Duration(days: 7) - const Duration(microseconds: 1),
      ),
    );
    expect(store.all.single.reviewed, isTrue);

    await store.refreshDueReviews(now: reviewedAt.add(const Duration(days: 7)));
    expect(store.all.single.reviewed, isFalse);
    expect(store.all.single.reviewedAt, isNull);
    expect(store.all.where((entry) => !entry.reviewed), hasLength(1));

    await store.deleteMistake(mistake.id);

    expect(store.all, isEmpty);
  });

  test(
    'starts the seven-day interval for reviewed records without a date',
    () async {
      final mistake = Mistake(
        id: 'legacy-reviewed',
        classId: 'physics',
        description: 'Previously reviewed.',
        createdAt: DateTime(2026, 11, 9),
        reviewed: true,
      );
      await box.put(mistake.id, {...mistake.toMap(), 'reviewedAt': null});

      final beforeInitialization = DateTime.now();
      await store.initialize();
      final afterInitialization = DateTime.now();
      final migrated = store.all.single;

      expect(migrated.reviewed, isTrue);
      expect(migrated.reviewedAt, isNotNull);
      expect(migrated.reviewedAt!.isBefore(beforeInitialization), isFalse);
      expect(migrated.reviewedAt!.isAfter(afterInitialization), isFalse);
      await store.refreshDueReviews(
        now: migrated.reviewedAt!.add(
          const Duration(days: 7) - const Duration(microseconds: 1),
        ),
      );
      expect(store.all.single.reviewed, isTrue);
    },
  );
}
