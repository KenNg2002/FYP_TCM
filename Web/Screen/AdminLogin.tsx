import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Mail, Lock, Eye, EyeOff, ArrowRight, X, KeyRound } from 'lucide-react';
import { signInWithEmailAndPassword, signOut } from 'firebase/auth';
import { doc, getDoc } from 'firebase/firestore';
// IMPORTANT: Ensure 'db' is exported from your firebaseConfig.ts
import { auth, db } from '../firebaseConfig';
import { serverBaseUrl } from '../ipaddress';
import { validatePassword } from '../validation';

const AdminLogin: React.FC = () => {
  const navigate = useNavigate();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');
  const [infoMessage, setInfoMessage] = useState('');

  const [isForgotModalOpen, setIsForgotModalOpen] = useState(false);
  const [resetStep, setResetStep] = useState<'email' | 'code'>('email');
  const [resetEmail, setResetEmail] = useState('');
  const [resetCode, setResetCode] = useState('');
  const [resetNewPassword, setResetNewPassword] = useState('');
  const [resetConfirmPassword, setResetConfirmPassword] = useState('');
  const [resetErrors, setResetErrors] = useState<{ [key: string]: string }>({});
  const [isResetSubmitting, setIsResetSubmitting] = useState(false);

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

  const openForgotPasswordModal = () => {
    setResetStep('email');
    setResetEmail(email);
    setResetCode('');
    setResetNewPassword('');
    setResetConfirmPassword('');
    setResetErrors({});
    setIsForgotModalOpen(true);
  };

  const handleRequestCode = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!resetEmail) {
      setResetErrors({ resetEmail: 'Please enter your email address' });
      return;
    }

    setIsResetSubmitting(true);
    setResetErrors({});

    try {
      const response = await fetch(`${serverBaseUrl}/request-password-reset`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: resetEmail }),
      });
      const result = await response.json();

      if (result.success) {
        setResetStep('code');
      } else {
        setResetErrors({ resetEmail: result.error || 'Failed to send reset code. Please try again.' });
      }
    } catch (error) {
      console.error('Failed to request password reset:', error);
      setResetErrors({ resetEmail: 'Could not reach the server. Please try again.' });
    } finally {
      setIsResetSubmitting(false);
    }
  };

  const handleConfirmReset = async (e: React.FormEvent) => {
    e.preventDefault();

    const newErrors: { [key: string]: string } = {};
    if (!resetCode.trim()) newErrors.resetCode = 'Please enter the code from your email';
    const passwordErr = validatePassword(resetNewPassword);
    if (passwordErr) newErrors.resetNewPassword = passwordErr;
    if (!newErrors.resetNewPassword && resetNewPassword !== resetConfirmPassword) newErrors.resetConfirmPassword = 'Passwords do not match';
    setResetErrors(newErrors);
    if (Object.keys(newErrors).length > 0) return;

    setIsResetSubmitting(true);

    try {
      const response = await fetch(`${serverBaseUrl}/confirm-password-reset`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: resetEmail, code: resetCode.trim(), newPassword: resetNewPassword }),
      });
      const result = await response.json();

      if (result.success) {
        setIsForgotModalOpen(false);
        setErrorMessage('');
        setInfoMessage('Password reset successfully! Please sign in with your new password.');
      } else {
        setResetErrors({ resetCode: result.error || 'Failed to reset password. Please try again.' });
      }
    } catch (error) {
      console.error('Failed to confirm password reset:', error);
      setResetErrors({ resetCode: 'Could not reach the server. Please try again.' });
    } finally {
      setIsResetSubmitting(false);
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
          <div className="w-16 h-16 rounded-2xl overflow-hidden shadow-md mb-4">
            <img src="/logo.png" alt="SH Wellness" className="w-full h-full object-cover" />
          </div>
          <h1 className="text-2xl font-black text-gray-800 tracking-wide">SH Wellness Staff Portal</h1>
          <p className="text-sm text-gray-400 mt-2 font-medium">Secure Access for Admins & Doctors</p>
        </div>

        {/* Error Message Alert */}
        {errorMessage && (
          <div className="mb-6 p-4 bg-red-50 border border-red-100 rounded-xl flex items-start">
            <span className="text-red-600 text-sm font-medium">{errorMessage}</span>
          </div>
        )}

        {/* Info Message Alert */}
        {infoMessage && (
          <div className="mb-6 p-4 bg-green-50 border border-green-100 rounded-xl flex items-start">
            <span className="text-green-700 text-sm font-medium">{infoMessage}</span>
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
                onChange={(e) => setEmail(e.target.value.toLowerCase())}
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
            <button type="button" onClick={openForgotPasswordModal} className="text-xs font-bold text-green-600 hover:text-green-700 transition-colors">
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
        &copy; 2026 SH Wellness. All rights reserved.
      </p>

      {/* Forgot Password Modal */}
      {isForgotModalOpen && (
        <div className="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center z-50 p-4 animate-fade-in">
          <div className="bg-white rounded-2xl shadow-xl w-full max-w-md overflow-hidden">
            <div className="px-6 py-4 border-b border-gray-100 flex justify-between items-center bg-gray-50">
              <h2 className="text-lg font-bold text-gray-800 flex items-center">
                <KeyRound className="w-5 h-5 mr-2 text-green-600" /> Reset Password
              </h2>
              <button onClick={() => setIsForgotModalOpen(false)} className="text-gray-400 hover:text-gray-600"><X className="w-5 h-5" /></button>
            </div>

            {resetStep === 'email' ? (
              <form onSubmit={handleRequestCode} noValidate className="p-6 space-y-4">
                <p className="text-sm text-gray-500">Enter your account email and we'll send you a 6-digit reset code.</p>
                <div>
                  <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Email Address</label>
                  <div className="relative">
                    <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><Mail className="h-5 w-5 text-gray-400" /></div>
                    <input type="email" value={resetEmail} onChange={(e) => setResetEmail(e.target.value.toLowerCase())} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-green-500 focus:ring-2 focus:ring-green-200 outline-none transition-all" />
                  </div>
                  {resetErrors.resetEmail && <p className="text-red-500 text-xs mt-1">{resetErrors.resetEmail}</p>}
                </div>
                <button type="submit" disabled={isResetSubmitting} className="w-full flex items-center justify-center bg-green-600 hover:bg-green-700 text-white py-3.5 rounded-xl font-bold transition-all disabled:opacity-70">
                  {isResetSubmitting ? <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin"></div> : 'Send Code'}
                </button>
              </form>
            ) : (
              <form onSubmit={handleConfirmReset} noValidate className="p-6 space-y-4">
                <p className="text-sm text-gray-500">Enter the code sent to <span className="font-bold">{resetEmail}</span> and choose a new password.</p>
                <div>
                  <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Reset Code</label>
                  <input type="text" value={resetCode} onChange={(e) => setResetCode(e.target.value)} className="w-full px-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-green-500 focus:ring-2 focus:ring-green-200 outline-none transition-all tracking-widest" placeholder="123456" />
                  {resetErrors.resetCode && <p className="text-red-500 text-xs mt-1">{resetErrors.resetCode}</p>}
                </div>
                <div>
                  <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">New Password</label>
                  <div className="relative">
                    <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><Lock className="h-5 w-5 text-gray-400" /></div>
                    <input type="password" value={resetNewPassword} onChange={(e) => setResetNewPassword(e.target.value)} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-green-500 focus:ring-2 focus:ring-green-200 outline-none transition-all" />
                  </div>
                  {resetErrors.resetNewPassword ? (
                    <p className="text-red-500 text-xs mt-1">{resetErrors.resetNewPassword}</p>
                  ) : (
                    <p className="text-gray-400 text-xs mt-1">At least 8 chars with uppercase, lowercase, number & symbol.</p>
                  )}
                </div>
                <div>
                  <label className="block text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">Confirm New Password</label>
                  <div className="relative">
                    <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"><Lock className="h-5 w-5 text-gray-400" /></div>
                    <input type="password" value={resetConfirmPassword} onChange={(e) => setResetConfirmPassword(e.target.value)} className="w-full pl-11 pr-4 py-3 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-green-500 focus:ring-2 focus:ring-green-200 outline-none transition-all" />
                  </div>
                  {resetErrors.resetConfirmPassword && <p className="text-red-500 text-xs mt-1">{resetErrors.resetConfirmPassword}</p>}
                </div>
                <div className="flex items-center justify-between pt-2">
                  <button type="button" onClick={() => setResetStep('email')} className="text-xs font-bold text-gray-500 hover:text-gray-700">
                    Back
                  </button>
                  <button type="submit" disabled={isResetSubmitting} className="flex items-center justify-center bg-green-600 hover:bg-green-700 text-white px-6 py-2.5 rounded-lg font-bold transition-colors disabled:opacity-70">
                    {isResetSubmitting ? <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin"></div> : 'Reset Password'}
                  </button>
                </div>
              </form>
            )}
          </div>
        </div>
      )}
    </div>
  );
};

export default AdminLogin;