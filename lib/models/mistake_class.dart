class MistakeClass {
  const MistakeClass({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, Object?> toMap() => {'id': id, 'name': name};

  factory MistakeClass.fromMap(Map<dynamic, dynamic> map) =>
      MistakeClass(id: map['id'] as String, name: map['name'] as String);
}
