import React, { useState } from 'react';
import { Mail, Lock, User, Phone, CreditCard, Loader2, FileText } from 'lucide-react';
import { initializeApp } from 'firebase/app';
import { getAuth, createUserWithEmailAndPassword, signOut } from 'firebase/auth';
import { doc, writeBatch, serverTimestamp } from 'firebase/firestore';
import { ref, uploadBytes, getDownloadURL } from 'firebase/storage';
import { db, storage, firebaseConfig } from '../firebaseConfig';
import Toast from './Toast';
import AvatarUpload from './AvatarUpload';
import { validateName, validateEmail, validatePhone, validatePassword } from '../validation';

// Secondary app instance used only for silent registration, so the current Admin session isn't kicked out
const secondaryApp = initializeApp(firebaseConfig, "SecondaryApp_Delivery");
const secondaryAuth = getAuth(secondaryApp);

const RegisterDeliveryMan: React.FC = () => {
  const [isLoading, setIsLoading] = useState(false);
  const [successMsg, setSuccessMsg] = useState('');
  const [errorMsg, setErrorMsg] = useState('');
  const [photoFile, setPhotoFile] = useState<File | null>(null);
  const [errors, setErrors] = useState<{ [key: string]: string }>({});

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
    setSuccessMsg('');
    setErrorMsg('');

    const newErrors: { [key: string]: string } = {};
    const nameErr = validateName(formData.username); if (nameErr) newErrors.username = nameErr;
    const emailErr = validateEmail(formData.userEmail); if (emailErr) newErrors.userEmail = emailErr;
    const phoneErr = validatePhone(formData.userPhoneNum); if (phoneErr) newErrors.userPhoneNum = phoneErr;
    const passwordErr = validatePassword(formData.password); if (passwordErr) newErrors.password = passwordErr;
    if (!formData.vehiclePlateNum.trim()) newErrors.vehiclePlateNum = 'Please enter the vehicle plate number';
    if (!formData.drivingLicense.trim()) newErrors.drivingLicense = 'Please enter the driving license ID';
    setErrors(newErrors);
    if (Object.keys(newErrors).length > 0) return;

    setIsLoading(true);

    try {
      const userCredential = await createUserWithEmailAndPassword(
        secondaryAuth,
        formData.userEmail,
        formData.password
      );

      const newDeliveryManUid = userCredential.user.uid;

      let photoURL: string | null = null;
      if (photoFile) {
        const photoRef = ref(storage, `profile_photos/${newDeliveryManUid}.jpg`);
        await uploadBytes(photoRef, photoFile);
        photoURL = await getDownloadURL(photoRef);
      }

      // Batch write so both tables are written atomically
      const batch = writeBatch(db);

      const userRef = doc(db, 'User', newDeliveryManUid);
      batch.set(userRef, {
        userID: newDeliveryManUid, // matches the document ID
        username: formData.username,
        userEmail: formData.userEmail,
        userPhoneNum: formData.userPhoneNum,
        userRole: 'DeliveryMan',
        accountStatus: 'Active',
        userRegistedDate: serverTimestamp(),
        photoURL
      });

      const deliveryManRef = doc(db, 'DeliveryMan', newDeliveryManUid);
      batch.set(deliveryManRef, {
        deliverymanID: newDeliveryManUid, // foreign key to the User table
        vehiclePlateNum: formData.vehiclePlateNum.toUpperCase(),
        drivingLicense: formData.drivingLicense,
        currentAvailability: 'Offline' // defaults offline until the rider goes online from the mobile app
      });

      await batch.commit();

      await signOut(secondaryAuth);

      setSuccessMsg(`Delivery Man ${formData.username} has been successfully registered!`);
      setFormData({ username: '', userEmail: '', password: '', userPhoneNum: '', vehiclePlateNum: '', drivingLicense: '' });
      setPhotoFile(null);
      setErrors({});

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
      <div className="bg-white p-8 rounded-[30px] shadow-sm border border-gray-100 max-w-3xl mx-auto">
        
        {successMsg && <Toast type="success" message={successMsg} onDismiss={() => setSuccessMsg('')} />}
        {errorMsg && <Toast type="error" message={errorMsg} onDismiss={() => setErrorMsg('')} />}

        <form onSubmit={handleRegister} noValidate className="space-y-6">

          <AvatarUpload value={photoFile} onChange={setPhotoFile} ringColorClass="ring-orange-200" />

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Full Name</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><User className="h-5 w-5 text-gray-400" /></div>
                <input required type="text" placeholder="Full Name" value={formData.username} onChange={(e) => setFormData({...formData, username: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-orange-500 focus:ring-2 focus:ring-orange-200 outline-none transition-all" />
              </div>
              {errors.username && <p className="text-red-500 text-xs mt-1">{errors.username}</p>}
            </div>

            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Phone Number</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><Phone className="h-5 w-5 text-gray-400" /></div>
                <input required type="tel" placeholder="Phone Number" value={formData.userPhoneNum} onChange={(e) => setFormData({...formData, userPhoneNum: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-orange-500 focus:ring-2 focus:ring-orange-200 outline-none transition-all" />
              </div>
              {errors.userPhoneNum && <p className="text-red-500 text-xs mt-1">{errors.userPhoneNum}</p>}
            </div>

            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Company Email</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><Mail className="h-5 w-5 text-gray-400" /></div>
                <input required type="email" placeholder="Company Email" value={formData.userEmail} onChange={(e) => setFormData({...formData, userEmail: e.target.value.toLowerCase()})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-orange-500 focus:ring-2 focus:ring-orange-200 outline-none transition-all" />
              </div>
              {errors.userEmail && <p className="text-red-500 text-xs mt-1">{errors.userEmail}</p>}
            </div>

            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Temporary Password</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><Lock className="h-5 w-5 text-gray-400" /></div>
                <input required type="text" placeholder="Temporary Password" value={formData.password} onChange={(e) => setFormData({...formData, password: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-orange-500 focus:ring-2 focus:ring-orange-200 outline-none transition-all" />
              </div>
              {errors.password ? (
                <p className="text-red-500 text-xs mt-1">{errors.password}</p>
              ) : (
                <p className="text-gray-400 text-xs mt-1">At least 8 chars with uppercase, lowercase, number & symbol.</p>
              )}
            </div>
          </div>

          <div className="border-t border-gray-100 pt-6 mt-6 grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Vehicle Plate Number</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><CreditCard className="h-5 w-5 text-gray-400" /></div>
                <input required type="text" placeholder="Vehicle Plate Number" value={formData.vehiclePlateNum} onChange={(e) => setFormData({...formData, vehiclePlateNum: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-orange-500 focus:ring-2 focus:ring-orange-200 outline-none transition-all uppercase" />
              </div>
              {errors.vehiclePlateNum && <p className="text-red-500 text-xs mt-1">{errors.vehiclePlateNum}</p>}
            </div>

            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Driving License ID</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><FileText className="h-5 w-5 text-gray-400" /></div>
                <input required type="text" placeholder="License Number" value={formData.drivingLicense} onChange={(e) => setFormData({...formData, drivingLicense: e.target.value})} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-orange-500 focus:ring-2 focus:ring-orange-200 outline-none transition-all" />
              </div>
              {errors.drivingLicense && <p className="text-red-500 text-xs mt-1">{errors.drivingLicense}</p>}
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