import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, Plus, Trash2, Clock, ShieldBan, Loader2, X, Edit, CalendarDays, RefreshCw } from 'lucide-react';
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

const DoctorBlockTimes: React.FC = () => {
  const navigate = useNavigate();
  const [blockTimes, setBlockTimes] = useState<BlockTime[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [adminID, setAdminID] = useState<string>('');

  // 弹窗与表单状态
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  
  const [form, setForm] = useState({
    isRecurring: false,
    specificDate: '',
    dayOfWeek: 'Monday',
    startTime: '',
    endTime: '',
    blockType: 'Break',
    reason: ''
  });

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

      // 简单的排序：把 Recurring 放前面，Specific Date 放后面
      fetchedBlocks.sort((a, b) => (a.isRecurring === b.isRecurring) ? 0 : a.isRecurring ? -1 : 1);
      
      setBlockTimes(fetchedBlocks);
    } catch (error) {
      console.error("Error fetching block times:", error);
    } finally {
      setIsLoading(false);
    }
  };

  const openNewModal = () => {
    setEditingId(null);
    setForm({ isRecurring: false, specificDate: '', dayOfWeek: 'Monday', startTime: '', endTime: '', blockType: 'Break', reason: '' });
    setIsModalOpen(true);
  };

  const openEditModal = (block: BlockTime) => {
    setEditingId(block.id);
    setForm({ 
      isRecurring: block.isRecurring,
      specificDate: block.specificDate || '',
      dayOfWeek: block.dayOfWeek || 'Monday',
      startTime: block.startTime,
      endTime: block.endTime,
      blockType: block.blockType,
      reason: block.reason || ''
    });
    setIsModalOpen(true);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsLoading(true);

    const payload = {
      adminID: adminID,
      isRecurring: form.isRecurring,
      specificDate: form.isRecurring ? null : form.specificDate,
      dayOfWeek: form.isRecurring ? form.dayOfWeek : null,
      startTime: form.startTime,
      endTime: form.endTime,
      blockType: form.blockType,
      reason: form.reason
    };

    try {
      if (editingId) {
        await updateDoc(doc(db, 'BlockTime', editingId), payload);
      } else {
        await addDoc(collection(db, 'BlockTime'), payload);
      }
      setIsModalOpen(false);
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
        fetchBlockTimes();
      } catch (error) {
        alert("Failed to delete block time.");
        setIsLoading(false);
      }
    }
  };

  return (
    <div className="space-y-6 animate-fade-in relative">
      
      <div className="bg-white p-6 rounded-[24px] shadow-sm border border-gray-100 flex items-center justify-between">
        <div className="flex items-center space-x-4">
          <button onClick={() => navigate('/dashboard')} className="p-3 bg-gray-50 hover:bg-gray-100 text-gray-500 rounded-xl transition-colors">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <div>
            <h2 className="text-2xl font-black text-gray-800 tracking-wide">Manage Block Times</h2>
            <p className="text-sm text-gray-500 font-medium mt-1">Manage your leaves, breaks, and unbookable time slots.</p>
          </div>
        </div>
        <button onClick={openNewModal} className="flex items-center bg-red-600 hover:bg-red-700 text-white px-5 py-3 rounded-xl font-bold text-sm shadow-md transition-colors">
          <Plus className="w-5 h-5 mr-1" /> Add Block Time
        </button>
      </div>

      <div className="bg-white rounded-[24px] shadow-sm border border-gray-100 overflow-hidden">
        {isLoading ? (
          <div className="flex justify-center items-center h-64"><Loader2 className="w-8 h-8 animate-spin text-red-600" /></div>
        ) : blockTimes.length === 0 ? (
          <div className="p-12 text-center">
            <ShieldBan className="w-16 h-16 text-gray-300 mx-auto mb-4" />
            <p className="text-gray-500 font-medium">No block times configured.</p>
          </div>
        ) : (
          <table className="w-full text-sm text-left text-gray-500">
            <thead className="text-xs text-gray-700 uppercase bg-gray-50 border-b border-gray-100">
              <tr>
                <th className="px-6 py-5">Type / Reason</th>
                <th className="px-6 py-5">When (Date / Day)</th>
                <th className="px-6 py-5">Time</th>
                <th className="px-6 py-5 text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              {blockTimes.map((block) => (
                <tr key={block.id} className="border-b hover:bg-gray-50 transition-colors">
                  <td className="px-6 py-5">
                    <div className="flex items-center space-x-3">
                      <div className="p-2 bg-gray-100 rounded-lg"><ShieldBan className="w-4 h-4 text-gray-500"/></div>
                      <div>
                        <p className="font-bold text-gray-800 uppercase">{block.blockType}</p>
                        <p className="text-xs text-gray-400">{block.reason || 'No reason provided'}</p>
                      </div>
                    </div>
                  </td>
                  <td className="px-6 py-5">
                    {block.isRecurring ? (
                      <span className="flex items-center text-blue-600 font-bold bg-blue-50 w-max px-3 py-1 rounded-md">
                        <RefreshCw className="w-3 h-3 mr-1.5" /> Every {block.dayOfWeek}
                      </span>
                    ) : (
                      <span className="flex items-center text-orange-600 font-bold bg-orange-50 w-max px-3 py-1 rounded-md">
                        <CalendarDays className="w-3 h-3 mr-1.5" /> {block.specificDate}
                      </span>
                    )}
                  </td>
                  <td className="px-6 py-5 font-bold text-gray-700">
                    <div className="flex items-center"><Clock className="w-4 h-4 mr-1.5 text-gray-400"/> {block.startTime} - {block.endTime}</div>
                  </td>
                  <td className="px-6 py-5 text-right space-x-2">
                    <button onClick={() => openEditModal(block)} className="p-2 text-blue-500 hover:bg-blue-50 rounded-lg inline-block">
                      <Edit className="w-5 h-5" />
                    </button>
                    <button onClick={() => handleDelete(block.id)} className="p-2 text-red-500 hover:bg-red-50 rounded-lg inline-block">
                      <Trash2 className="w-5 h-5" />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {isModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-40 backdrop-blur-sm">
          <div className="bg-white rounded-[24px] shadow-2xl w-full max-w-md p-8 animate-fade-in">
            <div className="flex justify-between items-center mb-6">
              <h2 className="text-xl font-bold text-gray-800 flex items-center"><ShieldBan className="mr-2 text-red-600"/> {editingId ? 'Edit Block Time' : 'New Block Time'}</h2>
              <button onClick={() => setIsModalOpen(false)} className="text-gray-400 hover:bg-gray-100 p-2 rounded-full"><X className="w-5 h-5" /></button>
            </div>
            
            <form onSubmit={handleSave} className="space-y-4">
              <div className="flex items-center p-3 bg-gray-50 rounded-xl border border-gray-100">
                <input type="checkbox" id="recurring" checked={form.isRecurring} onChange={e => setForm({...form, isRecurring: e.target.checked})} className="w-5 h-5 text-red-600 rounded focus:ring-red-500" />
                <label htmlFor="recurring" className="ml-3 text-sm font-bold text-gray-700 cursor-pointer">Block this time every week</label>
              </div>

              {form.isRecurring ? (
                <div>
                  <label className="block text-xs font-bold text-gray-500 uppercase mb-2">Day of Week</label>
                  <select required value={form.dayOfWeek} onChange={e => setForm({...form, dayOfWeek: e.target.value})} className="w-full p-3 bg-gray-50 rounded-xl outline-none focus:ring-2 focus:ring-red-200">
                    <option>Monday</option><option>Tuesday</option><option>Wednesday</option><option>Thursday</option><option>Friday</option><option>Saturday</option><option>Sunday</option>
                  </select>
                </div>
              ) : (
                <div>
                  <label className="block text-xs font-bold text-gray-500 uppercase mb-2">Specific Date</label>
                  <input required type="date" value={form.specificDate} onChange={e => setForm({...form, specificDate: e.target.value})} className="w-full p-3 bg-gray-50 rounded-xl outline-none focus:ring-2 focus:ring-red-200" />
                </div>
              )}

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-bold text-gray-500 uppercase mb-2">Start Time</label>
                  <input required type="time" value={form.startTime} onChange={e => setForm({...form, startTime: e.target.value})} className="w-full p-3 bg-gray-50 rounded-xl outline-none focus:ring-2 focus:ring-red-200" />
                </div>
                <div>
                  <label className="block text-xs font-bold text-gray-500 uppercase mb-2">End Time</label>
                  <input required type="time" value={form.endTime} onChange={e => setForm({...form, endTime: e.target.value})} className="w-full p-3 bg-gray-50 rounded-xl outline-none focus:ring-2 focus:ring-red-200" />
                </div>
              </div>

              <div>
                <label className="block text-xs font-bold text-gray-500 uppercase mb-2">Block Type</label>
                <select value={form.blockType} onChange={e => setForm({...form, blockType: e.target.value})} className="w-full p-3 bg-gray-50 rounded-xl outline-none focus:ring-2 focus:ring-red-200">
                  <option>Break</option><option>Meeting</option><option>Emergency</option><option>Personal Leave</option>
                </select>
              </div>
              
              <div>
                <label className="block text-xs font-bold text-gray-500 uppercase mb-2">Reason (Optional)</label>
                <input type="text" placeholder="e.g., Dental Appointment" value={form.reason} onChange={e => setForm({...form, reason: e.target.value})} className="w-full p-3 bg-gray-50 rounded-xl outline-none focus:ring-2 focus:ring-red-200" />
              </div>
              
              <button type="submit" disabled={isLoading} className="w-full mt-4 py-3 bg-red-600 hover:bg-red-700 text-white font-bold rounded-xl shadow-md transition-colors disabled:opacity-50">
                {isLoading ? 'Saving...' : 'Save Block Time'}
              </button>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};

export default DoctorBlockTimes;