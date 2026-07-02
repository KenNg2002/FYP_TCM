import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _isPasswordVisible = false;
  // bool _agreeToTerms = false; // 暂时注释掉
  bool _isLoading = false;

  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color bgGray = const Color(0xFFF4F6F8);

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    // 🔒 安全升级：触发所有的强验证规则
    if (!_formKey.currentState!.validate()) return;

    // 暂时注释掉 T&C 验证
    /*
    if (!_agreeToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You must agree to the Terms and Conditions to proceed.'), backgroundColor: Colors.orangeAccent));
      return;
    }
    */

    setState(() => _isLoading = true);
    
    try {
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(), // Auth 会自动加密密码
      );

      String uid = userCredential.user!.uid;

      await FirebaseFirestore.instance.collection('User').doc(uid).set({
        'userID': uid,
        'username': _nameController.text.trim(),
        'userEmail': _emailController.text.trim(),
        'userPhoneNum': _phoneController.text.trim(), 
        'userRole': 'Customer', 
        'userRegistedDate': FieldValue.serverTimestamp(),
        'accountStatus': 'Active',
      });

      if (!mounted) return;
      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Account successfully created! Please login.'), backgroundColor: primaryGreen));
      Navigator.pop(context); 

    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      
      String errorMessage = 'An error occurred. Please try again.';
      if (e.code == 'weak-password') {
        errorMessage = 'The password provided is too weak.';
      } else if (e.code == 'email-already-in-use') {
        errorMessage = 'An account already exists for that email.';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'The email address is badly formatted.';
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage), backgroundColor: Colors.redAccent));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unexpected error: $e'), backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF212121)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 10.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Create Account", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF212121))),
                const SizedBox(height: 8),
                Text("Join us to balance your lifestyle", style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                const SizedBox(height: 30),

                // 🔒 验证：名字不可为空或全空格
                _buildFormField(
                  controller: _nameController,
                  label: "Full Name",
                  icon: Icons.person_outline,
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Please enter your full name' : null,
                ),
                const SizedBox(height: 20),

                // 🔒 验证：标准邮箱格式
                _buildFormField(
                  controller: _emailController,
                  label: "Email Address",
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Please enter your email';
                    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                    if (!emailRegex.hasMatch(value.trim())) return 'Please enter a valid email address';
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                
                // 🔒 验证：手机号格式 (支持 +60 格式或普通数字格式)
                _buildFormField(
                  controller: _phoneController,
                  label: "Phone Number",
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Please enter your phone number';
                    final phoneRegex = RegExp(r'^\+?[0-9]{9,15}$'); // 允许 9-15 位的数字，可选带 +
                    if (!phoneRegex.hasMatch(value.trim())) return 'Please enter a valid phone number (e.g. 0123456789)';
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // 🔒 验证：密码复杂性 (至少8位，包含字母和数字)
                _buildFormField(
                  controller: _passwordController,
                  label: "Password",
                  icon: Icons.lock_outline,
                  obscureText: !_isPasswordVisible,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please enter a password';
                    if (value.length < 8) return 'Password must be at least 8 characters long';
                    // 正则表达式：必须至少包含一个字母和一个数字
                    final passwordRegex = RegExp(r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d\S]{8,}$');
                    if (!passwordRegex.hasMatch(value)) return 'Password must contain at least one letter and one number';
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // 🔒 验证：确认密码必须一致
                _buildFormField(
                  controller: _confirmPasswordController,
                  label: "Confirm Password",
                  icon: Icons.lock_clock_outlined,
                  obscureText: !_isPasswordVisible,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please confirm your password';
                    if (value != _passwordController.text) return 'Passwords do not match';
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // T&C 暂时注释掉
                /*
                Row(
                  children: [
                    SizedBox(width: 24, height: 24, child: Checkbox(value: _agreeToTerms, activeColor: primaryGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)), onChanged: (value) => setState(() => _agreeToTerms = value ?? false))),
                    const SizedBox(width: 8),
                    Expanded(child: Text("I agree to the Terms of Service & Privacy Policy", style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500))),
                  ],
                ),
                */
                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleRegister,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : const Text("Sign Up", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      style: const TextStyle(fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: label,
        hintStyle: TextStyle(color: Colors.grey[400]),
        prefixIcon: Icon(icon, color: Colors.grey[500]),
        fillColor: bgGray,
        filled: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: primaryGreen, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.redAccent, width: 1)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.redAccent, width: 2)),
      ),
    );
  }
}