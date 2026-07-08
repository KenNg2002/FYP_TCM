import React, { useState } from 'react';
import { UserPlus, Mail, Lock, User, Phone, Stethoscope, Loader2, FileText } from 'lucide-react';
import { initializeApp } from 'firebase/app';
import { getAuth, createUserWithEmailAndPassword, signOut } from 'firebase/auth';
import { doc, writeBatch, serverTimestamp } from 'firebase/firestore';
import { ref, uploadBytes, getDownloadURL } from 'firebase/storage';
import { db, storage, firebaseConfig } from '../firebaseConfig';
import Toast from './Toast';
import AvatarUpload from './AvatarUpload';
import { validateName, validateEmail, validatePhone, validatePassword } from '../validation';

const secondaryApp = initializeApp(firebaseConfig, "SecondaryApp_Doctor");
const secondaryAuth = getAuth(secondaryApp);

const RegisterDoctor: React.FC = () => {
  const [isLoading, setIsLoading] = useState(false);
  const [successMsg, setSuccessMsg] = useState('');
  const [errorMsg, setErrorMsg] = useState('');
  const [photoFile, setPhotoFile] = useState<File | null>(null);
  const [errors, setErrors] = useState<{ [key: string]: string }>({});

  const [formData, setFormData] = useState({
    username: '',
    userEmail: '',
    userPhoneNum: '',
    password: '',
    specialty: 'TCM General Practice',
    description: ''
  });

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();
    setSuccessMsg('');
    setErrorMsg('');

    const newErrors: { [key: string]: string } = {};
    const nameErr = validateName(formData.username); if (nameErr) newErrors.username = nameErr;
    const emailErr = validateEmail(formData.userEmail); if (emailErr) newErrors.userEmail = emailErr;
    const phoneErr = validatePhone(formData.userPhoneNum); if (phoneErr) newErrors.userPhoneNum = phoneErr;
    const passwordErr = validatePassword(formData.password); if (passwordErr) newErrors.password = passwordErr;
    setErrors(newErrors);
    if (Object.keys(newErrors).length > 0) return;

    setIsLoading(true);

    try {
      const userCredential = await createUserWithEmailAndPassword(
        secondaryAuth, 
        formData.userEmail, 
        formData.password
      );
      
      const newDoctorUid = userCredential.user.uid;

      let photoURL: string | null = null;
      if (photoFile) {
        const photoRef = ref(storage, `profile_photos/${newDoctorUid}.jpg`);
        await uploadBytes(photoRef, photoFile);
        photoURL = await getDownloadURL(photoRef);
      }

      const batch = writeBatch(db);

      // userRole is always 'Admin' here: web login only checks User.userRole === 'Admin',
      // the actual Admin/Doctor distinction is decided by Administrator.adminRole (set below).
      const userRef = doc(db, 'User', newDoctorUid);
      batch.set(userRef, {
        userID: newDoctorUid,
        username: formData.username,
        userEmail: formData.userEmail,
        userPhoneNum: formData.userPhoneNum,
        userRole: 'Admin',
        userRegistedDate: serverTimestamp(),
        accountStatus: 'Active',
        photoURL
      });

      const adminRef = doc(db, 'Administrator', newDoctorUid);
      batch.set(adminRef, {
        adminID: newDoctorUid,
        adminRole: 'Doctor', 
        department: formData.specialty, 
        description: formData.description
      });

      await batch.commit();
      await signOut(secondaryAuth);

      setSuccessMsg(`Doctor ${formData.username} has been successfully registered!`);
      setFormData({ username: '', userEmail: '', userPhoneNum: '', password: '', specialty: 'TCM General Practice', description: '' });
      setPhotoFile(null);
      setErrors({});

    } catch (error: any) {
      console.error("Registration Error:", error);
      if (error.code === 'auth/email-already-in-use') setErrorMsg('This email is already registered.');
      else if (error.code === 'auth/weak-password') setErrorMsg('Password should be at least 6 characters.');
      else setErrorMsg('Failed to register doctor. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="space-y-6 animate-fade-in relative">
      <div className="bg-white p-8 rounded-[30px] shadow-sm border border-gray-100">
        <h2 className="text-2xl font-black text-gray-800 flex items-center">
          <UserPlus className="w-6 h-6 mr-3 text-blue-600" /> Register New Doctor
        </h2>
        <p className="text-gray-400 text-sm mt-2">Create a secure access account for a new Medical Doctor.</p>
      </div>

      <div className="bg-white p-8 rounded-[30px] shadow-sm border border-gray-100 max-w-2xl">
        {successMsg && <Toast type="success" message={successMsg} onDismiss={() => setSuccessMsg('')} />}
        {errorMsg && <Toast type="error" message={errorMsg} onDismiss={() => setErrorMsg('')} />}

        <form onSubmit={handleRegister} className="space-y-6">
          <AvatarUpload value={photoFile} onChange={setPhotoFile} ringColorClass="ring-blue-200" />

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Doctor's Full Name</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><User className="h-5 w-5 text-gray-400" /></div>
                <input required type="text" placeholder="e.g., Dr. Sarah Chen" value={formData.username} onChange={(e) => setFormData({...formData, username: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-blue-500 focus:ring-2 focus:ring-blue-200 outline-none transition-all" />
              </div>
              {errors.username && <p className="text-red-500 text-xs mt-1">{errors.username}</p>}
            </div>

            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Phone Number</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><Phone className="h-5 w-5 text-gray-400" /></div>
                <input required type="tel" placeholder="e.g., 0123456789" value={formData.userPhoneNum} onChange={(e) => setFormData({...formData, userPhoneNum: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-blue-500 focus:ring-2 focus:ring-blue-200 outline-none transition-all" />
              </div>
              {errors.userPhoneNum && <p className="text-red-500 text-xs mt-1">{errors.userPhoneNum}</p>}
            </div>

            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Email Address</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><Mail className="h-5 w-5 text-gray-400" /></div>
                <input required type="email" placeholder="doctor@tcm.com" value={formData.userEmail} onChange={(e) => setFormData({...formData, userEmail: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-blue-500 focus:ring-2 focus:ring-blue-200 outline-none transition-all" />
              </div>
              {errors.userEmail && <p className="text-red-500 text-xs mt-1">{errors.userEmail}</p>}
            </div>

            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Temporary Password</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><Lock className="h-5 w-5 text-gray-400" /></div>
                <input required type="text" placeholder="Min 8 chars, upper/lower/number/symbol" value={formData.password} onChange={(e) => setFormData({...formData, password: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-blue-500 focus:ring-2 focus:ring-blue-200 outline-none transition-all" />
              </div>
              {errors.password ? (
                <p className="text-red-500 text-xs mt-1">{errors.password}</p>
              ) : (
                <p className="text-gray-400 text-xs mt-1">At least 8 chars with uppercase, lowercase, number & symbol.</p>
              )}
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6 border-t border-gray-100 pt-6 mt-6">
            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Specialization</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><Stethoscope className="h-5 w-5 text-gray-400" /></div>
                <select value={formData.specialty} onChange={(e) => setFormData({...formData, specialty: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-blue-500 outline-none appearance-none">
                  <option value="TCM General Practice">TCM General Practice</option>
                  <option value="Acupuncture Specialist">Acupuncture Specialist</option>
                  <option value="Herbal Medicine Expert">Herbal Medicine Expert</option>
                  <option value="Pediatric TCM">Pediatric TCM</option>
                </select>
              </div>
            </div>
          </div>

          <div>
            <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Description / Bio (Optional)</label>
            <div className="relative">
              <div className="absolute top-3 left-0 pl-4 flex items-start pointer-events-none"><FileText className="h-5 w-5 text-gray-400" /></div>
              <textarea placeholder="Brief introduction about the doctor..." value={formData.description} onChange={(e) => setFormData({...formData, description: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-blue-500 focus:ring-2 focus:ring-blue-200 outline-none transition-all min-h-[100px] resize-y" />
            </div>
          </div>

          <button type="submit" disabled={isLoading} className="w-full mt-8 flex items-center justify-center bg-blue-600 hover:bg-blue-700 text-white py-3.5 rounded-xl font-bold transition-all shadow-lg shadow-blue-200 disabled:opacity-70">
            {isLoading ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Create Doctor Account'}
          </button>
        </form>
      </div>
    </div>
  );
};

export default RegisterDoctor;