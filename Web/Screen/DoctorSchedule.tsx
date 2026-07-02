import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { User, CalendarDays, Loader2, PlayCircle, CheckSquare, ShieldBan, CalendarRange } from 'lucide-react';
import { collection, query, where, getDocs, doc, getDoc, updateDoc } from 'firebase/firestore';
import { auth, db } from '../firebaseConfig';

interface TimelineItem {
  id: string;
  time: string;
  date: string;
  sortTime: number; 
  type: 'Appointment' | 'BlockTime'; 
  patientName?: string;
  status?: string;
  apptType?: string;
  reason?: string;
  blockType?: string;
}

const DoctorSchedule: React.FC = () => {
  const navigate = useNavigate();
  const [timelineItems, setTimelineItems] = useState<TimelineItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [doctorName, setDoctorName] = useState<string>('');
  const [adminID, setAdminID] = useState<string>(''); 

  // ⚠️ 权限控制：从本地缓存读取当前登录者的角色
  // 注意：User.userRole 登录后统一是 'Admin'，Admin/Doctor 细分要看 Administrator.adminRole
  const currentUserRole = localStorage.getItem('adminRole') || '';
  const isDoctor = currentUserRole === 'Doctor';

  useEffect(() => {
    // 如果不是医生，就根本不要去请求数据库，直接停止
    if (!isDoctor) return;
    
    fetchDailyData();
  }, [isDoctor]);

  const fetchDailyData = async () => {
    setIsLoading(true);
    try {
      const currentUser = auth.currentUser;
      if (!currentUser) throw new Error("No user logged in");
      setAdminID(currentUser.uid); 

      const adminDoc = await getDoc(doc(db, 'User', currentUser.uid)); 
      let currentDoctorName = adminDoc.exists() ? adminDoc.data().adminName : "Unknown Doctor";
      setDoctorName(currentDoctorName);

      const todayDateObj = new Date();
      const todayStr = todayDateObj.toISOString().split('T')[0]; 
      const todayDayOfWeek = todayDateObj.toLocaleDateString('en-US', { weekday: 'long' }); 

      // 【核心安全逻辑 1】：这里限制了只能抓取 doctorName 是自己的预约
      const apptQuery = query(collection(db, 'Appointment'), where('doctorName', '==', currentDoctorName));
      const apptSnapshot = await getDocs(apptQuery);
      const appointments: TimelineItem[] = apptSnapshot.docs.map(doc => {
        const data = doc.data();
        return {
          id: doc.id, type: 'Appointment', patientName: data.patientName || 'Unknown',
          time: data.time || '00:00', date: data.date || todayStr, status: data.status || 'Pending',
          apptType: data.type || 'Consultation', sortTime: new Date(`${data.date || todayStr} ${data.time || '00:00'}`).getTime()
        };
      });

      // 【核心安全逻辑 2】：这里限制了只能抓取 adminID 是自己的 BlockTime
      const blockQuery = query(collection(db, 'BlockTime'), where('adminID', '==', currentUser.uid));
      const blockSnapshot = await getDocs(blockQuery);
      
      const blockTimes: TimelineItem[] = [];
      
      blockSnapshot.docs.forEach(doc => {
        const data = doc.data();
        let isMatchForToday = false;

        if (data.isRecurring) {
          isMatchForToday = data.dayOfWeek === todayDayOfWeek;
        } else {
          isMatchForToday = data.specificDate === todayStr;
        }

        if (isMatchForToday) {
          blockTimes.push({
            id: doc.id, type: 'BlockTime', time: data.startTime || '00:00', date: todayStr, 
            reason: data.reason || 'Blocked', blockType: data.blockType || 'Unavailable', 
            sortTime: new Date(`${todayStr} ${data.startTime || '00:00'}`).getTime()
          });
        }
      });

      const combinedTimeline = [...appointments, ...blockTimes].sort((a, b) => a.sortTime - b.sortTime);
      setTimelineItems(combinedTimeline);

    } catch (error) {
      console.error("Error fetching timeline data:", error);
    } finally {
      setIsLoading(false);
    }
  };

  const updateAppointmentStatus = async (id: string, newStatus: string) => {
    try {
      setIsLoading(true);
      await updateDoc(doc(db, 'Appointment', id), { status: newStatus });
      fetchDailyData();
    } catch (error) {
      setIsLoading(false);
    }
  };

  // ⚠️ 权限拦截 UI：如果不是医生，显示拒绝访问的画面
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

  const todayDisplayString = new Date().toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'short', day: 'numeric' });

  return (
    <div className="space-y-6 animate-fade-in relative">
      
      <div className="bg-white p-8 rounded-[30px] shadow-sm border border-gray-100 flex justify-between items-end">
        <div>
          <h2 className="text-2xl font-black text-gray-800">{doctorName ? `${doctorName}'s Schedule` : 'My Daily Schedule'}</h2>
          <p className="text-gray-400 text-sm mt-1">{todayDisplayString}</p>
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

      <div className="space-y-4">
        {isLoading ? (
          <div className="flex justify-center items-center h-40"><Loader2 className="w-8 h-8 animate-spin text-green-600" /></div>
        ) : timelineItems.length === 0 ? (
          <div className="bg-white p-10 rounded-[25px] border border-gray-100 shadow-sm text-center">
            <CalendarDays className="w-12 h-12 text-gray-300 mx-auto mb-3" />
            <p className="text-gray-500 font-medium">Your schedule is clear for today.</p>
          </div>
        ) : (
          timelineItems.map((item) => {
            if (item.type === 'BlockTime') {
              return (
                <div key={item.id} className="flex items-center p-6 rounded-[25px] border-2 border-dashed border-gray-200 bg-gray-50 opacity-80">
                  <div className="w-32 border-r border-gray-200 mr-8 flex flex-col justify-center">
                    <p className="font-black text-gray-500 text-lg">{item.time}</p>
                    <p className="text-xs text-gray-400 font-bold mt-1">{item.date}</p>
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

            const isInProgress = item.status === 'In Progress';
            const isCompleted = item.status === 'Completed' || item.status === 'Cancelled';
            
            return (
              <div key={item.id} className={`flex items-center p-6 rounded-[25px] border-2 transition-all duration-300 ${
                isInProgress ? 'border-green-500 bg-white shadow-xl scale-[1.01] z-10 relative' : 
                isCompleted ? 'border-gray-50 bg-gray-50 opacity-70' : 'border-transparent bg-white shadow-sm hover:border-green-100'
              }`}>
                <div className="w-32 border-r border-gray-100 mr-8 flex flex-col justify-center">
                  <p className="font-black text-gray-800 text-lg">{item.time}</p>
                  <p className="text-xs text-gray-400 font-bold mt-1">{item.date}</p>
                </div>
                <div className="flex-1 flex items-center justify-between">
                  <div className="flex items-center space-x-4">
                    <div className={`p-3 rounded-xl ${isInProgress ? 'bg-green-600 text-white shadow-md' : 'bg-green-100 text-green-600'}`}>
                      <User className="w-5 h-5" />
                    </div>
                    <div>
                      <p className={`font-bold text-lg ${isCompleted ? 'text-gray-500 line-through' : 'text-gray-800'}`}>{item.patientName}</p>
                      <div className="flex items-center mt-1 space-x-2">
                        <span className="text-xs text-gray-500 font-bold bg-gray-100 px-2 py-0.5 rounded-md">{item.apptType}</span>
                        <span className={`text-xs font-bold px-2 py-0.5 rounded-md ${item.status === 'Confirmed' ? 'bg-blue-50 text-blue-600' : item.status === 'Pending' ? 'bg-orange-50 text-orange-600' : ''}`}>{item.status}</span>
                      </div>
                    </div>
                  </div>
                  <div className="flex items-center">
                    {item.status === 'Confirmed' && (
                      <button onClick={() => updateAppointmentStatus(item.id, 'In Progress')} className="flex items-center space-x-1 bg-gray-900 text-white px-5 py-2.5 rounded-xl font-bold text-xs hover:bg-black">
                        <PlayCircle className="w-4 h-4" /><span>Start Call</span>
                      </button>
                    )}
                    {item.status === 'In Progress' && (
                      <button onClick={() => updateAppointmentStatus(item.id, 'Completed')} className="flex items-center space-x-1 bg-green-600 text-white px-5 py-2.5 rounded-xl font-bold text-xs hover:bg-green-700 animate-pulse">
                        <CheckSquare className="w-4 h-4" /><span>Mark Completed</span>
                      </button>
                    )}
                  </div>
                </div>
              </div>
            );
          })
        )}
      </div>

    </div>
  );
};

export default DoctorSchedule;