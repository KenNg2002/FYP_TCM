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

  // 🚀 核心升级：跨表查询 (Administrator + User)
  Future<void> _fetchDoctors() async {
    try {
      // 第一步：从 Administrator 表中找出所有角色为 Doctor 的文档
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('Administrator')
          .where('adminRole', isEqualTo: 'Doctor')
          .get();

      // 第二步：遍历这些 Doctor，拿着他们的 ID 去 User 表找真实姓名
      List<Future<Map<String, dynamic>>> fetchPromises = snapshot.docs.map((doc) async {
        var adminData = doc.data() as Map<String, dynamic>;
        
        // 假设 User 表的 Document ID 和 Administrator 表是一致的
        // 如果你的 ID 存在字段里，可以写成: String uid = adminData['adminID'];
        String uid = adminData['adminID'] ?? doc.id; 

        // 去 User 表拿数据
        DocumentSnapshot userSnap = await FirebaseFirestore.instance.collection('User').doc(uid).get();

        String doctorName = "Unknown Doctor";
        
        if (userSnap.exists) {
          var userData = userSnap.data() as Map<String, dynamic>;
          // 💡 成功从 User 表中读取 username！
          doctorName = userData['username'] ?? "Unknown Doctor";
        } else {
          // 如果 User 表里找不到，提供一个后备方案 (Fallback)
          doctorName = adminData['adminName'] ?? "Unknown Doctor";
        }

        // 组装最终的数据给 UI 显示
        return {
          "adminID": uid,
          "name": doctorName, // 👈 这里现在是 User 表里的 username
          "specialty": adminData['department'] ?? "TCM Department", // 👈 Administrator 表的 department
          "description": adminData['description'] ?? "No description available.", // 👈 Administrator 表的 description
          "image": Icons.person_4_rounded,
        };
      }).toList();

      // 并发执行所有查询，速度极快
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
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 30,
                                backgroundColor: primaryGreen.withOpacity(0.1),
                                child: Icon(doctor["image"], color: primaryGreen, size: 30),
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