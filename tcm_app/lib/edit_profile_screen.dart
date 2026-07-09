import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class EditProfileScreen extends StatefulWidget {
  final String currentName;
  final String currentPhone;
  final String currentEmail;
  final String currentDob;
  final String? currentPhotoURL;

  const EditProfileScreen({
    super.key,
    required this.currentName,
    required this.currentPhone,
    required this.currentEmail,
    required this.currentDob,
    this.currentPhotoURL,
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
  File? _pickedImage;

  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color bgGray = const Color(0xFFF4F6F8);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
    _phoneController = TextEditingController(text: widget.currentPhone);
    _dobController = TextEditingController(text: widget.currentDob);
  }

  Future<void> _pickImage() async {
    final XFile? picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      setState(() => _pickedImage = File(picked.path));
    }
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

      String? photoURL = widget.currentPhotoURL;
      if (_pickedImage != null) {
        final storageRef = FirebaseStorage.instance.ref().child('profile_photos/$uid.jpg');
        await storageRef.putFile(_pickedImage!);
        photoURL = await storageRef.getDownloadURL();
      }

      await FirebaseFirestore.instance.collection('User').doc(uid).update({
        'username': _nameController.text.trim(),
        'userPhoneNum': _phoneController.text.trim(),
        'photoURL': photoURL,
      });

      await FirebaseFirestore.instance.collection('Customer').doc(uid).set({
        'customerID': uid, // Field name casing must match 'customerID' exactly (case-sensitive)
        'dateOfBirth': _dobController.text.trim(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Profile updated!'), backgroundColor: primaryGreen));

      // Returning true here triggers user_profile_screen's _fetchUserData() to reload
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
                Center(
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: bgGray,
                          backgroundImage: _pickedImage != null
                              ? FileImage(_pickedImage!)
                              : (widget.currentPhotoURL != null && widget.currentPhotoURL!.isNotEmpty)
                                  ? NetworkImage(widget.currentPhotoURL!) as ImageProvider
                                  : null,
                          child: (_pickedImage == null && (widget.currentPhotoURL == null || widget.currentPhotoURL!.isEmpty))
                              ? Icon(Icons.person, size: 48, color: Colors.grey[400])
                              : null,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: primaryGreen,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildTextField(controller: _nameController, label: "Full Name", icon: Icons.person_outline, validator: (v) => v!.trim().isEmpty ? "Name required" : null),
                const SizedBox(height: 20),
                _buildTextField(
                  controller: _phoneController,
                  label: "Phone Number",
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Phone required';
                    if (!RegExp(r'^\+?[0-9]{10,11}$').hasMatch(v.trim())) return 'Please enter a valid phone number (10-11 digits)';
                    return null;
                  },
                ),
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

  Widget _buildTextField({required TextEditingController controller, required String label, required IconData icon, TextInputType keyboardType = TextInputType.text, bool obscureText = false, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller, keyboardType: keyboardType, obscureText: obscureText, validator: validator,
      decoration: InputDecoration(
        labelText: label, prefixIcon: Icon(icon, color: Colors.grey[500]),
        fillColor: Colors.white, filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }
}
