import React, { useEffect, useState } from 'react';
import { CheckCircle, AlertCircle, X } from 'lucide-react';

interface ToastProps {
  message: string;
  type?: 'success' | 'error';
  duration?: number;
  onDismiss: () => void;
}

// Slides down from the top, stays for `duration` ms, then slides back up and disappears
const Toast: React.FC<ToastProps> = ({ message, type = 'success', duration = 3500, onDismiss }) => {
  const [isExiting, setIsExiting] = useState(false);

  useEffect(() => {
    setIsExiting(false);
    const timer = setTimeout(() => setIsExiting(true), duration);
    return () => clearTimeout(timer);
  }, [message, duration]);

  const isSuccess = type === 'success';

  return (
    <div
      onAnimationEnd={() => {
        if (isExiting) onDismiss();
      }}
      className={`fixed top-6 left-1/2 z-50 ${isExiting ? 'animate-toast-out' : 'animate-toast-in'}`}
    >
      <div
        className={`flex items-center gap-3 min-w-[320px] max-w-md px-6 py-4 rounded-2xl shadow-2xl border text-sm font-bold ${
          isSuccess
            ? 'bg-green-600 border-green-500 text-white'
            : 'bg-red-600 border-red-500 text-white'
        }`}
      >
        {isSuccess ? (
          <CheckCircle className="w-5 h-5 flex-shrink-0" />
        ) : (
          <AlertCircle className="w-5 h-5 flex-shrink-0" />
        )}
        <span className="flex-1">{message}</span>
        <button
          onClick={() => setIsExiting(true)}
          className="opacity-70 hover:opacity-100 transition-opacity flex-shrink-0"
        >
          <X className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
};

export default Toast;
