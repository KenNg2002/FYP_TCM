import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'notification_service.dart';

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

  // Toggle online/offline — the UI already disables this switch when there's an active task, so no guard is needed here
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

  // Look up the order's customerID and push a notification to that customer
  Future<void> _notifyCustomer(String orderId, String title, String body) async {
    try {
      final orderSnap = await FirebaseFirestore.instance.collection('Order').doc(orderId).get();
      final customerId = orderSnap.data()?['customerID'] as String?;
      if (customerId == null) return;
      NotificationService.instance.send(uids: [customerId], title: title, body: body, data: {'orderId': orderId});
    } catch (e) {
      print("Failed to notify customer: $e");
    }
  }

  // Rider taps "Start Delivery" — tasks are admin-assigned, so there's no claim/confirm-pickup step here
  Future<void> _startDelivery(String taskId, String orderId) async {
    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();
      batch.update(FirebaseFirestore.instance.collection('DeliveryTask').doc(taskId), {'taskStatus': 'Delivering', 'startTime': FieldValue.serverTimestamp()});
      batch.update(FirebaseFirestore.instance.collection('Order').doc(orderId), {'orderStatus': 'Delivering'});
      await batch.commit();
      _notifyCustomer(orderId, 'Order Out for Delivery', 'Your order $orderId is on its way!');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery Started! Head to customer.'), backgroundColor: Colors.blueAccent));
    } catch (e) {
      print("Start Delivery Error: $e");
    }
  }

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
                  _captureAndCompleteDelivery(taskId, orderId);
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

  // Opens the camera; if the user cancels, the delivery cannot be completed
  Future<void> _captureAndCompleteDelivery(String taskId, String orderId) async {
    XFile? photo;
    try {
      photo = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80);
    } catch (e) {
      print("Camera Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open camera: $e'), backgroundColor: Colors.redAccent));
      }
      return;
    }

    if (photo == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No photo taken. Delivery not completed.'), backgroundColor: Colors.redAccent));
      }
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context, barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: primaryGreen), const SizedBox(height: 16), const Text("Uploading Proof...", style: TextStyle(fontWeight: FontWeight.bold))]),
      ),
    );

    try {
      Reference storageRef = FirebaseStorage.instance.ref().child('delivery_proofs/$taskId.jpg');
      await storageRef.putFile(File(photo.path));
      String downloadUrl = await storageRef.getDownloadURL();

      WriteBatch batch = FirebaseFirestore.instance.batch();
      batch.update(FirebaseFirestore.instance.collection('DeliveryTask').doc(taskId), {'taskStatus': 'Completed', 'completedTime': FieldValue.serverTimestamp(), 'proofOfDeliveryPhoto': downloadUrl});
      batch.update(FirebaseFirestore.instance.collection('Order').doc(orderId), {'orderStatus': 'Completed'});
      await batch.commit();
      _notifyCustomer(orderId, 'Order Delivered', 'Your order $orderId has been delivered. Enjoy!');

      if (mounted) Navigator.pop(context);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery Completed!'), backgroundColor: Colors.green));
    } catch (e) {
      print("Complete Error: $e");
      if (mounted) Navigator.pop(context);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Single source of truth: the rider's currently assigned, unfinished tasks.
    // This stream both renders the task cards and decides whether the Online/Offline switch should be locked.
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('DeliveryTask')
          .where('deliverymanID', isEqualTo: currentRiderId)
          .where('taskStatus', whereIn: ['Assigned', 'Delivering'])
          .snapshots(),
      builder: (context, taskSnapshot) {
        var activeTasks = taskSnapshot.data?.docs ?? [];
        bool hasActiveTask = activeTasks.isNotEmpty;

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
                ),
                if (hasActiveTask)
                  const Text(
                    "Locked while you have an active delivery",
                    style: TextStyle(color: Colors.white70, fontSize: 10, fontStyle: FontStyle.italic),
                  ),
              ],
            ),
            actions: [
              if (!_isLoadingStatus)
                Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Switch(
                    value: _isOnline,
                    onChanged: hasActiveTask ? null : _toggleOnlineStatus,
                    activeColor: Colors.white,
                    activeTrackColor: Colors.greenAccent[400],
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: Colors.red[300],
                  ),
                )
            ],
          ),
          body: !_isOnline && !hasActiveTask
            ? _buildEmptyState()
            : taskSnapshot.connectionState == ConnectionState.waiting
              ? Center(child: CircularProgressIndicator(color: primaryGreen))
              : activeTasks.isEmpty
                ? _buildEmptyState()
                : Column(
                    children: [
                      _buildRiderStats(
                        activeTasks.where((t) => t["taskStatus"] == "Assigned").length,
                        activeTasks.where((t) => t["taskStatus"] == "Delivering").length,
                      ),
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
                  ),
        );
      },
    );
  }

  // ================= UI Components ================= //

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_isOnline ? Icons.motorcycle : Icons.snooze_rounded, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(_isOnline ? "No Active Tasks" : "You are Offline", style: TextStyle(color: Colors.grey[800], fontSize: 18, fontWeight: FontWeight.bold)),
          Text(_isOnline ? "Take a break! Waiting for the clinic to assign you an order." : "Switch to Online to start receiving orders.", style: TextStyle(color: Colors.grey[500], fontSize: 14), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildRiderStats(int assigned, int delivering) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
      decoration: BoxDecoration(color: primaryGreen, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)), boxShadow: [BoxShadow(color: primaryGreen.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))]),
      child: Row(
        children: [
          _buildStatBox("Assigned", assigned.toString(), Icons.inventory_2_rounded),
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

  Widget _buildActiveTaskCard(Map<String, dynamic> task, String taskId) {
    bool isAssigned = task["taskStatus"] == "Assigned";
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
                const Text("Delivery Task", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF4B5563))),
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
                onPressed: () => isAssigned ? _startDelivery(taskId, orderId) : _uploadProofAndComplete(taskId, orderId),
                icon: Icon(isAssigned ? Icons.play_arrow_rounded : Icons.camera_alt_rounded, color: Colors.white),
                label: Text(isAssigned ? "Start Delivery" : "Upload Proof & Complete", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: isAssigned ? Colors.blueAccent : primaryGreen, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color bgColor = status == "Assigned" ? Colors.blue[50]! : Colors.orange[50]!;
    Color textColor = status == "Assigned" ? Colors.blue[700]! : Colors.orange[800]!;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)), child: Text(status, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold)));
  }
}
