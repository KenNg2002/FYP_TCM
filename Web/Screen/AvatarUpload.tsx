import React, { useEffect, useRef, useState } from 'react';
import { Camera, User as UserIcon } from 'lucide-react';

interface AvatarUploadProps {
  value: File | null;
  onChange: (file: File | null) => void;
  ringColorClass?: string;
  initialUrl?: string | null;
}

const AvatarUpload: React.FC<AvatarUploadProps> = ({ value, onChange, ringColorClass = 'ring-blue-200', initialUrl = null }) => {
  const inputRef = useRef<HTMLInputElement>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(initialUrl);

  useEffect(() => {
    if (!value) {
      setPreviewUrl(initialUrl);
      if (inputRef.current) inputRef.current.value = '';
      return;
    }
    const url = URL.createObjectURL(value);
    setPreviewUrl(url);
    return () => URL.revokeObjectURL(url);
  }, [value, initialUrl]);

  return (
    <div className="flex flex-col items-center">
      <button
        type="button"
        onClick={() => inputRef.current?.click()}
        className={`relative w-24 h-24 rounded-full bg-gray-50 border-4 border-white shadow-md ring-2 ${ringColorClass} flex items-center justify-center overflow-hidden group`}
      >
        {previewUrl ? (
          <img src={previewUrl} alt="Profile preview" className="w-full h-full object-cover" />
        ) : (
          <UserIcon className="w-10 h-10 text-gray-300" />
        )}
        <span className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
          <Camera className="w-6 h-6 text-white" />
        </span>
      </button>
      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        onChange={(e) => onChange(e.target.files?.[0] || null)}
        className="hidden"
      />
      <span className="text-xs text-gray-400 mt-2">Click to upload photo (optional)</span>
    </div>
  );
};

export default AvatarUpload;
