import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EditProfileScreen extends StatefulWidget {
  final String currentName;
  final String currentPhone;
  final String currentEmail; 
  final String currentDob;

  const EditProfileScreen({
    super.key,
    required this.currentName,
    required this.currentPhone,
    required this.currentEmail,
    required this.currentDob,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _dobController;

  bool _isLoading = false;

  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color bgGray = const Color(0xFFF4F6F8);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
    _phoneController = TextEditingController(text: widget.currentPhone);
    _dobController = TextEditingController(text: widget.currentDob);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 20)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: primaryGreen)),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dobController.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      String uid = FirebaseAuth.instance.currentUser!.uid;

      // 1. Update basic fields in 'User' document (修复：完全对齐 ER 数据库图里的命名)
      await FirebaseFirestore.instance.collection('User').doc(uid).update({
        'username': _nameController.text.trim(),       // 之前这里错写成了 fullName
        'userPhoneNum': _phoneController.text.trim(),  // 之前这里错写成了 phoneNo
      });

      // 2. Update specific fields in 'Customer' document
      await FirebaseFirestore.instance.collection('Customer').doc(uid).set({
        'customerID': uid, // 确保与你截图里的 CustomerID / customerID 大小写一致
        'dateOfBirth': _dobController.text.trim(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Profile updated!'), backgroundColor: primaryGreen));
      
      // 这里带着 true 返回上一页，就会触发 user_profile_screen 里的 _fetchUserData() 重新加载！
      Navigator.pop(context, true); 

    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: $e'), backgroundColor: Colors.redAccent));
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
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF212121)), onPressed: () => Navigator.pop(context)),
        title: const Text("Edit Profile", style: TextStyle(color: Color(0xFF212121), fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _buildTextField(controller: _nameController, label: "Full Name", icon: Icons.person_outline, validator: (v) => v!.trim().isEmpty ? "Name required" : null),
                const SizedBox(height: 20),
                _buildTextField(controller: _phoneController, label: "Phone Number", icon: Icons.phone_outlined, keyboardType: TextInputType.phone, validator: (v) => v!.trim().isEmpty ? "Phone required" : null),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _dobController,
                  readOnly: true,
                  onTap: () => _selectDate(context),
                  decoration: InputDecoration(
                    labelText: "Date of Birth (Optional)",
                    prefixIcon: Icon(Icons.calendar_month_outlined, color: Colors.grey[500]),
                    fillColor: Colors.white, filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  initialValue: widget.currentEmail,
                  readOnly: true,
                  style: TextStyle(color: Colors.grey[600]),
                  decoration: InputDecoration(
                    labelText: "Email Address (Cannot be changed)",
                    prefixIcon: Icon(Icons.email_outlined, color: Colors.grey[400]),
                    fillColor: Colors.grey[200], filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity, height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _updateProfile,
                    style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                    child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("Save Changes", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String label, required IconData icon, TextInputType keyboardType = TextInputType.text, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller, keyboardType: keyboardType, validator: validator,
      decoration: InputDecoration(
        labelText: label, prefixIcon: Icon(icon, color: Colors.grey[500]),
        fillColor: Colors.white, filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }
}