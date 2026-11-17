import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart';
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
                icon: const Icon(Icons.grid_on, color: Colors.green.shade700),
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
                      child: Text(
                        "${m['name'] ?? '-'}",
                        style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

  // جلب بيانات الجدول الجاهزة للتصدير
  List<List<dynamic>> _debtsTableData() {
    List markets = debts?['data'] ?? [];
    double total = _toDouble(debts?['total_debts']);
    double totalAmount = _toDouble(debts?['total_orders_amount']);

    final rows = <List<dynamic>>[
      ['المطعم', 'عدد الطلبات', 'مجموع الطلبات', 'العمولة المستحقة'],
    ];
    for (var m in markets) {
      rows.add([
        m['name']?.toString() ?? '-',
        '${m['orders_count'] ?? 0}',
        '${_toDouble(m['total_orders_amount']).toStringAsFixed(2)}',
        '${_toDouble(m['debt']).toStringAsFixed(2)}',
      ]);
    }
    rows.add(['الإجمالي', '', totalAmount.toStringAsFixed(2), total.toStringAsFixed(2)]);
    return rows;
  }

  // تصدير PDF
  Future<void> _exportPdf() async {
    try {
      final fontData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
      final ttf = pw.Font.ttf(fontData);
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
                  pw.Table.fromTextArray(
                    headers: tableData.first.cast<String>(),
                    data: tableData.sublist(1).map((r) => r.map((c) => c.toString()).toList()).toList(),
                    headerStyle: pw.TextStyle(font: ttf, fontSize: 11, fontWeight: pw.FontWeight.bold),
                    cellStyle: pw.TextStyle(font: ttf, fontSize: 10),
                    cellAlignment: pw.Alignment.center,
                    headerAlignment: pw.Alignment.center,
                    border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFCCCCCC), width: 0.5),
                    oddRowColor: const PdfColor.fromInt(0xFFF8F9FB),
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
      final file = File('${dir.path}/حسابات_المطاعم_${now.year}-${now.month}-${now.day}.pdf');
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
        sheet.appendRow(row);
      }

      // تنسيق عرض الأعمدة
      sheet.setColumnWidth(0, 30);
      sheet.setColumnWidth(1, 14);
      sheet.setColumnWidth(2, 18);
      sheet.setColumnWidth(3, 18);

      final bytes = excel.encode()!;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/حسابات_المطاعم_${now.year}-${now.month}-${now.day}.xlsx');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'حسابات المطاعم');
    } catch (e) {
      debugPrint("Excel Export Error: $e");
    }
  }
}
