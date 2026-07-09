export function validateName(name: string): string | null {
  if (!name.trim()) return 'This field is required';
  return null;
}

export function validateEmail(email: string): string | null {
  const trimmed = email.trim();
  if (!trimmed) return 'Please enter an email address';
  const emailRegex = /^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$/;
  if (!emailRegex.test(trimmed)) return 'Please enter a valid email address';
  return null;
}

export function validatePhone(phone: string): string | null {
  const trimmed = phone.trim();
  if (!trimmed) return 'Please enter a phone number';
  const phoneRegex = /^\+?[0-9]{10,11}$/;
  if (!phoneRegex.test(trimmed)) return 'Please enter a valid phone number (10-11 digits)';
  return null;
}

export function validatePassword(password: string): string | null {
  if (!password) return 'Please enter a password';
  if (password.length < 8) return 'Password must be at least 8 characters long';
  if (!/[A-Z]/.test(password)) return 'Password must contain at least one uppercase letter';
  if (!/[a-z]/.test(password)) return 'Password must contain at least one lowercase letter';
  if (!/[0-9]/.test(password)) return 'Password must contain at least one number';
  if (!/[!@#$%^&*(),.?":{}|<>_\-+=~`[\]\\/;']/.test(password)) return 'Password must contain at least one special character';
  return null;
}
