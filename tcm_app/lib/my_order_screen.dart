import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'notification_service.dart';

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color bgGray = const Color(0xFFF4F6F8);

  // 骑手已经出发或药已经备好，取消会造成诊所/骑手的损失，锁死取消按钮
  static const List<String> _lockedStatuses = ['Assigned', 'Delivering', 'ReadyForPickup'];

  static const List<String> _cancelReasons = [
    'Selected the wrong time',
    'No longer needed',
    'Ordered by mistake',
    'Other',
  ];

  List<QueryDocumentSnapshot> _orders = [];
  final Map<String, List<QueryDocumentSnapshot>> _itemsByOrder = {};
  bool _isLoading = true;
  StreamSubscription<QuerySnapshot>? _orderSubscription;

  @override
  void initState() {
    super.initState();
    _listenToOrders();
  }

  @override
  void dispose() {
    _orderSubscription?.cancel();
    super.dispose();
  }

  // 用实时监听而不是一次性 get()：这样 Admin 那边一 approve/reject，
  // 这个页面马上就能看到最新状态，不用用户自己退出再进来刷新。
  void _listenToOrders() {
    String uid = FirebaseAuth.instance.currentUser?.uid ?? "TEST_CUSTOMER_001";

    // 不用 orderBy，避免要求建立复合索引；改成拿回来后本地排序
    _orderSubscription = FirebaseFirestore.instance
        .collection('Order')
        .where('customerID', isEqualTo: uid)
        .snapshots()
        .listen((snapshot) async {
      List<QueryDocumentSnapshot> orders = snapshot.docs;
      orders.sort((a, b) {
        Timestamp? tA = (a.data() as Map<String, dynamic>)['orderDate'] as Timestamp?;
        Timestamp? tB = (b.data() as Map<String, dynamic>)['orderDate'] as Timestamp?;
        if (tA == null || tB == null) return 0;
        return tB.compareTo(tA);
      });

      // 订单里的商品清单不会变，只补拉还没缓存过的新订单，避免每次更新都重复查询
      final uncachedIds = orders.map((o) => o.id).where((id) => !_itemsByOrder.containsKey(id));
      await Future.wait(uncachedIds.map((orderId) async {
        QuerySnapshot itemSnap = await FirebaseFirestore.instance
            .collection('CartItem')
            .where('orderID', isEqualTo: orderId)
            .get();
        _itemsByOrder[orderId] = itemSnap.docs;
      }));

      if (mounted) {
        setState(() {
          _orders = orders;
          _isLoading = false;
        });
      }
    }, onError: (e) {
      debugPrint("Error listening to orders: $e");
      if (mounted) setState(() => _isLoading = false);
    });
  }

  String _itemsSummary(String orderId) {
    final items = _itemsByOrder[orderId] ?? [];
    if (items.isEmpty) return "No items";
    return items.map((i) {
      final data = i.data() as Map<String, dynamic>;
      return "${data['productName'] ?? 'Item'} x${data['quantity'] ?? 1}";
    }).join(", ");
  }

  // ================= 通道 A：发货前取消 =================

  void _showCancelDialog(String orderId) {
    String? selectedReason;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Cancel Order", style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Please tell us why you're cancelling:", style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedReason,
                isExpanded: true,
                decoration: InputDecoration(filled: true, fillColor: bgGray, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
                hint: const Text("Select a reason"),
                items: _cancelReasons.map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setDialogState(() => selectedReason = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Back", style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: selectedReason == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      _submitCancellation(orderId, selectedReason!);
                    },
              child: const Text("Submit", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitCancellation(String orderId, String reason) async {
    try {
      await FirebaseFirestore.instance.collection('Order').doc(orderId).update({
        'orderStatus': 'Cancellation Pending',
        'cancellationReason': reason,
        'cancellationRequestedTime': FieldValue.serverTimestamp(),
      });

      NotificationService.instance.send(
        role: 'Admin',
        title: 'Cancellation Requested',
        body: 'Order $orderId — $reason',
        data: {'orderId': orderId},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cancellation request submitted.'), backgroundColor: Colors.orange));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to submit: $e'), backgroundColor: Colors.redAccent));
    }
  }

  // ================= 通道 B：送达后售后退款 =================

  void _showRefundDialog(String orderId) {
    TextEditingController reasonCtrl = TextEditingController();
    File? proofPhoto;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickProof() async {
              final XFile? picked = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80);
              if (picked != null) setModalState(() => proofPhoto = File(picked.path));
            }

            bool canSubmit = reasonCtrl.text.trim().isNotEmpty && proofPhoto != null;

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Request Refund", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text("Please describe the issue and attach a photo as proof.", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                    const SizedBox(height: 20),
                    TextField(
                      controller: reasonCtrl,
                      maxLines: 3,
                      onChanged: (_) => setModalState(() {}),
                      decoration: InputDecoration(labelText: "Reason (e.g. package damaged in transit)", filled: true, fillColor: bgGray, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: pickProof,
                      child: Container(
                        width: double.infinity,
                        height: 160,
                        decoration: BoxDecoration(color: bgGray, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey[300]!)),
                        child: proofPhoto == null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.camera_alt_rounded, size: 36, color: Colors.grey[500]),
                                  const SizedBox(height: 8),
                                  Text("Tap to take a photo of the issue", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                                ],
                              )
                            : ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.file(proofPhoto!, fit: BoxFit.cover, width: double.infinity, height: 160)),
                      ),
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: !canSubmit
                            ? null
                            : () {
                                Navigator.pop(context);
                                _submitRefundRequest(orderId, reasonCtrl.text.trim(), proofPhoto!);
                              },
                        style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                        child: const Text("Submit Refund Request", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submitRefundRequest(String orderId, String reason, File proofPhoto) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: primaryGreen), const SizedBox(height: 16), const Text("Submitting...", style: TextStyle(fontWeight: FontWeight.bold))]),
      ),
    );

    try {
      final storageRef = FirebaseStorage.instance.ref().child('refund_proofs/$orderId.jpg');
      await storageRef.putFile(proofPhoto);
      final proofUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance.collection('Order').doc(orderId).update({
        'orderStatus': 'Refund Pending',
        'refundReason': reason,
        'refundProofPhoto': proofUrl,
        'refundRequestedTime': FieldValue.serverTimestamp(),
        'rejectionReason': null,
      });

      NotificationService.instance.send(
        role: 'Admin',
        title: 'Refund Requested',
        body: 'Order $orderId — $reason',
        data: {'orderId': orderId},
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Refund request submitted.'), backgroundColor: Colors.orange));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to submit: $e'), backgroundColor: Colors.redAccent));
    }
  }

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
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryGreen))
          : _orders.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _orders.length,
                  itemBuilder: (context, index) {
                    final doc = _orders[index];
                    final order = doc.data() as Map<String, dynamic>;
                    return _buildOrderCard(doc.id, order);
                  },
                ),
    );
  }

  Widget _buildOrderCard(String orderId, Map<String, dynamic> order) {
    String status = order['orderStatus'] ?? 'Pending';
    double total = (order['totalAmount'] ?? 0.0).toDouble();
    Timestamp? orderDate = order['orderDate'] as Timestamp?;
    String dateStr = orderDate != null ? DateFormat('MMM dd, yyyy').format(orderDate.toDate()) : '';
    String? rejectionReason = order['rejectionReason'];

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
              Expanded(
                child: Text(order['orderID'] ?? orderId, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const SizedBox(width: 8),
              _buildStatusChip(status),
            ],
          ),
          const Divider(height: 24),
          Text(_itemsSummary(orderId), style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(dateStr, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              Text("RM ${total.toStringAsFixed(2)}", style: TextStyle(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          if (status == 'Completed' && rejectionReason != null && rejectionReason.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(10)),
              child: Text("Your last refund request was rejected: $rejectionReason", style: TextStyle(color: Colors.red[700], fontSize: 12)),
            ),
          ],
          const SizedBox(height: 12),
          _buildActionRow(orderId, status),
        ],
      ),
    );
  }

  Widget _buildActionRow(String orderId, String status) {
    if (status == 'Pending') {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _showCancelDialog(orderId),
          icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 18),
          label: const Text("Cancel Order", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      );
    }

    if (_lockedStatuses.contains(status)) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: null,
              icon: Icon(Icons.cancel_outlined, color: Colors.grey[400], size: 18),
              label: Text("Cancel Order", style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.grey[300]!), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ),
          const SizedBox(height: 6),
          Text("Your order is already being prepared/delivered and can no longer be cancelled.", style: TextStyle(color: Colors.grey[400], fontSize: 11), textAlign: TextAlign.center),
        ],
      );
    }

    if (status == 'Completed') {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _showRefundDialog(orderId),
          icon: Icon(Icons.assignment_return_outlined, color: primaryGreen, size: 18),
          label: Text("Request Refund", style: TextStyle(color: primaryGreen, fontWeight: FontWeight.bold)),
          style: OutlinedButton.styleFrom(side: BorderSide(color: primaryGreen), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      );
    }

    if (status == 'Cancellation Pending') {
      return _buildInfoBanner(Icons.hourglass_top_rounded, Colors.orange, "Cancellation request submitted — waiting for clinic approval");
    }

    if (status == 'Refund Pending') {
      return _buildInfoBanner(Icons.hourglass_top_rounded, Colors.orange, "Refund request submitted — under review");
    }

    if (status == 'Cancelled & Refunded' || status == 'Refunded') {
      return _buildInfoBanner(Icons.check_circle_outline_rounded, Colors.green, "This order has been refunded");
    }

    return const SizedBox.shrink();
  }

  Widget _buildInfoBanner(IconData icon, MaterialColor color, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(color: color[50], borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, color: color[700], size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color[700], fontSize: 12, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color bg = Colors.green[50]!;
    Color fg = primaryGreen;
    if (status == 'Pending') {
      bg = Colors.orange[50]!;
      fg = Colors.orange[800]!;
    }
    if (status == 'Assigned' || status == 'ReadyForPickup') {
      bg = Colors.blue[50]!;
      fg = Colors.blue[700]!;
    }
    if (status == 'Delivering') {
      bg = Colors.indigo[50]!;
      fg = Colors.indigo[700]!;
    }
    if (status == 'Cancellation Pending' || status == 'Refund Pending') {
      bg = Colors.orange[50]!;
      fg = Colors.orange[800]!;
    }
    if (status == 'Cancelled & Refunded' || status == 'Refunded') {
      bg = Colors.red[50]!;
      fg = Colors.red[700]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(status, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text("No orders yet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[700])),
        ],
      ),
    );
  }
}
