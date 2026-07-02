import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart'; 
import 'edit_profile_screen.dart';
import 'my_address_screen.dart';
import 'payment_method_screen.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color bgGray = const Color(0xFFF4F6F8);

  String _fullName = "Loading...";
  String _email = "Loading...";
  String _phoneNo = "";
  String _dob = "";
  
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('User').doc(currentUser.uid).get();
        DocumentSnapshot customerDoc = await FirebaseFirestore.instance.collection('Customer').doc(currentUser.uid).get();

        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          final custData = customerDoc.exists ? customerDoc.data() as Map<String, dynamic> : {};

          setState(() {
            _fullName = userData['username'] ?? "Valued Customer";
            _email = userData['userEmail'] ?? currentUser.email ?? "";
            _phoneNo = userData['userPhoneNum'] ?? "";
            _dob = custData['dateOfBirth'] ?? "";
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // ⚠️ 核心新增：企业级退出登录逻辑 (带防误触确认弹窗)
  Future<void> _handleLogout(BuildContext context) async {
    bool? confirmLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Logout", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to log out of your account?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Logout", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    // 如果用户点击了确认退出
    if (confirmLogout == true) {
      await FirebaseAuth.instance.signOut(); // 清除 Firebase 登录状态
      if (!mounted) return;
      
      // 清除整个路由栈 (防止按手机返回键又回到这个页面)，并跳转回 LoginScreen
      Navigator.pushAndRemoveUntil(
        context, 
        MaterialPageRoute(builder: (context) => const LoginScreen()), 
        (route) => false
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGray,
      appBar: AppBar(
        backgroundColor: primaryGreen, elevation: 0, centerTitle: true, automaticallyImplyLeading: false,
        title: const Text("My Profile", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading 
        ? Center(child: CircularProgressIndicator(color: primaryGreen))
        : SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                // Top Header
                Container(
                  width: double.infinity, padding: const EdgeInsets.only(bottom: 30, top: 10),
                  decoration: BoxDecoration(color: primaryGreen, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30))),
                  child: Column(
                    children: [
                      CircleAvatar(radius: 50, backgroundColor: Colors.white, child: Icon(Icons.person, size: 50, color: Colors.grey[500])),
                      const SizedBox(height: 16),
                      Text(_fullName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text(_email, style: const TextStyle(fontSize: 14, color: Colors.white70)),
                      if (_phoneNo.isNotEmpty) Text(_phoneNo, style: const TextStyle(fontSize: 14, color: Colors.white70)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // Menu List
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    children: [
                      _buildProfileMenu(Icons.person_outline, "Edit Profile", "Update your personal details", onTap: () async {
                        final bool? isUpdated = await Navigator.push(context, MaterialPageRoute(
                          builder: (context) => EditProfileScreen(
                            currentName: _fullName, currentPhone: _phoneNo, currentEmail: _email, currentDob: _dob,
                          ),
                        ));
                        if (isUpdated == true) { setState(() => _isLoading = true); _fetchUserData(); }
                      }),
                      
                      _buildProfileMenu(Icons.location_on_outlined, "My Addresses", "Manage delivery locations", onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const MyAddressScreen()));
                      }),
                      
                      _buildProfileMenu(Icons.payment_outlined, "Payment Methods", "Manage your credit cards & wallets", onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const PaymentMethodScreen()));
                      }),

                      const SizedBox(height: 20),

                      // ⚠️ 核心新增：专属的 Logout 按钮，视觉上使用红色警示
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.logout, color: Colors.white),
                          label: const Text("Logout", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            elevation: 0,
                          ),
                          onPressed: () => _handleLogout(context), // 绑定登出逻辑
                        ),
                      ),
                      const SizedBox(height: 40), // 底部留白
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildProfileMenu(IconData icon, String title, String subtitle, {VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: primaryGreen.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: primaryGreen),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[500])), 
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey), 
        onTap: onTap,
      ),
    );
  }
}