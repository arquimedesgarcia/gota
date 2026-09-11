class Municipality {
  const Municipality({
    required this.id,
    required this.name,
    required this.state,
    required this.country,
    required this.isActive,
  });

  final String id;
  final String name;
  final String state;
  final String country;
  final bool isActive;

  factory Municipality.fromJson(Map<String, dynamic> json) => Municipality(
        id: json['id'] as String,
        name: json['name'] as String,
        state: json['state'] as String? ?? '',
        country: json['country'] as String? ?? '',
        isActive: json['is_active'] as bool? ?? false,
      );
}
