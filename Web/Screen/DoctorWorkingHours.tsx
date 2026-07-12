import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, Trash2, Clock, CalendarRange, Loader2, Edit, AlertCircle } from 'lucide-react';
import { collection, query, where, getDocs, addDoc, updateDoc, deleteDoc, doc } from 'firebase/firestore';
import { auth, db } from '../firebaseConfig';

interface Schedule {
  id: string;
  dayOfWeek: string;
  startTime: string;
  endTime: string;
}

// Sort days in logical week order rather than alphabetically
const dayOrder: { [key: string]: number } = {
  'Monday': 1, 'Tuesday': 2, 'Wednesday': 3, 'Thursday': 4, 'Friday': 5, 'Saturday': 6, 'Sunday': 7
};

const emptyForm = {
  dayOfWeek: 'Monday',
  startTime: '08:00',
  endTime: '18:00'
};

const DoctorWorkingHours: React.FC = () => {
  const navigate = useNavigate();
  const [schedules, setSchedules] = useState<Schedule[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [adminID, setAdminID] = useState<string>('');

  const [editingId, setEditingId] = useState<string | null>(null);
  const [errorMsg, setErrorMsg] = useState<string>('');
  const [form, setForm] = useState(emptyForm);

  useEffect(() => {
    fetchWorkingHours();
  }, []);

  const fetchWorkingHours = async () => {
    setIsLoading(true);
    try {
      const currentUser = auth.currentUser;
      if (!currentUser) throw new Error("No user logged in");
      setAdminID(currentUser.uid);

      const q = query(collection(db, 'Schedule'), where('adminID', '==', currentUser.uid));
      const querySnapshot = await getDocs(q);

      const fetchedSchedules = querySnapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      })) as Schedule[];

      fetchedSchedules.sort((a, b) => dayOrder[a.dayOfWeek] - dayOrder[b.dayOfWeek]);
      setSchedules(fetchedSchedules);
    } catch (error) {
      console.error("Error fetching schedules:", error);
    } finally {
      setIsLoading(false);
    }
  };

  const resetForm = () => {
    setEditingId(null);
    setForm(emptyForm);
    setErrorMsg('');
  };

  const loadFormForEdit = (schedule: Schedule) => {
    setEditingId(schedule.id);
    setForm({
      dayOfWeek: schedule.dayOfWeek,
      startTime: schedule.startTime,
      endTime: schedule.endTime
    });
    setErrorMsg('');
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg('');

    // Only one schedule allowed per day; when editing, exclude the record
    // being edited itself, otherwise saving its own time would always fail this check.
    const isDuplicate = schedules.some(
      s => s.dayOfWeek === form.dayOfWeek && s.id !== editingId
    );

    if (isDuplicate) {
      setErrorMsg(`You already have a working slot set for ${form.dayOfWeek}.`);
      return;
    }

    setIsLoading(true);
    try {
      if (editingId) {
        await updateDoc(doc(db, 'Schedule', editingId), {
          dayOfWeek: form.dayOfWeek,
          startTime: form.startTime,
          endTime: form.endTime,
        });
      } else {
        await addDoc(collection(db, 'Schedule'), {
          adminID: adminID,
          dayOfWeek: form.dayOfWeek,
          startTime: form.startTime,
          endTime: form.endTime,
        });
      }

      resetForm();
      fetchWorkingHours();
    } catch (error) {
      console.error("Error saving schedule:", error);
      alert("Failed to save schedule.");
      setIsLoading(false);
    }
  };

  const handleDelete = async (id: string, day: string) => {
    if (window.confirm(`Are you sure you want to remove working hours for ${day}?`)) {
      setIsLoading(true);
      try {
        await deleteDoc(doc(db, 'Schedule', id));
        if (editingId === id) resetForm();
        fetchWorkingHours();
      } catch (error) {
        console.error("Error deleting schedule:", error);
        alert("Failed to delete schedule.");
        setIsLoading(false);
      }
    }
  };

  return (
    <div className="space-y-6 animate-fade-in">

      <div className="bg-white p-6 rounded-[24px] shadow-sm border border-gray-100 flex items-center space-x-4">
        <button
          onClick={() => navigate('/dashboard')}
          className="p-3 bg-gray-50 hover:bg-gray-100 text-gray-500 rounded-xl transition-colors"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div>
          <h2 className="text-2xl font-black text-gray-800 tracking-wide">Working Hours</h2>
          <p className="text-sm text-gray-500 font-medium mt-1">Configure your weekly availability for patient bookings.</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">

        <div className="lg:col-span-1 bg-white rounded-[24px] shadow-sm border border-gray-100 p-6">
          <div className="flex items-center justify-between mb-6">
            <h3 className="text-lg font-bold text-gray-800 flex items-center">
              <CalendarRange className="w-5 h-5 mr-2 text-blue-600" />
              {editingId ? 'Edit Time Slot' : 'Add Time Slot'}
            </h3>
            {editingId && (
              <button onClick={resetForm} className="text-xs font-bold text-gray-400 hover:text-gray-600">
                Cancel
              </button>
            )}
          </div>

          {errorMsg && (
            <div className="mb-4 p-3 bg-red-50 border border-red-100 text-red-600 text-xs font-bold rounded-lg flex items-start">
              <AlertCircle className="w-4 h-4 mr-2 flex-shrink-0 mt-0.5" />
              {errorMsg}
            </div>
          )}

          <form onSubmit={handleSave} className="space-y-4">
            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase mb-2">Day of the Week</label>
              <select
                required value={form.dayOfWeek} onChange={e => setForm({ ...form, dayOfWeek: e.target.value })}
                className="w-full p-3 bg-gray-50 border border-transparent rounded-xl outline-none focus:bg-white focus:border-blue-500 focus:ring-2 focus:ring-blue-200"
              >
                <option value="Monday">Monday</option><option value="Tuesday">Tuesday</option>
                <option value="Wednesday">Wednesday</option><option value="Thursday">Thursday</option>
                <option value="Friday">Friday</option><option value="Saturday">Saturday</option>
                <option value="Sunday">Sunday</option>
              </select>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-bold text-gray-500 uppercase mb-2">Start Time</label>
                <input required type="time" value={form.startTime} onChange={e => setForm({ ...form, startTime: e.target.value })} className="w-full p-3 bg-gray-50 border border-transparent rounded-xl outline-none focus:bg-white focus:border-blue-500 focus:ring-2 focus:ring-blue-200" />
              </div>
              <div>
                <label className="block text-xs font-bold text-gray-500 uppercase mb-2">End Time</label>
                <input required type="time" value={form.endTime} onChange={e => setForm({ ...form, endTime: e.target.value })} className="w-full p-3 bg-gray-50 border border-transparent rounded-xl outline-none focus:bg-white focus:border-blue-500 focus:ring-2 focus:ring-blue-200" />
              </div>
            </div>

            <button type="submit" disabled={isLoading} className="w-full mt-4 py-3 bg-blue-600 hover:bg-blue-700 text-white font-bold rounded-xl shadow-lg shadow-blue-200 transition-colors disabled:opacity-70">
              {isLoading ? 'Saving...' : editingId ? 'Update Weekly Routine' : 'Save Weekly Routine'}
            </button>
          </form>
        </div>

        <div className="lg:col-span-2 bg-white rounded-[24px] shadow-sm border border-gray-100 overflow-hidden">
          {isLoading ? (
            <div className="flex justify-center items-center h-64"><Loader2 className="w-8 h-8 animate-spin text-blue-600" /></div>
          ) : schedules.length === 0 ? (
            <div className="p-12 text-center">
              <CalendarRange className="w-16 h-16 text-gray-300 mx-auto mb-4" />
              <p className="text-gray-500 font-medium">You haven't set any working hours yet.</p>
            </div>
          ) : (
            <div className="divide-y divide-gray-100">
              {schedules.map((schedule) => (
                <div key={schedule.id} className={`flex items-center justify-between px-6 py-5 hover:bg-gray-50 transition-colors ${editingId === schedule.id ? 'bg-blue-50/50' : ''}`}>
                  <div className="flex items-center space-x-4">
                    <span className="font-black text-gray-800 text-base w-28">{schedule.dayOfWeek}</span>
                    <div className="flex items-center space-x-2 bg-blue-50 text-blue-700 w-max px-4 py-2 rounded-lg font-bold">
                      <Clock className="w-4 h-4" />
                      <span>{schedule.startTime} - {schedule.endTime}</span>
                    </div>
                  </div>
                  <div className="flex items-center space-x-2 flex-shrink-0">
                    <button
                      onClick={() => loadFormForEdit(schedule)}
                      className="p-2 text-blue-500 hover:bg-blue-50 rounded-lg transition-colors"
                      title="Edit Slot"
                    >
                      <Edit className="w-5 h-5" />
                    </button>
                    <button
                      onClick={() => handleDelete(schedule.id, schedule.dayOfWeek)}
                      className="p-2 text-red-500 hover:bg-red-50 rounded-lg transition-colors"
                      title="Delete Slot"
                    >
                      <Trash2 className="w-5 h-5" />
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default DoctorWorkingHours;
