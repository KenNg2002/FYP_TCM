import React, { useState, useEffect } from 'react';
import { UserPlus, Edit2, Trash2, Loader2, Mail, Phone, Stethoscope, Search, X } from 'lucide-react';
import { collection, query, where, getDocs, getDoc, doc, setDoc, updateDoc, deleteDoc, serverTimestamp } from 'firebase/firestore';
import { db } from '../firebaseConfig';

interface DoctorData {
  id: string;
  name: string;
  email: string;
  phone: string;
  department: string;
  description: string;
}

const DoctorManagement: React.FC = () => {
  const [doctors, setDoctors] = useState<DoctorData[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  
  // Modal & Form State
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  
  const [formData, setFormData] = useState({
    name: '',
    email: '',
    phone: '',
    department: 'TCM Department',
    description: ''
  });

  // 🚀 核心功能：联合读取 User 和 Administrator 表
  const fetchDoctors = async () => {
    setIsLoading(true);
    try {
      const adminQuery = query(collection(db, 'Administrator'), where('adminRole', '==', 'Doctor'));
      const snapshot = await getDocs(adminQuery);

      const fetchPromises = snapshot.docs.map(async (adminDoc) => {
        const adminData = adminDoc.data();
        const uid = adminData.adminID || adminDoc.id;

        const userSnap = await getDoc(doc(db, 'User', uid));
        const userData = userSnap.exists() ? userSnap.data() : {};

        return {
          id: uid,
          name: userData.username || adminData.adminName || 'Unknown Doctor',
          email: userData.userEmail || 'N/A',
          phone: userData.userPhoneNum || 'N/A',
          department: adminData.department || 'TCM Department',
          description: adminData.description || 'No description available.'
        };
      });

      const loadedDoctors = await Promise.all(fetchPromises);
      setDoctors(loadedDoctors);
    } catch (error) {
      console.error("Error fetching doctors:", error);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchDoctors();
  }, []);

  // 🚀 核心功能：联合写入 (新增或更新)
  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSaving(true);
    
    try {
      if (editingId) {
        // ========== 更新现有医生 ==========
        await updateDoc(doc(db, 'User', editingId), {
          username: formData.name,
          userEmail: formData.email,
          userPhoneNum: formData.phone
        });

        await updateDoc(doc(db, 'Administrator', editingId), {
          adminName: formData.name,
          department: formData.department,
          description: formData.description
        });

      } else {
        // ========== 新增医生 ==========
        // 1. 生成一个共享的唯一 ID
        const newUserRef = doc(collection(db, 'User')); 
        const newUid = newUserRef.id;

        // 2. 写入 User 表
        await setDoc(newUserRef, {
          username: formData.name,
          userEmail: formData.email,
          userPhoneNum: formData.phone,
          role: 'Doctor',
          createdAt: serverTimestamp()
        });

        // 3. 写入 Administrator 表
        await setDoc(doc(db, 'Administrator', newUid), {
          adminID: newUid,
          adminName: formData.name, // 备份冗余数据
          adminRole: 'Doctor',
          department: formData.department,
          description: formData.description,
          createdAt: serverTimestamp()
        });
      }

      setIsModalOpen(false);
      fetchDoctors(); // 刷新列表
    } catch (error) {
      console.error("Error saving doctor:", error);
      alert("Failed to save doctor data.");
    } finally {
      setIsSaving(false);
    }
  };

  // 🚀 核心功能：联合删除
  const handleDelete = async (id: string, name: string) => {
    if (!window.confirm(`Are you sure you want to remove Dr. ${name}? This action cannot be undone.`)) return;
    
    try {
      await deleteDoc(doc(db, 'Administrator', id));
      await deleteDoc(doc(db, 'User', id));
      fetchDoctors();
    } catch (error) {
      console.error("Error deleting doctor:", error);
      alert("Failed to delete doctor.");
    }
  };

  const openModalForAdd = () => {
    setEditingId(null);
    setFormData({ name: '', email: '', phone: '', department: 'TCM Department', description: '' });
    setIsModalOpen(true);
  };

  const openModalForEdit = (doctor: DoctorData) => {
    setEditingId(doctor.id);
    setFormData({
      name: doctor.name,
      email: doctor.email,
      phone: doctor.phone,
      department: doctor.department,
      description: doctor.description
    });
    setIsModalOpen(true);
  };

  return (
    <div className="space-y-6 animate-fade-in">
      {/* 头部区域 */}
      <div className="flex justify-between items-center bg-white p-6 rounded-xl shadow-sm border border-gray-100">
        <div>
          <h1 className="text-2xl font-bold text-gray-800">Practitioner Directory</h1>
          <p className="text-sm text-gray-500 mt-1">Manage all TCM doctors and their clinical profiles.</p>
        </div>
        <button 
          onClick={openModalForAdd}
          className="bg-green-600 hover:bg-green-700 text-white px-5 py-2.5 rounded-lg font-bold flex items-center transition-colors shadow-sm"
        >
          <UserPlus className="w-5 h-5 mr-2" /> Add New Doctor
        </button>
      </div>

      {/* 医生列表卡片网格 */}
      {isLoading ? (
        <div className="flex justify-center items-center h-64">
          <Loader2 className="w-10 h-10 animate-spin text-green-600" />
        </div>
      ) : doctors.length === 0 ? (
        <div className="bg-white rounded-xl shadow-sm border border-gray-100 h-64 flex flex-col items-center justify-center text-gray-400">
          <Stethoscope className="w-12 h-12 mb-3 opacity-50" />
          <p className="text-lg font-medium">No doctors found in the system.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {doctors.map((doctor) => (
            <div key={doctor.id} className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden hover:shadow-md transition-shadow relative group">
              {/* 卡片顶部绿色背景装饰 */}
              <div className="h-20 bg-green-50 w-full border-b border-green-100"></div>
              
              <div className="px-6 pb-6 relative">
                {/* 悬浮头像 */}
                <div className="absolute -top-10 left-6">
                  <div className="w-20 h-20 bg-white rounded-full p-1 shadow-sm border border-gray-100">
                    <div className="w-full h-full bg-green-100 rounded-full flex items-center justify-center">
                      <Stethoscope className="w-8 h-8 text-green-700" />
                    </div>
                  </div>
                </div>

                {/* 动作按钮 (Hover 显示) */}
                <div className="absolute top-3 right-6 flex gap-2">
                  <button onClick={() => openModalForEdit(doctor)} className="p-2 bg-blue-50 text-blue-600 hover:bg-blue-100 rounded-full transition-colors">
                    <Edit2 className="w-4 h-4" />
                  </button>
                  <button onClick={() => handleDelete(doctor.id, doctor.name)} className="p-2 bg-red-50 text-red-600 hover:bg-red-100 rounded-full transition-colors">
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>

                <div className="mt-12">
                  <h3 className="text-lg font-bold text-gray-900">{doctor.name}</h3>
                  <span className="inline-block px-3 py-1 bg-green-50 text-green-700 rounded-full text-xs font-bold mt-2 mb-4 border border-green-200">
                    {doctor.department}
                  </span>

                  <div className="space-y-2 text-sm text-gray-600">
                    <div className="flex items-center">
                      <Mail className="w-4 h-4 mr-3 text-gray-400" /> {doctor.email}
                    </div>
                    <div className="flex items-center">
                      <Phone className="w-4 h-4 mr-3 text-gray-400" /> {doctor.phone}
                    </div>
                  </div>

                  <div className="mt-4 pt-4 border-t border-gray-100">
                    <p className="text-xs text-gray-500 line-clamp-3 leading-relaxed">
                      {doctor.description}
                    </p>
                  </div>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* 新增/编辑 表单弹窗 */}
      {isModalOpen && (
        <div className="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center z-50 p-4 animate-fade-in">
          <div className="bg-white rounded-2xl shadow-xl w-full max-w-xl overflow-hidden">
            <div className="px-6 py-4 border-b border-gray-100 flex justify-between items-center bg-gray-50">
              <h2 className="text-lg font-bold text-gray-800 flex items-center">
                {editingId ? <Edit2 className="w-5 h-5 mr-2 text-blue-500" /> : <UserPlus className="w-5 h-5 mr-2 text-green-500" />}
                {editingId ? 'Edit Doctor Profile' : 'Register New Doctor'}
              </h2>
              <button onClick={() => setIsModalOpen(false)} className="text-gray-400 hover:text-gray-600"><X className="w-5 h-5" /></button>
            </div>
            
            <form onSubmit={handleSave} className="p-6 space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-bold text-gray-700 mb-1">Full Name</label>
                  <input required type="text" value={formData.name} onChange={(e) => setFormData({...formData, name: e.target.value})} className="w-full border border-gray-300 rounded-lg p-2.5 focus:ring-2 focus:ring-green-500 outline-none" placeholder="Dr. John Doe" />
                </div>
                <div>
                  <label className="block text-sm font-bold text-gray-700 mb-1">Department</label>
                  <input required type="text" value={formData.department} onChange={(e) => setFormData({...formData, department: e.target.value})} className="w-full border border-gray-300 rounded-lg p-2.5 focus:ring-2 focus:ring-green-500 outline-none" placeholder="TCM Department" />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-bold text-gray-700 mb-1">Email Address</label>
                  <input required type="email" value={formData.email} onChange={(e) => setFormData({...formData, email: e.target.value})} className="w-full border border-gray-300 rounded-lg p-2.5 focus:ring-2 focus:ring-green-500 outline-none" placeholder="doctor@clinic.com" />
                </div>
                <div>
                  <label className="block text-sm font-bold text-gray-700 mb-1">Phone Number</label>
                  <input required type="tel" value={formData.phone} onChange={(e) => setFormData({...formData, phone: e.target.value})} className="w-full border border-gray-300 rounded-lg p-2.5 focus:ring-2 focus:ring-green-500 outline-none" placeholder="+60 123456789" />
                </div>
              </div>

              <div>
                <label className="block text-sm font-bold text-gray-700 mb-1">Professional Description</label>
                <textarea required rows={4} value={formData.description} onChange={(e) => setFormData({...formData, description: e.target.value})} className="w-full border border-gray-300 rounded-lg p-2.5 focus:ring-2 focus:ring-green-500 outline-none resize-none" placeholder="Enter doctor's specialties, experience, and background..." />
              </div>

              <div className="pt-4 flex justify-end gap-3">
                <button type="button" onClick={() => setIsModalOpen(false)} className="px-5 py-2.5 rounded-lg text-gray-600 font-bold hover:bg-gray-100 transition-colors">
                  Cancel
                </button>
                <button type="submit" disabled={isSaving} className="bg-green-600 hover:bg-green-700 text-white px-6 py-2.5 rounded-lg font-bold transition-colors disabled:bg-green-400 flex items-center">
                  {isSaving ? <Loader2 className="w-5 h-5 animate-spin" /> : (editingId ? 'Save Changes' : 'Register Doctor')}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};

export default DoctorManagement;