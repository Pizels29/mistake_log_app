import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';

import 'data/daily_mistake_widget.dart';
import 'data/mistake_store.dart';
import 'models/mistake_class.dart';
import 'models/mistake.dart';

const _background = Color(0xFF000000);
const _surface = Color(0xFF0D0D0D);
const _surfaceRaised = Color(0xFF171717);
const _line = Color(0xFF242426);
const _text = Color(0xFFF5F5F7);
const _muted = Color(0xFF98989D);
const _accent = Color(0xFFF5F5F7);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final box = await Hive.openBox<Map>('mistakes');
  final classesBox = await Hive.openBox<Map>('classes');
  final store = MistakeStore(box, classesBox);
  await store.initialize();
  await store.refreshDueReviews();
  runApp(MistakeLogApp(store: store));
}

class MistakeLogApp extends StatelessWidget {
  const MistakeLogApp({super.key, required this.store});

  final MistakeStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mistake Log',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _background,
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          onPrimary: Color(0xFF000000),
          surface: _surface,
          onSurface: _text,
          outline: _line,
        ),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _surfaceRaised,
          hintStyle: const TextStyle(color: _muted),
          labelStyle: const TextStyle(color: _muted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _accent, width: 1.2),
          ),
        ),
      ),
      home: MistakeLogScreen(store: store),
      onUnknownRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => MistakeLogScreen(store: store),
      ),
    );
  }
}

class MistakeLogScreen extends StatefulWidget {
  const MistakeLogScreen({super.key, required this.store});

  final MistakeStore store;

  @override
  State<MistakeLogScreen> createState() => _MistakeLogScreenState();
}

class _MistakeLogScreenState extends State<MistakeLogScreen>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  Timer? _reviewTimer;
  String _query = '';
  String? _classFilter;
  String? _tagFilter;
  bool _showReviewed = false;
  Future<void> _widgetSync = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleNextReviewRefresh();
    unawaited(_syncDailyWidget());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshDueReviews();
    }
  }

  Future<void> _refreshDueReviews() async {
    await widget.store.refreshDueReviews();
    if (mounted) {
      _scheduleNextReviewRefresh();
      await _syncDailyWidget();
    }
  }

  void _scheduleNextReviewRefresh() {
    _reviewTimer?.cancel();
    final now = DateTime.now();
    final dueDates =
        widget.store.all
            .where((entry) => entry.reviewed && entry.reviewedAt != null)
            .map((entry) => entry.reviewedAt!.add(MistakeStore.reviewInterval))
            .where((date) => date.isAfter(now))
            .toList()
          ..sort();
    if (dueDates.isEmpty) return;
    _reviewTimer = Timer(dueDates.first.difference(now), _refreshDueReviews);
  }

  Future<void> _setReviewed(Mistake mistake, bool reviewed) async {
    await widget.store.setReviewed(mistake, reviewed);
    if (mounted) {
      _scheduleNextReviewRefresh();
      await _syncDailyWidget();
    }
  }

  Future<void> _saveMistake(Mistake mistake) async {
    await widget.store.save(mistake);
    await _syncDailyWidget();
  }

  Future<void> _deleteMistake(String id) async {
    await widget.store.deleteMistake(id);
    await _syncDailyWidget();
  }

  Future<void> _syncDailyWidget() {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return Future<void>.value();
    }
    _widgetSync = _widgetSync.then((_) async {
      try {
        await DailyMistakeWidget.sync(widget.store.all, {
          for (final entry in widget.store.classes) entry.id: entry.name,
        });
      } catch (error) {
        debugPrint('Home-screen widget update failed: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Widget could not be updated: $error')),
          );
        }
      }
    });
    return _widgetSync;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reviewTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openMistakeEditor({Mistake? mistake}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => AddMistakeSheet(
        classes: widget.store.classes,
        mistake: mistake,
        onSave: _saveMistake,
      ),
    );
  }

  Future<void> _openManageClasses() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => ManageClassesSheet(store: widget.store),
    );
    if (mounted) {
      await _syncDailyWidget();
      setState(() {
        if (_classFilter != null &&
            !widget.store.classes.any((entry) => entry.id == _classFilter)) {
          _classFilter = null;
        }
      });
    }
  }

  Future<void> _openAddMistake() => _openMistakeEditor();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder(
          valueListenable: widget.store.changes,
          builder: (context, box, _) {
            final all = widget.store.all;
            final classes = widget.store.classes;
            final classNames = {
              for (final entry in classes) entry.id: entry.name,
            };
            final activeEntries = all.where(
              (entry) => entry.reviewed == _showReviewed,
            );
            final tags =
                activeEntries.expand((entry) => entry.tags).toSet().toList()
                  ..sort();
            final entries = activeEntries.where((entry) {
              final matchesClass =
                  _classFilter == null || entry.classId == _classFilter;
              final matchesTag =
                  _tagFilter == null || entry.tags.contains(_tagFilter);
              final query = _query.trim().toLowerCase();
              final matchesQuery =
                  query.isEmpty ||
                  entry.description.toLowerCase().contains(query) ||
                  (classNames[entry.classId] ?? 'Unassigned')
                      .toLowerCase()
                      .contains(query) ||
                  entry.tags.any((tag) => tag.toLowerCase().contains(query));
              return matchesClass && matchesTag && matchesQuery;
            }).toList();

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1056),
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 40),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _Header(
                            onAdd: _openAddMistake,
                            onManageClasses: _openManageClasses,
                          ),
                          const SizedBox(height: 28),
                          _LogToolbar(
                            controller: _searchController,
                            query: _query,
                            onQueryChanged: (value) =>
                                setState(() => _query = value),
                          ),
                          const SizedBox(height: 16),
                          _SubjectFilters(
                            classes: classes,
                            selected: _classFilter,
                            showReviewed: _showReviewed,
                            onSelected: (value) => setState(
                              () => _classFilter = _classFilter == value
                                  ? null
                                  : value,
                            ),
                            onReviewedSelected: () => setState(() {
                              _showReviewed = !_showReviewed;
                              _classFilter = null;
                              _tagFilter = null;
                            }),
                          ),
                          if (tags.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _TagFilters(
                              tags: tags,
                              selected: _tagFilter,
                              onSelected: (value) =>
                                  setState(() => _tagFilter = value),
                            ),
                          ],
                          const SizedBox(height: 20),
                          if (entries.isEmpty)
                            _EmptyState(
                              hasEntries: all.any(
                                (entry) => entry.reviewed == _showReviewed,
                              ),
                              showingReviewed: _showReviewed,
                            )
                          else
                            ...entries.map(
                              (entry) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _MistakeCard(
                                  mistake: entry,
                                  className:
                                      classNames[entry.classId] ?? 'Unassigned',
                                  onEdit: () =>
                                      _openMistakeEditor(mistake: entry),
                                  onReviewedChanged: (reviewed) =>
                                      _setReviewed(entry, reviewed),
                                  onDelete: () => _confirmDeleteMistake(
                                    context,
                                    entry,
                                    _deleteMistake,
                                  ),
                                ),
                              ),
                            ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onAdd, required this.onManageClasses});

  final VoidCallback onAdd;
  final VoidCallback onManageClasses;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final iconOnly = constraints.maxWidth <= 360;
        return Row(
          children: [
            const Text(
              'Mistake Log',
              style: TextStyle(
                color: _text,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.55,
              ),
            ),
            const Spacer(),
            IconButton(
              key: const ValueKey('manage-classes-button'),
              tooltip: 'Manage classes',
              onPressed: onManageClasses,
              icon: const Icon(Icons.tune_rounded),
              color: _muted,
            ),
            FilledButton.icon(
              key: const ValueKey('add-mistake-button'),
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: iconOnly
                  ? const SizedBox.shrink()
                  : const Text('Add mistake'),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: const Color(0xFF000000),
                padding: EdgeInsets.symmetric(
                  horizontal: iconOnly ? 12 : 16,
                  vertical: 14,
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LogToolbar extends StatelessWidget {
  const _LogToolbar({
    required this.controller,
    required this.query,
    required this.onQueryChanged,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final search = TextField(
          controller: controller,
          onChanged: onQueryChanged,
          decoration: InputDecoration(
            hintText: 'Search mistakes',
            prefixIcon: const Icon(Icons.search_rounded, size: 19),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      controller.clear();
                      onQueryChanged('');
                    },
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            isDense: true,
          ),
        );
        if (constraints.maxWidth <= 560) {
          return search;
        }
        return Align(
          alignment: Alignment.centerRight,
          child: SizedBox(width: 340, child: search),
        );
      },
    );
  }
}

class _SubjectFilters extends StatelessWidget {
  const _SubjectFilters({
    required this.classes,
    required this.selected,
    required this.showReviewed,
    required this.onSelected,
    required this.onReviewedSelected,
  });

  final List<MistakeClass> classes;
  final String? selected;
  final bool showReviewed;
  final ValueChanged<String?> onSelected;
  final VoidCallback onReviewedSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChip(
            label: 'All classes',
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final mistakeClass in classes)
            _FilterChip(
              label: mistakeClass.name,
              selected: selected == mistakeClass.id,
              onTap: () => onSelected(mistakeClass.id),
            ),
          _FilterChip(
            label: 'Reviewed',
            selected: showReviewed,
            onTap: onReviewedSelected,
          ),
        ],
      ),
    );
  }
}

class _TagFilters extends StatelessWidget {
  const _TagFilters({
    required this.tags,
    required this.selected,
    required this.onSelected,
  });

  final List<String> tags;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        _FilterChip(
          label: 'All tags',
          selected: selected == null,
          onTap: () => onSelected(null),
        ),
        for (final tag in tags)
          _FilterChip(
            label: tag,
            selected: selected == tag,
            onTap: () => onSelected(selected == tag ? null : tag),
          ),
      ],
    ),
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        backgroundColor: _surface,
        selectedColor: _accent,
        labelStyle: TextStyle(
          color: selected ? const Color(0xFF000000) : _muted,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
        side: BorderSide(color: selected ? _accent : _line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      ),
    );
  }
}

class _MistakeCard extends StatelessWidget {
  const _MistakeCard({
    required this.mistake,
    required this.className,
    this.onEdit,
    required this.onReviewedChanged,
    required this.onDelete,
  });

  final Mistake mistake;
  final String className;
  final VoidCallback? onEdit;
  final ValueChanged<bool> onReviewedChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final photo = mistake.photoBytes;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final reviewButton = OutlinedButton(
            key: ValueKey('review-${mistake.id}'),
            onPressed: () => onReviewedChanged(!mistake.reviewed),
            style: OutlinedButton.styleFrom(
              foregroundColor: mistake.reviewed ? _muted : _accent,
              side: BorderSide(color: mistake.reviewed ? _line : _accent),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Text(mistake.reviewed ? 'Restore' : 'Mark reviewed'),
          );
          final actions = Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (onEdit case final onEdit?)
                IconButton(
                  key: ValueKey('edit-${mistake.id}'),
                  tooltip: 'Edit mistake',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 19),
                  color: _muted,
                ),
              IconButton(
                key: ValueKey('delete-${mistake.id}'),
                tooltip: 'Delete mistake',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 19),
                color: _muted,
              ),
              reviewButton,
            ],
          );
          final details = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 9,
                  runSpacing: 6,
                  children: [
                    Text(
                      className,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text('·', style: TextStyle(color: _muted)),
                    Text(
                      _formatDate(mistake.createdAt),
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                    if (mistake.reviewed)
                      const _ReviewedBadge()
                    else
                      const _PendingBadge(),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  mistake.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                if (mistake.tags.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final tag in mistake.tags) _TagBadge(label: tag),
                    ],
                  ),
                ],
              ],
            ),
          );
          if (constraints.maxWidth <= 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    _PhotoThumbnail(photoBytes: photo),
                    const SizedBox(width: 14),
                    details,
                  ],
                ),
                const SizedBox(height: 10),
                actions,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _PhotoThumbnail(photoBytes: photo),
              const SizedBox(width: 16),
              details,
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }
}

Future<void> _confirmDeleteMistake(
  BuildContext context,
  Mistake mistake,
  Future<void> Function(String id) deleteMistake,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete this mistake?'),
      content: const Text('This action cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await deleteMistake(mistake.id);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mistake could not be deleted: $error')),
      );
    }
  }
}

class _TagBadge extends StatelessWidget {
  const _TagBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: _surfaceRaised,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _line),
    ),
    child: Text(label, style: const TextStyle(color: _muted, fontSize: 10)),
  );
}

class _PhotoThumbnail extends StatelessWidget {
  const _PhotoThumbnail({required this.photoBytes});

  final Uint8List? photoBytes;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: SizedBox(
        width: 68,
        height: 68,
        child: photoBytes == null
            ? Container(
                color: _surfaceRaised,
                child: const Icon(
                  Icons.description_outlined,
                  color: _muted,
                  size: 22,
                ),
              )
            : Image.memory(photoBytes!, fit: BoxFit.cover),
      ),
    );
  }
}

class _ReviewedBadge extends StatelessWidget {
  const _ReviewedBadge();

  @override
  Widget build(BuildContext context) =>
      const _StatusBadge(label: 'Reviewed', color: _muted);
}

class _PendingBadge extends StatelessWidget {
  const _PendingBadge();

  @override
  Widget build(BuildContext context) =>
      const _StatusBadge(label: 'To review', color: _muted);
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w400),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasEntries, required this.showingReviewed});

  final bool hasEntries;
  final bool showingReviewed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Text(
            showingReviewed
                ? (hasEntries ? 'No matching mistakes' : 'No reviewed mistakes')
                : (hasEntries ? 'No matching mistakes' : 'No mistakes yet'),
            style: const TextStyle(
              color: _text,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasEntries
                ? 'Try another class, tag or search term.'
                : showingReviewed
                ? 'Mistakes you mark reviewed will appear here.'
                : 'Add a mistake to start your log.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class ManageClassesSheet extends StatefulWidget {
  const ManageClassesSheet({super.key, required this.store});

  final MistakeStore store;

  @override
  State<ManageClassesSheet> createState() => _ManageClassesSheetState();
}

class _ManageClassesSheetState extends State<ManageClassesSheet> {
  final _nameController = TextEditingController();
  MistakeClass? _editingClass;
  String? _editorError;
  bool _isAdding = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _beginAdd() {
    setState(() {
      _isAdding = true;
      _editingClass = null;
      _editorError = null;
      _nameController.clear();
    });
  }

  void _beginEdit(MistakeClass mistakeClass) {
    setState(() {
      _isAdding = false;
      _editingClass = mistakeClass;
      _editorError = null;
      _nameController.text = mistakeClass.name;
    });
  }

  void _cancelEdit() {
    setState(() {
      _isAdding = false;
      _editingClass = null;
      _editorError = null;
      _saving = false;
      _nameController.clear();
    });
  }

  Future<void> _saveClass() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _editorError = 'Enter a class name.');
      return;
    }
    if (_saving) return;

    setState(() {
      _saving = true;
      _editorError = null;
    });
    try {
      final editingClass = _editingClass;
      if (editingClass == null) {
        final now = DateTime.now();
        final id = '${now.microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
        await widget.store.addClass(MistakeClass(id: id, name: name));
      } else {
        await widget.store.renameClass(editingClass, name);
      }
      if (mounted) _cancelEdit();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _editorError = error.toString();
        });
      }
    }
  }

  Future<void> _removeClass(
    BuildContext context,
    MistakeClass mistakeClass,
  ) async {
    final assignedCount = widget.store.all
        .where((entry) => entry.classId == mistakeClass.id)
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${mistakeClass.name}?'),
        content: Text(
          assignedCount == 0
              ? 'This class will be removed.'
              : '$assignedCount ${assignedCount == 1 ? 'mistake' : 'mistakes'} '
                    'will be kept in Unassigned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove class'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await widget.store.removeClass(mistakeClass);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Class could not be removed: $error')),
        );
      }
    }
  }

  Widget _buildClassList(BuildContext context) => ValueListenableBuilder(
    valueListenable: widget.store.classesChanges,
    builder: (context, box, _) => ListView(
      children: [
        for (final entry in widget.store.classes)
          ListTile(
            title: Text(entry.name),
            subtitle: Text(
              '${widget.store.all.where((mistake) => mistake.classId == entry.id).length} '
              'mistakes',
              style: const TextStyle(color: _muted),
            ),
            trailing: entry.id == MistakeStore.unassignedClassId
                ? null
                : Wrap(
                    children: [
                      IconButton(
                        tooltip: 'Edit ${entry.name}',
                        onPressed: () => _beginEdit(entry),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Remove ${entry.name}',
                        onPressed: () => _removeClass(context, entry),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: 0.82,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Classes',
                    style: const TextStyle(
                      color: _text,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                FilledButton.icon(
                  key: const ValueKey('add-class-button'),
                  onPressed: _saving
                      ? null
                      : _isAdding
                      ? _cancelEdit
                      : _beginAdd,
                  icon: Icon(
                    _isAdding ? Icons.close_rounded : Icons.add_rounded,
                    size: 18,
                  ),
                  label: Text(_isAdding ? 'Cancel' : 'Add class'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Removing a class keeps its mistakes in Unassigned.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ),
            if (_isAdding || _editingClass != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('class-name-field'),
                      controller: _nameController,
                      autofocus: true,
                      maxLength: 60,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Class name',
                        hintText: 'e.g. Chemistry',
                        errorText: _editorError,
                        counterText: '',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _saving ? null : _saveClass(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('save-class-button'),
                    onPressed: _saving ? null : _saveClass,
                    child: Text(_saving ? 'Saving…' : 'Save'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: widget.store.classesChanges,
                builder: (context, box, _) => _buildClassList(context),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class AddMistakeSheet extends StatefulWidget {
  const AddMistakeSheet({
    super.key,
    required this.classes,
    required this.onSave,
    this.mistake,
  });

  final List<MistakeClass> classes;
  final Mistake? mistake;
  final Future<void> Function(Mistake mistake) onSave;

  @override
  State<AddMistakeSheet> createState() => _AddMistakeSheetState();
}

class _AddMistakeSheetState extends State<AddMistakeSheet> {
  static const _suggestedTags = [
    'conceptual',
    'procedural',
    'calculation',
    'careless',
  ];

  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _tagController = TextEditingController();
  final _picker = ImagePicker();
  late String _classId;
  late List<String> _tags;
  Uint8List? _photoBytes;
  String? _photoError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.mistake;
    _classId = widget.classes.any((entry) => entry.id == existing?.classId)
        ? existing!.classId
        : MistakeStore.unassignedClassId;
    _descriptionController.text = existing?.description ?? '';
    _photoBytes = existing?.photoBytes;
    _tags = [...?existing?.tags];
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _addTag([String? value]) {
    final tag = (value ?? _tagController.text).trim();
    if (tag.isEmpty ||
        _tags.any((entry) => entry.toLowerCase() == tag.toLowerCase())) {
      _tagController.clear();
      return;
    }
    setState(() {
      _tags.add(tag);
      _tagController.clear();
    });
  }

  Future<void> _choosePhoto() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photoBytes = bytes;
        _photoError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _photoError = 'Could not load that photo. Please try again.',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Photo could not be added: $error')),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    final existing = widget.mistake;
    final mistake = Mistake(
      id:
          existing?.id ??
          '${now.microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}',
      classId: _classId,
      description: _descriptionController.text.trim(),
      createdAt: existing?.createdAt ?? now,
      reviewed: existing?.reviewed ?? false,
      photoBytes: _photoBytes,
      tags: List.unmodifiable(_tags),
    );
    try {
      await widget.onSave(mistake);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mistake could not be saved: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.mistake;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 34,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _line,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      existing == null ? 'Add a mistake' : 'Edit mistake',
                      style: const TextStyle(
                        color: _text,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Capture what happened while it is still fresh.',
                      style: TextStyle(color: _muted, fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('mistake-class-field'),
                      initialValue: _classId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Class'),
                      items: [
                        for (final entry in widget.classes)
                          DropdownMenuItem(
                            value: entry.id,
                            child: Text(entry.name),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _classId = value);
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: const ValueKey('mistake-description-field'),
                      controller: _descriptionController,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'What happened?',
                        hintText: 'Describe the problem and where your work went wrong…',
                        alignLabelWithHint: true,
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Add a short description to continue.'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tags',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final tag in _tags)
                          InputChip(
                            label: Text(tag),
                            onDeleted: () => setState(() => _tags.remove(tag)),
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('mistake-tag-field'),
                            controller: _tagController,
                            textCapitalization: TextCapitalization.words,
                            onSubmitted: (_) => _addTag(),
                            decoration: const InputDecoration(
                              hintText: 'Add a tag',
                              isDense: true,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('add-tag-button'),
                          tooltip: 'Add tag',
                          onPressed: _addTag,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final tag in _suggestedTags)
                          if (!_tags.any(
                            (entry) => entry.toLowerCase() == tag.toLowerCase(),
                          ))
                            ActionChip(
                              label: Text(tag),
                              onPressed: () => _addTag(tag),
                              backgroundColor: _surfaceRaised,
                            ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_photoBytes == null)
                      OutlinedButton.icon(
                        key: const ValueKey('add-photo-button'),
                        onPressed: _choosePhoto,
                        icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                        label: const Text('Add a photo (optional)'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _text,
                          side: const BorderSide(color: _line),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                        ),
                      )
                    else
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(
                              _photoBytes!,
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: _choosePhoto,
                            child: const Text('Replace photo'),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _photoBytes = null),
                            child: const Text(
                              'Remove',
                              style: TextStyle(color: _muted),
                            ),
                          ),
                        ],
                      ),
                    if (_photoError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _photoError!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const ValueKey('save-mistake-button'),
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: const Color(0xFF000000),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: Text(_saving ? 'Saving…' : 'Save to log'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
