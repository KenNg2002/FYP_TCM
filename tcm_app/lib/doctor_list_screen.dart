import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'clinic_appointment_screen.dart';

class DoctorListScreen extends StatefulWidget {
  const DoctorListScreen({super.key});

  @override
  State<DoctorListScreen> createState() => _DoctorListScreenState();
}

class _DoctorListScreenState extends State<DoctorListScreen> {
  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color bgGray = const Color(0xFFF4F6F8);

  List<Map<String, dynamic>> _doctors = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDoctors();
  }

  // Joins across two collections: Administrator (role/department) + User (name/photo)
  Future<void> _fetchDoctors() async {
    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('Administrator')
          .where('adminRole', isEqualTo: 'Doctor')
          .get();

      // For each doctor, look up their real name in the User collection using their ID
      List<Future<Map<String, dynamic>>> fetchPromises = snapshot.docs.map((doc) async {
        var adminData = doc.data() as Map<String, dynamic>;

        String uid = adminData['adminID'] ?? doc.id;

        DocumentSnapshot userSnap = await FirebaseFirestore.instance.collection('User').doc(uid).get();

        String doctorName = "Unknown Doctor";
        String? photoURL;

        if (userSnap.exists) {
          var userData = userSnap.data() as Map<String, dynamic>;
          doctorName = userData['username'] ?? "Unknown Doctor";
          photoURL = userData['photoURL'];
        } else {
          doctorName = adminData['adminName'] ?? "Unknown Doctor";
        }

        return {
          "adminID": uid,
          "name": doctorName,
          "specialty": adminData['department'] ?? "TCM Department",
          "description": adminData['description'] ?? "No description available.",
          "image": Icons.person_4_rounded,
          "photoURL": photoURL,
        };
      }).toList();

      // Run all lookups concurrently for speed
      List<Map<String, dynamic>> loadedDoctors = await Future.wait(fetchPromises);

      if (mounted) {
        setState(() {
          _doctors = loadedDoctors;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching doctors: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showDoctorProfile(Map<String, dynamic> doctor) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Center(
              child: CircleAvatar(
                radius: 50,
                backgroundColor: primaryGreen.withOpacity(0.1),
                backgroundImage: (doctor["photoURL"] != null && (doctor["photoURL"] as String).isNotEmpty)
                    ? NetworkImage(doctor["photoURL"])
                    : null,
                child: (doctor["photoURL"] == null || (doctor["photoURL"] as String).isEmpty)
                    ? Icon(doctor["image"], color: primaryGreen, size: 50)
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(doctor["name"], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(doctor["specialty"], style: TextStyle(color: primaryGreen, fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 24),
            Text("ABOUT", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Text(doctor["description"], style: TextStyle(color: Colors.grey[700], fontSize: 14, height: 1.5)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGray,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text("Select Practitioner", style: TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryGreen))
          : _doctors.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  physics: const BouncingScrollPhysics(),
                  itemCount: _doctors.length,
                  itemBuilder: (context, index) {
                    var doctor = _doctors[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => _showDoctorProfile(doctor),
                            child: Row(
                            children: [
                              CircleAvatar(
                                radius: 30,
                                backgroundColor: primaryGreen.withOpacity(0.1),
                                backgroundImage: (doctor["photoURL"] != null && (doctor["photoURL"] as String).isNotEmpty)
                                    ? NetworkImage(doctor["photoURL"])
                                    : null,
                                child: (doctor["photoURL"] == null || (doctor["photoURL"] as String).isEmpty)
                                    ? Icon(doctor["image"], color: primaryGreen, size: 30)
                                    : null,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(doctor["name"], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                    Text(doctor["specialty"], style: TextStyle(color: primaryGreen, fontSize: 13, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            doctor["description"],
                            style: TextStyle(color: Colors.grey[600], fontSize: 13, height: 1.4),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => ClinicAppointmentScreen(doctor: doctor)),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryGreen,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: const Text("Book Appointment", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.medical_information_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text("No Doctors Available", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[800])),
          const SizedBox(height: 8),
          Text("Please check back later for available practitioners.", style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }
}