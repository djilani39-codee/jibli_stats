import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' hide Border;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(
  const MaterialApp(debugShowCheckedModeBanner: false, home: JibliDashboard()),
);

class JibliDashboard extends StatefulWidget {
  const JibliDashboard({super.key});

  @override
  State<JibliDashboard> createState() => _JibliDashboardState();
}

class _JibliDashboardState extends State<JibliDashboard> {
  Map<String, dynamic>? data;
  Map<String, dynamic>? debts; // حسابات المطاعم (ديون المحلات)
  Map<int, int> debtsByUser = {}; // إجمالي الدين غير المسدد لكل موزع
  List debtEntries = []; // كل الديون غير المسددة
  int grandDebt = 0;
  String selectedPeriod = 'today';
  bool isLoading = true;

  // تحويل القيم بأمان لمنع أخطاء النوع (Double/Int)
  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  Future<void> fetchData(String period) async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(
        Uri.parse(
          'https://foodwood.site/jibli/public/api/jibli-analytics?period=$period',
        ),
      );
      if (response.statusCode == 200) {
        setState(() {
          data = json.decode(response.body)['data'];
          selectedPeriod = period;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
      setState(() => isLoading = false);
    }
  }

  Future<void> fetchDebts() async {
    try {
      final response = await http.get(
        Uri.parse('https://foodwood.site/jibli/public/api/markets-debts'),
      );
      if (response.statusCode == 200) {
        setState(() {
          debts = json.decode(response.body);
        });
      }
    } catch (e) {
      debugPrint("Debts Error: $e");
    }
  }

  // ===== جلب ديون الموزعين (دفتر الديون) =====
  static const String _chargeSecret = 'JibliStats#2026\$Charge';
  static const String _chargeUrl = 'https://foodwood.site/jibli/public/credit_charge.php';

  Future<void> fetchDriverDebts() async {
    try {
      final res = await http.post(
        Uri.parse(_chargeUrl),
        headers: {
          'Content-Type': 'application/json',
          'X-App-Key': _chargeSecret,
        },
        body: json.encode({'action': 'list'}),
      );
      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body['success'] == true) {
          final totals = <int, int>{};
          for (var t in (body['totals'] ?? [])) {
            final uid = int.tryParse('${t['user_id']}') ?? 0;
            totals[uid] = int.tryParse('${t['total']}') ?? 0;
          }
          setState(() {
            debtsByUser = totals;
            debtEntries = body['entries'] ?? [];
            grandDebt = int.tryParse('${body['grand_total']}') ?? 0;
          });
        }
      }
    } catch (e) {
      debugPrint("Driver Debts Error: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    fetchData('today');
    fetchDebts();
    fetchDriverDebts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: Text(
          "تحليلات جيبلي",
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : RefreshIndicator(
              onRefresh: () => fetchData(selectedPeriod),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFilters(),
                    const SizedBox(height: 20),
                    _buildSummaryCards(),
                    const SizedBox(height: 25),
                    _buildSectionTitle("نمو الأرباح والطلبات"),
                    _buildCorrectedChart(), // المنحنى المنضبط داخل المربع
                    _buildTodayOrders(),
                    const SizedBox(height: 25),
                    _buildSectionTitle("السجل اليومي وأداء الموصلين"),
                    _buildDailyListWithDrivers(), // الموصلين في مستطيلات
                    const SizedBox(height: 25),
                    _buildMarketsDebts(), // حسابات المطاعم (قسم سفلي)
                    const SizedBox(height: 25),
                    _buildSectionTitle("فلكسي الموزعين"),
                    _buildDriversFlexi(), // فلكسي الموزعين النشطين آخر شهر
                  ],
                ),
              ),
            ),
    );
  }

  // إصلاح المنحنى البياني لمنع الخروج عن الإطار
  Widget _buildCorrectedChart() {
    if (data?['monthly_trend'] == null) return const SizedBox();
    List trend = data!['monthly_trend'];

    double maxP = 0;
    double maxO = 0;
    // جلب أعلى قيمة للربح وأعلى عدد للطلبات بشكل منفصل
    for (var m in trend) {
      if (_toDouble(m['profit']) > maxP) maxP = _toDouble(m['profit']);
      if (_toDouble(m['orders']) > maxO) maxO = _toDouble(m['orders']);
    }

    // سقف الرسم يعتمد على الربح (لأنه القيمة الأكبر دائماً)
    double chartMaxY = maxP > 0 ? maxP * 1.3 : 1000;

    return Container(
      height: 260,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.fromLTRB(10, 25, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: chartMaxY,
          barGroups: trend.asMap().entries.map((e) {
            double actualProfit = _toDouble(e.value['profit']);
            double actualOrders = _toDouble(e.value['orders']);

            // تصحيح: تحجيم عمود الطلبات ليتناسب بصرياً مع الربح دون تغيير قيمته الحقيقية في العرض
            // نستخدم نسبة وتناسب (إذا كان أعلى ربح هو 50000 وأعلى طلب هو 100، نجعل الـ 100 تصل لـ 70% من ارتفاع الـ 50000)
            double visualScaledOrders = maxO > 0
                ? (actualOrders / maxO) * (maxP * 0.7)
                : 0;

            return BarChartGroupData(
              x: e.key,
              barRods: [
                // عمود الربح (برتقالي)
                BarChartRodData(
                  toY: actualProfit,
                  color: Colors.orange,
                  width: 12,
                  borderRadius: BorderRadius.circular(4),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: chartMaxY,
                    color: Colors.grey.withOpacity(0.05),
                  ),
                ),
                // عمود الطلبات (أزرق فاتح) - تم تصحيح الحساب هنا
                BarChartRodData(
                  toY: visualScaledOrders,
                  color: Colors.blue.withOpacity(0.4),
                  width: 12,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
              // لإظهار القيم الحقيقية عند الضغط على العمود (اختياري)
              showingTooltipIndicators: [],
            );
          }).toList(),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, m) => Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    trend[v.toInt()]['month_name'],
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                String label = rodIndex == 0 ? "ربح: " : "طلبات: ";
                String value = rodIndex == 0
                    ? "${trend[groupIndex]['profit']} دج"
                    : "${trend[groupIndex]['orders']}";
                return BarTooltipItem(
                  label + value,
                  const TextStyle(color: Colors.white, fontSize: 10),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // السجل اليومي المنسق في مستطيلات مع الموصلين
  Widget _buildDailyListWithDrivers() {
    List daily = data?['daily_breakdown'] ?? [];
    return Column(
      children: daily.map((day) {
        return Container(
          margin: const EdgeInsets.only(bottom: 15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10),
            ],
          ),
          child: ExpansionTile(
            shape: const RoundedRectangleBorder(side: BorderSide.none),
            leading: const Icon(Icons.receipt_long, color: Colors.blueGrey),
            title: Text(
              day['order_day'],
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            trailing: Text(
              "${day['profit_total']} دج",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
                fontSize: 15,
              ),
            ),
            children: [
              const Divider(height: 1),
              if (day['drivers'] != null && (day['drivers'] as List).isNotEmpty)
                ...(day['drivers'] as List)
                    .map(
                      (driver) => ListTile(
                        leading: const CircleAvatar(
                          radius: 12,
                          backgroundColor: Color(0xFFFFF3E0),
                          child: Icon(
                            Icons.person,
                            size: 14,
                            color: Colors.orange,
                          ),
                        ),
                        title: Text(
                          driver['name'],
                          style: GoogleFonts.cairo(fontSize: 13),
                        ),
                        trailing: Text(
                          "${driver['orders_count']} طلبات",
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    )
                    .toList()
              else
                const Padding(
                  padding: EdgeInsets.all(15),
                  child: Text(
                    "لا توجد بيانات موصلين",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            "إجمالي الربح",
            "${_toDouble(data?['period_profit']).toInt()} دج",
            Colors.orange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            "متوسط الربح",
            "${_toDouble(data?['period_avg']).toStringAsFixed(1)} دج",
            Colors.blue,
          ),
        ),
      ],
    );
  }

  Widget _statCard(String t, String v, Color c) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      children: [
        Text(t, style: GoogleFonts.cairo(fontSize: 10, color: Colors.grey)),
        Text(
          v,
          style: GoogleFonts.cairo(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: c,
          ),
        ),
      ],
    ),
  );

  Widget _buildFilters() {
    final p = {
      'today': 'اليوم',
      'yesterday': 'الأمس',
      'week': 'الأسبوع',
      'month': 'الشهر',
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: p.entries
          .map(
            (e) => ChoiceChip(
              label: Text(e.value, style: GoogleFonts.cairo(fontSize: 11)),
              selected: selectedPeriod == e.key,
              onSelected: (_) => fetchData(e.key),
              selectedColor: Colors.orange,
              labelStyle: TextStyle(
                color: selectedPeriod == e.key ? Colors.white : Colors.black,
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildSectionTitle(String t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(
      t,
      style: GoogleFonts.cairo(
        fontWeight: FontWeight.bold,
        fontSize: 15,
        color: Colors.blueGrey,
      ),
    ),
  );

  // قسم طلبات اليوم: رقم الطلب، الزبون، السائق، وقت الحجز
  Widget _buildTodayOrders() {
    if (data == null || data!['today_orders'] == null) return const SizedBox();
    List orders = data!['today_orders'];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "طلبات اليوم",
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 10),
          if (orders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  "لا توجد طلبات بعد اليوم",
                  style: GoogleFonts.cairo(fontSize: 13, color: Colors.grey),
                ),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text("رقم الطلب", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                Expanded(
                  child: Text("الزبون", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                Expanded(
                  child: Text("السائق", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                Expanded(
                  child: Text("وقت الحجز", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            ),
            const Divider(),
            ...orders.map((o) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "#${o['order_id'] ?? '-'}",
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        o['customer_name']?.toString() ?? '-',
                        style: GoogleFonts.cairo(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        o['driver_name']?.toString() ?? '—',
                        style: GoogleFonts.cairo(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        o['booked_at']?.toString() ?? '-',
                        style: GoogleFonts.cairo(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ],
      ),
    );
  }

  // قسم سفلي: حسابات المطاعم (العمولات المستحقة — غير المسواة فقط مثل لوحة التحكم)
  Widget _buildMarketsDebts() {
    if (debts == null || debts!['data'] == null) return const SizedBox();
    List markets = debts!['data'];
    double total = _toDouble(debts!['total_debts']);
    double totalAmount = _toDouble(debts!['total_orders_amount']);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "حسابات المطاعم",
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                tooltip: "تصدير PDF",
                onPressed: markets.isEmpty ? null : _exportPdf,
              ),
              IconButton(
                icon: Icon(Icons.grid_on, color: Colors.green.shade700),
                tooltip: "تصدير Excel",
                onPressed: markets.isEmpty ? null : _exportExcel,
              ),
            ],
          ),
          Text(
            "العمولات المستحقة (الطلبات غير المسواة)",
            style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          if (markets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  "لا توجد عمولات مستحقة حالياً",
                  style: GoogleFonts.cairo(fontSize: 13, color: Colors.grey),
                ),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text("المطعم", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                Expanded(
                  child: Text("الطلبات", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center),
                ),
                Expanded(
                  flex: 2,
                  child: Text("مجموع الطلبات", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center),
                ),
                Expanded(
                  flex: 2,
                  child: Text("العمولة", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.left),
                ),
              ],
            ),
            const Divider(),
            ...markets.map((m) {
              double d = _toDouble(m['debt']);
              double amt = _toDouble(m['total_orders_amount']);
              int cnt = (m['orders_count'] is int) ? m['orders_count'] : int.tryParse('${m['orders_count']}') ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              "${m['name'] ?? '-'}",
                              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 2),
                          InkWell(
                            onTap: () => _exportMarketPdf(m),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(Icons.picture_as_pdf, size: 17, color: Colors.red.shade400),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Text(
                        "$cnt",
                        style: GoogleFonts.cairo(fontSize: 12, color: Colors.blueGrey),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        "${amt.toStringAsFixed(0)}",
                        style: GoogleFonts.cairo(fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        "${d.toStringAsFixed(2)} دج",
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                        textAlign: TextAlign.left,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            const Divider(),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      "الإجمالي",
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      "${totalAmount.toStringAsFixed(0)}",
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      "${total.toStringAsFixed(2)} دج",
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.red.shade700,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDriversFlexi() {
    final flexi = debts?['flexi'];
    if (flexi == null || flexi['data'] == null) return const SizedBox();
    List users = flexi['data'];
    int count = (flexi['count'] is int) ? flexi['count'] : int.tryParse('${flexi['count']}') ?? 0;
    int totalFlexi = (flexi['total'] is int) ? flexi['total'] : int.tryParse('${flexi['total']}') ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "الموزعون النشطون (آخر 30 يوم)",
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                tooltip: "تصدير PDF",
                onPressed: users.isEmpty ? null : _exportFlexiPdf,
              ),
              IconButton(
                icon: Icon(Icons.grid_on, color: Colors.green.shade700),
                tooltip: "تصدير Excel",
                onPressed: users.isEmpty ? null : _exportFlexiExcel,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // ملخص: عدد الموزعين + إجمالي الفلكسي
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text("عدد الموزعين", style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      Text("$count", style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text("إجمالي الفلكسي", style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      Text("$totalFlexi", style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text("إجمالي الديون", style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      Text("$grandDebt", style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (users.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  "لا يوجد موزعون نشطون",
                  style: GoogleFonts.cairo(fontSize: 13, color: Colors.grey),
                ),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text("الموزع", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                Expanded(
                  flex: 3,
                  child: Text("الهاتف", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center),
                ),
                Expanded(
                  flex: 2,
                  child: Text("طلبات آخر شهر", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center),
                ),
                Expanded(
                  flex: 2,
                  child: Text("الفلكسي", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.left),
                ),
              ],
            ),
            const Divider(),
            ...users.map((u) {
              int credit = (u['credit'] is int) ? u['credit'] : int.tryParse('${u['credit']}') ?? 0;
              int orders30 = (u['orders_30'] is int) ? u['orders_30'] : int.tryParse('${u['orders_30']}') ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              "${u['name'] ?? '-'}",
                              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 2),
                          InkWell(
                            onTap: () => _showChargeDialog(u),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(Icons.add_card, size: 18, color: Colors.green.shade700),
                            ),
                          ),
                          InkWell(
                            onTap: () => _showDebtsDialog(u),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.receipt_long,
                                size: 18,
                                color: (debtsByUser[int.tryParse('${u['id']}') ?? 0] ?? 0) > 0
                                    ? Colors.red.shade600
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        "${u['phone'] ?? '-'}",
                        style: GoogleFonts.cairo(fontSize: 11, color: Colors.blueGrey),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        "$orders30",
                        style: GoogleFonts.cairo(fontSize: 12, color: Colors.blue.shade700),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        "$credit",
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                        textAlign: TextAlign.left,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ],
      ),
    );
  }

  // جلب بيانات الجدول الجاهزة للتصدير
  List<List<String>> _debtsTableData() {
    List markets = debts?['data'] ?? [];
    double total = _toDouble(debts?['total_debts']);
    double totalAmount = _toDouble(debts?['total_orders_amount']);

    final rows = <List<String>>[
      ['المطعم', 'عدد الطلبات', 'مجموع الطلبات', 'العمولة المستحقة'],
    ];
    for (var m in markets) {
      rows.add([
        m['name']?.toString() ?? '-',
        '${m['orders_count'] ?? 0}',
        _toDouble(m['total_orders_amount']).toStringAsFixed(2),
        _toDouble(m['debt']).toStringAsFixed(2),
      ]);
    }
    rows.add(['الإجمالي', '', totalAmount.toStringAsFixed(2), total.toStringAsFixed(2)]);
    return rows;
  }

  Future<pw.Font> _loadArabicFont() async {
    final fontData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
    return pw.Font.ttf(fontData);
  }

  // تصدير PDF (قائمة المطاعم)
  Future<void> _exportPdf() async {
    try {
      final ttf = await _loadArabicFont();
      final pdf = pw.Document();
      final tableData = _debtsTableData();
      final now = DateTime.now();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'حسابات المطاعم - جيبلي',
                    style: pw.TextStyle(font: ttf, fontSize: 18, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    'العمولات المستحقة (الطلبات غير المسواة) - ${now.year}/${now.month}/${now.day}',
                    style: pw.TextStyle(font: ttf, fontSize: 10, color: const PdfColor.fromInt(0xFF777777)),
                  ),
                  pw.SizedBox(height: 12),
                  pw.TableHelper.fromTextArray(
                    headers: tableData.first,
                    data: tableData.sublist(1),
                    headerStyle: pw.TextStyle(font: ttf, fontSize: 11, fontWeight: pw.FontWeight.bold),
                    cellStyle: pw.TextStyle(font: ttf, fontSize: 10),
                    cellAlignment: pw.Alignment.center,
                    headerAlignment: pw.Alignment.center,
                    border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFCCCCCC), width: 0.5),
                    cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Text(
                    'تم التصدير من تطبيق جيبلي ستاتس',
                    style: pw.TextStyle(font: ttf, fontSize: 9, color: const PdfColor.fromInt(0xFF999999)),
                  ),
                ],
              ),
            );
          },
        ),
      );

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/markets_accounts_${now.year}-${now.month}-${now.day}.pdf');
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles([XFile(file.path)], text: 'حسابات المطاعم');
    } catch (e) {
      debugPrint("PDF Export Error: $e");
    }
  }

  // تصدير Excel
  Future<void> _exportExcel() async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['حسابات المطاعم'];
      final tableData = _debtsTableData();
      final now = DateTime.now();

      for (final row in tableData) {
        sheet.appendRow(row.map((c) => TextCellValue(c.toString())).toList());
      }

      // تنسيق عرض الأعمدة
      sheet.setColumnWidth(0, 30);
      sheet.setColumnWidth(1, 14);
      sheet.setColumnWidth(2, 18);
      sheet.setColumnWidth(3, 18);

      final bytes = excel.encode()!;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/markets_accounts_${now.year}-${now.month}-${now.day}.xlsx');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'حسابات المطاعم');
    } catch (e) {
      debugPrint("Excel Export Error: $e");
    }
  }

  // PDF تفصيلي لمطعم واحد: كل طلباته غير المسواة بالتفصيل
  Future<void> _exportMarketPdf(Map m) async {
    try {
      final ttf = await _loadArabicFont();
      final pdf = pw.Document();
      final now = DateTime.now();

      final name = m['name']?.toString() ?? '-';
      final rate = _toDouble(m['admin_commission']);
      final ordersCount = m['orders_count']?.toString() ?? '0';
      final totalAmount = _toDouble(m['total_orders_amount']);
      final debt = _toDouble(m['debt']);
      List details = m['details'] ?? [];

      // صفوف التفاصيل: منتج [خيارات] | سعر | كمية | مجموع | عمولة | رقم الطلب | وقت الطلب
      final tableRows = <List<String>>[];
      for (var d in details) {
        final opts = (d['options'] is List) ? (d['options'] as List).join(' + ') : '';
        String productName = d['product_name']?.toString() ?? '-';
        if (opts.isNotEmpty) productName += ' [$opts]';
        tableRows.add([
          productName,
          _toDouble(d['price']).toStringAsFixed(2),
          '${d['quantity'] ?? ''}',
          _toDouble(d['total']).toStringAsFixed(2),
          _toDouble(d['commission']).toStringAsFixed(2),
          '#${d['order_id'] ?? ''}',
          d['ordered_at']?.toString() ?? '',
        ]);
      }
      // صف الإجمالي
      tableRows.add([
        'الإجمالي',
        '',
        ordersCount,
        totalAmount.toStringAsFixed(2),
        debt.toStringAsFixed(2),
        '',
        '',
      ]);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          build: (pw.Context context) => [
            // اسم المطعم في الأعلى + المجموع
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFFFF3E0),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    name,
                    style: pw.TextStyle(font: ttf, fontSize: 20, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'تفاصيل الطلبات غير المسواة - العمولة ${rate.toStringAsFixed(0)}% - ${now.year}/${now.month}/${now.day}',
                    style: pw.TextStyle(font: ttf, fontSize: 10, color: const PdfColor.fromInt(0xFF777777)),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                    children: [
                      pw.Column(children: [
                        pw.Text('عدد الطلبات', style: pw.TextStyle(font: ttf, fontSize: 9, color: const PdfColor.fromInt(0xFF888888))),
                        pw.Text(ordersCount, style: pw.TextStyle(font: ttf, fontSize: 13, fontWeight: pw.FontWeight.bold)),
                      ]),
                      pw.Column(children: [
                        pw.Text('مجموع الطلبات', style: pw.TextStyle(font: ttf, fontSize: 9, color: const PdfColor.fromInt(0xFF888888))),
                        pw.Text('${totalAmount.toStringAsFixed(2)} دج', style: pw.TextStyle(font: ttf, fontSize: 13, fontWeight: pw.FontWeight.bold)),
                      ]),
                      pw.Column(children: [
                        pw.Text('العمولة المستحقة', style: pw.TextStyle(font: ttf, fontSize: 9, color: const PdfColor.fromInt(0xFF888888))),
                        pw.Text('${debt.toStringAsFixed(2)} دج', style: pw.TextStyle(font: ttf, fontSize: 13, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFFB71C1C))),
                      ]),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: ['المنتج [الخيارات]', 'السعر', 'الكمية', 'المجموع', 'العمولة', 'رقم الطلب', 'وقت الطلب'],
              data: tableRows,
              headerStyle: pw.TextStyle(font: ttf, fontSize: 10, fontWeight: pw.FontWeight.bold),
              cellStyle: pw.TextStyle(font: ttf, fontSize: 9),
              cellAlignment: pw.Alignment.center,
              headerAlignment: pw.Alignment.center,
              border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFCCCCCC), width: 0.5),
              headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF0F0F0)),
              cellPadding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 3),
              columnWidths: {
                0: const pw.FixedColumnWidth(110),
                1: const pw.FixedColumnWidth(45),
                2: const pw.FixedColumnWidth(35),
                3: const pw.FixedColumnWidth(55),
                4: const pw.FixedColumnWidth(55),
                5: const pw.FixedColumnWidth(50),
                6: const pw.FixedColumnWidth(75),
              },
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'تم التصدير من تطبيق جيبلي ستاتس',
              style: pw.TextStyle(font: ttf, fontSize: 9, color: const PdfColor.fromInt(0xFF999999)),
            ),
          ],
        ),
      );

      // اسم ملف ASCII لضمان الفتح على كل الأجهزة
      final safeName = name
          .replaceAll(RegExp(r'[^\x00-\x7F]'), '')
          .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
          .trim();
      final fileName = 'debt_${safeName.isEmpty ? 'market' : safeName}_${now.year}-${now.month}-${now.day}.pdf';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles([XFile(file.path)], text: 'حسابات $name');
    } catch (e) {
      debugPrint("Market PDF Export Error: $e");
    }
  }

  // ===== شحن رصيد (فلكسي) الموزع =====
  Future<void> _chargeCredit(int userId, int amount) async {
    try {
      final res = await http.post(
        Uri.parse(_chargeUrl),
        headers: {
          'Content-Type': 'application/json',
          'X-App-Key': _chargeSecret,
        },
        body: json.encode({'user_id': userId, 'amount': amount}),
      );
      final body = json.decode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.green.shade700,
              content: Text(
                "تم شحن ${body['name']} بـ $amount دج — الرصيد الجديد: ${body['new']} دج — الدين: ${body['total_debt'] ?? amount} دج",
                style: GoogleFonts.cairo(fontSize: 13),
              ),
            ),
          );
        }
        await fetchDebts();
        await fetchDriverDebts();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade700,
              content: Text(
                _errMsg(body['message']),
                style: GoogleFonts.cairo(fontSize: 13),
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Charge Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text("خطأ في الاتصال: $e", style: GoogleFonts.cairo(fontSize: 13)),
          ),
        );
      }
    }
  }

  // ===== دفتر ديون الموزع =====
  String _errMsg(dynamic code) {
    switch ('$code') {
      case 'forbidden':
        return 'غير مصرح';
      case 'missing_user':
        return 'الموزع غير محدد';
      case 'not_found':
        return 'الموزع غير موجود';
      case 'not_driver':
        return 'هذا المستخدم ليس موزعاً';
      case 'bad_amount':
        return 'المبلغ غير صالح';
      case 'missing_debt_id':
        return 'الدين غير محدد';
      case 'debt_not_found':
        return 'الدين غير موجود';
      case 'server_error':
        return 'خطأ في السيرفر';
      default:
        return 'فشل: $code';
    }
  }

  Future<void> _payDebt(int userId, int debtId) async {
    try {
      final res = await http.post(
        Uri.parse(_chargeUrl),
        headers: {'Content-Type': 'application/json', 'X-App-Key': _chargeSecret},
        body: json.encode({'action': 'pay', 'user_id': userId, 'debt_id': debtId}),
      );
      final body = json.decode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        await fetchDriverDebts();
        if (mounted) _toast('تم تسديد ${body['amount'] ?? ''} دج', Colors.green.shade700);
      } else {
        if (mounted) _toast(_errMsg(body['message']), Colors.red.shade700);
      }
    } catch (e) {
      debugPrint("Pay Debt Error: $e");
    }
  }

  Future<void> _payAllDebts(int userId) async {
    try {
      final res = await http.post(
        Uri.parse(_chargeUrl),
        headers: {'Content-Type': 'application/json', 'X-App-Key': _chargeSecret},
        body: json.encode({'action': 'pay', 'user_id': userId, 'all': 1}),
      );
      final body = json.decode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        await fetchDriverDebts();
        if (mounted) _toast('تم تسديد كل ديون ${body['name'] ?? ''} ✅', Colors.green.shade700);
      } else {
        if (mounted) _toast(_errMsg(body['message']), Colors.red.shade700);
      }
    } catch (e) {
      debugPrint("PayAll Debt Error: $e");
    }
  }

  Future<void> _addManualDebt(int userId, int amount, String note) async {
    try {
      final res = await http.post(
        Uri.parse(_chargeUrl),
        headers: {'Content-Type': 'application/json', 'X-App-Key': _chargeSecret},
        body: json.encode({'action': 'add_debt', 'user_id': userId, 'amount': amount, 'note': note}),
      );
      final body = json.decode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        await fetchDriverDebts();
        if (mounted) _toast('تم تسجيل دين ${body['amount'] ?? amount} دج — إجمالي الدين: ${body['total_debt'] ?? ''}', Colors.green.shade700);
      } else {
        if (mounted) _toast(_errMsg(body['message']), Colors.red.shade700);
      }
    } catch (e) {
      debugPrint("Add Debt Error: $e");
    }
  }

  void _toast(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        content: Text(msg, style: GoogleFonts.cairo(fontSize: 13)),
      ),
    );
  }

  Future<void> _showDebtsDialog(Map u) async {
    final int userId = (u['id'] is int) ? u['id'] : int.tryParse('${u['id']}') ?? 0;
    final name = u['name']?.toString() ?? '-';
    final amountController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final myEntries = debtEntries
                .where((e) => (int.tryParse('${e['user_id']}') ?? 0) == userId)
                .toList();
            final total = debtsByUser[userId] ?? 0;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: Text("ديون $name", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16)),
              content: SizedBox(
                width: 340,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: total > 0 ? Colors.red.shade50 : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          total > 0 ? "إجمالي الدين: $total دج" : "لا دين عليه ✅",
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: total > 0 ? Colors.red.shade800 : Colors.green.shade800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (myEntries.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text("لا توجد ديون مسجلة", style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey)),
                        )
                      else ...[
                        ...myEntries.map((e) {
                          final id = int.tryParse('${e['id']}') ?? 0;
                          final amt = int.tryParse('${e['amount']}') ?? 0;
                          final note = (e['note'] ?? '').toString();
                          final date = (e['date'] ?? '').toString();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text("$amt دج", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red.shade700)),
                                      Text("$note — $date", style: GoogleFonts.cairo(fontSize: 10, color: Colors.grey.shade600)),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    foregroundColor: Colors.green.shade700,
                                  ),
                                  onPressed: () async {
                                    await _payDebt(userId, id);
                                    setDialogState(() {});
                                  },
                                  child: Text("تسديد", style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        if (total > 0)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () async {
                                await _payAllDebts(userId);
                                setDialogState(() {});
                              },
                              icon: const Icon(Icons.done_all, size: 18),
                              label: Text("تسديد الكل ($total دج)", style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                            ),
                          ),
                      ],
                      const Divider(height: 24),
                      Text("إضافة دين يدوي (مبلغ أقرضته له)", style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade700)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: amountController,
                              keyboardType: TextInputType.number,
                              style: GoogleFonts.cairo(fontSize: 13),
                              decoration: InputDecoration(
                                labelText: "المبلغ (دج)",
                                labelStyle: GoogleFonts.cairo(fontSize: 11),
                                isDense: true,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade800,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              final amt = int.tryParse(amountController.text.trim()) ?? 0;
                              if (amt <= 0) return;
                              amountController.clear();
                              await _addManualDebt(userId, amt, 'دين يدوي');
                              setDialogState(() {});
                            },
                            child: Text("إضافة", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text("إغلاق", style: GoogleFonts.cairo(color: Colors.grey)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showChargeDialog(Map u) async {
    final int userId = (u['id'] is int) ? u['id'] : int.tryParse('${u['id']}') ?? 0;
    final int current = (u['credit'] is int) ? u['credit'] : int.tryParse('${u['credit']}') ?? 0;
    final name = u['name']?.toString() ?? '-';
    final controller = TextEditingController(text: '2000');

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            void quick(int v) {
              controller.text = '$v';
              setDialogState(() {});
            }

            final amount = int.tryParse(controller.text.trim()) ?? 0;
            final newBalance = current + amount;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: Text("شحن فلكسي", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 17)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text("الرصيد الحالي: $current دج",
                      style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade700)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final v in [2000, 4000])
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: OutlinedButton(
                            onPressed: () => quick(v),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              side: BorderSide(
                                color: amount == v ? Colors.green.shade700 : Colors.grey.shade300,
                                width: amount == v ? 2 : 1,
                              ),
                            ),
                            child: Text("+$v", style: GoogleFonts.cairo(fontSize: 12)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: "المبلغ (دج)",
                      labelStyle: GoogleFonts.cairo(fontSize: 12),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    style: GoogleFonts.cairo(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          "الرصيد بعد الشحن: $newBalance دج",
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade900,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "+ $amount دج سيُسجَّل كدين عليه",
                          style: GoogleFonts.cairo(fontSize: 11, color: Colors.red.shade700),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text("إلغاء", style: GoogleFonts.cairo(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: amount <= 0
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          await _chargeCredit(userId, amount);
                        },
                  child: Text("تأكيد الشحن", style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // جلب صفوف جدول الفلكسي للتصدير
  List<List<String>> _flexiTableData() {
    final flexi = debts?['flexi'];
    List users = (flexi?['data'] ?? []) as List;
    int count = _toDouble(flexi?['count']).toInt();
    int totalFlexi = _toDouble(flexi?['total']).toInt();

    final rows = <List<String>>[
      ['الموزع', 'الهاتف', 'طلبات آخر شهر', 'الفلكسي'],
    ];
    for (var u in users) {
      rows.add([
        u['name']?.toString() ?? '-',
        u['phone']?.toString() ?? '-',
        '${u['orders_30'] ?? 0}',
        '${u['credit'] ?? 0}',
      ]);
    }
    rows.add(['الإجمالي - $count موزع', '', '', '$totalFlexi']);
    return rows;
  }

  // تصدير PDF لفلكسي الموزعين
  Future<void> _exportFlexiPdf() async {
    try {
      final ttf = await _loadArabicFont();
      final pdf = pw.Document();
      final tableData = _flexiTableData();
      final now = DateTime.now();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'فلكسي الموزعين - جيبلي',
                    style: pw.TextStyle(font: ttf, fontSize: 18, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    'الموزعون النشطون آخر 30 يوم - ${now.year}/${now.month}/${now.day}',
                    style: pw.TextStyle(font: ttf, fontSize: 10, color: const PdfColor.fromInt(0xFF777777)),
                  ),
                  pw.SizedBox(height: 12),
                  pw.TableHelper.fromTextArray(
                    headers: tableData.first,
                    data: tableData.sublist(1),
                    headerStyle: pw.TextStyle(font: ttf, fontSize: 11, fontWeight: pw.FontWeight.bold),
                    cellStyle: pw.TextStyle(font: ttf, fontSize: 10),
                    cellAlignment: pw.Alignment.center,
                    headerAlignment: pw.Alignment.center,
                    border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFCCCCCC), width: 0.5),
                    cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Text(
                    'تم التصدير من تطبيق جيبلي ستاتس',
                    style: pw.TextStyle(font: ttf, fontSize: 9, color: const PdfColor.fromInt(0xFF999999)),
                  ),
                ],
              ),
            );
          },
        ),
      );

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/drivers_flexi_${now.year}-${now.month}-${now.day}.pdf');
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles([XFile(file.path)], text: 'فلكسي الموزعين');
    } catch (e) {
      debugPrint("Flexi PDF Export Error: $e");
    }
  }

  // تصدير Excel لفلكسي الموزعين
  Future<void> _exportFlexiExcel() async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['فلكسي الموزعين'];
      final tableData = _flexiTableData();
      final now = DateTime.now();

      for (final row in tableData) {
        sheet.appendRow(row.map((c) => TextCellValue(c.toString())).toList());
      }

      sheet.setColumnWidth(0, 30);
      sheet.setColumnWidth(1, 18);
      sheet.setColumnWidth(2, 16);
      sheet.setColumnWidth(3, 14);

      final bytes = excel.encode()!;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/drivers_flexi_${now.year}-${now.month}-${now.day}.xlsx');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'فلكسي الموزعين');
    } catch (e) {
      debugPrint("Flexi Excel Export Error: $e");
    }
  }
}
