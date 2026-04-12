# main.dart

```dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:jibli_stats/services/excel_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:excel/excel.dart' as excel hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

// كيفية عرض البيانات في Flutter:
// 1. استخدم ListView.builder لعرض قوائم كبيرة من البيانات
// 2. استخدم Card و ListTile لتصميم عناصر القائمة
// 3. CircleAvatar للصور أو الأرقام التسلسلية
// 4. Column في trailing لعرض معلومات متعددة

// كيفية استخدام ExcelService:
// final service = ExcelService();
// List<MarketData> rawData = await service.syncFromWebExcel();
// List<MarketData> aggregatedData = service.aggregateCommissions(rawData);

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
  String selectedPeriod = 'today';
  bool isLoading = true;
  List<MarketData> syncResults = [];
  bool isSyncing = false;

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
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        print('Decoded data: ${decoded['data']}');
        setState(() {
          data = decoded['data'];
          selectedPeriod = period;
          isLoading = false;
        });
      } else {
        print('Failed to load data: ${response.statusCode}');
        setState(() => isLoading = false);
      }
    } catch (e) {
      print("Error: $e");
      setState(() => isLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    fetchData('today');
  }

  Future<void> _syncMarketPayments() async {
    setState(() => isSyncing = true);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("جاري مزامنة الديون من الإكسل...")),
    );

    try {
      final service = ExcelService();
      final rawResults = await service.syncFromWebExcel();
      
      // تجميع المبالغ لكل سوق في سطر واحد
      final aggregatedResults = service.aggregateCommissions(rawResults);
      
      setState(() {
        syncResults = aggregatedResults;
        isSyncing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("تم تحديث ${aggregatedResults.length} محل بنجاح!"),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      setState(() => isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("خطأ أثناء المزامنة: $e"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// دالة فتح ملف الإكسيل في المتصفح
  Future<void> _openExcelInBrowser() async {
    const String url = "https://foodwood.site/jibli/public/productOrdersDetailsByMarkets/exportExcel";
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("فشل فتح الرابط")),
      );
    }
  }

  /// دالة مشاركة تفاصيل الديون عبر الواتساب
  Future<void> _shareToWhatsApp(String marketName, double amount) async {
    String message = "تحية طيبة، محل $marketName، ديونكم الحالية لخدمة جيبلي هي: ${amount.toStringAsFixed(2)} دج.";
    String url = "whatsapp://send?text=${Uri.encodeComponent(message)}";
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تطبيق واتساب غير مثبت")),
      );
    }
  }

  /// دالة استخراج بيانات محل معين من ملف الإكسيل الكامل
  Future<void> _downloadSpecificMarketSheet(String targetMarketName) async {
    try {
      setState(() => isSyncing = true);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("جاري استخراج بيانات $targetMarketName..."),
          duration: const Duration(seconds: 2),
        ),
      );

      // 1. تحميل الملف الكامل من الإنترنت
      final response = await http.get(
        Uri.parse("https://foodwood.site/jibli/public/productOrdersDetailsByMarkets/exportExcel"),
      );
      if (response.statusCode != 200) {
        throw "خطأ في الاتصال بالسيرفر: ${response.statusCode}";
      }

      // 2. فك تشفير الإكسيل
      var bytes = response.bodyBytes;
      var excelFile = excel.Excel.decodeBytes(bytes);
      
      // 3. إنشاء ملف إكسيل جديد فارغ
      var newExcel = excel.Excel.createExcel();
      bool sheetFound = false;

      // 4. البحث عن الشيت المطلوب ونسخه للملف الجديد
      for (var table in excelFile.tables.keys) {
        if (table == targetMarketName) {
          // حذف الـ Sheet1 الافتراضي وإعادة تسميته
          newExcel.rename('Sheet1', targetMarketName);
          
          var sourceSheet = excelFile.tables[table]!;
          var targetSheet = newExcel.tables[targetMarketName]!;

          // نسخ جميع الصفوف من المصدر إلى الهدف
          for (var row in sourceSheet.rows) {
            targetSheet.appendRow(
              row.map((cell) => cell?.value).toList(),
            );
          }
          sheetFound = true;
          break;
        }
      }

      if (!sheetFound) {
        throw "لم يتم العثور على بيانات لمحل: $targetMarketName";
      }

      // 5. حفظ الملف الجديد في ذاكرة الهاتف الؤقتة
      final directory = await getTemporaryDirectory();
      final filePath = "${directory.path}/$targetMarketName.xlsx";
      final file = File(filePath);
      await file.writeAsBytes(newExcel.encode()!);

      setState(() => isSyncing = false);

      // 6. فتح الملف
      final result = await OpenFilex.open(filePath);
      
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("تم حفظ الملف: $filePath"),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("فشل التحميل: $e"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
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
                    const SizedBox(height: 25),
                    _buildSectionTitle("السجل اليومي وأداء الموصلين"),
                    _buildDailyListWithDrivers(), // الموصلين في مستطيلات
                    const SizedBox(height: 25),
                    _buildSectionTitle("كم يجب أن يدفع لي كل محل"),
                    _buildMarketPayments(),
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

  // قائمة ما يجب أن يدفعه كل محل
  Widget _buildMarketPayments() {
    // إذا كانت هناك نتائج من المزامنة، عرضها، وإلا عرض البيانات من API
    List displayData = [];
    
    if (syncResults.isNotEmpty) {
      displayData = syncResults;
    } else {
      List marketPayments = data?['market_payments'] ?? [];
      displayData = marketPayments;
    }

    if (displayData.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text(
                "لا توجد بيانات محلات",
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 15),
              ElevatedButton.icon(
                icon: const Icon(Icons.download),
                label: const Text("تحميل من الإكسل"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                ),
                onPressed: isSyncing ? null : _syncMarketPayments,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 15),
          child: Stack(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text("تحديث من الإكسل"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  minimumSize: const Size.fromHeight(45),
                  disabledBackgroundColor: Colors.orange.shade300,
                ),
                onPressed: isSyncing ? null : _syncMarketPayments,
              ),
              if (isSyncing)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        AnimatedOpacity(
          opacity: isSyncing ? 0.6 : 1.0,
          duration: const Duration(milliseconds: 300),
          child: ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayData.length,
            itemBuilder: (context, index) {
              var market = displayData[index];
              String marketName = '';
              double amount = 0;

              if (market is MarketData) {
                marketName = market.marketName;
                amount = market.sideValue; // عرض العمولة بدلاً من المبلغ الإجمالي
              } else {
                marketName = market['market_name'] ?? 'غير معروف';
                amount = _toDouble(market['commission_owed']);
              }

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.shade100,
                    radius: 18,
                    child: Text(
                      "${index + 1}",
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  title: Text(
                    marketName,
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: const Text("عمولة مستحقة", style: TextStyle(fontSize: 11)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            "${amount.toStringAsFixed(2)} دج",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                              fontSize: 15,
                            ),
                          ),
                          const Text(
                            "مبلغ الدفع",
                            style: TextStyle(fontSize: 9, color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      // زر تحميل ملف الإكسيل للمحل
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.file_download_outlined, size: 20),
                          color: Colors.blue,
                          onPressed: isSyncing ? null : () => _downloadSpecificMarketSheet(marketName),
                          tooltip: "استخراج بيانات المحل",
                        ),
                      ),
                      // زر مشاركة المبلغ (واتساب)
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.share_outlined, size: 20),
                          color: Colors.green,
                          onPressed: isSyncing ? null : () => _shareToWhatsApp(marketName, amount),
                          tooltip: "مشاركة بالواتس",
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
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

  // مثال لعرض تفاصيل الطلبات (يمكن استخدامه لعرض بيانات الطلبات)
  Widget _buildOrderDetailsList(List ordersData) {
    return ListView.builder(
      itemCount: ordersData.length,
      itemBuilder: (context, index) {
        var order = ordersData[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: Text(
                "${index + 1}",
                style: const TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              order['product_name'] ?? 'منتج غير معروف',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            subtitle: Text("المتجر: ${order['market_name'] ?? 'غير محدد'}"),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "${order['price'] ?? 0} DA",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                    fontSize: 16,
                  ),
                ),
                Text(
                  "الكمية: ${order['quantity'] ?? 0}",
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
}
```