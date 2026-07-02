// import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';

// 确保这些路径指向你真实存放文件的位置
import AdminLogin from './Screen/AdminLogin';
import AdminDashboard from './Screen/AdminDashboard';
// ⚠️ 新增：导入刚才创建的医生排班管理页面
import DoctorWorkingHours from './Screen/DoctorWorkingHours';
import DoctorBlockTimes from './Screen/DoctorBlockTimes';

function App() {
  return (
    // BrowserRouter 是必须的！没有它，useNavigate 就会导致白屏
    <BrowserRouter>
      <Routes>
        {/* 当用户输入根目录网址时，默认把他们重定向到登录页 */}
        <Route path="/" element={<Navigate to="/login" replace />} />
        
        {/* 登录页路由 */}
        <Route path="/login" element={<AdminLogin />} />
        
        {/* 后台主面板路由（登录成功后会跳转到这里） */}
        <Route path="/dashboard" element={<AdminDashboard />} />

        {/* ⚠️ 新增：医生工作时间管理页面的路由 */}
        <Route path="/working-hours" element={<DoctorWorkingHours />} />

        {/* 医生阻挡时间管理页面的路由 */}
        <Route path="/block-times" element={<DoctorBlockTimes />} />
      </Routes>
    </BrowserRouter>
  );
}

export default App;