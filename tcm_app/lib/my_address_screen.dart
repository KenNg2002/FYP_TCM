import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MyAddressScreen extends StatefulWidget {
  const MyAddressScreen({super.key});

  @override
  State<MyAddressScreen> createState() => _MyAddressScreenState();
}

class _MyAddressScreenState extends State<MyAddressScreen> {
  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color bgGray = const Color(0xFFF4F6F8);

  List<Map<String, dynamic>> _addressList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAddresses();
  }

  // Fetch all addresses for this Customer
  Future<void> _fetchAddresses() async {
    try {
      String uid = FirebaseAuth.instance.currentUser!.uid;
      
      // ⚠️ 修复 1：严格使用小写 c 的 'customerID' 进行匹配
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('shippingaddress') 
          .where('customerID', isEqualTo: uid)
          .get();

      List<Map<String, dynamic>> loadedAddresses = snapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['sId'] = doc.id; 
        return data;
      }).toList();

      if (mounted) {
        setState(() {
          _addressList = loadedAddresses;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching addresses: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        // 如果有权限问题或其他错误，弹窗提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading addresses: $e'), backgroundColor: Colors.redAccent)
        );
      }
    }
  }

  Future<void> _saveAddress({
    String? sId,
    required String receiverName,
    required String phoneNo,
    required String fullAddress,
    required String label,
  }) async {
    setState(() => _isLoading = true);
    try {
      String uid = FirebaseAuth.instance.currentUser!.uid;
      
      CollectionReference addressRef = FirebaseFirestore.instance.collection('shippingaddress');

      Map<String, dynamic> data = {
        'customerID': uid, // ⚠️ 修复 1：写入时也严格使用小写 c
        'receiverName': receiverName,
        'phoneNo': phoneNo,
        'fullAddress': fullAddress,
        'label': label,
      };

      if (sId == null) {
        DocumentReference docRef = await addressRef.add(data);
        await docRef.update({'sId': docRef.id}); 
      } else {
        data['sId'] = sId;
        await addressRef.doc(sId).update(data); 
      }

      await _fetchAddresses(); 
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Address saved successfully!'), backgroundColor: primaryGreen)
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save address: $e'), backgroundColor: Colors.redAccent)
        );
      }
    }
  }

  void _showAddressForm({Map<String, dynamic>? existingAddress}) {
    TextEditingController nameController = TextEditingController(text: existingAddress?['receiverName'] ?? "");
    TextEditingController phoneController = TextEditingController(text: existingAddress?['phoneNo'] ?? "");
    TextEditingController addressController = TextEditingController(text: existingAddress?['fullAddress'] ?? "");
    String selectedLabel = existingAddress?['label'] ?? "Home";

    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return StatefulBuilder( 
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom, 
                left: 24, right: 24, top: 24
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min, 
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existingAddress == null ? "Add New Address" : "Edit Address", 
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)
                    ),
                    const SizedBox(height: 20),
                    
                    TextField(
                      controller: nameController, 
                      decoration: InputDecoration(labelText: "Receiver Name", filled: true, fillColor: bgGray, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none))
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController, 
                      keyboardType: TextInputType.phone, 
                      decoration: InputDecoration(labelText: "Phone Number", filled: true, fillColor: bgGray, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none))
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressController, 
                      maxLines: 3, 
                      decoration: InputDecoration(labelText: "Full Address", filled: true, fillColor: bgGray, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none))
                    ),
                    const SizedBox(height: 16),
                    
                    const Text("Label", style: TextStyle(fontWeight: FontWeight.bold)),
                    Row(
                      children: ["Home", "Office", "Other"].map((label) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text(label),
                            selected: selectedLabel == label,
                            selectedColor: primaryGreen.withOpacity(0.2),
                            onSelected: (bool selected) { if (selected) setModalState(() => selectedLabel = label); },
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 30),
                    
                    SizedBox(
                      width: double.infinity, height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          if (nameController.text.isNotEmpty && phoneController.text.isNotEmpty && addressController.text.isNotEmpty) {
                            Navigator.pop(context);
                            _saveAddress(
                              sId: existingAddress?['sId'], 
                              receiverName: nameController.text.trim(),
                              phoneNo: phoneController.text.trim(),
                              fullAddress: addressController.text.trim(),
                              label: selectedLabel,
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                        child: const Text("Save Address", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            );
          }
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
        title: const Text("My Addresses", style: TextStyle(color: Color(0xFF212121), fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: _isLoading 
          ? Center(child: CircularProgressIndicator(color: primaryGreen))
          : _addressList.isEmpty 
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.location_off_outlined, size: 80, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text("No Address Found", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: _addressList.length,
                itemBuilder: (context, index) {
                  final addr = _addressList[index];

                  // ⚠️ 修复 2：强大的防空指针保护 (Null Safety)
                  // 这样即使你在数据库里少填了某个字段，也不会导致白屏崩溃
                  String label = addr['label'] ?? 'Home';
                  String receiverName = addr['receiverName'] ?? 'Unknown User';
                  String phoneNo = addr['phoneNo'] ?? '-';
                  String fullAddress = addr['fullAddress'] ?? 'No Address Data';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.transparent, width: 2)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(label == 'Office' ? Icons.work_outline : Icons.home_rounded, color: primaryGreen, size: 24),
                            const SizedBox(width: 8),
                            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text("$receiverName | $phoneNo", style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(fullAddress, style: TextStyle(color: Colors.grey[700], height: 1.5)),
                        const Divider(height: 30),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            GestureDetector(
                              onTap: () => _showAddressForm(existingAddress: addr), 
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined, color: primaryGreen, size: 18), 
                                  const SizedBox(width: 4), 
                                  Text("Edit", style: TextStyle(color: primaryGreen, fontWeight: FontWeight.bold))
                                ]
                              )
                            ),
                          ],
                        )
                      ],
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddressForm(),
        backgroundColor: primaryGreen,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Add New", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}