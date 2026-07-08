import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';
import 'delivery_edit_profile_screen.dart';

class DeliveryProfileScreen extends StatefulWidget {
  @override
  _DeliveryProfileScreenState createState() => _DeliveryProfileScreenState();
}

class _DeliveryProfileScreenState extends State<DeliveryProfileScreen> {
  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color bgGray = const Color(0xFFF4F6F8);
  
  String _riderName = "Loading...";
  String _riderId = "";
  
  // Fields from the User collection
  String _userEmail = "Loading...";
  String _userPhoneNum = "Loading...";

  // Fields from the DeliveryMan collection
  String _drivingLicense = "Loading...";
  String _vehiclePlateNum = "Loading...";
  String? _photoURL;

  @override
  void initState() {
    super.initState();
    _fetchProfileData();
  }

  Future<void> _fetchProfileData() async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        var userDoc = await FirebaseFirestore.instance.collection('User').doc(currentUser.uid).get();
        var deliveryDoc = await FirebaseFirestore.instance.collection('DeliveryMan').doc(currentUser.uid).get();

        if (mounted) {
          setState(() {
            _riderName = userDoc.data()?['username'] ?? "Unknown Rider";
            _userEmail = userDoc.data()?['userEmail'] ?? "No Email provided";
            _userPhoneNum = userDoc.data()?['userPhoneNum'] ?? "No Phone provided";

            _drivingLicense = deliveryDoc.data()?['drivingLicense'] ?? "No License Record";
            _vehiclePlateNum = deliveryDoc.data()?['vehiclePlateNum'] ?? "No Vehicle Record";
            _photoURL = userDoc.data()?['photoURL'];

            // Short display ID derived from the UID
            _riderId = currentUser.uid.length >= 8 ? currentUser.uid.substring(0, 8).toUpperCase() : "00000000";
          });
        }
      }
    } catch (e) {
      print("Fetch Profile Error: $e");
    }
  }

  void _handleLogout() async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushAndRemoveUntil(
      context, 
      MaterialPageRoute(builder: (context) => const LoginScreen()), 
      (route) => false
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGray,
      appBar: AppBar(
        backgroundColor: primaryGreen, 
        elevation: 0, 
        centerTitle: true, 
        automaticallyImplyLeading: false, 
        title: const Text("Rider Profile", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            Container(
              width: double.infinity, 
              padding: const EdgeInsets.only(bottom: 30, top: 20),
              decoration: BoxDecoration(
                color: primaryGreen, 
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)), 
                boxShadow: [BoxShadow(color: primaryGreen.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))]
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.white,
                    backgroundImage: (_photoURL != null && _photoURL!.isNotEmpty) ? NetworkImage(_photoURL!) : null,
                    child: (_photoURL == null || _photoURL!.isEmpty) ? const Icon(Icons.motorcycle, size: 50, color: Colors.grey) : null,
                  ),
                  const SizedBox(height: 16),
                  Text(_riderName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), 
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)), 
                    child: Text("ID: RDR-$_riderId", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1))
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // Static demo stat cards - not wired to real data yet
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _buildStatCard("Status", "Active", Icons.verified_user_rounded),
                  const SizedBox(width: 16),
                  _buildStatCard("Rating", "4.9⭐", Icons.star_rounded),
                ],
              ),
            ),
            const SizedBox(height: 30),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Account Information", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4B5563))),
                  const SizedBox(height: 12),

                  _buildProfileMenu(Icons.email_rounded, "Email Address", _userEmail),
                  _buildProfileMenu(Icons.phone_android_rounded, "Phone Number", _userPhoneNum),
                  _buildProfileMenu(Icons.badge_rounded, "Driving License", _drivingLicense),
                  _buildProfileMenu(Icons.motorcycle_rounded, "Vehicle Plate", _vehiclePlateNum),

                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final bool? isUpdated = await Navigator.push(context, MaterialPageRoute(
                          builder: (context) => DeliveryEditProfileScreen(
                            currentName: _riderName,
                            currentPhone: _userPhoneNum,
                            currentEmail: _userEmail,
                            currentVehiclePlateNum: _vehiclePlateNum,
                            currentDrivingLicense: _drivingLicense,
                            currentPhotoURL: _photoURL,
                          ),
                        ));
                        if (isUpdated == true) _fetchProfileData();
                      },
                      icon: Icon(Icons.edit_rounded, color: primaryGreen),
                      label: Text("Edit Profile", style: TextStyle(color: primaryGreen, fontSize: 16, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: primaryGreen, width: 2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),
                  
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _handleLogout,
                      icon: const Icon(Icons.logout_rounded, color: Colors.red),
                      label: const Text("Log Out", style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16), 
                        side: BorderSide(color: Colors.red[300]!, width: 2), 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20), 
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(20), 
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]
        ), 
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, 
          children: [
            Icon(icon, color: primaryGreen, size: 28), 
            const SizedBox(height: 12), 
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1F2937))), 
            Text(title, style: TextStyle(color: Colors.grey[500], fontSize: 13, fontWeight: FontWeight.bold))
          ]
        )
      )
    );
  }

  Widget _buildProfileMenu(IconData icon, String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12), 
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(15), 
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5)]
      ), 
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), 
        leading: Container(
          padding: const EdgeInsets.all(8), 
          decoration: BoxDecoration(color: primaryGreen.withOpacity(0.1), shape: BoxShape.circle), 
          child: Icon(icon, color: primaryGreen)
        ), 
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), 
        subtitle: subtitle.isNotEmpty 
            ? Text(subtitle, style: TextStyle(color: Colors.grey[700], fontSize: 13, fontWeight: FontWeight.w500)) 
            : null, 
      )
    );
  }
}