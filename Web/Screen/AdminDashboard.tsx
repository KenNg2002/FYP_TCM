import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { signOut } from 'firebase/auth';
import { doc, getDoc } from 'firebase/firestore';
import { auth, db } from '../firebaseConfig';
import { registerWebPushToken } from '../notifications';

import ClinicAppointments from './ClinicAppointments';
import AllAppointments from './AllAppointments';
import HerbalProducts from './HerbalProducts';
import OrdersDelivery from './OrdersDelivery';
import DiagnosisReview from './DiagnosisReview';
import DoctorSchedule from './DoctorSchedule';
import RegisterAdmin from './RegisterAdmin';
import RegisterDoctor from './RegisterDoctor';
import RegisterDeliveryMan from './RegisterDeliveryMan';
import MyProfile from './MyProfile';
import RefundManagement from './RefundManagement';

import {
  LayoutDashboard, Leaf, ShoppingCart, CalendarCheck,
  Users, LogOut, Search, Bell, CalendarDays, ShieldCheck, Stethoscope, Bike, UserCircle, Undo2
} from 'lucide-react';

import { DashboardCharts } from './DashboardCharts';

// Administrator.adminRole determines which menu items are visible:
// - Admin: product/order/personnel registration related
// - Doctor: own schedule, diagnosis review, clinic appointments
const menuConfig: { name: string; icon: any; roles: Array<'Admin' | 'Doctor'> }[] = [
  { name: 'Dashboard', icon: LayoutDashboard, roles: ['Admin', 'Doctor'] },
  { name: 'Diagnosis Review', icon: Search, roles: ['Doctor'] },
  { name: 'My Schedule', icon: CalendarDays, roles: ['Doctor'] },
  { name: 'Clinic Appointments', icon: CalendarCheck, roles: ['Doctor'] },
  { name: 'All Appointments', icon: CalendarCheck, roles: ['Admin'] },
  { name: 'Herbal Products', icon: Leaf, roles: ['Admin'] },
  { name: 'Orders & Delivery', icon: ShoppingCart, roles: ['Admin'] },
  { name: 'Register Admin', icon: ShieldCheck, roles: ['Admin'] },
  { name: 'Register Doctor', icon: Stethoscope, roles: ['Admin'] },
  { name: 'Register Delivery Man', icon: Bike, roles: ['Admin'] },
  { name: 'Cancellations & Refunds', icon: Undo2, roles: ['Admin'] },
  { name: 'My Profile', icon: UserCircle, roles: ['Admin', 'Doctor'] },
];

const AdminDashboard: React.FC = () => {
  // Administrator.adminRole, stored at login time (see AdminLogin.tsx)
  const adminRole = (localStorage.getItem('adminRole') as 'Admin' | 'Doctor') || 'Doctor';
  const menuItems = menuConfig.filter((item) => item.roles.includes(adminRole));

  const [activeMenu, setActiveMenu] = useState(menuItems[0]?.name ?? 'Dashboard');
  const [photoURL, setPhotoURL] = useState<string | null>(null);
  const navigate = useNavigate();

  useEffect(() => {
    registerWebPushToken();
  }, []);

  useEffect(() => {
    const fetchAvatar = async () => {
      const uid = auth.currentUser?.uid;
      if (!uid) return;
      const userSnap = await getDoc(doc(db, 'User', uid));
      if (userSnap.exists()) {
        setPhotoURL(userSnap.data().photoURL || null);
      }
    };
    fetchAvatar();
  }, []);

  const handleLogout = async () => {
    try {
      await signOut(auth);

      // Clear locally stored userRole / adminRole to prevent permission leakage
      localStorage.removeItem('userRole');
      localStorage.removeItem('adminRole');

      navigate('/login', { replace: true });
    } catch (error) {
      console.error("Error logging out:", error);
      alert("Failed to log out. Please try again.");
    }
  };

  return (
    <div className="flex h-screen bg-gray-50 font-sans">
      <aside className="w-64 bg-gray-900 text-white flex flex-col shadow-xl">
        <div className="h-20 flex items-center px-6 border-b border-gray-800">
          <div className="w-8 h-8 rounded-lg overflow-hidden mr-3">
            <img src="/logo.png" alt="SH Wellness" className="w-full h-full object-cover" />
          </div>
          <span className="text-xl font-bold tracking-wider">SH Wellness</span>
        </div>

        <nav className="flex-1 py-6 space-y-2 px-3">
          {menuItems.map((item) => {
            const Icon = item.icon;
            const isActive = activeMenu === item.name;
            return (
              <button
                key={item.name}
                onClick={() => setActiveMenu(item.name)}
                className={`w-full flex items-center px-4 py-3 rounded-xl transition-all duration-200 ${
                  isActive ? 'bg-green-600 text-white shadow-md' : 'text-gray-400 hover:bg-gray-800 hover:text-white'
                }`}
              >
                <Icon className={`w-5 h-5 mr-3 ${isActive ? 'text-white' : 'text-gray-400'}`} />
                <span className="font-medium text-sm">{item.name}</span>
              </button>
            );
          })}
        </nav>

        <div className="p-4 border-t border-gray-800">
          <button 
            onClick={handleLogout}
            className="w-full flex items-center px-4 py-3 text-red-400 hover:bg-red-500 hover:text-white rounded-xl transition-colors"
          >
            <LogOut className="w-5 h-5 mr-3" />
            <span className="font-medium text-sm">Log Out</span>
          </button>
        </div>
      </aside>

      <main className="flex-1 flex flex-col overflow-hidden">
        <header className="h-20 bg-white shadow-sm flex items-center justify-between px-8">
          <h1 className="text-2xl font-bold text-gray-800">{activeMenu} Overview</h1>
          <div className="flex items-center space-x-6">
            <div className="w-10 h-10 rounded-full bg-gray-100 flex items-center justify-center overflow-hidden">
              {photoURL ? (
                <img src={photoURL} alt="Profile" className="w-full h-full object-cover" />
              ) : (
                <UserCircle className="w-7 h-7 text-gray-400" />
              )}
            </div>
          </div>
        </header>

        <div className="flex-1 overflow-auto p-8">
          {activeMenu === 'Dashboard' && (
            <div className="space-y-6">
                <div className="flex justify-between items-center mb-4">
                <h2 className="text-xl font-black text-gray-800">Performance Summary: April 2026</h2>
                <span className="bg-green-100 text-green-700 px-4 py-1.5 rounded-full text-xs font-bold border border-green-200">
                    Status: Data Synchronized
                </span>
                </div>

                <div className="grid grid-cols-4 gap-6">
                <StatCard title="Monthly Revenue" value="RM 24,580" trend="+12.5%" isUp={true} color="bg-blue-50 text-blue-600" />
                <StatCard title="Total Orders" value="342" trend="+8.3%" isUp={true} color="bg-orange-50 text-orange-600" />
                <StatCard title="AI Scans" value="1,120" trend="+24.1%" isUp={true} color="bg-green-50 text-green-600" />
                <StatCard title="Appointments" value="86" trend="-2.4%" isUp={false} color="bg-purple-50 text-purple-600" />
                </div>
                <DashboardCharts />
            </div>
          )}

          {activeMenu === 'My Schedule' && <DoctorSchedule />}
          {activeMenu === 'Diagnosis Review' && <DiagnosisReview />}
          {activeMenu === 'Herbal Products' && <HerbalProducts />}
          {activeMenu === 'Orders & Delivery' && <OrdersDelivery />}
          {activeMenu === 'Clinic Appointments' && <ClinicAppointments />}
          {activeMenu === 'All Appointments' && <AllAppointments />}
          {activeMenu === 'Register Admin' && <RegisterAdmin />}
          {activeMenu === 'Register Doctor' && <RegisterDoctor />}
          {activeMenu === 'Register Delivery Man' && <RegisterDeliveryMan />}
          {activeMenu === 'Cancellations & Refunds' && <RefundManagement />}
          {activeMenu === 'My Profile' && <MyProfile />}

          {activeMenu === 'Users & Riders' && (
            <div className="flex items-center justify-center h-full text-gray-400 text-xl font-medium">
              Users & Riders Management System Coming Soon...
            </div>
          )}
        </div>
      </main>
    </div>
  );
};

const StatCard = ({ title, value, trend, isUp, color }: any) => (
  <div className="bg-white p-6 rounded-[30px] shadow-sm border border-gray-100 relative overflow-hidden group hover:shadow-lg transition-all">
    <div className="relative z-10">
      <p className="text-xs font-black text-gray-400 uppercase tracking-widest mb-1">{title}</p>
      <p className="text-2xl font-black text-gray-800">{value}</p>
      <div className={`flex items-center mt-2 text-[10px] font-bold ${isUp ? 'text-green-500' : 'text-red-500'}`}>
        {isUp ? '▲' : '▼'} {trend} <span className="text-gray-300 ml-1">vs last month</span>
      </div>
    </div>
    <div className={`absolute -right-4 -bottom-4 w-24 h-24 rounded-full opacity-10 ${color.split(' ')[0]}`}></div>
  </div>
);

export default AdminDashboard;