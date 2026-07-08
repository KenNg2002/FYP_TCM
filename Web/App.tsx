// import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';

import AdminLogin from './Screen/AdminLogin';
import AdminDashboard from './Screen/AdminDashboard';
import DoctorWorkingHours from './Screen/DoctorWorkingHours';
import DoctorBlockTimes from './Screen/DoctorBlockTimes';

function App() {
  return (
    // BrowserRouter is required here, otherwise useNavigate causes a blank screen
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Navigate to="/login" replace />} />

        <Route path="/login" element={<AdminLogin />} />

        <Route path="/dashboard" element={<AdminDashboard />} />

        <Route path="/working-hours" element={<DoctorWorkingHours />} />

        <Route path="/block-times" element={<DoctorBlockTimes />} />
      </Routes>
    </BrowserRouter>
  );
}

export default App;