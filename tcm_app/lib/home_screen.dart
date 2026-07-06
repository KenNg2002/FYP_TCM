import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'ai_scanner_screen.dart';
import 'herbal_store_screen.dart';
import 'my_appointment_screen.dart';
import 'my_order_screen.dart';
import 'user_profile_screen.dart';
import 'doctor_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  // Brand color definitions
  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color bgGray = const Color(0xFFF4F6F8);

  String _userName = "Guest";
  String? _photoURL;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance.collection('User').doc(currentUser.uid).get();
      if (userDoc.exists && mounted) {
        setState(() {
          _userName = userDoc.data()?['username'] ?? "Guest";
          _photoURL = userDoc.data()?['photoURL'];
        });
      }
    } catch (e) {
      // Keep default greeting if the fetch fails; not critical to block the home view.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGray,
      body: SafeArea(
        // IndexedStack preserves the state of the pages when switching tabs
        child: IndexedStack(
          index: _currentIndex,
          children: [
            _buildHomeView(),        // Index 0: Main Dashboard
            HerbalStoreScreen(),     // Index 1: Store
            DoctorListScreen(),      // Index 2: Clinic
            UserProfileScreen(),     // Index 3: Profile
          ],
        ),
      ),
      // Modern Bottom Navigation Bar
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              blurRadius: 10,
              spreadRadius: 2,
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            backgroundColor: Colors.white,
            selectedItemColor: primaryGreen,
            unselectedItemColor: Colors.grey,
            type: BottomNavigationBarType.fixed,
            showUnselectedLabels: true,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: "Home"),
              BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_rounded), label: "Store"),
              BottomNavigationBarItem(icon: Icon(Icons.local_hospital_rounded), label: "Doctor"),
              BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: "Profile"),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // VIEW 1: MAIN DASHBOARD (Home)
  // ==========================================
  Widget _buildHomeView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Greeting
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Hello, $_userName",
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF212121)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "How are you feeling today?",
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => setState(() => _currentIndex = 3),
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: primaryGreen.withOpacity(0.2),
                  backgroundImage: (_photoURL != null && _photoURL!.isNotEmpty) ? NetworkImage(_photoURL!) : null,
                  child: (_photoURL == null || _photoURL!.isEmpty) ? Icon(Icons.person, color: primaryGreen) : null,
                ),
              )
            ],
          ),
          const SizedBox(height: 30),

          // 2. HERO FEATURE: AI Tongue Scanner Banner
          GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => AIScannerScreen()));
            },
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryGreen, const Color(0xFF4CAF50)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: primaryGreen.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          "AI Tongue Diagnosis",
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Scan your tongue to discover your body constitution & get herbal recommendations.",
                          style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 36),
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),

          // 3. Section Title
          const Text(
            "Quick Actions",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF212121)),
          ),
          const SizedBox(height: 16),

          // 4. Quick Action Cards (Your implementation)
          Row(
            children: [
              _buildSmallActionCard(
                title: "My Orders",
                icon: Icons.inventory_2_rounded,
                color: Colors.blueAccent,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => MyOrdersScreen()));
                },
              ),
              const SizedBox(width: 16),
              _buildSmallActionCard(
                title: "Appointments",
                icon: Icons.event_available_rounded,
                color: Colors.orangeAccent,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const MyAppointmentsScreen()));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // REUSABLE WIDGETS
  // ==========================================
  Widget _buildSmallActionCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF212121)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}