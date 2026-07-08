import React, { useState, useEffect, useRef } from 'react';
import { Calendar, Clock, FileText, Loader2, XCircle, X, AlertCircle } from 'lucide-react';
import { collection, query, where, onSnapshot, getDoc, doc, updateDoc, serverTimestamp } from 'firebase/firestore';
import { auth, db } from '../firebaseConfig';

// The Appointment schema is actually written by the mobile app (clinic_appointment_screen.dart):
// customerID / adminID / appointmentDate / appointmentTime / remark / status
interface Appointment {
  id: string;
  customerID: string;
  appointmentDate: string; // 'yyyy-MM-dd'
  appointmentTime: string; // 'hh:mm AM/PM'
  remark: string;
  status: string; // 'Upcoming' | 'Completed' | 'Cancelled'
  cancelReason?: string;
}

const ClinicAppointments: React.FC = () => {
  const [appointments, setAppointments] = useState<Appointment[]>([]);
  const [patientNames, setPatientNames] = useState<{ [customerID: string]: string }>({});
  const [isLoading, setIsLoading] = useState(true);

  const [cancelTarget, setCancelTarget] = useState<Appointment | null>(null);
  const [cancelReason, setCancelReason] = useState('');
  const [isCancelling, setIsCancelling] = useState(false);

  // Tracks customerIDs we've already resolved a name for, so we don't re-query the User table on every list change
  const resolvedPatientIds = useRef<Set<string>>(new Set());

  // Real-time listener scoped to this doctor's own appointments only (not all doctors').
  // Patients can cancel/create appointments from the mobile app anytime, and the open page needs to reflect it immediately
  useEffect(() => {
    const currentUser = auth.currentUser;
    if (!currentUser) {
      setIsLoading(false);
      return;
    }

    const q = query(collection(db, 'Appointment'), where('adminID', '==', currentUser.uid));
    const unsubscribe = onSnapshot(q, async (snapshot) => {
      const fetchedData = snapshot.docs.map(d => ({
        id: d.id,
        customerID: d.data().customerID || '',
        appointmentDate: d.data().appointmentDate || 'TBD',
        appointmentTime: d.data().appointmentTime || 'TBD',
        remark: d.data().remark || '',
        status: d.data().status || 'Upcoming',
        cancelReason: d.data().cancelReason || '',
      })) as Appointment[];

      fetchedData.sort((a, b) => `${a.appointmentDate} ${a.appointmentTime}`.localeCompare(`${b.appointmentDate} ${b.appointmentTime}`));
      setAppointments(fetchedData);
      setIsLoading(false);

      const uniqueCustomerIDs = Array.from(new Set(fetchedData.map(a => a.customerID).filter(Boolean)));
      const uncachedIDs = uniqueCustomerIDs.filter(cid => !resolvedPatientIds.current.has(cid));
      if (uncachedIDs.length === 0) return;

      const namePairs = await Promise.all(uncachedIDs.map(async (cid) => {
        try {
          const userSnap = await getDoc(doc(db, 'User', cid));
          return [cid, userSnap.exists() ? (userSnap.data().username || 'Unknown Patient') : 'Unknown Patient'] as const;
        } catch {
          return [cid, 'Unknown Patient'] as const;
        }
      }));
      namePairs.forEach(([cid]) => resolvedPatientIds.current.add(cid));
      setPatientNames(prev => ({ ...prev, ...Object.fromEntries(namePairs) }));
    }, (error) => {
      console.error("Error fetching appointments:", error);
      alert("Failed to load appointments. Please check your connection.");
      setIsLoading(false);
    });

    return () => unsubscribe();
  }, []);

  const openCancelModal = (apt: Appointment) => {
    setCancelTarget(apt);
    setCancelReason('');
  };

  const confirmCancel = async () => {
    if (!cancelTarget || !cancelReason.trim()) return;
    setIsCancelling(true);
    try {
      await updateDoc(doc(db, 'Appointment', cancelTarget.id), {
        status: 'Cancelled',
        cancelReason: cancelReason.trim(),
        cancelledBy: 'Doctor',
        cancelledAt: serverTimestamp(),
      });
      setCancelTarget(null);
    } catch (error) {
      console.error("Error cancelling appointment:", error);
      alert("Failed to cancel appointment.");
    } finally {
      setIsCancelling(false);
    }
  };

  const getStatusBadgeColor = (status: string) => {
    switch (status) {
      case 'Completed': return 'bg-green-100 text-green-700 border-green-200';
      case 'Arrived': return 'bg-purple-100 text-purple-700 border-purple-200';
      case 'Overdue': return 'bg-red-600 text-white border-red-600';
      case 'Absent': return 'bg-gray-200 text-gray-600 border-gray-300';
      case 'Cancelled': return 'bg-red-100 text-red-700 border-red-200';
      default: return 'bg-blue-100 text-blue-700 border-blue-200'; // Upcoming
    }
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="bg-white p-6 rounded-[24px] shadow-sm border border-gray-100">
        <h2 className="text-2xl font-black text-gray-800 tracking-wide">Clinic Appointments</h2>
        <p className="text-sm text-gray-500 font-medium mt-1">All of your patients' bookings.</p>
      </div>

      {isLoading ? (
        <div className="flex justify-center items-center h-64">
          <Loader2 className="w-10 h-10 animate-spin text-green-600" />
        </div>
      ) : appointments.length === 0 ? (
        <div className="bg-white p-10 rounded-[24px] border border-gray-100 shadow-sm text-center">
          <Calendar className="w-16 h-16 text-gray-300 mx-auto mb-4" />
          <h3 className="text-lg font-bold text-gray-800">No Appointments Found</h3>
          <p className="text-gray-500 text-sm mt-2">You currently have no bookings.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-4">
          {appointments.map(apt => (
            <div key={apt.id} className="bg-white p-6 rounded-[24px] border border-gray-100 shadow-sm hover:shadow-md transition-all">
              <div className="flex items-center justify-between">
                <div className="flex items-center space-x-6">
                  <div className="w-14 h-14 bg-green-50 rounded-2xl flex items-center justify-center text-green-600 shadow-sm">
                    <Calendar className="w-6 h-6" />
                  </div>
                  <div>
                    <p className="font-black text-gray-800 text-lg tracking-wide">{patientNames[apt.customerID] || 'Loading...'}</p>
                    <div className="flex items-center text-gray-500 text-xs mt-1.5 space-x-4 font-medium">
                      <span className="flex items-center bg-gray-50 px-2 py-1 rounded-md"><Calendar className="w-3.5 h-3.5 mr-1.5 text-orange-500" /> {apt.appointmentDate}</span>
                      <span className="flex items-center bg-gray-50 px-2 py-1 rounded-md"><Clock className="w-3.5 h-3.5 mr-1.5 text-blue-500" /> {apt.appointmentTime}</span>
                    </div>
                  </div>
                </div>

                <div className="flex items-center space-x-3">
                  <span className={`px-4 py-1.5 rounded-full text-xs font-bold uppercase tracking-widest border ${getStatusBadgeColor(apt.status)}`}>
                    {apt.status}
                  </span>

                  {(apt.status === 'Upcoming' || apt.status === 'Overdue') && (
                    <button
                      onClick={() => openCancelModal(apt)}
                      className="p-1.5 bg-red-50 text-red-600 hover:bg-red-600 hover:text-white rounded-lg transition-colors"
                      title="Cancel Appointment"
                    >
                      <XCircle className="w-5 h-5" />
                    </button>
                  )}
                </div>
              </div>

              {apt.remark && (
                <div className="mt-4 pt-4 border-t border-gray-50 flex items-start text-sm text-gray-600">
                  <FileText className="w-4 h-4 mr-2 mt-0.5 text-gray-400 flex-shrink-0" />
                  <span><span className="font-bold text-gray-700">Patient's remark: </span>{apt.remark}</span>
                </div>
              )}

              {apt.status === 'Cancelled' && apt.cancelReason && (
                <div className="mt-4 pt-4 border-t border-gray-50 flex items-start text-sm text-red-600">
                  <AlertCircle className="w-4 h-4 mr-2 mt-0.5 flex-shrink-0" />
                  <span><span className="font-bold">Cancellation reason: </span>{apt.cancelReason}</span>
                </div>
              )}
            </div>
          ))}
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
              Cancelling <span className="font-bold text-gray-700">{patientNames[cancelTarget.customerID] || 'this patient'}</span>'s appointment on {cancelTarget.appointmentDate} at {cancelTarget.appointmentTime}. The patient will see this reason in their app.
            </p>

            <label className="block text-xs font-bold text-gray-500 uppercase mb-2">Reason (Required)</label>
            <textarea
              required
              value={cancelReason}
              onChange={e => setCancelReason(e.target.value)}
              rows={3}
              placeholder="e.g., Doctor is unavailable due to an emergency"
              className="w-full p-3 bg-gray-50 rounded-xl outline-none focus:ring-2 focus:ring-red-200 resize-none"
            />

            <button
              onClick={confirmCancel}
              disabled={!cancelReason.trim() || isCancelling}
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

export default ClinicAppointments;
