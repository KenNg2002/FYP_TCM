import React, { useState, useEffect } from 'react';
import { Calendar, User, Clock, MapPin, Loader2, CheckCircle, XCircle } from 'lucide-react';
import { collection, getDocs, updateDoc, doc } from 'firebase/firestore';
import { db } from '../firebaseConfig'; // Ensure this path is correct

// Define the Appointment data structure based on typical FYP needs
interface Appointment {
  id: string; // Firebase Document ID
  patientName: string;
  doctorName: string;
  date: string; // e.g., '2026-10-25'
  time: string; // e.g., '14:30'
  status: string; // 'Pending', 'Confirmed', 'Completed', 'Cancelled'
  location?: string;
}

const ClinicAppointments: React.FC = () => {
  const [appointments, setAppointments] = useState<Appointment[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  // Read sub-role from local storage (Set during Login). User.userRole is always
  // 'Admin' after login; Admin vs Doctor is tracked separately via Administrator.adminRole.
  const currentUserRole = localStorage.getItem('adminRole') || 'Admin';
  const isAdmin = currentUserRole === 'Admin';

  // Load appointments when the component mounts
  useEffect(() => {
    fetchAppointments();
  }, []);

  // 1. READ: Fetch all doctors' appointments from Firebase
  const fetchAppointments = async () => {
    setIsLoading(true);
    try {
      // Assuming your table is named 'Appointment'
      const querySnapshot = await getDocs(collection(db, 'Appointment'));
      
      const fetchedData = querySnapshot.docs.map(doc => ({
        id: doc.id,
        patientName: doc.data().patientName || 'Unknown Patient',
        doctorName: doc.data().doctorName || 'Unassigned',
        date: doc.data().date || 'TBD',
        time: doc.data().time || 'TBD',
        status: doc.data().status || 'Pending',
        location: doc.data().location || 'Main Branch',
      })) as Appointment[];

      // Sort by date and time (simplistic sorting)
      fetchedData.sort((a, b) => new Date(`${a.date} ${a.time}`).getTime() - new Date(`${b.date} ${b.time}`).getTime());

      setAppointments(fetchedData);
    } catch (error) {
      console.error("Error fetching appointments:", error);
      alert("Failed to load appointments. Please check your connection.");
    } finally {
      setIsLoading(false);
    }
  };

  // 2. UPDATE: Admin changes the appointment status
  const updateStatus = async (id: string, newStatus: string) => {
    // Double check permission before making database writes
    if (!isAdmin) return;

    try {
      setIsLoading(true);
      await updateDoc(doc(db, 'Appointment', id), {
        status: newStatus
      });
      
      // Refresh the list to show updated status
      fetchAppointments();
    } catch (error) {
      console.error("Error updating status:", error);
      alert("Failed to update status.");
      setIsLoading(false);
    }
  };

  // Helper function to render correct status badge colors
  const getStatusBadgeColor = (status: string) => {
    switch (status) {
      case 'Confirmed': return 'bg-blue-100 text-blue-700 border-blue-200';
      case 'Completed': return 'bg-green-100 text-green-700 border-green-200';
      case 'Cancelled': return 'bg-red-100 text-red-700 border-red-200';
      default: return 'bg-orange-100 text-orange-700 border-orange-200'; // Pending
    }
  };

  return (
    <div className="space-y-6 animate-fade-in">
      {/* Top Header Section */}
      <div className="bg-white p-6 rounded-[24px] shadow-sm border border-gray-100 flex justify-between items-center">
        <div>
          <h2 className="text-2xl font-black text-gray-800 tracking-wide">Clinic Visit Schedule</h2>
          <p className="text-sm text-gray-500 font-medium mt-1">Master view of all practitioners' appointments.</p>
        </div>
        
        {/* Only Admin can see the Manual Booking button (Placeholder for future feature) */}
        {isAdmin && (
          <button className="bg-green-600 hover:bg-green-700 text-white px-6 py-3 rounded-xl font-bold text-sm shadow-md shadow-green-200 transition-colors">
            + Manual Booking
          </button>
        )}
      </div>

      {/* Appointments List */}
      {isLoading ? (
        <div className="flex justify-center items-center h-64">
          <Loader2 className="w-10 h-10 animate-spin text-green-600" />
        </div>
      ) : appointments.length === 0 ? (
        <div className="bg-white p-10 rounded-[24px] border border-gray-100 shadow-sm text-center">
          <Calendar className="w-16 h-16 text-gray-300 mx-auto mb-4" />
          <h3 className="text-lg font-bold text-gray-800">No Appointments Found</h3>
          <p className="text-gray-500 text-sm mt-2">There are currently no bookings in the database.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-4">
          {appointments.map(apt => (
            <div key={apt.id} className="bg-white p-6 rounded-[24px] border border-gray-100 shadow-sm flex items-center justify-between hover:shadow-md transition-all group relative overflow-hidden">
              
              {/* Left Side: Appointment Info */}
              <div className="flex items-center space-x-6 relative z-10">
                <div className="w-14 h-14 bg-green-50 rounded-2xl flex items-center justify-center text-green-600 group-hover:bg-green-600 group-hover:text-white transition-colors shadow-sm">
                  <Calendar className="w-6 h-6" />
                </div>
                <div>
                  <p className="font-black text-gray-800 text-lg tracking-wide">{apt.patientName}</p>
                  <div className="flex items-center text-gray-500 text-xs mt-1.5 space-x-4 font-medium">
                    <span className="flex items-center bg-gray-50 px-2 py-1 rounded-md"><User className="w-3.5 h-3.5 mr-1.5 text-green-600" /> {apt.doctorName}</span>
                    <span className="flex items-center bg-gray-50 px-2 py-1 rounded-md"><Clock className="w-3.5 h-3.5 mr-1.5 text-blue-500" /> {apt.time}</span>
                    <span className="flex items-center bg-gray-50 px-2 py-1 rounded-md"><MapPin className="w-3.5 h-3.5 mr-1.5 text-orange-500" /> {apt.location}</span>
                  </div>
                </div>
              </div>

              {/* Right Side: Status & Actions */}
              <div className="flex flex-col items-end relative z-10">
                <span className="text-xs font-black text-gray-400 mb-3 tracking-wider">{apt.date}</span>
                
                <div className="flex items-center space-x-3">
                  {/* Status Badge */}
                  <span className={`px-4 py-1.5 rounded-full text-xs font-bold uppercase tracking-widest border ${getStatusBadgeColor(apt.status)}`}>
                    {apt.status}
                  </span>

                  {/* Admin Action Buttons (Only show if Admin AND status is Pending or Confirmed) */}
                  {isAdmin && apt.status === 'Pending' && (
                    <button 
                      onClick={() => updateStatus(apt.id, 'Confirmed')}
                      className="p-1.5 bg-blue-50 text-blue-600 hover:bg-blue-600 hover:text-white rounded-lg transition-colors"
                      title="Confirm Appointment"
                    >
                      <CheckCircle className="w-5 h-5" />
                    </button>
                  )}
                  
                  {isAdmin && (apt.status === 'Pending' || apt.status === 'Confirmed') && (
                    <button 
                      onClick={() => updateStatus(apt.id, 'Cancelled')}
                      className="p-1.5 bg-red-50 text-red-600 hover:bg-red-600 hover:text-white rounded-lg transition-colors"
                      title="Cancel Appointment"
                    >
                      <XCircle className="w-5 h-5" />
                    </button>
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

export default ClinicAppointments;