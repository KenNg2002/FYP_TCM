import React, { useState } from 'react';
import { ShieldCheck, Mail, Lock, User, Phone, Loader2 } from 'lucide-react';
import { initializeApp } from 'firebase/app';
import { getAuth, createUserWithEmailAndPassword, signOut } from 'firebase/auth';
import { doc, writeBatch, serverTimestamp } from 'firebase/firestore';
import { db, firebaseConfig } from '../firebaseConfig';
import Toast from './Toast';

const secondaryApp = initializeApp(firebaseConfig, "SecondaryApp_Admin");
const secondaryAuth = getAuth(secondaryApp);

const RegisterAdmin: React.FC = () => {
  const [isLoading, setIsLoading] = useState(false);
  const [successMsg, setSuccessMsg] = useState('');
  const [errorMsg, setErrorMsg] = useState('');

  // 1. 状态里移除了 department 和 description
  const [formData, setFormData] = useState({
    username: '', 
    userEmail: '',
    userPhoneNum: '',
    password: ''
  });

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsLoading(true);
    setSuccessMsg('');
    setErrorMsg('');

    try {
      const userCredential = await createUserWithEmailAndPassword(
        secondaryAuth, 
        formData.userEmail, 
        formData.password
      );
      
      const newAdminUid = userCredential.user.uid;
      const batch = writeBatch(db);

      // A. 写入 User 表
      const userRef = doc(db, 'User', newAdminUid);
      batch.set(userRef, {
        userID: newAdminUid,
        username: formData.username,
        userEmail: formData.userEmail,
        userPhoneNum: formData.userPhoneNum,
        userRole: 'Admin', 
        userRegistedDate: serverTimestamp(),
        accountStatus: 'Active'
      });

      // B. 写入 Administrator 表
      const adminRef = doc(db, 'Administrator', newAdminUid);
      batch.set(adminRef, {
        adminID: newAdminUid,
        adminRole: 'Admin',
        department: null,  // ⚠️ 按照你的要求，直接设为 null
        description: null  // ⚠️ 按照你的要求，直接设为 null
      });

      await batch.commit();
      await signOut(secondaryAuth);

      setSuccessMsg(`Administrator ${formData.username} has been successfully registered!`);
      // 注册成功后清空表单
      setFormData({ username: '', userEmail: '', userPhoneNum: '', password: '' });

    } catch (error: any) {
      console.error("Registration Error:", error);
      if (error.code === 'auth/email-already-in-use') setErrorMsg('This email is already registered.');
      else if (error.code === 'auth/weak-password') setErrorMsg('Password should be at least 6 characters.');
      else setErrorMsg('Failed to register administrator. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="space-y-6 animate-fade-in relative">
      <div className="bg-white p-8 rounded-[30px] shadow-sm border border-gray-100">
        <h2 className="text-2xl font-black text-gray-800 flex items-center">
          <ShieldCheck className="w-7 h-7 mr-3 text-purple-600" /> Register Administrator
        </h2>
        <p className="text-gray-400 text-sm mt-2">Create a high-level access account for internal staff.</p>
      </div>

      <div className="bg-white p-8 rounded-[30px] shadow-sm border border-gray-100 max-w-2xl">
        {successMsg && <Toast type="success" message={successMsg} onDismiss={() => setSuccessMsg('')} />}
        {errorMsg && <Toast type="error" message={errorMsg} onDismiss={() => setErrorMsg('')} />}

        <form onSubmit={handleRegister} className="space-y-6">
          {/* 完美的 2x2 布局排版 */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Admin Full Name</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><User className="h-5 w-5 text-gray-400" /></div>
                <input required type="text" placeholder="e.g., Manager Wong" value={formData.username} onChange={(e) => setFormData({...formData, username: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-purple-500 focus:ring-2 focus:ring-purple-200 outline-none transition-all" />
              </div>
            </div>

            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Phone Number</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><Phone className="h-5 w-5 text-gray-400" /></div>
                <input required type="tel" placeholder="e.g., 0123456789" value={formData.userPhoneNum} onChange={(e) => setFormData({...formData, userPhoneNum: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-purple-500 focus:ring-2 focus:ring-purple-200 outline-none transition-all" />
              </div>
            </div>

            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Company Email</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><Mail className="h-5 w-5 text-gray-400" /></div>
                <input required type="email" placeholder="admin@tcm.com" value={formData.userEmail} onChange={(e) => setFormData({...formData, userEmail: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-purple-500 focus:ring-2 focus:ring-purple-200 outline-none transition-all" />
              </div>
            </div>

            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Temporary Password</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><Lock className="h-5 w-5 text-gray-400" /></div>
                <input required type="text" minLength={6} placeholder="Minimum 6 chars" value={formData.password} onChange={(e) => setFormData({...formData, password: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-purple-500 focus:ring-2 focus:ring-purple-200 outline-none transition-all" />
              </div>
            </div>
          </div>

          <button type="submit" disabled={isLoading} className="w-full mt-8 flex items-center justify-center bg-purple-600 hover:bg-purple-700 text-white py-3.5 rounded-xl font-bold transition-all shadow-lg shadow-purple-200 disabled:opacity-70">
            {isLoading ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Create Admin Account'}
          </button>
        </form>
      </div>
    </div>
  );
};

export default RegisterAdmin;