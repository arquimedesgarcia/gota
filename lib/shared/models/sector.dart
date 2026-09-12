class Sector {
  const Sector({
    required this.id,
    required this.municipalityId,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String municipalityId;
  final String name;
  final bool isActive;

  factory Sector.fromJson(Map<String, dynamic> json) => Sector(
    id: json['id'] as String,
    municipalityId: json['municipality_id'] as String,
    name: json['name'] as String,
    isActive: json['is_active'] as bool? ?? false,
  );
}
