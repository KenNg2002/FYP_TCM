import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, Trash2, Clock, ShieldBan, Loader2, Edit, CalendarDays, RefreshCw } from 'lucide-react';
import { collection, query, where, getDocs, addDoc, updateDoc, deleteDoc, doc } from 'firebase/firestore';
import { auth, db } from '../firebaseConfig';

interface BlockTime {
  id: string;
  isRecurring: boolean;
  specificDate: string | null;
  dayOfWeek: string | null;
  startTime: string;
  endTime: string;
  blockType: string;
  reason: string;
}

const emptyForm = {
  isRecurring: false,
  specificDate: '',
  dayOfWeek: 'Monday',
  isWholeDay: false,
  startTime: '',
  endTime: '',
  blockType: 'Break',
  reason: ''
};

// Sentinel start/end time stored for whole-day blocks
const WHOLE_DAY_START = '00:00';
const WHOLE_DAY_END = '23:59';

// Sort days in logical week order rather than whatever order Firestore returns them in
const dayOrder: { [key: string]: number } = {
  'Monday': 1, 'Tuesday': 2, 'Wednesday': 3, 'Thursday': 4, 'Friday': 5, 'Saturday': 6, 'Sunday': 7
};

// Handles both 24h "HH:MM" (from <input type="time">) and 12h "hh:mm AM/PM" (as stored on Appointment docs)
const parseTimeToMinutes = (time: string): number => {
  const ampmMatch = time.match(/^(\d{1,2}):(\d{2})\s*(AM|PM)$/i);
  if (ampmMatch) {
    let h = parseInt(ampmMatch[1], 10);
    const m = parseInt(ampmMatch[2], 10);
    const period = ampmMatch[3].toUpperCase();
    if (period === 'AM' && h === 12) h = 0;
    if (period === 'PM' && h !== 12) h += 12;
    return h * 60 + m;
  }
  const [h, m] = time.split(':').map(Number);
  return h * 60 + m;
};

const getDayOfWeek = (dateStr: string): string => {
  const [y, m, d] = dateStr.split('-').map(Number);
  const date = new Date(y, m - 1, d);
  return ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][date.getDay()];
};

const DoctorBlockTimes: React.FC = () => {
  const navigate = useNavigate();
  const [blockTimes, setBlockTimes] = useState<BlockTime[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [adminID, setAdminID] = useState<string>('');

  const [editingId, setEditingId] = useState<string | null>(null);
  const [form, setForm] = useState(emptyForm);

  const [activeTab, setActiveTab] = useState<'recurring' | 'onetime'>('recurring');

  useEffect(() => {
    fetchBlockTimes();
  }, []);

  const fetchBlockTimes = async () => {
    setIsLoading(true);
    try {
      const currentUser = auth.currentUser;
      if (!currentUser) throw new Error("No user logged in");
      setAdminID(currentUser.uid);

      const q = query(collection(db, 'BlockTime'), where('adminID', '==', currentUser.uid));
      const querySnapshot = await getDocs(q);

      const fetchedBlocks = querySnapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      })) as BlockTime[];

      setBlockTimes(fetchedBlocks);
    } catch (error) {
      console.error("Error fetching block times:", error);
    } finally {
      setIsLoading(false);
    }
  };

  const resetForm = () => {
    setEditingId(null);
    setForm(emptyForm);
  };

  const loadFormForEdit = (block: BlockTime) => {
    setEditingId(block.id);
    setForm({
      isRecurring: block.isRecurring,
      specificDate: block.specificDate || '',
      dayOfWeek: block.dayOfWeek || 'Monday',
      isWholeDay: block.startTime === WHOLE_DAY_START && block.endTime === WHOLE_DAY_END,
      startTime: block.startTime,
      endTime: block.endTime,
      blockType: block.blockType,
      reason: block.reason || ''
    });
    // Switch to the matching tab so the user can see the item they're editing
    setActiveTab(block.isRecurring ? 'recurring' : 'onetime');
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsLoading(true);

    const payload = {
      adminID: adminID,
      isRecurring: form.isRecurring,
      specificDate: form.isRecurring ? null : form.specificDate,
      dayOfWeek: form.isRecurring ? form.dayOfWeek : null,
      startTime: form.isWholeDay ? WHOLE_DAY_START : form.startTime,
      endTime: form.isWholeDay ? WHOLE_DAY_END : form.endTime,
      blockType: form.blockType,
      reason: form.reason
    };

    try {
      // Don't let a block time swallow up a slot patients have already booked —
      // the doctor has to cancel those appointments (from Clinic Appointments) first.
      const blockStartMin = parseTimeToMinutes(payload.startTime);
      const blockEndMin = parseTimeToMinutes(payload.endTime);
      const todayStr = new Date().toISOString().slice(0, 10);

      const apptSnap = await getDocs(query(collection(db, 'Appointment'), where('adminID', '==', adminID)));
      const conflicts = apptSnap.docs
        .map(d => d.data())
        .filter(a => a.status !== 'Cancelled')
        .filter(a => payload.isRecurring
          ? a.appointmentDate >= todayStr && getDayOfWeek(a.appointmentDate) === payload.dayOfWeek
          : a.appointmentDate === payload.specificDate)
        .filter(a => {
          const slotStart = parseTimeToMinutes(a.appointmentTime);
          const slotEnd = slotStart + 30; // matches the 30-minute booking granularity used for appointments
          return slotStart < blockEndMin && slotEnd > blockStartMin;
        });

      if (conflicts.length > 0) {
        alert(`Cannot block this time — there ${conflicts.length === 1 ? 'is' : 'are'} ${conflicts.length} existing appointment${conflicts.length === 1 ? '' : 's'} in this slot. Please cancel ${conflicts.length === 1 ? 'it' : 'them'} first from Clinic Appointments.`);
        setIsLoading(false);
        return;
      }

      if (editingId) {
        await updateDoc(doc(db, 'BlockTime', editingId), payload);
      } else {
        await addDoc(collection(db, 'BlockTime'), payload);
      }
      setActiveTab(form.isRecurring ? 'recurring' : 'onetime');
      resetForm();
      fetchBlockTimes();
    } catch (error) {
      alert("Failed to save block time.");
      setIsLoading(false);
    }
  };

  const handleDelete = async (id: string) => {
    if (window.confirm("Are you sure you want to delete this block time? Patients will be able to book this slot again.")) {
      setIsLoading(true);
      try {
        await deleteDoc(doc(db, 'BlockTime', id));
        if (editingId === id) resetForm();
        fetchBlockTimes();
      } catch (error) {
        alert("Failed to delete block time.");
        setIsLoading(false);
      }
    }
  };

  const recurringBlocks = blockTimes
    .filter(b => b.isRecurring)
    .sort((a, b) => (dayOrder[a.dayOfWeek || ''] || 0) - (dayOrder[b.dayOfWeek || ''] || 0));
  const oneTimeBlocks = blockTimes.filter(b => !b.isRecurring);
  const visibleBlocks = activeTab === 'recurring' ? recurringBlocks : oneTimeBlocks;

  return (
    <div className="space-y-6 animate-fade-in">

      <div className="bg-white p-6 rounded-[24px] shadow-sm border border-gray-100 flex items-center space-x-4">
        <button onClick={() => navigate('/dashboard')} className="p-3 bg-gray-50 hover:bg-gray-100 text-gray-500 rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div>
          <h2 className="text-2xl font-black text-gray-800 tracking-wide">Manage Block Times</h2>
          <p className="text-sm text-gray-500 font-medium mt-1">Manage your leaves, breaks, and unbookable time slots.</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">

        <div className="lg:col-span-1 bg-white rounded-[24px] shadow-sm border border-gray-100 p-6">
          <div className="flex items-center justify-between mb-6">
            <h3 className="text-lg font-bold text-gray-800 flex items-center">
              <ShieldBan className="w-5 h-5 mr-2 text-red-600" />
              {editingId ? 'Edit Block Time' : 'Add Block Time'}
            </h3>
            {editingId && (
              <button onClick={resetForm} className="text-xs font-bold text-gray-400 hover:text-gray-600">
                Cancel
              </button>
            )}
          </div>

          <form onSubmit={handleSave} className="space-y-4">
            <div className="flex items-center p-3 bg-gray-50 rounded-xl border border-gray-100">
              <input type="checkbox" id="recurring" checked={form.isRecurring} onChange={e => setForm({ ...form, isRecurring: e.target.checked })} className="w-5 h-5 text-red-600 rounded focus:ring-red-500" />
              <label htmlFor="recurring" className="ml-3 text-sm font-bold text-gray-700 cursor-pointer">Block this time every week</label>
            </div>

            {form.isRecurring ? (
              <div>
                <label className="block text-xs font-bold text-gray-500 uppercase mb-2">Day of Week</label>
                <select required value={form.dayOfWeek} onChange={e => setForm({ ...form, dayOfWeek: e.target.value })} className="w-full p-3 bg-gray-50 rounded-xl outline-none focus:ring-2 focus:ring-red-200">
                  <option>Monday</option><option>Tuesday</option><option>Wednesday</option><option>Thursday</option><option>Friday</option><option>Saturday</option><option>Sunday</option>
                </select>
              </div>
            ) : (
              <div>
                <label className="block text-xs font-bold text-gray-500 uppercase mb-2">Specific Date</label>
                <input required type="date" value={form.specificDate} onChange={e => setForm({ ...form, specificDate: e.target.value })} className="w-full p-3 bg-gray-50 rounded-xl outline-none focus:ring-2 focus:ring-red-200" />
              </div>
            )}

            <div className="flex items-center p-3 bg-gray-50 rounded-xl border border-gray-100">
              <input type="checkbox" id="wholeDay" checked={form.isWholeDay} onChange={e => setForm({ ...form, isWholeDay: e.target.checked })} className="w-5 h-5 text-red-600 rounded focus:ring-red-500" />
              <label htmlFor="wholeDay" className="ml-3 text-sm font-bold text-gray-700 cursor-pointer">Block the whole day</label>
            </div>

            {!form.isWholeDay && (
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-bold text-gray-500 uppercase mb-2">Start Time</label>
                  <input required type="time" value={form.startTime} onChange={e => setForm({ ...form, startTime: e.target.value })} className="w-full p-3 bg-gray-50 rounded-xl outline-none focus:ring-2 focus:ring-red-200" />
                </div>
                <div>
                  <label className="block text-xs font-bold text-gray-500 uppercase mb-2">End Time</label>
                  <input required type="time" value={form.endTime} onChange={e => setForm({ ...form, endTime: e.target.value })} className="w-full p-3 bg-gray-50 rounded-xl outline-none focus:ring-2 focus:ring-red-200" />
                </div>
              </div>
            )}

            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase mb-2">Block Type</label>
              <select value={form.blockType} onChange={e => setForm({ ...form, blockType: e.target.value })} className="w-full p-3 bg-gray-50 rounded-xl outline-none focus:ring-2 focus:ring-red-200">
                <option>Break</option><option>Meeting</option><option>Emergency</option><option>Personal Leave</option>
              </select>
            </div>

            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase mb-2">Reason (Optional)</label>
              <input type="text" placeholder="e.g., Dental Appointment" value={form.reason} onChange={e => setForm({ ...form, reason: e.target.value })} className="w-full p-3 bg-gray-50 rounded-xl outline-none focus:ring-2 focus:ring-red-200" />
            </div>

            <button type="submit" disabled={isLoading} className="w-full mt-4 py-3 bg-red-600 hover:bg-red-700 text-white font-bold rounded-xl shadow-md transition-colors disabled:opacity-50">
              {isLoading ? 'Saving...' : editingId ? 'Update Block Time' : 'Save Block Time'}
            </button>
          </form>
        </div>

        <div className="lg:col-span-2 bg-white rounded-[24px] shadow-sm border border-gray-100 overflow-hidden">
          <div className="flex items-center space-x-2 p-4 border-b border-gray-100">
            <button
              onClick={() => setActiveTab('recurring')}
              className={`flex items-center px-4 py-2 rounded-xl text-sm font-bold transition-colors ${activeTab === 'recurring' ? 'bg-blue-50 text-blue-600' : 'text-gray-400 hover:bg-gray-50'}`}
            >
              <RefreshCw className="w-4 h-4 mr-1.5" /> Recurring ({recurringBlocks.length})
            </button>
            <button
              onClick={() => setActiveTab('onetime')}
              className={`flex items-center px-4 py-2 rounded-xl text-sm font-bold transition-colors ${activeTab === 'onetime' ? 'bg-orange-50 text-orange-600' : 'text-gray-400 hover:bg-gray-50'}`}
            >
              <CalendarDays className="w-4 h-4 mr-1.5" /> One-Time ({oneTimeBlocks.length})
            </button>
          </div>

          {isLoading ? (
            <div className="flex justify-center items-center h-64"><Loader2 className="w-8 h-8 animate-spin text-red-600" /></div>
          ) : visibleBlocks.length === 0 ? (
            <div className="p-12 text-center">
              <ShieldBan className="w-16 h-16 text-gray-300 mx-auto mb-4" />
              <p className="text-gray-500 font-medium">
                {activeTab === 'recurring' ? 'No recurring block times configured.' : 'No one-time block times configured.'}
              </p>
            </div>
          ) : (
            <div className="divide-y divide-gray-100">
              {visibleBlocks.map((block) => (
                <div key={block.id} className={`flex items-center justify-between px-6 py-5 hover:bg-gray-50 transition-colors ${editingId === block.id ? 'bg-red-50/50' : ''}`}>
                  <div className="flex items-center space-x-4">
                    <div className="p-2 bg-gray-100 rounded-lg"><ShieldBan className="w-4 h-4 text-gray-500" /></div>
                    <div>
                      <p className="font-bold text-gray-800 uppercase text-sm">{block.blockType}</p>
                      <p className="text-xs text-gray-400">{block.reason || 'No reason provided'}</p>
                      <div className="flex items-center space-x-3 mt-2">
                        {block.isRecurring ? (
                          <span className="flex items-center text-blue-600 font-bold bg-blue-50 w-max px-3 py-1 rounded-md text-xs">
                            <RefreshCw className="w-3 h-3 mr-1.5" /> Every {block.dayOfWeek}
                          </span>
                        ) : (
                          <span className="flex items-center text-orange-600 font-bold bg-orange-50 w-max px-3 py-1 rounded-md text-xs">
                            <CalendarDays className="w-3 h-3 mr-1.5" /> {block.specificDate}
                          </span>
                        )}
                        <span className="flex items-center text-gray-600 font-bold text-xs">
                          <Clock className="w-3 h-3 mr-1.5 text-gray-400" />
                          {block.startTime === WHOLE_DAY_START && block.endTime === WHOLE_DAY_END ? 'Whole Day' : `${block.startTime} - ${block.endTime}`}
                        </span>
                      </div>
                    </div>
                  </div>
                  <div className="flex items-center space-x-2 flex-shrink-0">
                    <button onClick={() => loadFormForEdit(block)} className="p-2 text-blue-500 hover:bg-blue-50 rounded-lg">
                      <Edit className="w-5 h-5" />
                    </button>
                    <button onClick={() => handleDelete(block.id)} className="p-2 text-red-500 hover:bg-red-50 rounded-lg">
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

export default DoctorBlockTimes;
