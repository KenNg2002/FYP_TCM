import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class DeliveryHistoryScreen extends StatefulWidget {
  @override
  _DeliveryHistoryScreenState createState() => _DeliveryHistoryScreenState();
}

class _DeliveryHistoryScreenState extends State<DeliveryHistoryScreen> {
  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color bgGray = const Color(0xFFF4F6F8);
  String? currentRiderId;

  @override
  void initState() {
    super.initState();
    currentRiderId = FirebaseAuth.instance.currentUser?.uid ?? "TEST_RIDER_001";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGray,
      appBar: AppBar(
        backgroundColor: Colors.white, 
        elevation: 0, 
        centerTitle: true, 
        automaticallyImplyLeading: false,
        title: const Text("Delivery History", style: TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // 🚀 核心修复：暂时去掉了 orderBy，这样就不需要去 Firebase 建立复合索引了！数据会立刻出来！
        stream: FirebaseFirestore.instance.collection('DeliveryTask')
            .where('deliverymanID', isEqualTo: currentRiderId)
            .where('taskStatus', isEqualTo: 'Completed')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: primaryGreen));
          }
          
          var historyTasks = snapshot.data?.docs ?? [];

          if (historyTasks.isEmpty) {
            return _buildEmptyState();
          }

          // 💡 我们在本地用代码进行排序，代替 Firebase 的 orderBy
          historyTasks.sort((a, b) {
            Timestamp? timeA = (a.data() as Map<String, dynamic>)['completedTime'] as Timestamp?;
            Timestamp? timeB = (b.data() as Map<String, dynamic>)['completedTime'] as Timestamp?;
            if (timeA == null || timeB == null) return 0;
            return timeB.compareTo(timeA); // 倒序：最新的在最上面
          });

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            physics: const BouncingScrollPhysics(),
            itemCount: historyTasks.length,
            itemBuilder: (context, index) {
              var data = historyTasks[index].data() as Map<String, dynamic>;
              return _buildHistoryCard(data);
            },
          );
        },
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> data) {
    Timestamp? completedTs = data['completedTime'] as Timestamp?;
    String dateStr = "Unknown Date";
    String timeStr = "Unknown Time";
    
    if (completedTs != null) {
      DateTime dt = completedTs.toDate();
      dateStr = DateFormat('MMM dd, yyyy').format(dt); 
      timeStr = DateFormat('hh:mm a').format(dt);     
    }

    return GestureDetector(
      onTap: () => _showTaskDetail(data),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(data["orderID"] ?? "Unknown Order", overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1F2937))),
                ),
                const SizedBox(width: 8),
                Text(data["taskStatus"], style: TextStyle(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey[400]),
              ],
            ),
            const Divider(height: 24, thickness: 1, color: Color(0xFFF3F4F6)),
            Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Text(dateStr, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                const SizedBox(width: 16),
                Icon(Icons.access_time_rounded, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Text(timeStr, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showTaskDetail(Map<String, dynamic> data) {
    String? proofUrl = data['proofOfDeliveryPhoto'] as String?;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(data["orderID"] ?? "Unknown Order", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: primaryGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                        child: Text(data["taskStatus"] ?? "Completed", style: TextStyle(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  if (proofUrl != null && proofUrl.isNotEmpty) ...[
                    const Text("Proof of Delivery", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Image.network(proofUrl, width: double.infinity, height: 220, fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 24),
                  ],

                  _buildDetailRow(Icons.storefront_rounded, Colors.blue, "Pick-up Location", data["pickupLocation"] ?? "TCM Clinic HQ"),
                  const SizedBox(height: 16),
                  _buildDetailRow(Icons.location_on_rounded, Colors.red, "Drop-off Location", data["dropoffLocation"] ?? "-"),

                  const Divider(height: 40, thickness: 1, color: Color(0xFFF3F4F6)),

                  const Text("Timeline", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 12),
                  _buildTimelineRow("Assigned", data['assignedTime'] as Timestamp?),
                  _buildTimelineRow("Started Delivery", data['startTime'] as Timestamp?),
                  _buildTimelineRow("Completed", data['completedTime'] as Timestamp?),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, MaterialColor color, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color[50], shape: BoxShape.circle), child: Icon(icon, color: color[400], size: 20)),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineRow(String label, Timestamp? ts) {
    String value = "—";
    if (ts != null) {
      DateTime dt = ts.toDate();
      value = "${DateFormat('MMM dd, yyyy').format(dt)} • ${DateFormat('hh:mm a').format(dt)}";
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_rounded, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text("No completed deliveries yet.", style: TextStyle(color: Colors.grey[500], fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}