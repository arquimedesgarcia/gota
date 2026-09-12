class AppUser {
  const AppUser({
    required this.id,
    required this.authUserId,
    required this.createdAt,
    required this.lastSeenAt,
    required this.isBlocked,
  });

  final String id;
  final String authUserId;
  final DateTime createdAt;
  final DateTime? lastSeenAt;
  final bool isBlocked;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    authUserId: json['auth_user_id'] as String? ?? '',
    createdAt: _parseDate(json['created_at']),
    lastSeenAt: _parseDateOrNull(json['last_seen_at']),
    isBlocked: json['is_blocked'] as bool? ?? false,
  );

  static DateTime _parseDate(Object? value) =>
      DateTime.tryParse(value as String? ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  static DateTime? _parseDateOrNull(Object? value) =>
      DateTime.tryParse(value as String? ?? '');
}
