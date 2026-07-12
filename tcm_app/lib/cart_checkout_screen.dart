import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'checkout_payment_screen.dart';

class CartCheckoutScreen extends StatefulWidget {
  @override
  _CartCheckoutScreenState createState() => _CartCheckoutScreenState();
}

class _CartCheckoutScreenState extends State<CartCheckoutScreen> {
  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color bgGray = const Color(0xFFF4F6F8);
  
  String? customerId;
  String? cartId; 
  bool _isLoading = true; 

  @override
  void initState() {
    super.initState();
    _initializeUserCart();
  }

  Future<void> _initializeUserCart() async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      String uid = currentUser?.uid ?? "TEST_CUSTOMER_001"; 
      customerId = uid;
      cartId = uid; 

      var cartDoc = await FirebaseFirestore.instance.collection('ShoppingCart').doc(cartId).get();
      
      if (!cartDoc.exists) {
        await FirebaseFirestore.instance.collection('ShoppingCart').doc(cartId).set({
          'customerID': customerId,
          'lastActive': FieldValue.serverTimestamp(),
          'totalAmount': 0.0,
        });
      }
    } catch (e) {
      print("Error initializing cart: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateQuantity(String docId, int currentQty, int stockQuantity, double unitPrice, bool isAdd, String unit) async {
    int step = 1;
    int newQty = isAdd ? currentQty + step : currentQty - step;
    if (newQty < step) return;
    // "unlimited" items aren't stock-tracked, so there's no cap to enforce
    if (unit != 'unlimited' && newQty > stockQuantity) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot exceed available stock ($stockQuantity $unit).'), backgroundColor: Colors.orange));
      return;
    }
    await FirebaseFirestore.instance.collection('CartItem').doc(docId).update({
      'quantity': newQty,
      'subtotal': newQty * unitPrice,
    });
  }

  Future<void> _deleteItem(String docId) async {
    await FirebaseFirestore.instance.collection('CartItem').doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGray,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0, centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1F2937)), onPressed: () => Navigator.pop(context)),
        title: const Text("My Cart", style: TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32))) 
        : Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('CartItem')
                      .where('cartID', isEqualTo: cartId)
                      .where('orderID', isNull: true) // Only show items not yet paid for
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)));
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return _buildEmptyCart();

                    var cartItems = snapshot.data!.docs;
                    double totalAmount = 0.0;

                    for (var item in cartItems) {
                      totalAmount += (item['subtotal'] ?? 0.0).toDouble();
                    }

                    if (cartId != null) {
                      FirebaseFirestore.instance.collection('ShoppingCart').doc(cartId).update({
                        'totalAmount': totalAmount,
                        'lastActive': FieldValue.serverTimestamp(),
                      });
                    }

                    return Column(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            itemCount: cartItems.length,
                            itemBuilder: (context, index) {
                              var item = cartItems[index];
                              return _buildCartItemCard(item);
                            },
                          ),
                        ),
                        _buildCheckoutBar(totalAmount, cartItems.length),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_bag_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text("Your cart is empty", style: TextStyle(color: Colors.grey[800], fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text("Looks like you haven't added any herbs yet.", style: TextStyle(color: Colors.grey[500], fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildCartItemCard(QueryDocumentSnapshot item) {
    String docId = item.id;
    String productName = item['productName'] ?? 'Unknown Herb';
    int quantity = item['quantity'] ?? 1;
    double subtotal = (item['subtotal'] ?? 0.0).toDouble();
    int stockQuantity = item['stockQuantity'] ?? 0;
    String unit = item['unit'] ?? 'pcs';
    // "unlimited" is a stock-tracking mode, not a real unit — display it as plain pieces
    String displayUnit = unit == 'unlimited' ? 'pcs' : unit;

    double unitPrice = quantity > 0 ? (subtotal / quantity) : 0.0;

    return Dismissible(
      key: Key(docId),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(20)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 30),
      ),
      onDismissed: (direction) => _deleteItem(docId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]),
        child: Row(
          children: [
            Container(width: 70, height: 70, decoration: BoxDecoration(color: primaryGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(15)), child: Icon(Icons.eco, color: primaryGreen, size: 32)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(productName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
                  const SizedBox(height: 6),
                  Text("RM ${unitPrice.toStringAsFixed(2)} / $displayUnit", style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text("Subtotal: RM ${subtotal.toStringAsFixed(2)}", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: primaryGreen)),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.grey[200]!), borderRadius: BorderRadius.circular(25)),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.remove, size: 16), color: Colors.grey[600], constraints: const BoxConstraints(minWidth: 35, minHeight: 35), padding: EdgeInsets.zero, onPressed: () => _updateQuantity(docId, quantity, stockQuantity, unitPrice, false, unit)),
                  Text('$quantity $displayUnit', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  IconButton(icon: const Icon(Icons.add, size: 16), color: primaryGreen, constraints: const BoxConstraints(minWidth: 35, minHeight: 35), padding: EdgeInsets.zero, onPressed: () => _updateQuantity(docId, quantity, stockQuantity, unitPrice, true, unit)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckoutBar(double totalAmount, int itemCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(30)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))]),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
              children: [
                Text("Total ($itemCount items)", style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text("RM ${totalAmount.toStringAsFixed(2)}", style: TextStyle(color: const Color(0xFF1F2937), fontSize: 22, fontWeight: FontWeight.w900)),
              ],
            ),
            ElevatedButton(
              onPressed: itemCount == 0 ? null : () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => CheckoutPaymentScreen(cartId: cartId!, totalAmount: totalAmount)));
              },
              style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, disabledBackgroundColor: Colors.grey[300], padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 0),
              child: const Row(children: [Text("Checkout", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)), SizedBox(width: 8), Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20)]),
            ),
          ],
        ),
      ),
    );
  }
}