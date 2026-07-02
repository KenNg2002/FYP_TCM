import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DeliveryTaskScreen extends StatefulWidget {
  @override
  _DeliveryTaskScreenState createState() => _DeliveryTaskScreenState();
}

class _DeliveryTaskScreenState extends State<DeliveryTaskScreen> {
  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color bgGray = const Color(0xFFF4F6F8);
  String? currentRiderId;

  bool _isOnline = false;
  bool _isLoadingStatus = true;

  @override
  void initState() {
    super.initState();
    currentRiderId = FirebaseAuth.instance.currentUser?.uid ?? "TEST_RIDER_001";
    _fetchCurrentAvailability(); 
  }

  // 1. 获取上下线状态
  Future<void> _fetchCurrentAvailability() async {
    try {
      var doc = await FirebaseFirestore.instance.collection('DeliveryMan').doc(currentRiderId).get();
      if (doc.exists && mounted) {
        setState(() {
          _isOnline = doc.data()?['currentAvailability'] == 'Online';
          _isLoadingStatus = false;
        });
      }
    } catch (e) {
      print("Error fetching status: $e");
      if (mounted) setState(() => _isLoadingStatus = false);
    }
  }

  // 2. 切换上下线
  Future<void> _toggleOnlineStatus(bool value) async {
    setState(() { _isOnline = value; }); 
    try {
      await FirebaseFirestore.instance.collection('DeliveryMan').doc(currentRiderId).update({
        'currentAvailability': value ? 'Online' : 'Offline'
      });
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? 'You are now Online. Ready for orders!' : 'You are now Offline. Taking a break!'),
          backgroundColor: value ? Colors.green : Colors.grey[700],
          duration: const Duration(seconds: 2),
        )
      );
    } catch (e) {
      print("Error updating status: $e");
      setState(() { _isOnline = !value; });
    }
  }

  // 🚀 3. 核心功能：原子级安全抢单
  Future<void> _grabOrder(String orderId, String shippingAddress) async {
    DocumentReference orderRef = FirebaseFirestore.instance.collection('Order').doc(orderId);
    DocumentReference newTaskRef = FirebaseFirestore.instance.collection('DeliveryTask').doc();

    showDialog(
      context: context, barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot orderSnapshot = await transaction.get(orderRef);
        if (!orderSnapshot.exists) throw Exception("Order does not exist!");

        if (orderSnapshot.get('orderStatus') != 'ReadyToPickUp') {
          throw Exception("Order has already been grabbed!");
        }

        transaction.update(orderRef, {'orderStatus': 'Accepted'});

        // 完美契合你的 UI 字段要求
        transaction.set(newTaskRef, {
          'taskID': newTaskRef.id,
          'orderID': orderId,
          'deliverymanID': currentRiderId,
          'taskStatus': 'Pending Pickup', // 匹配你的状态判断
          'pickupLocation': 'TCM Clinic HQ', 
          'dropoffLocation': shippingAddress, 
          'proofOfDeliveryPhoto': '',
          'acceptedTime': FieldValue.serverTimestamp(),
          'pickupTime': null,
          'completedTime': null,
        });
      });

      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🎉 Grabbed successfully!'), backgroundColor: Colors.green));
    } catch (e) {
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed: 手慢了，已被抢走！'), backgroundColor: Colors.redAccent));
    }
  }

  // 4. 确认取货
  Future<void> _pickUpParcel(String taskId, String orderId) async {
    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();
      batch.update(FirebaseFirestore.instance.collection('DeliveryTask').doc(taskId), {'taskStatus': 'Delivering', 'pickupTime': FieldValue.serverTimestamp()});
      batch.update(FirebaseFirestore.instance.collection('Order').doc(orderId), {'orderStatus': 'Delivering'});
      await batch.commit();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Parcel Picked Up! Head to customer.'), backgroundColor: Colors.blueAccent));
    } catch (e) {
      print("Pickup Error: $e");
    }
  }

  // 5. 拍照上传完成订单
  void _uploadProofAndComplete(String taskId, String orderId) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_rounded, size: 50, color: Colors.grey),
            const SizedBox(height: 16),
            const Text("Take Photo of Parcel at Doorstep", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context); 
                  _simulateUploadingAndComplete(taskId, orderId); 
                },
                icon: const Icon(Icons.camera_rounded, color: Colors.white),
                label: const Text("Open Camera", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _simulateUploadingAndComplete(String taskId, String orderId) async {
    showDialog(
      context: context, barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: primaryGreen), const SizedBox(height: 16), const Text("Uploading Proof...", style: TextStyle(fontWeight: FontWeight.bold))]),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 1500));
    
    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();
      batch.update(FirebaseFirestore.instance.collection('DeliveryTask').doc(taskId), {'taskStatus': 'Completed', 'completedTime': FieldValue.serverTimestamp(), 'proofOfDeliveryPhoto': 'https://dummy.com/proof.jpg'});
      batch.update(FirebaseFirestore.instance.collection('Order').doc(orderId), {'orderStatus': 'Completed'});
      await batch.commit();
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery Completed!'), backgroundColor: Colors.green));
    } catch (e) {
      Navigator.pop(context);
      print("Complete Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGray,
      appBar: AppBar(
        backgroundColor: primaryGreen, elevation: 0, centerTitle: false, automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Rider Dashboard", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)), 
            Text(
              _isLoadingStatus ? "Loading status..." : (_isOnline ? "Online • Ready for orders" : "Offline • Not taking orders"), 
              style: TextStyle(color: _isOnline ? Colors.greenAccent : Colors.red[200], fontSize: 12, fontWeight: FontWeight.bold)
            )
          ],
        ),
        actions: [
          if (!_isLoadingStatus)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Switch(
                value: _isOnline,
                onChanged: _toggleOnlineStatus,
                activeColor: Colors.white,
                activeTrackColor: Colors.greenAccent[400],
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: Colors.red[300],
              ),
            )
        ],
      ),
      body: !_isOnline 
        ? _buildEmptyState() 
        // 🚀 双流监听架构：先看自己有没有在派的单
        : StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('DeliveryTask')
                .where('deliverymanID', isEqualTo: currentRiderId)
                .where('taskStatus', whereIn: ['Pending Pickup', 'Delivering'])
                .snapshots(),
            builder: (context, activeSnapshot) {
              if (activeSnapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: primaryGreen));
              
              var activeTasks = activeSnapshot.data?.docs ?? [];
              
              if (activeTasks.isNotEmpty) {
                // 👉 有专属任务：显示你设计的绿色统计数据 + 任务卡片
                int pending = activeTasks.where((t) => t["taskStatus"] == "Pending Pickup").length;
                int delivering = activeTasks.where((t) => t["taskStatus"] == "Delivering").length;

                return Column(
                  children: [
                    _buildRiderStats(pending, delivering),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: activeTasks.length,
                        itemBuilder: (context, index) {
                          var taskData = activeTasks[index].data() as Map<String, dynamic>;
                          return _buildActiveTaskCard(taskData, activeTasks[index].id);
                        },
                      ),
                    ),
                  ],
                );
              } else {
                // 👉 没专属任务：去监听全局的 "抢单大厅"
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('Order')
                      .where('orderStatus', isEqualTo: 'ReadyToPickUp')
                      .snapshots(),
                  builder: (context, broadcastSnapshot) {
                    if (broadcastSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    
                    var broadcastOrders = broadcastSnapshot.data?.docs ?? [];
                    if (broadcastOrders.isEmpty) return _buildEmptyState();

                    return ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: broadcastOrders.length,
                      itemBuilder: (context, index) => _buildGrabCard(broadcastOrders[index]),
                    );
                  }
                );
              }
            }
          ),
    );
  }

  // ================= UI 组件库 ================= //

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_isOnline ? Icons.motorcycle : Icons.snooze_rounded, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(_isOnline ? "No Active Tasks" : "You are Offline", style: TextStyle(color: Colors.grey[800], fontSize: 18, fontWeight: FontWeight.bold)),
          Text(_isOnline ? "Take a break! Waiting for dispatch." : "Switch to Online to start taking orders.", style: TextStyle(color: Colors.grey[500], fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildRiderStats(int pending, int delivering) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
      decoration: BoxDecoration(color: primaryGreen, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)), boxShadow: [BoxShadow(color: primaryGreen.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))]),
      child: Row(
        children: [
          _buildStatBox("To Pick Up", pending.toString(), Icons.inventory_2_rounded),
          const SizedBox(width: 16),
          _buildStatBox("Delivering", delivering.toString(), Icons.motorcycle_rounded),
        ],
      ),
    );
  }

  Widget _buildStatBox(String title, String count, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Icon(icon, color: Colors.white70, size: 24), const SizedBox(height: 12), Text(count, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)), Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13))],
        ),
      ),
    );
  }

  // 骑手已接的单：你设计的完美任务卡片
  Widget _buildActiveTaskCard(Map<String, dynamic> task, String taskId) {
    bool isPendingPickup = task["taskStatus"] == "Pending Pickup";
    String orderId = task['orderID'] ?? 'Unknown';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Order #$orderId", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF4B5563))),
                _buildStatusChip(task["taskStatus"]),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6)),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.blue[50], shape: BoxShape.circle), child: Icon(Icons.storefront_rounded, color: Colors.blue[400], size: 20)),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Pick-up Location", style: TextStyle(color: Colors.grey, fontSize: 12)), const SizedBox(height: 4), Text(task["pickupLocation"] ?? "TCM Clinic HQ", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)))])),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle), child: Icon(Icons.location_on_rounded, color: Colors.red[400], size: 20)),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Drop-off Location", style: TextStyle(color: Colors.grey, fontSize: 12)), const SizedBox(height: 4), Text(task["dropoffLocation"] ?? "", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)))])),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16), decoration: const BoxDecoration(color: Color(0xFFF9FAFB), borderRadius: BorderRadius.vertical(bottom: Radius.circular(20))),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => isPendingPickup ? _pickUpParcel(taskId, orderId) : _uploadProofAndComplete(taskId, orderId),
                icon: Icon(isPendingPickup ? Icons.inventory_2_rounded : Icons.camera_alt_rounded, color: Colors.white),
                label: Text(isPendingPickup ? "Confirm Pick Up" : "Upload Proof & Complete", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: isPendingPickup ? Colors.blueAccent : primaryGreen, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 大厅抢单卡片
  Widget _buildGrabCard(QueryDocumentSnapshot order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Order: ${order['orderID'] ?? order.id}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(10)), child: const Text("Ready to Pick Up", style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold))),
            ],
          ),
          const Divider(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.location_on, color: primaryGreen, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(order['shippingAddress'] ?? 'No Address', style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937)))),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Earning (Total)", style: TextStyle(fontSize: 10, color: Colors.grey)),
                  Text("RM ${(order['totalAmount'] ?? 0.0).toStringAsFixed(2)}", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryGreen)),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _grabOrder(order.id, order['shippingAddress'] ?? 'No Address'),
                icon: const Icon(Icons.flash_on, color: Colors.white, size: 16),
                label: const Text("GRAB NOW", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color bgColor = status == "Pending Pickup" ? Colors.blue[50]! : Colors.orange[50]!;
    Color textColor = status == "Pending Pickup" ? Colors.blue[700]! : Colors.orange[800]!;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)), child: Text(status, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold)));
  }
}