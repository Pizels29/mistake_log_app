import 'dart:typed_data';

class Mistake {
  const Mistake({
    required this.id,
    required this.classId,
    required this.description,
    required this.createdAt,
    required this.reviewed,
    this.reviewedAt,
    this.photoBytes,
    this.tags = const [],
  });

  final String id;
  final String classId;
  final String description;
  final DateTime createdAt;
  final bool reviewed;
  final DateTime? reviewedAt;
  final Uint8List? photoBytes;
  final List<String> tags;

  Mistake copyWith({bool? reviewed}) => Mistake(
    id: id,
    classId: classId,
    description: description,
    createdAt: createdAt,
    reviewed: reviewed ?? this.reviewed,
    reviewedAt: reviewedAt,
    photoBytes: photoBytes,
    tags: tags,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'classId': classId,
    'description': description,
    'createdAt': createdAt.toIso8601String(),
    'reviewed': reviewed,
    'reviewedAt': reviewedAt?.toIso8601String(),
    'photoBytes': photoBytes,
    'tags': tags,
  };

  factory Mistake.fromMap(Map<dynamic, dynamic> map) {
    final classId = map['classId'] as String? ?? map['subject'] as String;
    final storedPhoto = map['photoBytes'];
    final storedTags = map['tags'];

    return Mistake(
      id: map['id'] as String,
      classId: classId,
      description: map['description'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      reviewed: map['reviewed'] as bool? ?? false,
      reviewedAt: map['reviewedAt'] == null
          ? null
          : DateTime.parse(map['reviewedAt'] as String),
      photoBytes: storedPhoto == null
          ? null
          : storedPhoto is Uint8List
          ? storedPhoto
          : Uint8List.fromList(List<int>.from(storedPhoto as List)),
      tags: storedTags == null ? const [] : List<String>.from(storedTags),
    );
  }
}
