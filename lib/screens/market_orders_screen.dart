import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class MarketOrdersScreen extends StatefulWidget {
  @override
  _MarketOrdersScreenState createState() => _MarketOrdersScreenState();
}

class _MarketOrdersScreenState extends State<MarketOrdersScreen> {
  List<dynamic> orders = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  // 1. دالة جلب البيانات من السيرفر بصيغة JSON
  Future<void> fetchData() async {
    final String url = "https://foodwood.site/jibli/public/productOrdersDetailsByMarkets/exportExcel";

    try {
      final response = await http.get(
        Uri.parse(url),
        // 👈 هذا هو الجزء الأهم الذي يمنع تحميل ملف الإكسل ويجلب JSON
        headers: {
          "Accept": "application/json",
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            orders = data['data'];
            isLoading = false;
          });
          return;
        }
      }

      throw Exception('فشل الاتصال بالسيرفر');
    } catch (e) {
      print("Error: $e");
      setState(() => isLoading = false);
    }
  }

  double calculateTotalCommission() {
    double totalCommission = 0;
    for (var item in orders) {
      // تحويل القيمة إلى رقم بدقة
      double val = double.tryParse(item['commission'].toString()) ?? 0.0;
      totalCommission += val;
    }
    print("المجموع الصحيح للحقول الخضراء: $totalCommission");
    return totalCommission;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("بيانات الطلبات والأسواق"),
        backgroundColor: Colors.green,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : orders.isEmpty
              ? const Center(child: Text("لا توجد بيانات حالياً"))
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: orders.length,
                        itemBuilder: (context, index) {
                          final item = orders[index];
                          final String greenValue = item['commission'].toString(); // القيمة الخضراء
                          final String totalPrice = item['total_price'].toString();       // الإجمالي

                          return Card(
                            margin: const EdgeInsets.all(8),
                            child: ListTile(
                              leading: CircleAvatar(child: Text("${index + 1}")),
                              title: Text(item['product_name'] ?? 'اسم المنتج غير معروف'),
                              subtitle: Text("Total: $totalPrice"),
                              // عرض الحقل الأخضر في جانب العنصر
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.green[100], // خلفية خضراء فاتحة
                                  border: Border.all(color: Colors.green),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  greenValue, 
                                  style: const TextStyle(
                                    color: Colors.green[900], 
                                    fontWeight: FontWeight.bold
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // ثم تعرضه في أسفل الصفحة
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.green[50],
                      child: Text(
                        "مجموع العمولات: ${calculateTotalCommission()}",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
    );
  }
}
