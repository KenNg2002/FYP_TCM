import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class ClinicAppointmentScreen extends StatefulWidget {
  final Map<String, dynamic> doctor; 

  ClinicAppointmentScreen({required this.doctor});

  @override
  _ClinicAppointmentScreenState createState() => _ClinicAppointmentScreenState();
}

class _ClinicAppointmentScreenState extends State<ClinicAppointmentScreen> {
  final Color primaryGreen = const Color(0xFF2E7D32);
  final TextEditingController _remarkController = TextEditingController();

  // 日期与时间状态
  DateTime? _selectedDate;
  List<Map<String, dynamic>> _timeSlots = [];
  String _selectedTimeSlot = "";
  
  // 医生工作日预查列表
  List<String> _workingDays = [];
  // dayOfWeek -> {startTime, endTime}，初始化时一次抓好，避免每次选日期都重新查 Schedule
  Map<String, Map<String, String>> _scheduleByDay = {};
  // 当前日历显示月份里，整天都没名额的日期 ('yyyy-MM-dd')
  Set<String> _fullyBookedDates = {};

  // 🚀 实时数据：其他病人随时可能抢订，医生也可能随时新增 Block Time，
  // 用 Stream 而不是一次性 get()，这样这个页面开着的时候数据不会过期
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

  // 🚀 初始化应用：查医生工作日 -> 自动选中最近一天 -> 订阅实时预约/拦截时间数据
  Future<void> _initializeApp() async {
    await _fetchWorkingDays();

    // 自动寻找未来 90 天里，医生最近的第一个上班日
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

  // 实时监听这个医生的 Appointment + BlockTime，任何一边一有变化就重新计算可选时段
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

  // 查询 Schedule 表找出医生每周哪几天有排班，顺便把每天的上下班时间也缓存起来
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

  // 🚀 算出当前显示月份里，哪些日期整天都没有名额了 (用来在日历上灰掉)
  // 数据来自实时监听的 _allAppointments / _allBlockTimes，不用再单独查一次 Firestore
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
      if (daySchedule == null) continue; // 本来就没排班，日历那边已经会灰掉

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

  // 生成可用时间槽：同样改用实时数据 _allAppointments / _allBlockTimes 现算，不用再查 Firestore
  void _generateTimeSlotsForSelectedDate() {
    if (!mounted) return;
    setState(() {
      _isLoadingSlots = true;
      _timeSlots.clear();
      _selectedTimeSlot = "";
    });

    String dayOfWeek = DateFormat('EEEE').format(_selectedDate!);
    String dateString = DateFormat('yyyy-MM-dd').format(_selectedDate!);

    // 1. 获取常规排班 (复用初始化时已经抓好的数据，不用再查一次 Schedule)
    var daySchedule = _scheduleByDay[dayOfWeek];
    if (daySchedule == null) {
      if (mounted) setState(() => _isLoadingSlots = false);
      return;
    }
    String schedStart = daySchedule['startTime']!;
    String schedEnd = daySchedule['endTime']!;

    // 2. 拦截时间 (请假/开会/特殊设置)
    List<Map<String, dynamic>> activeBlocks = [];
    for (var b in _allBlockTimes) {
      bool isRecurring = b['isRecurring'] ?? false;
      if ((isRecurring && b['dayOfWeek'] == dayOfWeek) ||
          (!isRecurring && b['specificDate'] == dateString)) {
        activeBlocks.add(b);
      }
    }

    // 3. 已被别人预约的时间
    List<String> bookedTimes = _allAppointments
        .where((d) => d['appointmentDate'] == dateString)
        .map((d) => d['appointmentTime'] as String)
        .toList();

    // 4. 切割时间槽 (每 30 分钟切割)
    int startMin = _timeToMinutes(schedStart);
    int endMin = _timeToMinutes(schedEnd);
    int interval = 30; // 30分钟间隔

    // 如果选中的是今天，过了的时间槽也要锁住
    DateTime now = DateTime.now();
    bool isToday = DateFormat('yyyy-MM-dd').format(now) == dateString;
    int nowMin = now.hour * 60 + now.minute;

    List<Map<String, dynamic>> generatedSlots = [];

    for (int time = startMin; time + interval <= endMin; time += interval) {
      int slotStart = time;
      int slotEnd = time + interval;
      String slotLabel = _minutesToAmPm(slotStart);

      // 判断是否与拦截时间冲突
      bool isBlocked = activeBlocks.any((block) {
        int bStart = _timeToMinutes(block['startTime']);
        int bEnd = _timeToMinutes(block['endTime']);
        return (slotStart < bEnd && slotEnd > bStart);
      });

      // 判断是否已被别人抢了
      bool isAlreadyBooked = bookedTimes.contains(slotLabel);

      // 判断是否已经过了现在的时间 (只在选今天时生效)
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

  // 写入数据库
  Future<void> _confirmBooking() async {
    setState(() => _isConfirming = true);
    try {
      String customerId = FirebaseAuth.instance.currentUser?.uid ?? "TEST_PATIENT_01";
      String dateString = DateFormat('yyyy-MM-dd').format(_selectedDate!);

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
                      _buildCalendarSelector(), // 原生完整日历组件

                      const SizedBox(height: 32),

                      const Text("Select Time", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      _isLoadingSlots 
                          ? Center(child: CircularProgressIndicator(color: primaryGreen))
                          : _buildTimeGrid(), // 3列网格大按钮

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

  // 🚀 完整日历视图 (翻页选月，智能置灰不可用日期)
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
          lastDate: DateTime.now().add(const Duration(days: 90)), // 开放3个月预约
          selectableDayPredicate: (DateTime date) {
            if (_workingDays.isEmpty) return true;
            String dayOfWeek = DateFormat('EEEE').format(date);
            if (!_workingDays.contains(dayOfWeek)) return false; // 智能变灰拦截 (非工作日)
            String dateString = DateFormat('yyyy-MM-dd').format(date);
            return !_fullyBookedDates.contains(dateString); // 整天满档也灰掉
          },
          onDisplayedMonthChanged: (DateTime newMonth) {
            _computeFullyBookedDatesForMonth(newMonth); // 翻页选月后重新算这个月哪些日期满档
          },
          onDateChanged: (DateTime newDate) {
            setState(() {
              _selectedDate = newDate;
            });
            _generateTimeSlotsForSelectedDate(); // 选新日期后重新计算时间槽
          },
        ),
      ),
    );
  }

  // 🚀 舒适大字体：3 列排版 30 分钟时间网格
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
        crossAxisCount: 3, // 恢复3列排版让按钮变宽
        childAspectRatio: 2.2, // 调整比例更饱满
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
                fontSize: 14, // 字体放大
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