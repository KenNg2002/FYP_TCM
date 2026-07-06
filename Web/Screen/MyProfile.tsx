import React, { useEffect, useState } from 'react';
import { UserCircle, Mail, Lock, User, Phone, Stethoscope, FileText, Loader2 } from 'lucide-react';
import { doc, getDoc, writeBatch } from 'firebase/firestore';
import { ref, uploadBytes, getDownloadURL } from 'firebase/storage';
import { auth, db, storage } from '../firebaseConfig';
import Toast from './Toast';
import AvatarUpload from './AvatarUpload';

const MyProfile: React.FC = () => {
  const adminRole = (localStorage.getItem('adminRole') as 'Admin' | 'Doctor') || 'Doctor';

  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [successMsg, setSuccessMsg] = useState('');
  const [errorMsg, setErrorMsg] = useState('');

  const [username, setUsername] = useState('');
  const [userEmail, setUserEmail] = useState('');
  const [userPhoneNum, setUserPhoneNum] = useState('');
  const [specialty, setSpecialty] = useState('TCM General Practice');
  const [description, setDescription] = useState('');
  const [existingPhotoURL, setExistingPhotoURL] = useState<string | null>(null);
  const [photoFile, setPhotoFile] = useState<File | null>(null);

  useEffect(() => {
    const fetchProfile = async () => {
      const uid = auth.currentUser?.uid;
      if (!uid) return;

      try {
        const userSnap = await getDoc(doc(db, 'User', uid));
        if (userSnap.exists()) {
          const data = userSnap.data();
          setUsername(data.username || '');
          setUserEmail(data.userEmail || '');
          setUserPhoneNum(data.userPhoneNum || '');
          setExistingPhotoURL(data.photoURL || null);
        }

        if (adminRole === 'Doctor') {
          const adminSnap = await getDoc(doc(db, 'Administrator', uid));
          if (adminSnap.exists()) {
            const data = adminSnap.data();
            setSpecialty(data.department || 'TCM General Practice');
            setDescription(data.description || '');
          }
        }
      } catch (error) {
        console.error('Error fetching profile:', error);
        setErrorMsg('Failed to load your profile.');
      } finally {
        setIsLoading(false);
      }
    };

    fetchProfile();
  }, [adminRole]);

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    const uid = auth.currentUser?.uid;
    if (!uid) return;

    setIsSaving(true);
    setSuccessMsg('');
    setErrorMsg('');

    try {
      let photoURL = existingPhotoURL;
      if (photoFile) {
        const photoRef = ref(storage, `profile_photos/${uid}.jpg`);
        await uploadBytes(photoRef, photoFile);
        photoURL = await getDownloadURL(photoRef);
      }

      const batch = writeBatch(db);
      batch.update(doc(db, 'User', uid), {
        username,
        userPhoneNum,
        photoURL
      });

      if (adminRole === 'Doctor') {
        batch.update(doc(db, 'Administrator', uid), {
          department: specialty,
          description
        });
      }

      await batch.commit();

      setExistingPhotoURL(photoURL);
      setPhotoFile(null);
      setSuccessMsg('Profile updated successfully!');
    } catch (error) {
      console.error('Error updating profile:', error);
      setErrorMsg('Failed to update your profile. Please try again.');
    } finally {
      setIsSaving(false);
    }
  };

  if (isLoading) {
    return (
      <div className="flex justify-center items-center h-64">
        <Loader2 className="w-8 h-8 animate-spin text-green-600" />
      </div>
    );
  }

  return (
    <div className="space-y-6 animate-fade-in relative">
      <div className="bg-white p-8 rounded-[30px] shadow-sm border border-gray-100">
        <h2 className="text-2xl font-black text-gray-800 flex items-center">
          <UserCircle className="w-7 h-7 mr-3 text-green-600" /> My Profile
        </h2>
        <p className="text-gray-400 text-sm mt-2">Update your personal details and profile photo.</p>
      </div>

      <div className="bg-white p-8 rounded-[30px] shadow-sm border border-gray-100 max-w-2xl">
        {successMsg && <Toast type="success" message={successMsg} onDismiss={() => setSuccessMsg('')} />}
        {errorMsg && <Toast type="error" message={errorMsg} onDismiss={() => setErrorMsg('')} />}

        <form onSubmit={handleSave} className="space-y-6">
          <AvatarUpload value={photoFile} onChange={setPhotoFile} initialUrl={existingPhotoURL} ringColorClass="ring-green-200" />

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Full Name</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><User className="h-5 w-5 text-gray-400" /></div>
                <input required type="text" value={username} onChange={(e) => setUsername(e.target.value)} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-green-500 focus:ring-2 focus:ring-green-200 outline-none transition-all" />
              </div>
            </div>

            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Phone Number</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><Phone className="h-5 w-5 text-gray-400" /></div>
                <input required type="tel" value={userPhoneNum} onChange={(e) => setUserPhoneNum(e.target.value)} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-green-500 focus:ring-2 focus:ring-green-200 outline-none transition-all" />
              </div>
            </div>

            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Email Address</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><Mail className="h-5 w-5 text-gray-400" /></div>
                <input type="email" value={userEmail} readOnly className="w-full pl-11 pr-4 py-3 bg-gray-100 border border-transparent rounded-xl text-sm text-gray-500 outline-none cursor-not-allowed" />
              </div>
            </div>

            <div>
              <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Role</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><Lock className="h-5 w-5 text-gray-400" /></div>
                <input type="text" value={adminRole} readOnly className="w-full pl-11 pr-4 py-3 bg-gray-100 border border-transparent rounded-xl text-sm text-gray-500 outline-none cursor-not-allowed" />
              </div>
            </div>
          </div>

          {adminRole === 'Doctor' && (
            <div className="border-t border-gray-100 pt-6 mt-6 space-y-6">
              <div>
                <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Specialization</label>
                <div className="relative">
                  <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><Stethoscope className="h-5 w-5 text-gray-400" /></div>
                  <select value={specialty} onChange={(e) => setSpecialty(e.target.value)} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-green-500 outline-none appearance-none">
                    <option value="TCM General Practice">TCM General Practice</option>
                    <option value="Acupuncture Specialist">Acupuncture Specialist</option>
                    <option value="Herbal Medicine Expert">Herbal Medicine Expert</option>
                    <option value="Pediatric TCM">Pediatric TCM</option>
                  </select>
                </div>
              </div>

              <div>
                <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Description / Bio</label>
                <div className="relative">
                  <div className="absolute top-3 left-0 pl-4 flex items-start pointer-events-none"><FileText className="h-5 w-5 text-gray-400" /></div>
                  <textarea placeholder="Brief introduction about yourself..." value={description} onChange={(e) => setDescription(e.target.value)} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-green-500 focus:ring-2 focus:ring-green-200 outline-none transition-all min-h-[100px] resize-y" />
                </div>
              </div>
            </div>
          )}

          <button type="submit" disabled={isSaving} className="w-full mt-8 flex items-center justify-center bg-green-600 hover:bg-green-700 text-white py-3.5 rounded-xl font-bold transition-all shadow-lg shadow-green-200 disabled:opacity-70">
            {isSaving ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Save Changes'}
          </button>
        </form>
      </div>
    </div>
  );
};

export default MyProfile;
