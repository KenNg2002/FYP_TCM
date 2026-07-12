import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'notification_service.dart';

class MyAppointmentsScreen extends StatefulWidget {
  const MyAppointmentsScreen({super.key});

  @override
  State<MyAppointmentsScreen> createState() => _MyAppointmentsScreenState();
}

class _MyAppointmentsScreenState extends State<MyAppointmentsScreen> {
  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color bgGray = const Color(0xFFF4F6F8);

  final Map<String, String> _doctorNameCache = {};

  // Look up doctor name by adminID: check the User collection first, fall back to Administrator
  Future<String> _getDoctorName(String adminID) async {
    if (adminID.isEmpty) return "Unknown Doctor";
    if (_doctorNameCache.containsKey(adminID)) return _doctorNameCache[adminID]!;

    String name = "Unknown Doctor";
    try {
      var userSnap = await FirebaseFirestore.instance.collection('User').doc(adminID).get();
      if (userSnap.exists) {
        name = (userSnap.data() as Map<String, dynamic>)['username'] ?? name;
      } else {
        var adminSnap = await FirebaseFirestore.instance.collection('Administrator').doc(adminID).get();
        if (adminSnap.exists) {
          name = (adminSnap.data() as Map<String, dynamic>)['adminName'] ?? name;
        }
      }
    } catch (e) {
      debugPrint("Fetch doctor name error: $e");
    }

    _doctorNameCache[adminID] = name;
    return name;
  }

  Future<void> _cancelAppointment(String appointmentId, Map<String, dynamic> apt) async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Cancel Appointment?"),
        content: const Text("This will free up the time slot for other patients."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes, Cancel", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance.collection('Appointment').doc(appointmentId).update({'status': 'Cancelled'});

      final adminID = apt['adminID'] ?? '';
      if (adminID.isNotEmpty) {
        NotificationService.instance.send(
          uids: [adminID],
          title: 'Appointment Cancelled',
          body: 'A patient cancelled their appointment on ${apt['appointmentDate']} at ${apt['appointmentTime']}.',
          data: {'appointmentId': appointmentId},
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appointment cancelled.'), backgroundColor: Colors.grey));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to cancel: $e'), backgroundColor: Colors.red));
      }
    }
  }

  int _timeToMinutes(String label) {
    try {
      var parts = label.split(' ');
      var hm = parts[0].split(':');
      int h = int.parse(hm[0]);
      int m = int.parse(hm[1]);
      bool isPm = parts[1].toUpperCase() == 'PM';
      if (isPm && h != 12) h += 12;
      if (!isPm && h == 12) h = 0;
      return h * 60 + m;
    } catch (_) {
      return 0;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Cancelled':
        return Colors.red;
      case 'Absent':
        return Colors.grey;
      case 'Overdue':
        return Colors.deepOrange;
      case 'Arrived':
        return Colors.purple;
      case 'Completed':
        return Colors.blueGrey;
      default: // Upcoming
        return primaryGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    String customerId = FirebaseAuth.instance.currentUser?.uid ?? "TEST_PATIENT_01";

    return Scaffold(
      backgroundColor: bgGray,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1F2937)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("My Appointments", style: TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('Appointment').where('customerID', isEqualTo: customerId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: primaryGreen));
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error loading appointments: ${snapshot.error}"));
          }

          var docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) return _buildEmptyState();

          docs.sort((a, b) {
            var aData = a.data() as Map<String, dynamic>;
            var bData = b.data() as Map<String, dynamic>;
            int dateCompare = (aData['appointmentDate'] ?? '').compareTo(bData['appointmentDate'] ?? '');
            if (dateCompare != 0) return dateCompare;
            return _timeToMinutes(aData['appointmentTime'] ?? '') - _timeToMinutes(bData['appointmentTime'] ?? '');
          });

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var doc = docs[index];
              var apt = doc.data() as Map<String, dynamic>;
              String status = apt['status'] ?? 'Upcoming';
              bool canCancel = status == 'Upcoming';
              String remark = (apt['remark'] ?? '').toString();
              String cancelReason = (apt['cancelReason'] ?? '').toString();

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.calendar_month_rounded, color: primaryGreen),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "${apt['appointmentDate']} • ${apt['appointmentTime']}",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                        Text(status, style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Divider(height: 30),
                    Text("Practitioner:", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                    FutureBuilder<String>(
                      future: _getDoctorName(apt['adminID'] ?? ''),
                      builder: (context, snap) => Text(
                        snap.data ?? "Loading...",
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (remark.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text("Your Remark:", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                      Text(remark, style: TextStyle(color: Colors.grey[700], fontSize: 14, fontStyle: FontStyle.italic)),
                    ],
                    if (status == 'Cancelled' && cancelReason.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(10)),
                        child: Text(
                          "Cancelled by clinic: $cancelReason",
                          style: TextStyle(color: Colors.red[700], fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                    if (canCancel) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => _cancelAppointment(doc.id, apt),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("Cancel Appointment", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
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
          Icon(Icons.event_busy_rounded, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text("No Appointments Yet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800])),
          const SizedBox(height: 8),
          Text("Book an appointment with a practitioner to see it here.", style: TextStyle(color: Colors.grey[500], fontSize: 14)),
        ],
      ),
    );
  }
}
