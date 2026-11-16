class JibliStats {
  final int totalUsers;
  final int totalOrders;
  final int totalSms;
  final double totalRevenue;

  JibliStats({
    required this.totalUsers,
    required this.totalOrders,
    required this.totalSms,
    required this.totalRevenue,
  });

  // لتحويل البيانات القادمة من JSON إلى كائن Dart
  factory JibliStats.fromJson(Map<String, dynamic> json) {
    return JibliStats(
      totalUsers: json['total_users'] ?? 0,
      totalOrders: json['total_orders'] ?? 0,
      totalSms: json['total_sms'] ?? 0,
      totalRevenue: (json['total_revenue'] ?? 0).toDouble(),
    );
  }
}
