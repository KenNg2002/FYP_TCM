import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom'; 
import { Leaf, Mail, Lock, Eye, EyeOff, ArrowRight } from 'lucide-react';
import { signInWithEmailAndPassword, signOut } from 'firebase/auth'; 
import { doc, getDoc } from 'firebase/firestore'; 
// IMPORTANT: Ensure 'db' is exported from your firebaseConfig.ts
import { auth, db } from '../firebaseConfig'; 

const AdminLogin: React.FC = () => {
  const navigate = useNavigate();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(''); 
    setIsLoading(true);  

    try {
      // 1. Execute Firebase Web Authentication
      const userCredential = await signInWithEmailAndPassword(auth, email, password);
      const user = userCredential.user;
      
      // 2. Fetch the user's data from the Firestore 'User' collection (Updated from Administrator)
      const userDocRef = doc(db, 'User', user.uid); 
      const userDocSnap = await getDoc(userDocRef);

      if (userDocSnap.exists()) {
        const userData = userDocSnap.data();

        // 3. Only 'Admin' may log into the web portal. The finer-grained Admin/Doctor
        // distinction lives in the 'Administrator' table (adminRole field), not here.
        if (userData.userRole === 'Admin') {
          // 3b. Fetch the sub-role from the Administrator table (doc id === user uid)
          const adminDocRef = doc(db, 'Administrator', user.uid);
          const adminDocSnap = await getDoc(adminDocRef);

          if (!adminDocSnap.exists()) {
            await signOut(auth);
            throw new Error("no-admin-record");
          }

          const adminData = adminDocSnap.data();
          const adminRole = adminData.adminRole;

          if (adminRole !== 'Admin' && adminRole !== 'Doctor') {
            await signOut(auth);
            throw new Error("invalid-admin-role");
          }

          console.log(`Authorization successful. adminRole: ${adminRole}, UID: ${user.uid}`);

          // 4. Save the verified roles to localStorage (used to filter menus & data across the app)
          localStorage.setItem('userRole', userData.userRole);
          localStorage.setItem('adminRole', adminRole);

          navigate('/dashboard');
        } else {
          // Force sign out if the user has a different role (e.g., 'Customer' or 'Rider')
          await signOut(auth);
          throw new Error("access-denied");
        }
      } else {
        // Force sign out if the user document does not exist in the 'User' table
        await signOut(auth);
        throw new Error("no-record");
      }

    } catch (error: any) {
      console.error("Firebase Login Error:", error);
      
      let customMessage = "An error occurred during login. Please try again.";
      
      // 5. Handle specific authentication & authorization errors
      if (error.message === 'access-denied') {
        customMessage = "Access Denied: You do not have Admin privileges.";
      } else if (error.message === 'no-record') {
        customMessage = "Access Denied: User record not found in the database.";
      } else if (error.message === 'no-admin-record' || error.message === 'invalid-admin-role') {
        customMessage = "Access Denied: Administrator profile not found. Please contact IT support.";
      } else if (error.code === 'auth/user-not-found' || error.code === 'auth/invalid-email') {
        customMessage = "No account found with this email address.";
      } else if (error.code === 'auth/wrong-password' || error.code === 'auth/invalid-credential') {
        customMessage = "Incorrect email or password. Please try again.";
      } else if (error.code === 'auth/too-many-requests') {
        customMessage = "Too many failed attempts. Please try again later.";
      }
      
      setErrorMessage(customMessage); 
    } finally {
      setIsLoading(false); 
    }
  };

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col justify-center items-center p-4 font-sans">
      
      {/* Main Login Card */}
      <div className="w-full max-w-md bg-white rounded-[30px] shadow-xl border border-gray-100 p-10 relative overflow-hidden">
        
        {/* Decorative background circle */}
        <div className="absolute -top-10 -right-10 w-40 h-40 bg-green-50 rounded-full opacity-50 pointer-events-none"></div>

        {/* Branding Header */}
        <div className="flex flex-col items-center mb-10 relative z-10">
          <div className="w-16 h-16 bg-green-500 rounded-full flex items-center justify-center shadow-md mb-4">
            <Leaf className="w-8 h-8 text-white" />
          </div>
          <h1 className="text-2xl font-black text-gray-800 tracking-wide">TCM Staff Portal</h1>
          <p className="text-sm text-gray-400 mt-2 font-medium">Secure Access for Admins & Doctors</p>
        </div>

        {/* Error Message Alert */}
        {errorMessage && (
          <div className="mb-6 p-4 bg-red-50 border border-red-100 rounded-xl flex items-start">
            <span className="text-red-600 text-sm font-medium">{errorMessage}</span>
          </div>
        )}

        {/* Login Form */}
        <form onSubmit={handleLogin} className="space-y-6 relative z-10">
          
          {/* Email Input Field */}
          <div>
            <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">
              Email Address
            </label>
            <div className="relative">
              <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                <Mail className="h-5 w-5 text-gray-400" />
              </div>
              <input
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-green-500 focus:ring-2 focus:ring-green-200 outline-none transition-all duration-200"
                placeholder="staff@tcm.com"
              />
            </div>
          </div>

          {/* Password Input Field */}
          <div>
            <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">
              Password
            </label>
            <div className="relative">
              <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                <Lock className="h-5 w-5 text-gray-400" />
              </div>
              <input
                type={showPassword ? 'text' : 'password'}
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full pl-11 pr-12 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-green-500 focus:ring-2 focus:ring-green-200 outline-none transition-all duration-200"
                placeholder="••••••••"
              />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                className="absolute inset-y-0 right-0 pr-4 flex items-center text-gray-400 hover:text-green-600 transition-colors"
              >
                {showPassword ? <EyeOff className="h-5 w-5" /> : <Eye className="h-5 w-5" />}
              </button>
            </div>
          </div>

          {/* Forgot Password Link */}
          <div className="flex justify-end">
            <button type="button" className="text-xs font-bold text-green-600 hover:text-green-700 transition-colors">
              Forgot Password?
            </button>
          </div>

          {/* Submit Button */}
          <button
            type="submit"
            disabled={isLoading}
            className="w-full flex items-center justify-center space-x-2 bg-green-600 hover:bg-green-700 text-white py-3.5 rounded-xl font-bold transition-all duration-200 shadow-lg shadow-green-200 disabled:opacity-70 disabled:cursor-not-allowed mt-2"
          >
            {isLoading ? (
              <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin"></div>
            ) : (
              <>
                <span>Sign In</span>
                <ArrowRight className="w-5 h-5" />
              </>
            )}
          </button>
        </form>
      </div>

      {/* Footer Text */}
      <p className="mt-8 text-xs font-medium text-gray-400">
        &copy; 2026 Traditional Chinese Medicine System. All rights reserved.
      </p>
    </div>
  );
};

export default AdminLogin;