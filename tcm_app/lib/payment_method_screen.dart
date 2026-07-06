import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http; // ⚠️ 引入网络请求库
import 'dart:convert';
import 'ipaddress.dart';

class PaymentMethodScreen extends StatefulWidget {
  const PaymentMethodScreen({super.key});

  @override
  State<PaymentMethodScreen> createState() => _PaymentMethodScreenState();
}

class _PaymentMethodScreenState extends State<PaymentMethodScreen> {
  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color bgGray = const Color(0xFFF4F6F8);

  List<Map<String, dynamic>> _cardList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCards();
  }

  Future<void> _fetchCards() async {
    try {
      String uid = FirebaseAuth.instance.currentUser!.uid;
      
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('paymentmethod')
          .where('CustomerID', isEqualTo: uid)
          .get();

      List<Map<String, dynamic>> loadedCards = snapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['pId'] = doc.id; 
        return data;
      }).toList();

      setState(() {
        _cardList = loadedCards;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error fetching cards: $e");
      setState(() => _isLoading = false);
    }
  }

  // 🚀 核心升级：真实调用 Node.js 后端获取 Stripe Token
  Future<void> _saveCard({
    required String cardName,
    required String cardNumber,
    required String expiryDate,
    required String cvv, 
  }) async {
    setState(() => _isLoading = true);
    try {
      User currentUser = FirebaseAuth.instance.currentUser!;
      String uid = currentUser.uid;
      String email = currentUser.email ?? 'customer@tcm.com';

      // 1. 解析 MM/YY 格式
      List<String> expiryParts = expiryDate.split('/');
      int expMonth = int.parse(expiryParts[0]);
      int expYear = int.parse('20${expiryParts[1]}'); // 转成 20XX 年

      // 2. 呼叫我们刚才写的 Node.js 绑卡 API
      // ⚠️ 如果你用 Android 模拟器，地址是 10.0.2.2；如果是真机/iOS，填你电脑的局域网 IP
      // final url = Uri.parse('http://10.0.2.2:$serverPort/save-card'); // Android emulator
      // final url = Uri.parse('http://localhost:$serverPort/save-card'); // Chrome/web testing
      final url = Uri.parse('$serverBaseUrl/save-card'); // Physical device (see ipaddress.dart)
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'number': cardNumber,
          'expMonth': expMonth,
          'expYear': expYear,
          'cvc': cvv,
        }),
      );

      final jsonResponse = jsonDecode(response.body);

      if (jsonResponse['success'] == true) {
        // 3. 绑卡成功！把后端传回来的【安全代币】存进 Firebase (绝对不存完整卡号)
        String stripeCustomerId = jsonResponse['customerId'];
        String stripePaymentMethodId = jsonResponse['paymentMethodId'];
        String last4 = jsonResponse['last4'];
        String brand = jsonResponse['brand']; // 比如 visa, mastercard

        String cardType = brand == 'mastercard' ? 'Mastercard' : 'Visa';

        CollectionReference cardRef = FirebaseFirestore.instance.collection('paymentmethod');
        Map<String, dynamic> data = {
          'CustomerID': uid,
          'cardName': cardName.toUpperCase(),
          'last4': last4, 
          'expiryDate': expiryDate, 
          'cardType': cardType,
          'stripeCustomerId': stripeCustomerId,       // ⚠️ 存入 Stripe 顾客代币
          'stripePaymentMethodId': stripePaymentMethodId, // ⚠️ 存入 支付代币
          'addedAt': FieldValue.serverTimestamp(),
        };

        DocumentReference docRef = await cardRef.add(data);
        await docRef.update({'pId': docRef.id}); 

        await _fetchCards(); 
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Card added securely!'), backgroundColor: primaryGreen)
        );
      } else {
        throw Exception(jsonResponse['error']);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add card: $e'), backgroundColor: Colors.redAccent)
      );
    }
  }

  Future<void> _deleteCard(String pId) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('paymentmethod').doc(pId).delete();
      await _fetchCards();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Card removed successfully.'), backgroundColor: Colors.orangeAccent)
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error removing card: $e'), backgroundColor: Colors.redAccent)
      );
    }
  }

  void _showAddCardBottomSheet() {
    final formKey = GlobalKey<FormState>(); 
    TextEditingController nameController = TextEditingController();
    TextEditingController numberController = TextEditingController();
    TextEditingController expiryController = TextEditingController();
    TextEditingController cvvController = TextEditingController();

    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom, 
            left: 24, right: 24, top: 24
          ),
          child: SingleChildScrollView(
            child: Form( 
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min, 
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Add New Card", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  
                  TextFormField(
                    controller: nameController, 
                    validator: (value) => value!.trim().isEmpty ? "Name cannot be empty" : null,
                    decoration: InputDecoration(labelText: "Cardholder Name", filled: true, fillColor: bgGray, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none), errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.redAccent, width: 1)), focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.redAccent, width: 2)))
                  ),
                  const SizedBox(height: 12),
                  
                  TextFormField(
                    controller: numberController, 
                    keyboardType: TextInputType.number, 
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly, 
                      LengthLimitingTextInputFormatter(16),
                    ],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return "Card number required";
                      if (value.length != 16) return "Must be exactly 16 digits";
                      return null;
                    },
                    decoration: InputDecoration(labelText: "Card Number (16 digits)", counterText: "", filled: true, fillColor: bgGray, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none), errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.redAccent, width: 1)), focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.redAccent, width: 2)))
                  ),
                  const SizedBox(height: 12),
                  
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: expiryController, 
                          keyboardType: TextInputType.number, 
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')), 
                            _ExpiryDateFormatter(),
                            LengthLimitingTextInputFormatter(5), 
                          ],
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return "Required";
                            if (!RegExp(r'^(0[1-9]|1[0-2])\/\d{2}$').hasMatch(value)) return "Invalid (MM/YY)";
                            return null;
                          },
                          decoration: InputDecoration(labelText: "Expiry (MM/YY)", counterText: "", filled: true, fillColor: bgGray, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none), errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.redAccent, width: 1)), focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.redAccent, width: 2)))
                        ),
                      ),
                      const SizedBox(width: 12),
                      
                      Expanded(
                        child: TextFormField(
                          controller: cvvController, 
                          keyboardType: TextInputType.number, 
                          obscureText: true,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(3),
                          ],
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return "Required";
                            if (value.length != 3) return "Must be 3 digits";
                            return null;
                          },
                          decoration: InputDecoration(labelText: "CVV", counterText: "", filled: true, fillColor: bgGray, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none), errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.redAccent, width: 1)), focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.redAccent, width: 2)))
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  
                  SizedBox(
                    width: double.infinity, height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        if (formKey.currentState!.validate()) {
                          Navigator.pop(context);
                          _saveCard(
                            cardName: nameController.text.trim(),
                            cardNumber: numberController.text.trim(),
                            expiryDate: expiryController.text.trim(),
                            cvv: cvvController.text.trim(),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                      child: const Text("Save Card Securely", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGray,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0, centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF212121)), onPressed: () => Navigator.pop(context)),
        title: const Text("Payment Methods", style: TextStyle(color: Color(0xFF212121), fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: _isLoading 
          ? Center(child: CircularProgressIndicator(color: primaryGreen))
          : _cardList.isEmpty 
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.credit_card_off_outlined, size: 80, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text("No Cards Found", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                    const SizedBox(height: 8),
                    Text("Add a credit or debit card for faster checkout.", style: TextStyle(color: Colors.grey[500])),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: _cardList.length,
                itemBuilder: (context, index) {
                  final card = _cardList[index];
                  
                  List<Color> cardGradient = card['cardType'] == 'Mastercard' 
                      ? [const Color(0xFF1E3C72), const Color(0xFF2A5298)] 
                      : [const Color(0xFF2E7D32), const Color(0xFF4CAF50)];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: cardGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: cardGradient[1].withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Icon(Icons.memory, color: Colors.amber[300], size: 40),
                            Text(card['cardType'], style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                          ],
                        ),
                        const SizedBox(height: 30),
                        Text(
                          "**** **** **** ${card['last4']}",
                          style: const TextStyle(color: Colors.white, fontSize: 22, letterSpacing: 2, fontFamily: 'monospace'),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("CARDHOLDER", style: TextStyle(color: Colors.white54, fontSize: 10)),
                                  const SizedBox(height: 4),
                                  Text(card['cardName'], overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("EXPIRES", style: TextStyle(color: Colors.white54, fontSize: 10)),
                                const SizedBox(height: 4),
                                Text(card['expiryDate'], style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () => _deleteCard(card['pId']),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                                child: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
                              ),
                            )
                          ],
                        )
                      ],
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCardBottomSheet,
        backgroundColor: primaryGreen,
        icon: const Icon(Icons.add_card, color: Colors.white),
        label: const Text("Add Card", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String newText = newValue.text;
    String oldText = oldValue.text;
    if (newText.length < oldText.length) return newValue;
    String cleaned = newText.replaceAll('/', '');
    if (cleaned.length > 2) cleaned = '${cleaned.substring(0, 2)}/${cleaned.substring(2)}';
    if (cleaned.length > 5) cleaned = cleaned.substring(0, 5);
    return TextEditingValue(text: cleaned, selection: TextSelection.collapsed(offset: cleaned.length));
  }
}