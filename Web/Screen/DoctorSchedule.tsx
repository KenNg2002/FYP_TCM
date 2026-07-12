import React, { useState, useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { User, CalendarDays, Loader2, CheckSquare, ShieldBan, CalendarRange, ChevronLeft, ChevronRight, AlertTriangle, UserCheck, UserX, XCircle, X, AlertCircle } from 'lucide-react';
import { collection, query, where, getDocs, onSnapshot, doc, getDoc, updateDoc, serverTimestamp } from 'firebase/firestore';
import { auth, db } from '../firebaseConfig';
import { sendNotification } from '../notifications';

// The Appointment schema is actually written by the mobile app (clinic_appointment_screen.dart):
// customerID / adminID / appointmentDate ('yyyy-MM-dd') / appointmentTime ('hh:mm AM/PM') / remark / status
//
// Status flow (30-minute slots, e.g. 09:00 - 09:30):
// Upcoming (default) --T+15min still not Attended--> Overdue (auto) --T+30min still unresolved--> Absent (auto)
// Upcoming / Overdue --Admin clicks Attend--> Arrived --Admin clicks Mark as Complete--> Completed
// Overdue --Admin clicks Mark as Absent--> Absent
interface RawAppointment {
  id: string;
  customerID: string;
  appointmentDate: string;
  appointmentTime: string;
  remark: string;
  status: string; // 'Upcoming' | 'Arrived' | 'Overdue' | 'Absent' | 'Completed' | 'Cancelled'
  cancelReason?: string;
}

interface RawBlockTime {
  id: string;
  isRecurring: boolean;
  specificDate: string | null;
  dayOfWeek: string | null;
  startTime: string;
  endTime: string;
  blockType: string;
  reason: string;
}

interface TimelineItem {
  id: string;
  type: 'Appointment' | 'BlockTime';
  sortMinutes: number;
  timeLabel: string;
  patientName?: string;
  status?: string;
  remark?: string;
  cancelReason?: string;
  blockType?: string;
  reason?: string;
}

const weekdayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

const toDateString = (d: Date) => {
  const y = d.getFullYear();
  const m = (d.getMonth() + 1).toString().padStart(2, '0');
  const day = d.getDate().toString().padStart(2, '0');
  return `${y}-${m}-${day}`;
};

// "09:00 AM" -> minutes, for sorting
const parse12hToMinutes = (label: string): number => {
  try {
    const [time, period] = label.trim().split(' ');
    const [hStr, mStr] = time.split(':');
    let h = parseInt(hStr, 10);
    const m = parseInt(mStr, 10);
    if (period?.toUpperCase() === 'PM' && h !== 12) h += 12;
    if (period?.toUpperCase() === 'AM' && h === 12) h = 0;
    return h * 60 + m;
  } catch {
    return 0;
  }
};

// "09:00" (24-hour format, from the Working Hours / Block Time <input type="time">) -> minutes
const parse24hToMinutes = (time: string): number => {
  const [hStr, mStr] = (time || '0:0').split(':');
  return parseInt(hStr, 10) * 60 + parseInt(mStr || '0', 10);
};

// 'yyyy-MM-dd' + "09:00 AM" -> a full Date object, for comparing against "now"
const buildDateTime = (dateStr: string, timeLabel: string): Date => {
  const [y, m, d] = dateStr.split('-').map(Number);
  const dt = new Date(y, (m || 1) - 1, d || 1);
  dt.setMinutes(parse12hToMinutes(timeLabel));
  return dt;
};

const DoctorSchedule: React.FC = () => {
  const navigate = useNavigate();
  const [appointments, setAppointments] = useState<RawAppointment[]>([]);
  const [blockTimes, setBlockTimes] = useState<RawBlockTime[]>([]);
  const [patientNames, setPatientNames] = useState<{ [customerID: string]: string }>({});
  const [isLoading, setIsLoading] = useState(true);
  const [doctorName, setDoctorName] = useState<string>('');

  const today = new Date();
  const [selectedDate, setSelectedDate] = useState<Date>(today);
  const [viewMonth, setViewMonth] = useState<Date>(new Date(today.getFullYear(), today.getMonth(), 1));
  const [now, setNow] = useState<Date>(new Date()); // ticks every minute so Overdue status updates automatically without a page refresh

  // Read the logged-in user's role from local cache to gate access
  const currentUserRole = localStorage.getItem('adminRole') || '';
  const isDoctor = currentUserRole === 'Doctor';

  // Doctor's own profile + block times aren't changed by anyone else, so a one-time fetch is enough
  useEffect(() => {
    if (!isDoctor) return;
    const currentUser = auth.currentUser;
    if (!currentUser) return;

    (async () => {
      try {
        const userSnap = await getDoc(doc(db, 'User', currentUser.uid));
        let name = userSnap.exists() ? userSnap.data().username : null;
        if (!name) {
          const adminSnap = await getDoc(doc(db, 'Administrator', currentUser.uid));
          name = adminSnap.exists() ? adminSnap.data().adminName : 'Doctor';
        }
        setDoctorName(name || 'Doctor');

        const blockSnap = await getDocs(query(collection(db, 'BlockTime'), where('adminID', '==', currentUser.uid)));
        setBlockTimes(blockSnap.docs.map(d => ({
          id: d.id,
          isRecurring: d.data().isRecurring || false,
          specificDate: d.data().specificDate || null,
          dayOfWeek: d.data().dayOfWeek || null,
          startTime: d.data().startTime || '00:00',
          endTime: d.data().endTime || '00:00',
          blockType: d.data().blockType || 'Unavailable',
          reason: d.data().reason || 'Blocked',
        })));
      } catch (error) {
        console.error("Error fetching doctor profile/block times:", error);
      }
    })();
  }, [isDoctor]);

  // Tracks customerIDs we've already resolved a name for, so we don't re-query the User table on every appointment list change
  const resolvedPatientIds = useRef<Set<string>>(new Set());

  // Real-time listener: patients can cancel/create appointments from the mobile app anytime, and the doctor's open page needs to reflect it immediately
  useEffect(() => {
    if (!isDoctor) {
      setIsLoading(false);
      return;
    }
    const currentUser = auth.currentUser;
    if (!currentUser) {
      setIsLoading(false);
      return;
    }

    const q = query(collection(db, 'Appointment'), where('adminID', '==', currentUser.uid));
    const unsubscribe = onSnapshot(q, async (snapshot) => {
      const fetchedAppointments: RawAppointment[] = snapshot.docs.map(d => ({
        id: d.id,
        customerID: d.data().customerID || '',
        appointmentDate: d.data().appointmentDate || '',
        appointmentTime: d.data().appointmentTime || '',
        remark: d.data().remark || '',
        status: d.data().status || 'Upcoming',
        cancelReason: d.data().cancelReason || '',
      }));
      setAppointments(fetchedAppointments);
      setIsLoading(false);

      const uniqueCustomerIDs = Array.from(new Set(fetchedAppointments.map(a => a.customerID).filter(Boolean)));
      const uncachedIDs = uniqueCustomerIDs.filter(cid => !resolvedPatientIds.current.has(cid));
      if (uncachedIDs.length === 0) return;

      const namePairs = await Promise.all(uncachedIDs.map(async (cid) => {
        try {
          const patientSnap = await getDoc(doc(db, 'User', cid));
          return [cid, patientSnap.exists() ? (patientSnap.data().username || 'Unknown Patient') : 'Unknown Patient'] as const;
        } catch {
          return [cid, 'Unknown Patient'] as const;
        }
      }));
      namePairs.forEach(([cid]) => resolvedPatientIds.current.add(cid));
      setPatientNames(prev => ({ ...prev, ...Object.fromEntries(namePairs) }));
    }, (error) => {
      console.error("Error fetching appointments:", error);
      setIsLoading(false);
    });

    return () => unsubscribe();
  }, [isDoctor]);

  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), 60000);
    return () => clearInterval(timer);
  }, []);

  // Prevents the same id from being written to Firestore twice concurrently by the auto-check
  const pendingAutoUpdates = useRef<Set<string>>(new Set());

  const applyStatusChange = async (id: string, newStatus: string) => {
    if (pendingAutoUpdates.current.has(id)) return;
    pendingAutoUpdates.current.add(id);
    try {
      await updateDoc(doc(db, 'Appointment', id), { status: newStatus });
      setAppointments(prev => prev.map(a => (a.id === id ? { ...a, status: newStatus } : a)));
    } catch (error) {
      console.error(`Failed to update appointment ${id} to ${newStatus}:`, error);
    } finally {
      pendingAutoUpdates.current.delete(id);
    }
  };

  const handleAttend = (id: string) => applyStatusChange(id, 'Arrived');
  const handleMarkAbsent = (id: string) => applyStatusChange(id, 'Absent');
  const handleMarkComplete = (id: string) => applyStatusChange(id, 'Completed');

  const [cancelTarget, setCancelTarget] = useState<TimelineItem | null>(null);
  const [cancelReasonInput, setCancelReasonInput] = useState('');
  const [isCancelling, setIsCancelling] = useState(false);

  const openCancelModal = (item: TimelineItem) => {
    setCancelTarget(item);
    setCancelReasonInput('');
  };

  const confirmCancel = async () => {
    if (!cancelTarget || !cancelReasonInput.trim()) return;
    setIsCancelling(true);
    try {
      await updateDoc(doc(db, 'Appointment', cancelTarget.id), {
        status: 'Cancelled',
        cancelReason: cancelReasonInput.trim(),
        cancelledBy: 'Doctor',
        cancelledAt: serverTimestamp(),
      });
      const cancelledAppt = appointments.find(a => a.id === cancelTarget.id);
      if (cancelledAppt) {
        sendNotification({
          uids: [cancelledAppt.customerID],
          title: 'Appointment Cancelled',
          body: `Your appointment on ${cancelledAppt.appointmentDate} at ${cancelledAppt.appointmentTime} was cancelled: ${cancelReasonInput.trim()}`,
          data: { appointmentId: cancelTarget.id },
        });
      }
      setAppointments(prev => prev.map(a => (a.id === cancelTarget.id ? { ...a, status: 'Cancelled', cancelReason: cancelReasonInput.trim() } : a)));
      setCancelTarget(null);
    } catch (error) {
      console.error("Error cancelling appointment:", error);
      alert("Failed to cancel appointment.");
    } finally {
      setIsCancelling(false);
    }
  };

  // Auto-checks the timeline triggers every minute (as `now` changes):
  // T+15min still Upcoming -> auto Overdue; T+30min (slot fully elapsed) still Overdue -> auto Absent
  useEffect(() => {
    appointments.forEach(a => {
      if (a.status !== 'Upcoming' && a.status !== 'Overdue') return;
      if (!a.appointmentDate || !a.appointmentTime) return;

      const slotStart = buildDateTime(a.appointmentDate, a.appointmentTime);
      const graceEnd = new Date(slotStart.getTime() + 15 * 60000);
      const slotEnd = new Date(slotStart.getTime() + 30 * 60000);

      if (a.status === 'Upcoming' && now >= graceEnd) {
        applyStatusChange(a.id, 'Overdue');
      } else if (a.status === 'Overdue' && now >= slotEnd) {
        applyStatusChange(a.id, 'Absent');
      }
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [now, appointments]);

  const getTimelineForDate = (d: Date): TimelineItem[] => {
    const dateStr = toDateString(d);
    const dayOfWeek = weekdayNames[d.getDay()];

    const apptItems: TimelineItem[] = appointments
      .filter(a => a.appointmentDate === dateStr)
      .map(a => ({
        id: a.id,
        type: 'Appointment',
        sortMinutes: parse12hToMinutes(a.appointmentTime),
        timeLabel: a.appointmentTime,
        patientName: patientNames[a.customerID] || 'Loading...',
        status: a.status,
        remark: a.remark,
        cancelReason: a.cancelReason,
      }));

    const blockItems: TimelineItem[] = blockTimes
      .filter(b => (b.isRecurring && b.dayOfWeek === dayOfWeek) || (!b.isRecurring && b.specificDate === dateStr))
      .map(b => ({
        id: b.id,
        type: 'BlockTime',
        sortMinutes: parse24hToMinutes(b.startTime),
        timeLabel: `${b.startTime} - ${b.endTime}`,
        blockType: b.blockType,
        reason: b.reason,
      }));

    return [...apptItems, ...blockItems].sort((a, b) => a.sortMinutes - b.sortMinutes);
  };

  // Dates with at least one appointment, used to render the dot indicator on the calendar
  const datesWithAppointments = new Set(
    appointments.filter(a => a.status !== 'Cancelled').map(a => a.appointmentDate)
  );

  if (!isDoctor) {
    return (
      <div className="flex flex-col items-center justify-center h-[70vh] animate-fade-in text-center">
        <div className="w-24 h-24 bg-red-50 rounded-full flex items-center justify-center mb-6">
          <ShieldBan className="w-12 h-12 text-red-500" />
        </div>
        <h2 className="text-3xl font-black text-gray-800 mb-2">Access Restricted</h2>
        <p className="text-gray-500 max-w-md">
          This area is strictly reserved for Medical Doctors to view their personal schedules and patients. Your current role is not authorized.
        </p>
      </div>
    );
  }

  const selectedDateStr = toDateString(selectedDate);
  const isSelectedToday = selectedDateStr === toDateString(today);
  const selectedDayDisplay = selectedDate.toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'short', day: 'numeric' });
  const timelineItems = getTimelineForDate(selectedDate);

  const firstOfMonth = new Date(viewMonth.getFullYear(), viewMonth.getMonth(), 1);
  const daysInMonth = new Date(viewMonth.getFullYear(), viewMonth.getMonth() + 1, 0).getDate();
  const leadingBlanks = firstOfMonth.getDay();
  const calendarCells: (Date | null)[] = [
    ...Array(leadingBlanks).fill(null),
    ...Array.from({ length: daysInMonth }, (_, i) => new Date(viewMonth.getFullYear(), viewMonth.getMonth(), i + 1)),
  ];

  return (
    <div className="space-y-6 animate-fade-in">

      <div className="bg-white p-8 rounded-[30px] shadow-sm border border-gray-100 flex justify-between items-end">
        <div>
          <h2 className="text-2xl font-black text-gray-800">{doctorName ? `${doctorName}'s Schedule` : 'My Schedule'}</h2>
          <p className="text-gray-400 text-sm mt-1">Tap a date to see your appointments for that day.</p>
        </div>
        <div className="flex space-x-3">
          <button
            onClick={() => navigate('/working-hours')}
            className="flex items-center bg-blue-50 text-blue-600 px-5 py-3 rounded-2xl font-bold text-sm border border-blue-100 hover:bg-blue-600 hover:text-white transition-all shadow-sm"
          >
            <CalendarRange className="w-4 h-4 mr-2" />
            Manage Working Hours
          </button>
          <button
            onClick={() => navigate('/block-times')}
            className="flex items-center bg-red-50 text-red-600 px-5 py-3 rounded-2xl font-bold text-sm border border-red-100 hover:bg-red-600 hover:text-white transition-all shadow-sm"
          >
            <ShieldBan className="w-4 h-4 mr-2" />
            Manage Block Times
          </button>
        </div>
      </div>

      {isLoading ? (
        <div className="flex justify-center items-center h-40"><Loader2 className="w-8 h-8 animate-spin text-green-600" /></div>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">

          <div className="lg:col-span-1 bg-white rounded-[24px] shadow-sm border border-gray-100 p-6">
            <div className="flex items-center justify-between mb-4">
              <button onClick={() => setViewMonth(new Date(viewMonth.getFullYear(), viewMonth.getMonth() - 1, 1))} className="p-2 hover:bg-gray-50 rounded-lg text-gray-500">
                <ChevronLeft className="w-5 h-5" />
              </button>
              <h3 className="font-black text-gray-800">{viewMonth.toLocaleDateString('en-US', { month: 'long', year: 'numeric' })}</h3>
              <button onClick={() => setViewMonth(new Date(viewMonth.getFullYear(), viewMonth.getMonth() + 1, 1))} className="p-2 hover:bg-gray-50 rounded-lg text-gray-500">
                <ChevronRight className="w-5 h-5" />
              </button>
            </div>

            <div className="grid grid-cols-7 gap-1 mb-2">
              {['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'].map(w => (
                <div key={w} className="text-center text-[11px] font-bold text-gray-400 py-1">{w}</div>
              ))}
            </div>

            <div className="grid grid-cols-7 gap-1">
              {calendarCells.map((d, idx) => {
                if (!d) return <div key={idx} />;
                const dStr = toDateString(d);
                const isToday = dStr === toDateString(today);
                const isSelected = dStr === selectedDateStr;
                const hasAppointment = datesWithAppointments.has(dStr);

                return (
                  <button
                    key={idx}
                    onClick={() => setSelectedDate(d)}
                    className={`relative aspect-square rounded-xl text-sm font-bold flex items-center justify-center transition-colors ${
                      isSelected ? 'bg-green-600 text-white' : isToday ? 'bg-green-50 text-green-700' : 'text-gray-700 hover:bg-gray-50'
                    }`}
                  >
                    {d.getDate()}
                    {hasAppointment && (
                      <span className={`absolute bottom-1.5 w-1.5 h-1.5 rounded-full ${isSelected ? 'bg-white' : 'bg-green-500'}`} />
                    )}
                  </button>
                );
              })}
            </div>
          </div>

          <div className="lg:col-span-2 space-y-4">
            <div className="flex items-center justify-between px-2">
              <h3 className="font-black text-gray-800 text-lg">{selectedDayDisplay}</h3>
              {isSelectedToday && <span className="bg-green-100 text-green-700 px-3 py-1 rounded-full text-xs font-bold">Today</span>}
            </div>

            {timelineItems.length === 0 ? (
              <div className="bg-white p-10 rounded-[25px] border border-gray-100 shadow-sm text-center">
                <CalendarDays className="w-12 h-12 text-gray-300 mx-auto mb-3" />
                <p className="text-gray-500 font-medium">No appointments on this day.</p>
              </div>
            ) : (
              timelineItems.map((item) => {
                if (item.type === 'BlockTime') {
                  return (
                    <div key={item.id} className="flex items-center p-6 rounded-[25px] border-2 border-dashed border-gray-200 bg-gray-50 opacity-80">
                      <div className="w-32 border-r border-gray-200 mr-8 flex flex-col justify-center">
                        <p className="font-black text-gray-500 text-sm">{item.timeLabel}</p>
                      </div>
                      <div className="flex-1 flex items-center space-x-4">
                        <div className="p-3 rounded-xl bg-gray-200 text-gray-500"><ShieldBan className="w-5 h-5" /></div>
                        <div>
                          <p className="font-bold text-lg text-gray-600 uppercase tracking-wide">{item.blockType}</p>
                          <p className="text-sm text-gray-500 font-medium mt-1">Reason: {item.reason}</p>
                        </div>
                      </div>
                    </div>
                  );
                }

                const isOverdue = item.status === 'Overdue';
                const isArrived = item.status === 'Arrived';
                const isDimmed = item.status === 'Completed' || item.status === 'Cancelled' || item.status === 'Absent';
                const canAct = isSelectedToday;

                // The appointment's scheduled time on selectedDate, used to compute how late it is
                const scheduledAt = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate());
                scheduledAt.setMinutes(item.sortMinutes);
                const minutesLate = Math.floor((now.getTime() - scheduledAt.getTime()) / 60000);

                const statusBadgeClass =
                  item.status === 'Upcoming' ? 'bg-blue-50 text-blue-600' :
                  item.status === 'Arrived' ? 'bg-purple-50 text-purple-600' :
                  item.status === 'Overdue' ? 'bg-red-600 text-white' :
                  item.status === 'Absent' ? 'bg-gray-200 text-gray-600' :
                  item.status === 'Cancelled' ? 'bg-red-50 text-red-600' :
                  'bg-gray-100 text-gray-500'; // Completed

                return (
                  <div key={item.id} className={`p-6 rounded-[25px] border-2 transition-all duration-300 ${
                    isOverdue ? 'border-red-400 bg-red-50' :
                    isArrived ? 'border-purple-300 bg-purple-50' :
                    isDimmed ? 'border-gray-50 bg-gray-50 opacity-70' : 'border-transparent bg-white shadow-sm hover:border-green-100'
                  }`}>
                  <div className="flex items-center">
                    <div className="w-32 border-r border-gray-100 mr-8 flex flex-col justify-center">
                      <p className="font-black text-gray-800 text-sm">{item.timeLabel}</p>
                    </div>
                    <div className="flex-1 flex items-center justify-between">
                      <div className="flex items-center space-x-4">
                        <div className={`p-3 rounded-xl ${isOverdue ? 'bg-red-100 text-red-600' : isArrived ? 'bg-purple-100 text-purple-600' : 'bg-green-100 text-green-600'}`}>
                          {isOverdue ? <AlertTriangle className="w-5 h-5" /> : <User className="w-5 h-5" />}
                        </div>
                        <div>
                          <p className={`font-bold text-lg ${isDimmed ? 'text-gray-500 line-through' : isOverdue ? 'text-red-700' : 'text-gray-800'}`}>{item.patientName}</p>
                          <div className="flex items-center mt-1 space-x-2">
                            <span className={`text-xs font-bold px-2 py-0.5 rounded-md ${statusBadgeClass}`}>{item.status}</span>
                            {isOverdue && minutesLate > 0 && (
                              <span className="flex items-center text-xs font-bold px-2 py-0.5 rounded-md bg-red-600 text-white">
                                <AlertTriangle className="w-3 h-3 mr-1" /> {minutesLate}m late
                              </span>
                            )}
                            {item.remark && <span className="text-xs text-gray-400 italic">"{item.remark}"</span>}
                          </div>
                        </div>
                      </div>
                      <div className="flex items-center space-x-2">
                        {canAct && (item.status === 'Upcoming' || item.status === 'Overdue') && (
                          <button onClick={() => handleAttend(item.id)} className="flex items-center space-x-1 bg-gray-900 text-white px-5 py-2.5 rounded-xl font-bold text-xs hover:bg-black">
                            <UserCheck className="w-4 h-4" /><span>Attend</span>
                          </button>
                        )}
                        {canAct && item.status === 'Overdue' && (
                          <button onClick={() => handleMarkAbsent(item.id)} className="flex items-center space-x-1 bg-red-600 text-white px-5 py-2.5 rounded-xl font-bold text-xs hover:bg-red-700">
                            <UserX className="w-4 h-4" /><span>Mark as Absent</span>
                          </button>
                        )}
                        {canAct && item.status === 'Arrived' && (
                          <button onClick={() => handleMarkComplete(item.id)} className="flex items-center space-x-1 bg-green-600 text-white px-5 py-2.5 rounded-xl font-bold text-xs hover:bg-green-700">
                            <CheckSquare className="w-4 h-4" /><span>Mark as Complete</span>
                          </button>
                        )}
                        {(item.status === 'Upcoming' || item.status === 'Overdue') && (
                          <button onClick={() => openCancelModal(item)} className="p-2 bg-red-50 text-red-600 hover:bg-red-600 hover:text-white rounded-lg transition-colors" title="Cancel Appointment">
                            <XCircle className="w-5 h-5" />
                          </button>
                        )}
                      </div>
                    </div>
                  </div>
                  {item.status === 'Cancelled' && item.cancelReason && (
                    <div className="mt-3 pt-3 border-t border-gray-100 flex items-start text-sm text-red-600">
                      <AlertCircle className="w-4 h-4 mr-2 mt-0.5 flex-shrink-0" />
                      <span><span className="font-bold">Cancellation reason: </span>{item.cancelReason}</span>
                    </div>
                  )}
                  </div>
                );
              })
            )}
          </div>
        </div>
      )}

      {/* Cancellation modal — a reason is required before it can be submitted */}
      {cancelTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-40 backdrop-blur-sm">
          <div className="bg-white rounded-[24px] shadow-2xl w-full max-w-md p-8 animate-fade-in">
            <div className="flex justify-between items-center mb-6">
              <h2 className="text-xl font-bold text-gray-800 flex items-center"><XCircle className="mr-2 text-red-600" /> Cancel Appointment</h2>
              <button onClick={() => setCancelTarget(null)} className="text-gray-400 hover:bg-gray-100 p-2 rounded-full"><X className="w-5 h-5" /></button>
            </div>

            <p className="text-sm text-gray-500 mb-4">
              Cancelling <span className="font-bold text-gray-700">{cancelTarget.patientName}</span>'s appointment at {cancelTarget.timeLabel} on {selectedDayDisplay}. The patient will see this reason in their app.
            </p>

            <label className="block text-xs font-bold text-gray-500 uppercase mb-2">Reason (Required)</label>
            <textarea
              required
              value={cancelReasonInput}
              onChange={e => setCancelReasonInput(e.target.value)}
              rows={3}
              placeholder="e.g., Doctor is unavailable due to an emergency"
              className="w-full p-3 bg-gray-50 rounded-xl outline-none focus:ring-2 focus:ring-red-200 resize-none"
            />

            <button
              onClick={confirmCancel}
              disabled={!cancelReasonInput.trim() || isCancelling}
              className="w-full mt-4 py-3 bg-red-600 hover:bg-red-700 text-white font-bold rounded-xl shadow-md transition-colors disabled:opacity-50"
            >
              {isCancelling ? 'Cancelling...' : 'Confirm Cancellation'}
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

export default DoctorSchedule;
