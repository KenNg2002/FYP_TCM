import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'address_utils.dart';
import 'ipaddress.dart';
import 'notification_service.dart';

class CheckoutPaymentScreen extends StatefulWidget {
  final String cartId;
  final double totalAmount;

  const CheckoutPaymentScreen({Key? key, required this.cartId, required this.totalAmount}) : super(key: key);

  @override
  _CheckoutPaymentScreenState createState() => _CheckoutPaymentScreenState();
}

class _CheckoutPaymentScreenState extends State<CheckoutPaymentScreen> {
  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color bgGray = const Color(0xFFF4F6F8);

  bool _isLoadingData = true;
  bool _isProcessing = false;

  List<Map<String, dynamic>> _savedAddresses = [];
  Map<String, dynamic>? _selectedAddress;

  List<Map<String, dynamic>> _savedPaymentMethods = [];
  String? _selectedPaymentId;
  bool _showPaymentError = false;
  
  String _deliveryMethod = 'Same-Day Delivery';
  double get _deliveryFee => _deliveryMethod == 'Self Pickup' ? 0.0 : 5.00;

  List<QueryDocumentSnapshot> _checkoutItems = [];

  @override
  void initState() {
    super.initState();
    _loadCheckoutData();
  }

  Future<void> _loadCheckoutData() async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      String customerId = currentUser?.uid ?? "TEST_CUSTOMER_001";

      var addressQuery = await FirebaseFirestore.instance.collection('shippingaddress').where('customerID', isEqualTo: customerId).get();
      var paymentQuery = await FirebaseFirestore.instance.collection('paymentmethod').where('CustomerID', isEqualTo: customerId).get();
      var itemsQuery = await FirebaseFirestore.instance.collection('CartItem').where('cartID', isEqualTo: widget.cartId).where('orderID', isNull: true).get();

      setState(() {
        if (addressQuery.docs.isNotEmpty) {
          _savedAddresses = addressQuery.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          _selectedAddress = _savedAddresses.first;
        }

        if (paymentQuery.docs.isNotEmpty) {
          _savedPaymentMethods = paymentQuery.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        }

        _checkoutItems = itemsQuery.docs;
        _isLoadingData = false;
      });
    } catch (e) {
      print("Error loading data: $e");
      setState(() => _isLoadingData = false);
    }
  }

  Future<void> _addNewAddress(String name, String phone, String addressLine1, String addressLine2, String city, String postcode, String state) async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    String customerId = currentUser?.uid ?? "TEST_CUSTOMER_001";
    DocumentReference newAddrRef = FirebaseFirestore.instance.collection('shippingaddress').doc();

    Map<String, dynamic> newAddrData = {
      'sId': newAddrRef.id,
      'customerID': customerId,
      'receiverName': name,
      'phoneNo': phone,
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'postcode': postcode,
      'state': state,
      'label': 'Home',
    };

    await newAddrRef.set(newAddrData); 

    setState(() {
      newAddrData['id'] = newAddrRef.id;
      _savedAddresses.add(newAddrData);
      _selectedAddress = newAddrData; 
    });
  }

  // One-click checkout — charges the saved card directly, no web redirect
  Future<void> _handleStripePayment() async {
    if (_deliveryMethod != 'Self Pickup' && _selectedAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a delivery address.'), backgroundColor: Colors.red));
      return;
    }

    if (_selectedPaymentId == null) {
      setState(() => _showPaymentError = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a payment method.'), backgroundColor: Colors.red));
      return;
    }

    setState(() { _isProcessing = true; });

    try {
      if (_selectedPaymentId == 'COD') {
        await Future.delayed(const Duration(seconds: 1));
        await _createOrderInFirebase();
        return;
      }

      var selectedCard = _savedPaymentMethods.firstWhere((card) => card['pId'] == _selectedPaymentId || card['id'] == _selectedPaymentId);

      String stripeCustomerId = selectedCard['stripeCustomerId'];
      String stripePaymentMethodId = selectedCard['stripePaymentMethodId'];

      // Convert total to cents (Stripe requires cents, e.g. RM 52.50 -> 5250)
      double finalTotalAmount = widget.totalAmount + _deliveryFee;
      int amountInCents = (finalTotalAmount * 100).toInt();

      // Call the Node.js backend to charge the card directly using the saved token — no web redirect needed
      // final url = Uri.parse('http://10.0.2.2:$serverPort/charge-card'); // Android emulator
      // final url = Uri.parse('http://localhost:$serverPort/charge-card'); // Chrome/web testing
      final url = Uri.parse('$serverBaseUrl/charge-card'); // Physical device (see ipaddress.dart)
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': amountInCents,
          'customerId': stripeCustomerId,
          'paymentMethodId': stripePaymentMethodId,
        }),
      );

      final jsonResponse = jsonDecode(response.body);

      if (jsonResponse['success'] == true) {
        // Stripe has already charged the card — immediately create the order in Firebase.
        // Save paymentIntentId: cancellations/refunds later need it to call Stripe to actually refund the money.
        await _createOrderInFirebase(stripePaymentIntentId: jsonResponse['paymentIntentId']);
      } else {
        throw Exception(jsonResponse['error']);
      }

    } catch (e) {
      print("Stripe Backend Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment failed. Please try another card.'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() { _isProcessing = false; });
    }
  }

  Future<void> _createOrderInFirebase({String? stripePaymentIntentId}) async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      String customerId = currentUser?.uid ?? "TEST_CUSTOMER_001";
      
      WriteBatch batch = FirebaseFirestore.instance.batch();
      DocumentReference orderRef = FirebaseFirestore.instance.collection('Order').doc();

      String fullShippingAddress = _deliveryMethod == 'Self Pickup'
          ? 'Self Pickup at TCM Clinic HQ'
          : "${_selectedAddress!['receiverName']} (${_selectedAddress!['phoneNo']})\n${formatAddress(_selectedAddress!)}";
      double finalTotalAmount = widget.totalAmount + _deliveryFee;

      batch.set(orderRef, {
        'orderID': orderRef.id,
        'orderDate': FieldValue.serverTimestamp(),
        'subTotal': widget.totalAmount,
        'deliveryFee': _deliveryFee,
        'totalAmount': finalTotalAmount,
        'deliveryMethod': _deliveryMethod,
        'shippingAddress': fullShippingAddress,
        'orderStatus': 'Pending',
        'customerID': customerId,
        'paymentMethodId': _selectedPaymentId,
        'stripePaymentIntentId': stripePaymentIntentId,
      });

      for (var item in _checkoutItems) {
        batch.update(item.reference, {'orderID': orderRef.id});
        String productId = item['productID'];
        int quantityBought = item['quantity'];
        DocumentReference productRef = FirebaseFirestore.instance.collection('HerbalProduct').doc(productId);
        batch.update(productRef, {'stockQuantity': FieldValue.increment(-quantityBought)});
      }

      DocumentReference cartRef = FirebaseFirestore.instance.collection('ShoppingCart').doc(widget.cartId);
      batch.update(cartRef, {
        'totalAmount': 0.0,
        'lastActive': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      NotificationService.instance.send(
        role: 'Admin',
        title: 'New Order Received',
        body: 'Order ${orderRef.id} — RM ${finalTotalAmount.toStringAsFixed(2)} ($_deliveryMethod)',
        data: {'orderId': orderRef.id},
      );

      _showSuccessDialog(orderRef.id);

    } catch (e) {
      print("Firebase Save Error: $e");
      setState(() { _isProcessing = false; });
    }
  }

  void _showSuccessDialog(String orderId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 16),
            const Text("Payment Successful!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text("Order ID: $orderId", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text("Back to Home", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      )
    );
  }

  void _showAddressSelector() {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
          child: Column(
            children: [
              const Padding(padding: EdgeInsets.all(20), child: Text("Select Delivery Address", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              Expanded(
                child: ListView.builder(
                  itemCount: _savedAddresses.length,
                  itemBuilder: (context, index) {
                    var addr = _savedAddresses[index];
                    bool isSelected = _selectedAddress?['sId'] == addr['sId'];
                    return ListTile(
                      leading: Icon(Icons.location_on, color: isSelected ? primaryGreen : Colors.grey[400]),
                      title: Text("${addr['receiverName']} | ${addr['phoneNo']}", style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                      subtitle: Text(formatAddress(addr), maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: isSelected ? Icon(Icons.check_circle, color: primaryGreen) : null,
                      onTap: () { setState(() => _selectedAddress = addr); Navigator.pop(context); },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add), label: const Text("Add New Address"),
                    style: OutlinedButton.styleFrom(foregroundColor: primaryGreen, side: BorderSide(color: primaryGreen), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                    onPressed: () { Navigator.pop(context); _showAddNewAddressDialog(); },
                  ),
                ),
              )
            ],
          ),
        );
      }
    );
  }

  void _showAddNewAddressDialog() {
    TextEditingController nameCtrl = TextEditingController();
    TextEditingController phoneCtrl = TextEditingController();
    TextEditingController line1Ctrl = TextEditingController();
    TextEditingController line2Ctrl = TextEditingController();
    TextEditingController cityCtrl = TextEditingController();
    TextEditingController postcodeCtrl = TextEditingController();
    TextEditingController stateCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("New Delivery Address", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Receiver Name")),
              TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "Phone Number")),
              const SizedBox(height: 10),
              TextField(controller: line1Ctrl, decoration: const InputDecoration(labelText: "Address Line 1", hintText: "House no., street name")),
              const SizedBox(height: 10),
              TextField(controller: line2Ctrl, decoration: const InputDecoration(labelText: "Address Line 2 (Optional)", hintText: "Unit, floor, building")),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: TextField(controller: postcodeCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Postcode"))),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: TextField(controller: cityCtrl, decoration: const InputDecoration(labelText: "City"))),
                ],
              ),
              const SizedBox(height: 10),
              TextField(controller: stateCtrl, decoration: const InputDecoration(labelText: "State")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen),
            onPressed: () {
              _addNewAddress(
                nameCtrl.text.trim(),
                phoneCtrl.text.trim(),
                line1Ctrl.text.trim(),
                line2Ctrl.text.trim(),
                cityCtrl.text.trim(),
                postcodeCtrl.text.trim(),
                stateCtrl.text.trim(),
              );
              Navigator.pop(context);
            },
            child: const Text("Save", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double finalTotalAmount = widget.totalAmount + _deliveryFee;

    return Scaffold(
      backgroundColor: bgGray,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0, centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1F2937)), onPressed: () => Navigator.pop(context)),
        title: const Text("Checkout", style: TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: _isLoadingData 
        ? const Center(child: CircularProgressIndicator()) 
        : SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_deliveryMethod == 'Self Pickup')
                  Container(
                    margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]),
                    child: Row(
                      children: [
                        Icon(Icons.storefront_rounded, color: primaryGreen, size: 30),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Pickup Location", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                              const SizedBox(height: 6),
                              const Text("TCM Clinic HQ", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  GestureDetector(
                    onTap: _showAddressSelector,
                    child: Container(
                      margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: _selectedAddress == null ? Colors.red.shade200 : Colors.transparent), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]),
                      child: Row(
                        children: [
                          Icon(Icons.location_on, color: primaryGreen, size: 30),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Delivery Address", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                                const SizedBox(height: 6),
                                _selectedAddress == null
                                  ? const Text("Tap to select or add address", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("${_selectedAddress!['receiverName']} | ${_selectedAddress!['phoneNo']}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                        Text(formatAddress(_selectedAddress!), style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937))),
                                      ],
                                    ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text("Order Items (${_checkoutItems.length})", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
                ),
                Container(
                  color: Colors.white,
                  child: ListView.builder(
                    shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _checkoutItems.length,
                    itemBuilder: (context, index) {
                      var item = _checkoutItems[index];
                      return ListTile(
                        leading: Container(width: 50, height: 50, decoration: BoxDecoration(color: primaryGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.eco, color: primaryGreen)),
                        title: Text(item['productName'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text("Quantity: ${item['quantity']}", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                        trailing: Text("RM ${(item['subtotal'] ?? 0.0).toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text("Delivery Method", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _buildDeliveryOption(Icons.electric_moped, "Same-Day Delivery", "Delivered today by our rider", "Same-Day Delivery", 5.00),
                      _buildDeliveryOption(Icons.storefront_rounded, "Self Pickup", "Pick up at TCM Clinic HQ", "Self Pickup", 0.0),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text("Payment Method", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
                ),
                if (_showPaymentError)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Text("Please select a payment method", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      ..._savedPaymentMethods.map((card) {
                        String last4 = card['last4']?.toString() ?? '0000';
                        return _buildPaymentOption(Icons.credit_card, card['cardType'] ?? 'Credit Card', "**** **** **** $last4", card['pId'] ?? card['id']);
                      }).toList(),
                      _buildPaymentOption(Icons.money, "Cash on Delivery (COD)", "Pay when you receive", "COD"),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),

      bottomNavigationBar: _isLoadingData ? const SizedBox.shrink() : Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))]),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Subtotal", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  Text("RM ${widget.totalAmount.toStringAsFixed(2)}", style: TextStyle(color: Colors.grey[800], fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Delivery Fee", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  Text("+ RM ${_deliveryFee.toStringAsFixed(2)}", style: TextStyle(color: Colors.grey[800], fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Total Payment", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                      Text("RM ${finalTotalAmount.toStringAsFixed(2)}", style: TextStyle(color: primaryGreen, fontSize: 24, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: _isProcessing ? null : _handleStripePayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 0,
                    ),
                    child: _isProcessing 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                      : const Text("Place Order", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeliveryOption(IconData icon, String title, String subtitle, String methodId, double fee) {
    bool isSelected = _deliveryMethod == methodId;
    return GestureDetector(
      onTap: () => setState(() => _deliveryMethod = methodId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: isSelected ? primaryGreen.withOpacity(0.05) : Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: isSelected ? primaryGreen : Colors.grey[200]!, width: isSelected ? 2 : 1)),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? primaryGreen : Colors.grey[400], size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? primaryGreen : const Color(0xFF1F2937))),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
            Text(fee == 0.0 ? "Free" : "RM ${fee.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? primaryGreen : Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentOption(IconData icon, String title, String subtitle, String paymentId) {
    bool isSelected = _selectedPaymentId == paymentId;
    return GestureDetector(
      onTap: () => setState(() { _selectedPaymentId = paymentId; _showPaymentError = false; }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: isSelected ? primaryGreen.withOpacity(0.05) : Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: isSelected ? primaryGreen : Colors.grey[200]!, width: isSelected ? 2 : 1)),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? primaryGreen : Colors.grey[400], size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? primaryGreen : const Color(0xFF1F2937))),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, color: primaryGreen),
          ],
        ),
      ),
    );
  }
}