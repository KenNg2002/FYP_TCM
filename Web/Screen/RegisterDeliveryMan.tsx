import React, { useState } from 'react';
import { Bike, Mail, Lock, User, Phone, CreditCard, Loader2, FileText } from 'lucide-react';
import { initializeApp } from 'firebase/app';
import { getAuth, createUserWithEmailAndPassword, signOut } from 'firebase/auth';
import { doc, writeBatch, serverTimestamp } from 'firebase/firestore';
import { db, firebaseConfig } from '../firebaseConfig';
import Toast from './Toast';

// 🔥 创建副引擎，专门用于静默注册，防止 Admin 当前账号被踢出
const secondaryApp = initializeApp(firebaseConfig, "SecondaryApp_Delivery");
const secondaryAuth = getAuth(secondaryApp);

const RegisterDeliveryMan: React.FC = () => {
  const [isLoading, setIsLoading] = useState(false);
  const [successMsg, setSuccessMsg] = useState('');
  const [errorMsg, setErrorMsg] = useState('');

  const [formData, setFormData] = useState({
    username: '',
    userEmail: '',
    password: '',
    userPhoneNum: '',
    vehiclePlateNum: '',
    drivingLicense: ''
  });

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsLoading(true);
    setSuccessMsg('');
    setErrorMsg('');

    try {
      // 1. 使用副引擎在 Firebase Auth 创建账号
      const userCredential = await createUserWithEmailAndPassword(
        secondaryAuth, 
        formData.userEmail, 
        formData.password
      );
      
      const newDeliveryManUid = userCredential.user.uid;

      // 2. 准备 Batch Write (批处理)，同时写入两个 Table
      const batch = writeBatch(db);

      // A. 写入 User Table
      const userRef = doc(db, 'User', newDeliveryManUid);
      batch.set(userRef, {
        userID: newDeliveryManUid, // 与 Document ID 保持一致
        username: formData.username,
        userEmail: formData.userEmail,
        userPhoneNum: formData.userPhoneNum,
        userRole: 'DeliveryMan', 
        accountStatus: 'Active',
        userRegistedDate: serverTimestamp()
      });

      // B. 写入 DeliveryMan Table
      const deliveryManRef = doc(db, 'DeliveryMan', newDeliveryManUid);
      batch.set(deliveryManRef, {
        deliverymanID: newDeliveryManUid, // 关联 User 表的主键
        vehiclePlateNum: formData.vehiclePlateNum.toUpperCase(), // 车牌号自动转大写
        drivingLicense: formData.drivingLicense,
        currentAvailability: 'Offline' // 刚注册完默认不接单，等他自己用手机 App 上线
      });

      // 执行所有写入操作
      await batch.commit();

      // 3. 登出副引擎
      await signOut(secondaryAuth);

      // 4. UI 提示并清空表单
      setSuccessMsg(`Delivery Man ${formData.username} has been successfully registered!`);
      setFormData({ username: '', userEmail: '', password: '', userPhoneNum: '', vehiclePlateNum: '', drivingLicense: '' });

    } catch (error: any) {
      console.error("Registration Error:", error);
      if (error.code === 'auth/email-already-in-use') {
        setErrorMsg('This email is already registered to another user.');
      } else if (error.code === 'auth/weak-password') {
        setErrorMsg('Password should be at least 6 characters.');
      } else {
        setErrorMsg('Failed to register delivery man. Please try again.');
      }
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="space-y-6 animate-fade-in relative">
      
      {/* 顶部标题区 */}
      <div className="bg-white p-8 rounded-[30px] shadow-sm border border-gray-100">
        <h2 className="text-2xl font-black text-gray-800 flex items-center">
          <Bike className="w-7 h-7 mr-3 text-orange-500" /> 
          Register Delivery Rider
        </h2>
        <p className="text-gray-400 text-sm mt-2">
          Create a new account for logistics and delivery personnel. The rider will be able to access the delivery app.
        </p>
      </div>

      {/* 注册表单 */}
      <div className="bg-white p-8 rounded-[30px] shadow-sm border border-gray-100 max-w-3xl">
        
        {successMsg && <Toast type="success" message={successMsg} onDismiss={() => setSuccessMsg('')} />}
        {errorMsg && <Toast type="error" message={errorMsg} onDismiss={() => setErrorMsg('')} />}

        <form onSubmit={handleRegister} className="space-y-6">
          
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* 全名 */}
            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Full Name</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><User className="h-5 w-5 text-gray-400" /></div>
                <input required type="text" placeholder="e.g., Ali Bin Abu" value={formData.username} onChange={(e) => setFormData({...formData, username: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-orange-500 focus:ring-2 focus:ring-orange-200 outline-none transition-all" />
              </div>
            </div>

            {/* 电话号码 */}
            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Phone Number</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><Phone className="h-5 w-5 text-gray-400" /></div>
                <input required type="tel" placeholder="e.g., 0123456789" value={formData.userPhoneNum} onChange={(e) => setFormData({...formData, userPhoneNum: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-orange-500 focus:ring-2 focus:ring-orange-200 outline-none transition-all" />
              </div>
            </div>

            {/* 邮箱 */}
            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Email Address</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><Mail className="h-5 w-5 text-gray-400" /></div>
                <input required type="email" placeholder="rider@tcm.com" value={formData.userEmail} onChange={(e) => setFormData({...formData, userEmail: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-orange-500 focus:ring-2 focus:ring-orange-200 outline-none transition-all" />
              </div>
            </div>

            {/* 密码 */}
            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Temporary Password</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><Lock className="h-5 w-5 text-gray-400" /></div>
                <input required type="text" minLength={6} placeholder="Minimum 6 characters" value={formData.password} onChange={(e) => setFormData({...formData, password: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-orange-500 focus:ring-2 focus:ring-orange-200 outline-none transition-all" />
              </div>
            </div>
          </div>

          <div className="border-t border-gray-100 pt-6 mt-6 grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* 车牌号 */}
            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Vehicle Plate Number</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><CreditCard className="h-5 w-5 text-gray-400" /></div>
                <input required type="text" placeholder="e.g., PFG 1234" value={formData.vehiclePlateNum} onChange={(e) => setFormData({...formData, vehiclePlateNum: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-orange-500 focus:ring-2 focus:ring-orange-200 outline-none transition-all uppercase" />
              </div>
            </div>

            {/* 驾驶证号码 */}
            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Driving License ID</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><FileText className="h-5 w-5 text-gray-400" /></div>
                <input required type="text" placeholder="License Number" value={formData.drivingLicense} onChange={(e) => setFormData({...formData, drivingLicense: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-orange-500 focus:ring-2 focus:ring-orange-200 outline-none transition-all" />
              </div>
            </div>
          </div>

          <button type="submit" disabled={isLoading} className="w-full mt-8 flex items-center justify-center bg-orange-500 hover:bg-orange-600 text-white py-3.5 rounded-xl font-bold transition-all shadow-lg shadow-orange-200 disabled:opacity-70">
            {isLoading ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Create Rider Account'}
          </button>
          
        </form>
      </div>
    </div>
  );
};

export default RegisterDeliveryMan;