import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';

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

  @override
  void initState() {
    super.initState();
    fetchData('today');
    fetchDebts();
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

  // قسم سفلي: حسابات المطاعم (ديون المحلات)
  Widget _buildMarketsDebts() {
    if (debts == null || debts!['data'] == null) return const SizedBox();
    List markets = debts!['data'];
    double total = _toDouble(debts!['total_debts']);

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "حسابات المطاعم",
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Text(
                "الإجمالي: ${total.toStringAsFixed(0)} دج",
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.red.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (markets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  "لا توجد ديون حالياً",
                  style: GoogleFonts.cairo(fontSize: 13, color: Colors.grey),
                ),
              ),
            )
          else
            ...markets.map((m) {
              double d = _toDouble(m['debt']);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(0xFFFFF3E0),
                      child: Icon(Icons.store, size: 16, color: Colors.orange),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        m['name']?.toString() ?? '-',
                        style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      "${d.toStringAsFixed(2)} دج",
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
        ],
      ),
    );
  }
}
