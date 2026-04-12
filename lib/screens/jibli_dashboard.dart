import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:jibli_stats/screens/market_orders_screen.dart';
import 'package:jibli_stats/services/excel_service.dart';

class JibliDashboard extends StatefulWidget {
  const JibliDashboard({super.key});

  @override
  State<JibliDashboard> createState() => _JibliDashboardState();
}

class _JibliDashboardState extends State<JibliDashboard> {
  Map<String, dynamic>? data;
  String selectedPeriod = 'today';
  bool isLoading = true;

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
      setState(() => isLoading = false);
      debugPrint("Error fetching data: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    fetchData('today');
  }

  // 1. دالة حساب نسبة النمو للمستثمر
  Widget _buildGrowthRate() {
    if (data == null || data!['monthly_trend'] == null) return const SizedBox();
    List trend = data!['monthly_trend'];
    if (trend.length < 2) return const SizedBox();

    double currentMonth = _toDouble(trend.last['profit']);
    double previousMonth = _toDouble(trend[trend.length - 2]['profit']);

    if (previousMonth == 0) return const SizedBox();

    double growth = ((currentMonth - previousMonth) / previousMonth) * 100;
    bool isPositive = growth >= 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isPositive ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isPositive ? Icons.trending_up : Icons.trending_down,
            color: isPositive ? Colors.green : Colors.red,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            "${isPositive ? '+' : ''}${growth.toStringAsFixed(1)}%",
            style: GoogleFonts.cairo(
              color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // 2. دالة الرسم البياني للأرباح الشهرية
  Widget _buildMonthlyChart() {
    if (data == null || data!['monthly_trend'] == null) return const SizedBox();
    List trend = data!['monthly_trend'];

    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(10, 20, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
        ],
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: 150000,
          barGroups: trend.asMap().entries.map((e) {
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: _toDouble(e.value['profit']),
                  color: Colors.orange,
                  width: 16,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          }).toList(),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, meta) {
                  int idx = val.toInt();
                  String label = '';
                  if (idx >= 0 && idx < trend.length) {
                    final monthName = trend[idx]?['month_name'];
                    label = monthName?.toString() ?? '';
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(label, style: const TextStyle(fontSize: 10)),
                  );
                },
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
        ),
      ),
    );
  }

  // 3. جدول ترند شهري مع متوسط الربح لكل طلب
  Widget _buildMonthlyTrendTable() {
    if (data == null || data!['monthly_trend'] == null) return const SizedBox();
    List trend = data!['monthly_trend'];
    if (trend.isEmpty) return const SizedBox();

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "تفاصيل الأرباح الشهرية",
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  "الشهر",
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: Text(
                  "إجمالي الربح (دج)",
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: Text(
                  "متوسط الربح لكل طلب (دج)",
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Divider(),
          ...trend.map((item) {
            final profit = _toDouble(item['profit']);
            final monthlyAvgFromApi = _toDouble(item['monthly_avg']);
            final orders = item['orders'] is num
                ? item['orders'] as int
                : int.tryParse(item['orders']?.toString() ?? '0') ?? 0;
            final avg = monthlyAvgFromApi > 0
                ? monthlyAvgFromApi
                : (orders > 0 ? profit / orders : 0.0);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item['month_name']?.toString() ?? '-',
                      style: GoogleFonts.cairo(fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      profit.toStringAsFixed(2),
                      style: GoogleFonts.cairo(fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      avg.toStringAsFixed(2),
                      style: GoogleFonts.cairo(fontSize: 12),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // 4. قائمة الموزعين النشطين
  Widget _buildActiveDriversList() {
    if (data == null || data!['active_drivers'] == null) {
      return const SizedBox();
    }
    List drivers = data!['active_drivers'];
    if (drivers.isEmpty) {
      return Center(
        child: Text("لا يوجد موزعين نشطين حالياً", style: GoogleFonts.cairo()),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: drivers.length,
      itemBuilder: (context, index) {
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.orange.shade100,
              child: const Icon(Icons.delivery_dining, color: Colors.orange),
            ),
            title: Text(
              drivers[index]?['name']?.toString() ?? '-',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              "توصيل ${drivers[index]?['orders_delivered'] ?? 0} طلبات",
              style: GoogleFonts.cairo(fontSize: 12),
            ),
            trailing: const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 20,
            ),
          ),
        );
      },
    );
  }

  Future<void> _syncExcelCommission() async {
    // إظهار رسالة "جاري المزامنة..."
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("جاري مزامنة الديون من السيرفر...")),
    );

    try {
      // استدعاء الخدمة
      await ExcelService().syncFromWebExcel();

      // تنبيه بالنجاح
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم تحديث الديون بنجاح!")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("فشل التزامن: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: Text(
          "لوحة تحكم جيبلي",
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFilterChips(),
                  const SizedBox(height: 20),
                  _buildMainProfitCard(),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.file_upload),
                    label: const Text('تحديث الديون من الإكسل'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _syncExcelCommission,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.list_alt),
                    label: const Text('عرض نسبة المحلات'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MarketOrdersScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "تحليل النمو الشهري",
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      _buildGrowthRate(),
                    ],
                  ),
                  const SizedBox(height: 15),
                  _buildMonthlyChart(),
                  _buildMonthlyTrendTable(),
                  const SizedBox(height: 30),
                  Text(
                    "الموزعون النشطون اليوم",
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 15),
                  _buildActiveDriversList(),
                ],
              ),
            ),
    );
  }

  Widget _buildFilterChips() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: ['today', 'week', 'month'].map((p) {
        bool isSelected = selectedPeriod == p;
        return ChoiceChip(
          label: Text(
            p == 'today'
                ? 'اليوم'
                : p == 'week'
                ? 'الأسبوع'
                : 'الشهر',
          ),
          selected: isSelected,
          onSelected: (v) => fetchData(p),
          selectedColor: Colors.orange,
          labelStyle: GoogleFonts.cairo(
            color: isSelected ? Colors.white : Colors.black,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMainProfitCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF8C00), Color(0xFFFF4500)],
        ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            "إجمالي الأرباح للفترة",
            style: GoogleFonts.cairo(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 5),
          Text(
            "${data?['period_profit'] ?? 0} دج",
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
