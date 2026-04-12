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
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart' as intl;

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
  pw.Font? _pdfArabicFont;

  // تحميل خط PDF العربي من الأصول
  Future<pw.Font?> _loadArabicPdfFont() async {
    if (_pdfArabicFont != null) return _pdfArabicFont;
    try {
      final fontData = await rootBundle.load('assets/fonts/Dubai-Regular.ttf');
      _pdfArabicFont = pw.Font.ttf(fontData);
    } catch (e) {
      print('Failed to load PDF Arabic font: $e');
    }
    return _pdfArabicFont;
  }

  // الحقول التي يجب حذفها من جداول PDF
  bool _isExcludedPdfHeader(String header) {
    final normalized = header.trim().toLowerCase();
    return normalized == 'order link' || normalized == 'order_link' || normalized == 'orderlink';
  }

  // الحقول التي يجب تلوينها بالأخضر في جداول PDF
  bool _isGreenPdfHeader(String header) {
    final normalized = header.trim().toLowerCase();
    return normalized == 'النسبة المستحقة' || normalized == 'due percentage' || normalized == 'percentage due' || normalized == 'commission percentage' || normalized == 'commission_percent';
  }

  pw.Widget _buildPdfTable(List<String> headers, List<List<String>> rows) {
    final validColumnIndexes = <int>[];
    final visibleHeaders = <String>[];

    for (var i = 0; i < headers.length; i++) {
      if (_isExcludedPdfHeader(headers[i])) continue;
      validColumnIndexes.add(i);
      visibleHeaders.add(headers[i]);
    }

    if (visibleHeaders.isEmpty) {
      return pw.Container();
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
          children: visibleHeaders.map((header) {
            return pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                header,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            );
          }).toList(),
        ),
        ...rows.map((row) {
          return pw.TableRow(
            children: validColumnIndexes.map((colIndex) {
              final textValue = colIndex < row.length ? row[colIndex] : '';
              final header = headers[colIndex];
              final isGreen = _isGreenPdfHeader(header);
              return pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(
                  textValue,
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: isGreen ? PdfColors.green : PdfColors.black,
                  ),
                ),
              );
            }).toList(),
          );
        }),
      ],
    );
  }

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

  Future<void> _sharePdfFile(List<int> bytes, String fileName, String message) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: message,
    );
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

  /// دالة استخراج البيانات التفصيلية للمحل من ملف الإكسيل
  Future<List<Map<String, dynamic>>> _fetchMarketDetailedData(String targetMarketName) async {
    try {
      final response = await http.get(
        Uri.parse("https://foodwood.site/jibli/public/productOrdersDetailsByMarkets/exportExcel"),
      );
      if (response.statusCode != 200) {
        return [];
      }

      var bytes = response.bodyBytes;
      var excelFile = excel.Excel.decodeBytes(bytes);
      List<Map<String, dynamic>> detailedData = [];

      // البحث عن بيانات المحل المطلوب
      for (var table in excelFile.tables.keys) {
        if (table == targetMarketName) {
          var sheet = excelFile.tables[table]!;
          var headers = <String>[];
          
          // استخراج رؤوس الأعمدة
          if (sheet.rows.isNotEmpty) {
            headers = sheet.rows[0]
                .map((cell) => cell?.value?.toString() ?? '')
                .toList();
          }

          // استخراج البيانات (تخطي الصف الأول - رؤوس الأعمدة)
          for (int i = 1; i < sheet.rows.length; i++) {
            var row = sheet.rows[i];
            Map<String, dynamic> rowData = {};
            for (int j = 0; j < headers.length; j++) {
              if (j < row.length) {
                final header = headers[j]?.toString() ?? '';
                if (_isExcludedPdfHeader(header)) continue;
                rowData[header] = row[j]?.value ?? '';
              }
            }
            if (rowData.isNotEmpty) {
              detailedData.add(rowData);
            }
          }
          break;
        }
      }

      return detailedData;
    } catch (e) {
      print("خطأ في استخراج البيانات: $e");
      return [];
    }
  }

  /// دالة إنشاء تقرير PDF مفصل للمحل
  Future<void> _generateMarketPDF(String marketName, double amount) async {
    try {
      // استخراج البيانات التفصيلية
      final detailedData = await _fetchMarketDetailedData(marketName);

      final pdf = pw.Document();
      final pdfFont = await _loadArabicPdfFont();

      final headers = detailedData.isNotEmpty
          ? detailedData.first.keys.toList()
          : <String>[];

      final rows = detailedData.map((rowMap) {
        return headers.map((header) {
          final value = rowMap[header];
          return value?.toString() ?? '';
        }).toList();
      }).toList();

      pdf.addPage(
        pw.MultiPage(
          theme: pw.ThemeData.withFont(
            base: pdfFont ?? pw.Font.helvetica(),
          ),
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(30),
          build: (pw.Context context) {
            return [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    "تقرير مالي تفصيلي - خدمة جيبلي",
                    style: const pw.TextStyle(fontSize: 18, color: PdfColors.orange),
                  ),
                  pw.Text(
                    intl.DateFormat('yyyy/MM/dd').format(DateTime.now()),
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                ],
              ),
              pw.Divider(thickness: 2, color: PdfColors.orange),
              pw.SizedBox(height: 15),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  color: PdfColors.grey100,
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      "اسم المحل: $marketName",
                      style: const pw.TextStyle(fontSize: 14),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      "نوع التقرير: كشف عمولات مستحقة - بيانات مفصلة",
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.blue),
                  color: PdfColors.blue50,
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      "إجمالي العمولات المستحقة:",
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                    pw.Text(
                      "${amount.toStringAsFixed(2)} دج",
                      style: const pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.green,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                "محتوى الشيت الكامل:",
                style: const pw.TextStyle(fontSize: 12),
              ),
              pw.SizedBox(height: 10),
              if (detailedData.isNotEmpty)
                _buildPdfTable(headers, rows)
              else
                pw.Text(
                  "لا توجد بيانات تفصيلية متاحة لهذا المحل.",
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.red),
                ),
              pw.Divider(),
              pw.Center(
                child: pw.Text(
                  "المستند الرسمي - جميع الحقوق محفوظة لمنصة جيبلي للتحليلات © 2024",
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                ),
              ),
            ];
          },
        ),
      );

      final pdfBytes = await pdf.save();
      await _sharePdfFile(
        pdfBytes,
        'Report_$marketName.pdf',
        'تقرير مالي مفصل لمحّل $marketName من خدمة جيبلي',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("تمت مشاركة تقرير PDF للمحل: $marketName"),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("خطأ: $e"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _generateFullExcelPDF() async {
    try {
      final response = await http.get(
        Uri.parse("https://foodwood.site/jibli/public/productOrdersDetailsByMarkets/exportExcel"),
      );
      if (response.statusCode != 200) {
        throw "خطأ في تحميل ملف الإكسل: ${response.statusCode}";
      }

      final bytes = response.bodyBytes;
      final excelFile = excel.Excel.decodeBytes(bytes);
      final pdf = pw.Document();
      final pdfFont = await _loadArabicPdfFont();

      pdf.addPage(
        pw.MultiPage(
          theme: pw.ThemeData.withFont(
            base: pdfFont ?? pw.Font.helvetica(),
          ),
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(30),
          build: (pw.Context context) {
            final List<pw.Widget> content = [];

            content.add(
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    "تقرير كامل من ملف الإكسل",
                    style: const pw.TextStyle(fontSize: 18, color: PdfColors.orange),
                  ),
                  pw.Text(
                    intl.DateFormat('yyyy/MM/dd').format(DateTime.now()),
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                ],
              ),
            );
            content.add(pw.Divider(thickness: 2, color: PdfColors.orange));
            content.add(pw.SizedBox(height: 15));

            if (excelFile.tables.isEmpty) {
              content.add(
                pw.Text(
                  "لا توجد أوراق في ملف الإكسل.",
                  style: const pw.TextStyle(fontSize: 12, color: PdfColors.red),
                ),
              );
            }

            for (var sheetName in excelFile.tables.keys) {
              final sheet = excelFile.tables[sheetName]!;
              content.add(
                pw.Text(
                  "ورقة: $sheetName",
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
              );
              content.add(pw.SizedBox(height: 8));

              if (sheet.rows.isEmpty) {
                content.add(
                  pw.Text(
                    "لا توجد بيانات في هذه الورقة.",
                    style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600),
                  ),
                );
                content.add(pw.SizedBox(height: 12));
                continue;
              }

              final headers = sheet.rows.first
                  .map((cell) => cell?.value?.toString() ?? '')
                  .toList();

              final data = sheet.rows.skip(1).map((row) {
                return List.generate(
                  headers.length,
                  (index) => index < row.length ? row[index]?.value?.toString() ?? '' : '',
                );
              }).toList();

              content.add(
                _buildPdfTable(
                  headers.isNotEmpty ? headers : ['البيانات'],
                  data.isNotEmpty ? data : [['-']],
                ),
              );
              content.add(pw.SizedBox(height: 16));
            }

            content.add(pw.Divider());
            content.add(
              pw.Center(
                child: pw.Text(
                  "المستند الرسمي - جميع الحقوق محفوظة لمنصة جيبلي للتحليلات © 2024",
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                ),
              ),
            );

            return content;
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Jibli_Full_Excel_Report.pdf',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("تم إنشاء تقرير PDF كامل من ملف الإكسل"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("خطأ: $e"),
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
              const Text("لا توجد بيانات محلات", style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 15),
              ElevatedButton.icon(
                icon: const Icon(Icons.download),
                label: const Text("تحميل من الإكسل"),
                onPressed: isSyncing ? null : _syncMarketPayments,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
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
          child: ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text("تحديث من الإكسل"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              minimumSize: const Size.fromHeight(45),
            ),
            onPressed: isSyncing ? null : _syncMarketPayments,
          ),
        ),
        // عرض مؤشر التحميل عند المزامنة
        if (isSyncing) const LinearProgressIndicator(color: Colors.orange),
        
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayData.length,
          itemBuilder: (context, index) {
            var market = displayData[index];
            String marketName = '';
            double amount = 0;

            if (market is MarketData) {
              marketName = market.marketName;
              amount = market.sideValue;
            } else {
              marketName = market['market_name'] ?? 'غير معروف';
              amount = _toDouble(market['commission_owed']);
            }

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                title: Text(marketName, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text("${amount.toStringAsFixed(2)} دج", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // زر الـ PDF الجديد
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 22),
                      onPressed: () => _generateMarketPDF(marketName, amount),
                      tooltip: "تقرير PDF",
                    ),
                    // زر الإكسيل
                    IconButton(
                      icon: const Icon(Icons.file_download_outlined, color: Colors.blue, size: 22),
                      onPressed: () => _downloadSpecificMarketSheet(marketName),
                      tooltip: "شيت إكسيل",
                    ),
                    // زر الواتساب
                    IconButton(
                      icon: const Icon(Icons.share_outlined, color: Colors.green, size: 22),
                      onPressed: () => _shareToWhatsApp(marketName, amount),
                      tooltip: "مشاركة",
                    ),
                  ],
                ),
              ),
            );
          },
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
