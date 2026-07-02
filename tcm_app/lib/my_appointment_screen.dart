import 'package:flutter/material.dart';

class MyAppointmentsScreen extends StatelessWidget {
  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color bgGray = const Color(0xFFF4F6F8);

  // 模拟预约数据
  final List<Map<String, dynamic>> _appointments = [
    {
      "doctor": "Dr. Sarah Chen",
      "date": "Oct 24, 2026",
      "time": "10:00 AM",
      "status": "Confirmed",
      "remark": "Persistent back pain and poor sleep."
    },
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
        title: const Text("My Appointments", style: TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.bold)),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _appointments.length,
        itemBuilder: (context, index) {
          final apt = _appointments[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_month_rounded, color: primaryGreen),
                    const SizedBox(width: 12),
                    Text("${apt['date']} • ${apt['time']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const Spacer(),
                    Text(apt["status"], style: TextStyle(color: primaryGreen, fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(height: 30),
                Text("Practitioner:", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                Text(apt["doctor"], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text("Your Remark:", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                Text(apt["remark"], style: TextStyle(color: Colors.grey[700], fontSize: 14, fontStyle: FontStyle.italic)),
              ],
            ),
          );
        },
      ),
    );
  }
}