import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:excel/excel.dart';

// نموذج البيانات لتمثيل بيانات السوق
class MarketData {
  final String marketName;
  double totalAmount;
  double sideValue; // 👈 الحقل الذي بجانب التوتال (قد يكون tax أو commission أو fee)

  MarketData({
    required this.marketName,
    required this.totalAmount,
    required this.sideValue,
  });
}

class ExcelService {
  /// دالة جلب البيانات الخام من الرابط
  Future<List<dynamic>> getRawData() async {
    final url =
        "https://foodwood.site/jibli/public/productOrdersDetailsByMarkets/exportExcel";

    try {
      debugPrint("🔗 جاري الاتصال بالرابط: $url");

      var requestUrl = Uri.parse(url);

      var response = await http.get(
        requestUrl,
        headers: {
          "Accept": "application/json",
        },
      );

      debugPrint("📊 حالة الرد (Status Code): ${response.statusCode}");

      if (response.statusCode == 200) {
        final Map<String, dynamic> decoded = jsonDecode(response.body);

        if (decoded['success'] == true && decoded['data'] is List) {
          List data = decoded['data'];
          debugPrint("📦 تم استلام ${data.length} طلب بنجاح.");
          return data;
        } else {
          debugPrint("⚠️ البيانات غير صحيحة.");
          return [];
        }
      } else {
        debugPrint("⚠️ السيرفر رد بخطأ: ${response.statusCode}");
        return [];
      }
    } catch (e) {
      debugPrint("‼️ خطأ فني أثناء المزامنة: $e");
      return [];
    }
  }

  /// دالة حساب ديون السوق بناءً على البيانات الخام
  double calculateMarketDebt(List<dynamic> allData, String marketName) {
    double totalCommission = 0.0;

    for (var item in allData) {
      // 1. فلترة البيانات حسب اسم المحل فقط
      if (item['market_name'] == marketName) {
        
        // 2. تحويل قيمة العمولة إلى رقم (معالجة النصوص والأرقام)
        double commission = double.tryParse(item['commission'].toString()) ?? 0.0;
        
        // 3. الجمع التراكمي
        totalCommission += commission;
      }
    }
    
    return totalCommission;
  }

  /// دالة قراءة البيانات من ملف Excel وإرجاعها كقائمة
  Future<List<Map<String, dynamic>>> getDataFromExcelFile(String filePath) async {
    List<Map<String, dynamic>> data = [];
    try {
      var bytes = File(filePath).readAsBytesSync();
      var excel = Excel.decodeBytes(bytes);

      for (var table in excel.tables.keys) {
        var sheet = excel.tables[table]!;

        // افتراض أن الصف الأول هو headers
        if (sheet.rows.isEmpty) continue;
        var headers = sheet.rows[0].map((cell) => cell?.value.toString() ?? '').toList();

        for (int i = 1; i < sheet.rows.length; i++) {
          var row = sheet.rows[i];
          Map<String, dynamic> rowData = {};
          for (int j = 0; j < headers.length && j < row.length; j++) {
            rowData[headers[j]] = row[j]?.value;
          }
          data.add(rowData);
        }
      }
    } catch (e) {
      print("خطأ في قراءة الملف: $e");
    }
    return data;
  }

  /// دالة قراءة العمولة من ملف Excel مباشرة
  Future<double> getCommissionFromExcelFile(String filePath) async {
    try {
      // 1. فتح الملف من المسار الموجود في السيرفر أو الهاتف
      var bytes = File(filePath).readAsBytesSync();
      var excel = Excel.decodeBytes(bytes);

      // 2. اختيار الورقة الأولى (Sheet1)
      for (var table in excel.tables.keys) {
        var sheet = excel.tables[table]!;

        // 3. الانتقال مباشرة إلى السطر الأخير (Last Row)
        var lastRowIndex = sheet.maxRows - 1;
        var lastRow = sheet.rows[lastRowIndex];

        // 4. قراءة خلية العمولة (نفرض أنها في العمود رقم 5، أي Index 4)
        // هذا هو الرقم الذي يظهر لك في الإكسيل (مثل 3642)
        var commissionValue = lastRow[4]?.value;

        return double.tryParse(commissionValue.toString()) ?? 0.0;
      }
    } catch (e) {
      print("خطأ في قراءة الملف: $e");
    }
    return 0.0;
  }

  /// دالة تحميل ملف Excel من الرابط وحفظه محلياً
  Future<String?> downloadExcelFile() async {
    final url = "https://foodwood.site/jibli/public/productOrdersDetailsByMarkets/exportExcel";

    try {
      debugPrint("🔗 جاري تحميل الملف من: $url");

      var response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        // حفظ الملف محلياً
        final directory = Directory.systemTemp;
        final filePath = '${directory.path}/temp_excel.xlsx';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        debugPrint("📁 تم حفظ الملف في: $filePath");
        return filePath;
      } else {
        debugPrint("⚠️ فشل تحميل الملف: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("‼️ خطأ في تحميل الملف: $e");
    }
    return null;
  }

  /// دالة معالجة ملف Excel المحمل وتوزيع العمولات حسب اسم المحل بطريقة ذكية
  Future<Map<String, double>> processDownloadedExcel(String filePath) async {
    var bytes = File(filePath).readAsBytesSync();
    var excel = Excel.decodeBytes(bytes);

    Map<String, double> marketCommissions = {};

    // 1. الدوران على كل الصفحات (Sheets) في الملف
    for (var sheetName in excel.tables.keys) {
      var sheet = excel.tables[sheetName]!;
      
      // نتخطى الصفحات الافتراضية إذا وجدت
      if (sheetName.toLowerCase().contains('sheet')) continue;

      // 2. الذهاب لآخر سطر في هذه الصفحة
      // المجموع النهائي عادة يكون في آخر سطر (MaxRows - 1)
      if (sheet.maxRows > 0) {
        var lastRowIndex = sheet.maxRows - 1;
        var lastRow = sheet.rows[lastRowIndex];

        // 3. البحث عن القيمة في الأعمدة الأخيرة (عادة تكون في العمود 5 أو 6)
        // سنبحث في آخر سطر عن أول رقم نقابله من جهة اليمين
        double finalTotal = 0.0;
        for (var cell in lastRow.reversed) {
          var value = cell?.value?.toString() ?? "";
          // تنظيف القيمة من الرموز وتحويلها لرقم
          double? parsed = double.tryParse(value.replaceAll(RegExp(r'[^0-9.]'), ''));
          if (parsed != null && parsed > 0) {
            finalTotal = parsed;
            break; // وجدنا المجموع النهائي في هذا الـ Sheet
          }
        }

        // 4. تخزين النتيجة باسم الصفحة (الذي هو اسم المحل)
        marketCommissions[sheetName] = finalTotal;
      }
    }

    // طباعة النتائج النهائية
    marketCommissions.forEach((name, value) {
      if (value > 0) {
        debugPrint("📍 المحل: $name | الديون: $value دج");
      }
    });

    return marketCommissions;
  }

  /// دالة قراءة العمولة من الرابط مباشرة دون حفظ الملف
  Future<double> fetchCommissionFromExcel() async {
    // 1. الرابط الذي زودتني به (رابط التصدير)
    final String url = "https://foodwood.site/jibli/public/productOrdersDetailsByMarkets/exportExcel";

    try {
      // 2. طلب الملف من السيرفر
      var response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        // 3. قراءة محتوى الإكسيل من الرد (Bytes)
        var bytes = response.bodyBytes;
        var excel = Excel.decodeBytes(bytes);

        // 4. الوصول إلى أول ورقة في الملف
        for (var table in excel.tables.keys) {
          var sheet = excel.tables[table]!;

          // 5. الذهاب مباشرة إلى آخر سطر (Last Row)
          var lastRowIndex = sheet.maxRows - 1;
          var lastRow = sheet.rows[lastRowIndex];

          // 6. استخراج القيمة من عمود العمولة (بفرض أنه العمود رقم 5، أي Index 4)
          var commissionValue = lastRow[4]?.value;

          debugPrint("القيمة المستخرجة من السطر الأخير هي: $commissionValue");
          // هنا يمكنك عرض القيمة في واجهة التطبيق
          return double.tryParse(commissionValue.toString()) ?? 0.0;
        }
      }
    } catch (e) {
      debugPrint("حدث خطأ أثناء قراءة الرابط: $e");
    }
    return 0.0;
  }
  /// دالة جلب البيانات من الرابط وتحويلها إلى قائمة بيانات الأسواق
  Future<List<MarketData>> syncFromWebExcel() async {
    final filePath = await downloadExcelFile();
    if (filePath == null) return [];

    final marketCommissions = await processDownloadedExcel(filePath);

    final List<MarketData> result = [];

    for (var entry in marketCommissions.entries) {
      result.add(MarketData(
        marketName: entry.key,
        totalAmount: 0.0, // إذا لم يكن هناك إجمالي، يمكن حسابه لاحقاً
        sideValue: entry.value, // العمولة
      ));
    }

    return result;
  }

  /// دالة إضافية اختيارية: تجميع المبالغ لكل سوق (عوضاً عن تكرار السوق)
  /// مثال الاستخدام:
  /// final service = ExcelService();
  /// List<MarketData> rawData = await service.syncFromWebExcel();
  /// List<MarketData> finalData = service.aggregateCommissions(rawData);
  List<MarketData> aggregateCommissions(List<MarketData> rawList) {
    Map<String, double> totals = {};
    Map<String, double> sideTotals = {};

    for (var item in rawList) {
      totals[item.marketName] = (totals[item.marketName] ?? 0.0) + item.totalAmount;
      sideTotals[item.marketName] = (sideTotals[item.marketName] ?? 0.0) + item.sideValue;
    }

    return totals.entries
        .map((e) => MarketData(
          marketName: e.key,
          totalAmount: e.value,
          sideValue: sideTotals[e.key] ?? 0.0,
        ))
        .toList();
  }
}
