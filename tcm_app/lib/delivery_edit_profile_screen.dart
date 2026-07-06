import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class DeliveryEditProfileScreen extends StatefulWidget {
  final String currentName;
  final String currentPhone;
  final String currentEmail;
  final String currentVehiclePlateNum;
  final String currentDrivingLicense;
  final String? currentPhotoURL;

  const DeliveryEditProfileScreen({
    super.key,
    required this.currentName,
    required this.currentPhone,
    required this.currentEmail,
    required this.currentVehiclePlateNum,
    required this.currentDrivingLicense,
    this.currentPhotoURL,
  });

  @override
  State<DeliveryEditProfileScreen> createState() => _DeliveryEditProfileScreenState();
}

class _DeliveryEditProfileScreenState extends State<DeliveryEditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _vehiclePlateController;
  late TextEditingController _drivingLicenseController;

  bool _isLoading = false;
  File? _pickedImage;

  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color bgGray = const Color(0xFFF4F6F8);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
    _phoneController = TextEditingController(text: widget.currentPhone);
    _vehiclePlateController = TextEditingController(text: widget.currentVehiclePlateNum);
    _drivingLicenseController = TextEditingController(text: widget.currentDrivingLicense);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _vehiclePlateController.dispose();
    _drivingLicenseController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      setState(() => _pickedImage = File(picked.path));
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

      WriteBatch batch = FirebaseFirestore.instance.batch();
      batch.update(FirebaseFirestore.instance.collection('User').doc(uid), {
        'username': _nameController.text.trim(),
        'userPhoneNum': _phoneController.text.trim(),
        'photoURL': photoURL,
      });
      batch.update(FirebaseFirestore.instance.collection('DeliveryMan').doc(uid), {
        'vehiclePlateNum': _vehiclePlateController.text.trim().toUpperCase(),
        'drivingLicense': _drivingLicenseController.text.trim(),
      });
      await batch.commit();

      if (!mounted) return;
      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Profile updated!'), backgroundColor: primaryGreen));
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
                              ? Icon(Icons.motorcycle, size: 48, color: Colors.grey[400])
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
                _buildTextField(controller: _phoneController, label: "Phone Number", icon: Icons.phone_outlined, keyboardType: TextInputType.phone, validator: (v) => v!.trim().isEmpty ? "Phone required" : null),
                const SizedBox(height: 20),
                _buildTextField(controller: _vehiclePlateController, label: "Vehicle Plate Number", icon: Icons.motorcycle_outlined, validator: (v) => v!.trim().isEmpty ? "Vehicle plate required" : null),
                const SizedBox(height: 20),
                _buildTextField(controller: _drivingLicenseController, label: "Driving License ID", icon: Icons.badge_outlined, validator: (v) => v!.trim().isEmpty ? "Driving license required" : null),
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
