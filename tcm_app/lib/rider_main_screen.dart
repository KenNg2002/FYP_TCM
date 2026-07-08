import 'package:flutter/material.dart';
import 'delivery_task_screen.dart';
import 'delivery_history_screen.dart';
import 'delivery_profile_screen.dart';

class RiderMainScreen extends StatefulWidget {
  @override
  _RiderMainScreenState createState() => _RiderMainScreenState();
}

class _RiderMainScreenState extends State<RiderMainScreen> {
  int _currentIndex = 0;
  final Color primaryGreen = const Color(0xFF2E7D32);
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      DeliveryTaskScreen(),
      DeliveryHistoryScreen(),
      DeliveryProfileScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BottomNavigationBar(
            selectedItemColor: primaryGreen,
            unselectedItemColor: Colors.grey[400],
            backgroundColor: Colors.white,
            currentIndex: _currentIndex,
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            onTap: (index) {
              setState(() { _currentIndex = index; });
            },
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.motorcycle_rounded), label: 'Tasks'),
              BottomNavigationBarItem(icon: Icon(Icons.receipt_long_rounded), label: 'History'),
              BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
            ],
          ),
        ),
      ),
    );
  }
}