import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'notification_service.dart';

class ClinicAppointmentScreen extends StatefulWidget {
  final Map<String, dynamic> doctor; 

  ClinicAppointmentScreen({required this.doctor});

  @override
  _ClinicAppointmentScreenState createState() => _ClinicAppointmentScreenState();
}

class _ClinicAppointmentScreenState extends State<ClinicAppointmentScreen> {
  final Color primaryGreen = const Color(0xFF2E7D32);
  final TextEditingController _remarkController = TextEditingController();

  DateTime? _selectedDate;
  List<Map<String, dynamic>> _timeSlots = [];
  String _selectedTimeSlot = "";

  List<String> _workingDays = [];
  // dayOfWeek -> {startTime, endTime}; fetched once at init so we don't re-query Schedule every time a date is picked
  Map<String, Map<String, String>> _scheduleByDay = {};
  // Dates in the currently viewed month with zero available slots, formatted 'yyyy-MM-dd'
  Set<String> _fullyBookedDates = {};

  // Live data: other patients can book at any time and the doctor can add block times at any time,
  // so we use streams instead of a one-off get() to keep this screen's data from going stale while it's open.
  StreamSubscription<QuerySnapshot>? _appointmentSubscription;
  StreamSubscription<QuerySnapshot>? _blockTimeSubscription;
  List<Map<String, dynamic>> _allAppointments = [];
  List<Map<String, dynamic>> _allBlockTimes = [];
  DateTime _viewedMonth = DateTime.now();

  bool _isInitializing = true;
  bool _isLoadingSlots = false;
  bool _isConfirming = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void dispose() {
    _appointmentSubscription?.cancel();
    _blockTimeSubscription?.cancel();
    _remarkController.dispose();
    super.dispose();
  }

  // Initialize: fetch the doctor's working days -> auto-select the nearest available day -> subscribe to live appointment/block-time data
  Future<void> _initializeApp() async {
    await _fetchWorkingDays();

    // Find the doctor's nearest working day within the next 90 days
    DateTime initial = DateTime.now();
    if (_workingDays.isNotEmpty) {
      for (int i = 0; i < 90; i++) {
        DateTime check = DateTime.now().add(Duration(days: i));
        if (_workingDays.contains(DateFormat('EEEE').format(check))) {
          initial = check;
          break;
        }
      }
    }

    _selectedDate = initial;
    _viewedMonth = initial;
    _listenToLiveBookingData();
  }

  // Live-listen to this doctor's Appointment + BlockTime; recompute available slots whenever either changes
  void _listenToLiveBookingData() {
    String adminID = widget.doctor['adminID'];

    _appointmentSubscription = FirebaseFirestore.instance
        .collection('Appointment')
        .where('adminID', isEqualTo: adminID)
        .snapshots()
        .listen((snapshot) {
      _allAppointments = snapshot.docs.map((d) => d.data()).toList();
      _recomputeAvailability();
    }, onError: (e) => debugPrint("Appointment stream error: $e"));

    _blockTimeSubscription = FirebaseFirestore.instance
        .collection('BlockTime')
        .where('adminID', isEqualTo: adminID)
        .snapshots()
        .listen((snapshot) {
      _allBlockTimes = snapshot.docs.map((d) => d.data()).toList();
      _recomputeAvailability();
    }, onError: (e) => debugPrint("BlockTime stream error: $e"));
  }

  void _recomputeAvailability() {
    if (!mounted) return;
    _computeFullyBookedDatesForMonth(_viewedMonth);
    if (_selectedDate != null) _generateTimeSlotsForSelectedDate();
    if (_isInitializing) setState(() => _isInitializing = false);
  }

  // Query the Schedule collection for the doctor's working days, and cache each day's start/end time along the way
  Future<void> _fetchWorkingDays() async {
    try {
      var snap = await FirebaseFirestore.instance.collection('Schedule')
          .where('adminID', isEqualTo: widget.doctor['adminID'])
          .get();

      _workingDays = snap.docs.map((doc) => doc['dayOfWeek'] as String).toList();
      _scheduleByDay = {
        for (var doc in snap.docs)
          doc['dayOfWeek'] as String: {
            'startTime': doc['startTime'] as String,
            'endTime': doc['endTime'] as String,
          }
      };
    } catch (e) {
      debugPrint("Fetch working days error: $e");
    }
  }

  // Compute which dates in the currently displayed month are fully booked (so the calendar can gray them out).
  // Uses the live-streamed _allAppointments / _allBlockTimes data — no extra Firestore query needed.
  void _computeFullyBookedDatesForMonth(DateTime month) {
    _viewedMonth = month;
    if (_workingDays.isEmpty) return;

    DateTime today = DateTime.now();
    DateTime firstSelectable = DateTime(today.year, today.month, today.day);
    DateTime lastSelectable = firstSelectable.add(const Duration(days: 90));

    DateTime monthStart = DateTime(month.year, month.month, 1);
    DateTime monthEnd = DateTime(month.year, month.month + 1, 0);

    DateTime rangeFrom = monthStart.isBefore(firstSelectable) ? firstSelectable : monthStart;
    DateTime rangeTo = monthEnd.isAfter(lastSelectable) ? lastSelectable : monthEnd;

    if (rangeFrom.isAfter(rangeTo)) {
      if (mounted) setState(() => _fullyBookedDates = {});
      return;
    }

    String fromStr = DateFormat('yyyy-MM-dd').format(rangeFrom);
    String toStr = DateFormat('yyyy-MM-dd').format(rangeTo);

    Map<String, List<String>> bookedTimesByDate = {};
    for (var d in _allAppointments) {
      if ((d['status'] ?? 'Upcoming') == 'Cancelled') continue; // freed-up slot — don't count it as booked
      String date = d['appointmentDate'];
      if (date.compareTo(fromStr) < 0 || date.compareTo(toStr) > 0) continue;
      bookedTimesByDate.putIfAbsent(date, () => []).add(d['appointmentTime']);
    }

    DateTime now = DateTime.now();
    String todayStr = DateFormat('yyyy-MM-dd').format(now);
    int nowMin = now.hour * 60 + now.minute;

    Set<String> fullyBooked = {};

    for (DateTime d = rangeFrom; !d.isAfter(rangeTo); d = d.add(const Duration(days: 1))) {
      String dayOfWeek = DateFormat('EEEE').format(d);
      var daySchedule = _scheduleByDay[dayOfWeek];
      if (daySchedule == null) continue; // No schedule for this day — the calendar already grays it out

      String dateString = DateFormat('yyyy-MM-dd').format(d);
      int startMin = _timeToMinutes(daySchedule['startTime']!);
      int endMin = _timeToMinutes(daySchedule['endTime']!);
      bool isToday = dateString == todayStr;

      List<Map<String, dynamic>> activeBlocks = [];
      for (var b in _allBlockTimes) {
        bool isRecurring = b['isRecurring'] ?? false;
        if ((isRecurring && b['dayOfWeek'] == dayOfWeek) ||
            (!isRecurring && b['specificDate'] == dateString)) {
          activeBlocks.add(b);
        }
      }

      List<String> bookedTimes = bookedTimesByDate[dateString] ?? [];

      bool hasFreeSlot = false;
      for (int time = startMin; time + 30 <= endMin; time += 30) {
        int slotStart = time;
        int slotEnd = time + 30;
        String slotLabel = _minutesToAmPm(slotStart);

        bool isBlocked = activeBlocks.any((block) {
          int bStart = _timeToMinutes(block['startTime']);
          int bEnd = _timeToMinutes(block['endTime']);
          return (slotStart < bEnd && slotEnd > bStart);
        });
        bool isAlreadyBooked = bookedTimes.contains(slotLabel);
        bool isPast = isToday && slotStart <= nowMin;

        if (!isBlocked && !isAlreadyBooked && !isPast) {
          hasFreeSlot = true;
          break;
        }
      }

      if (!hasFreeSlot) fullyBooked.add(dateString);
    }

    if (mounted) setState(() => _fullyBookedDates = fullyBooked);
  }

  // Generate available time slots — computed from the live _allAppointments / _allBlockTimes data, no extra Firestore query
  void _generateTimeSlotsForSelectedDate() {
    if (!mounted) return;
    setState(() {
      _isLoadingSlots = true;
      _timeSlots.clear();
      _selectedTimeSlot = "";
    });

    String dayOfWeek = DateFormat('EEEE').format(_selectedDate!);
    String dateString = DateFormat('yyyy-MM-dd').format(_selectedDate!);

    // 1. Get the regular schedule (reuses data fetched at init — no need to query Schedule again)
    var daySchedule = _scheduleByDay[dayOfWeek];
    if (daySchedule == null) {
      if (mounted) setState(() => _isLoadingSlots = false);
      return;
    }
    String schedStart = daySchedule['startTime']!;
    String schedEnd = daySchedule['endTime']!;

    // 2. Block times (leave, meetings, other exceptions)
    List<Map<String, dynamic>> activeBlocks = [];
    for (var b in _allBlockTimes) {
      bool isRecurring = b['isRecurring'] ?? false;
      if ((isRecurring && b['dayOfWeek'] == dayOfWeek) ||
          (!isRecurring && b['specificDate'] == dateString)) {
        activeBlocks.add(b);
      }
    }

    // 3. Times already booked by other patients (cancelled ones free up the slot again)
    List<String> bookedTimes = _allAppointments
        .where((d) => d['appointmentDate'] == dateString && (d['status'] ?? 'Upcoming') != 'Cancelled')
        .map((d) => d['appointmentTime'] as String)
        .toList();

    // 4. Slice into time slots (30-minute intervals)
    int startMin = _timeToMinutes(schedStart);
    int endMin = _timeToMinutes(schedEnd);
    int interval = 30;

    // If today is selected, also lock out time slots that have already passed
    DateTime now = DateTime.now();
    bool isToday = DateFormat('yyyy-MM-dd').format(now) == dateString;
    int nowMin = now.hour * 60 + now.minute;

    List<Map<String, dynamic>> generatedSlots = [];

    for (int time = startMin; time + interval <= endMin; time += interval) {
      int slotStart = time;
      int slotEnd = time + interval;
      String slotLabel = _minutesToAmPm(slotStart);

      bool isBlocked = activeBlocks.any((block) {
        int bStart = _timeToMinutes(block['startTime']);
        int bEnd = _timeToMinutes(block['endTime']);
        return (slotStart < bEnd && slotEnd > bStart);
      });

      bool isAlreadyBooked = bookedTimes.contains(slotLabel);

      bool isPast = isToday && slotStart <= nowMin;

      generatedSlots.add({
        "time": slotLabel,
        "isBooked": isBlocked || isAlreadyBooked || isPast,
      });
    }

    if (mounted) {
      setState(() {
        _timeSlots = generatedSlots;
        _isLoadingSlots = false;
      });
    }
  }

  int _timeToMinutes(String timeStr) {
    List<String> parts = timeStr.split(':');
    if (parts.length != 2) return 0;
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  String _minutesToAmPm(int minutes) {
    int h = minutes ~/ 60;
    int m = minutes % 60;
    String ampm = h >= 12 ? "PM" : "AM";
    int displayH = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    String mm = m.toString().padLeft(2, '0');
    String hh = displayH.toString().padLeft(2, '0');
    return "$hh:$mm $ampm";
  }

  Future<void> _confirmBooking() async {
    setState(() => _isConfirming = true);
    try {
      String customerId = FirebaseAuth.instance.currentUser?.uid ?? "TEST_PATIENT_01";
      String dateString = DateFormat('yyyy-MM-dd').format(_selectedDate!);

      // One appointment per patient per day, across any doctor — cancelled ones don't count
      QuerySnapshot sameDayAppointments = await FirebaseFirestore.instance
          .collection('Appointment')
          .where('customerID', isEqualTo: customerId)
          .where('appointmentDate', isEqualTo: dateString)
          .get();

      bool alreadyBookedThatDay = sameDayAppointments.docs.any((d) {
        final status = (d.data() as Map<String, dynamic>)['status'] ?? 'Upcoming';
        return status != 'Cancelled';
      });

      // Not a hard block — just a confirmation to catch accidental double-booking from a stray tap
      if (alreadyBookedThatDay) {
        if (!mounted) return;
        bool? proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Already Have a Booking'),
            content: const Text('You already have an appointment on this date. Are you sure you want to book another one?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Book Anyway', style: TextStyle(color: primaryGreen, fontWeight: FontWeight.bold))),
            ],
          ),
        );

        if (proceed != true) {
          if (mounted) setState(() => _isConfirming = false);
          return;
        }
      }

      DocumentReference apptRef = FirebaseFirestore.instance.collection('Appointment').doc();
      
      await apptRef.set({
        'appointmentID': apptRef.id,
        'customerID': customerId,
        'adminID': widget.doctor['adminID'],
        'appointmentDate': dateString,
        'appointmentTime': _selectedTimeSlot,
        'remark': _remarkController.text.trim(),
        'status': 'Upcoming',
        'createdAt': FieldValue.serverTimestamp(),
      });

      String patientName = 'A patient';
      try {
        DocumentSnapshot patientSnap = await FirebaseFirestore.instance.collection('User').doc(customerId).get();
        if (patientSnap.exists) {
          patientName = (patientSnap.data() as Map<String, dynamic>)['username'] ?? patientName;
        }
      } catch (_) {}

      NotificationService.instance.send(
        uids: [widget.doctor['adminID']],
        title: 'New Appointment Booked',
        body: '$patientName booked an appointment on $dateString at $_selectedTimeSlot.',
        data: {'appointmentId': apptRef.id},
      );

      _showSuccessDialog();

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to book: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1F2937)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text("Booking with ${widget.doctor['name']}", style: const TextStyle(color: Color(0xFF1F2937), fontSize: 16)),
      ),
      body: _isInitializing 
        ? Center(child: CircularProgressIndicator(color: primaryGreen))
        : Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDoctorMiniCard(),
                      const SizedBox(height: 32),

                      const Text("Select Date", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      _buildCalendarSelector(),

                      const SizedBox(height: 32),

                      const Text("Select Time", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      _isLoadingSlots 
                          ? Center(child: CircularProgressIndicator(color: primaryGreen))
                          : _buildTimeGrid(),

                      const SizedBox(height: 32),

                      const Text("Remarks / Symptoms", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _remarkController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: "Describe your symptoms (e.g. back pain, headache...)",
                          fillColor: Colors.white,
                          filled: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              _buildConfirmButton(),
            ],
          ),
    );
  }

  Widget _buildDoctorMiniCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: primaryGreen.withOpacity(0.1),
            radius: 24,
            backgroundImage: (widget.doctor['photoURL'] != null && (widget.doctor['photoURL'] as String).isNotEmpty)
                ? NetworkImage(widget.doctor['photoURL'])
                : null,
            child: (widget.doctor['photoURL'] == null || (widget.doctor['photoURL'] as String).isEmpty)
                ? Icon(widget.doctor['image'], color: primaryGreen, size: 24)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.doctor['name'], overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(widget.doctor['specialty'], overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ],
            ),
          )
        ],
      ),
    );
  }

  // Full calendar view — supports paging between months, with unavailable dates grayed out automatically
  Widget _buildCalendarSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Theme(
        data: ThemeData.light().copyWith(
          colorScheme: ColorScheme.light(
            primary: primaryGreen, 
            onPrimary: Colors.white, 
            onSurface: const Color(0xFF1F2937), 
          ),
        ),
        child: CalendarDatePicker(
          initialDate: _selectedDate ?? DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 90)), // Bookings open up to ~3 months ahead
          selectableDayPredicate: (DateTime date) {
            String dateString = DateFormat('yyyy-MM-dd').format(date);

            // Never lock out the date that's already selected/being viewed — if it becomes fully
            // booked while the picker is open, CalendarDatePicker's initialDate would otherwise
            // stop satisfying this predicate and crash with a failed assertion.
            if (_selectedDate != null && dateString == DateFormat('yyyy-MM-dd').format(_selectedDate!)) {
              return true;
            }

            if (_workingDays.isEmpty) return true;
            String dayOfWeek = DateFormat('EEEE').format(date);
            if (!_workingDays.contains(dayOfWeek)) return false;
            return !_fullyBookedDates.contains(dateString);
          },
          onDisplayedMonthChanged: (DateTime newMonth) {
            _computeFullyBookedDatesForMonth(newMonth);
          },
          onDateChanged: (DateTime newDate) {
            setState(() {
              _selectedDate = newDate;
            });
            _generateTimeSlotsForSelectedDate();
          },
        ),
      ),
    );
  }

  // 3-column grid of large, easy-to-tap 30-minute time slots
  Widget _buildTimeGrid() {
    if (_timeSlots.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(15)),
        child: const Text("Doctor is not available on this date. Please select another day.", 
          style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
      );
    }

    return GridView.builder(
      shrinkWrap: true, 
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.2,
        crossAxisSpacing: 12, 
        mainAxisSpacing: 12,  
      ),
      itemCount: _timeSlots.length,
      itemBuilder: (context, index) {
        var slot = _timeSlots[index];
        bool isBooked = slot["isBooked"];
        bool isSelected = _selectedTimeSlot == slot["time"];

        return GestureDetector(
          onTap: isBooked ? null : () => setState(() => _selectedTimeSlot = slot["time"]),
          child: Container(
            decoration: BoxDecoration(
              color: isBooked ? Colors.grey[200] : (isSelected ? primaryGreen : Colors.white),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSelected ? primaryGreen : Colors.transparent),
              boxShadow: isBooked || isSelected ? [] : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)], 
            ),
            alignment: Alignment.center,
            child: Text(
              slot["time"],
              style: TextStyle(
                fontSize: 14,
                color: isBooked ? Colors.grey[400] : (isSelected ? Colors.white : const Color(0xFF4B5563)),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                decoration: isBooked ? TextDecoration.lineThrough : null, 
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildConfirmButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: (_selectedTimeSlot.isEmpty || _isConfirming) ? null : () => _confirmBooking(),
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryGreen,
            disabledBackgroundColor: Colors.grey[300],
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            elevation: 0,
          ),
          child: _isConfirming 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text("Confirm Appointment", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      ),
    );
  }

  void _showSuccessDialog() {
    String formattedDate = DateFormat('MMM dd, yyyy').format(_selectedDate!);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Center(child: Icon(Icons.check_circle_rounded, color: primaryGreen, size: 60)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Booking Confirmed!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
              "Your appointment is set for\n$formattedDate at $_selectedTimeSlot.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], height: 1.5),
            ),
          ],
        ),
        actions: [
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.pop(context); 
                Navigator.pop(context); 
              },
              child: Text("Great!", style: TextStyle(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          )
        ],
      ),
    );
  }
}