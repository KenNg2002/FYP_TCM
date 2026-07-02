import 'package:flutter/material.dart';

class MyOrdersScreen extends StatelessWidget {
  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color bgGray = const Color(0xFFF4F6F8);

  // 模拟订单数据
  final List<Map<String, dynamic>> _orders = [
    {"id": "ORD-9921", "date": "Oct 22, 2026", "total": 52.50, "status": "Delivered", "items": "Chrysanthemum Tea x2, Goji Berries x1"},
    {"id": "ORD-9905", "date": "Oct 15, 2026", "total": 18.00, "status": "Delivered", "items": "Honeysuckle Detox x1"},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGray,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1F2937)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("My Orders", style: TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.bold)),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _orders.length,
        itemBuilder: (context, index) {
          final order = _orders[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(order["id"], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    _buildStatusChip(order["status"]),
                  ],
                ),
                const Divider(height: 24),
                Text(order["items"], style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(order["date"], style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                    Text("RM ${order["total"].toStringAsFixed(2)}", style: TextStyle(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(10)),
      child: Text(status, style: TextStyle(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}