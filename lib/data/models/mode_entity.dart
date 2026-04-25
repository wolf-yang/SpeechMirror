enum ModeType { preset, custom, persona }

class ModeEntity {
  const ModeEntity({
    required this.id,
    required this.name,
    required this.description,
    required this.modeType,
    required this.stylePrompt,
    this.examplesJson,
    this.negativeExamplesJson,
    required this.isBuiltin,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  final int id;
  final String name;
  final String description;
  final ModeType modeType;
  final String stylePrompt;
  final String? examplesJson;
  final String? negativeExamplesJson;
  final bool isBuiltin;
  final int createdAtMs;
  final int updatedAtMs;

  static ModeType typeFromString(String s) {
    switch (s) {
      case 'preset':
        return ModeType.preset;
      case 'persona':
        return ModeType.persona;
      default:
        return ModeType.custom;
    }
  }

  String get typeString {
    switch (modeType) {
      case ModeType.preset:
        return 'preset';
      case ModeType.custom:
        return 'custom';
      case ModeType.persona:
        return 'persona';
    }
  }

  factory ModeEntity.fromMap(Map<String, Object?> map) {
    return ModeEntity(
      id: map['id']! as int,
      name: map['name']! as String,
      description: map['description']! as String,
      modeType: typeFromString(map['mode_type']! as String),
      stylePrompt: map['style_prompt']! as String,
      examplesJson: map['examples_json'] as String?,
      negativeExamplesJson: map['negative_examples_json'] as String?,
      isBuiltin: (map['is_builtin'] as int) == 1,
      createdAtMs: map['created_at']! as int,
      updatedAtMs: map['updated_at']! as int,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'mode_type': typeString,
      'style_prompt': stylePrompt,
      'examples_json': examplesJson,
      'negative_examples_json': negativeExamplesJson,
      'is_builtin': isBuiltin ? 1 : 0,
      'created_at': createdAtMs,
      'updated_at': updatedAtMs,
    };
  }
}
