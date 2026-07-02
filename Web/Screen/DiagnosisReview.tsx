import React, { useState } from 'react';
import { CheckCircle, AlertCircle, Eye, ThumbsUp, ThumbsDown, XCircle } from 'lucide-react';

const mockReviews = [
  { id: 'SCAN-901', patient: 'Alex Johnson', date: 'Oct 24', time: '10:00 AM', aiResult: 'Heatiness (热气)', confidence: '92%', photoUrl: 'tongue_1.jpg' },
  { id: 'SCAN-902', patient: 'Sarah Lee', date: 'Oct 24', time: '11:15 AM', aiResult: 'Coldness (寒气)', confidence: '85%', photoUrl: 'tongue_2.jpg' },
];

const DiagnosisReview: React.FC = () => {
  const [selectedScan, setSelectedScan] = useState<any>(null);

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="bg-white p-6 rounded-3xl shadow-sm border border-gray-100">
        <h2 className="text-xl font-bold text-gray-800 mb-2">AI Diagnosis Verification</h2>
        <p className="text-sm text-gray-500">Verify the accuracy of AI-generated Heatiness/Coldness results based on ROI images.</p>
      </div>

      <div className="bg-white rounded-3xl shadow-sm border border-gray-100 overflow-hidden">
        <table className="w-full text-sm text-left">
          <thead className="bg-gray-50 text-gray-600 font-bold uppercase text-[10px] tracking-wider">
            <tr>
              <th className="px-6 py-5">Scan ID</th>
              <th className="px-6 py-5">Patient</th>
              <th className="px-6 py-5">AI Result</th>
              <th className="px-6 py-5">Confidence</th>
              <th className="px-6 py-5 text-center">Review</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-50">
            {mockReviews.map((scan) => (
              <tr key={scan.id} className="hover:bg-green-50/30 transition-colors">
                <td className="px-6 py-4 font-mono text-xs text-gray-400">{scan.id}</td>
                <td className="px-6 py-4 font-bold text-gray-800">{scan.patient}</td>
                <td className="px-6 py-4">
                  <span className={`font-bold ${scan.aiResult.includes('Heat') ? 'text-red-500' : 'text-blue-500'}`}>
                    {scan.aiResult}
                  </span>
                </td>
                <td className="px-6 py-4">
                   <div className="w-24 bg-gray-100 rounded-full h-1.5 mt-1">
                      <div className="bg-green-500 h-1.5 rounded-full" style={{ width: scan.confidence }}></div>
                   </div>
                   <span className="text-[10px] text-gray-400 font-bold">{scan.confidence} Match</span>
                </td>
                <td className="px-6 py-4 text-center">
                  <button onClick={() => setSelectedScan(scan)} className="bg-green-600 text-white p-2 rounded-xl shadow-lg shadow-green-100 hover:scale-105 transition-transform">
                    <Eye className="w-4 h-4" />
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {selectedScan && (
        <div className="fixed inset-0 bg-gray-900/60 backdrop-blur-md z-50 flex justify-center items-center p-4">
          <div className="bg-white w-full max-w-2xl rounded-[40px] shadow-2xl p-10 relative animate-zoom-in">
            <button onClick={() => setSelectedScan(null)} className="absolute top-8 right-8 text-gray-300 hover:text-gray-600">
              <XCircle className="w-8 h-8" />
            </button>

            <h2 className="text-2xl font-black text-gray-800 mb-8">Manual Verification</h2>

            <div className="grid grid-cols-2 gap-10">
              <div className="space-y-4">
                <p className="text-xs font-black text-gray-400 uppercase tracking-widest">ROI Capture</p>
                <div className="aspect-square bg-gray-900 rounded-[30px] border-8 border-gray-50 flex items-center justify-center text-gray-600 italic text-xs">
                  [ Tongue Photo Area ]
                </div>
              </div>

              <div className="flex flex-col h-full">
                <p className="text-xs font-black text-gray-400 uppercase tracking-widest mb-4">AI Prediction</p>
                <div className="p-4 bg-gray-50 rounded-2xl border border-gray-100 mb-6">
                   <p className="text-2xl font-black text-gray-800">{selectedScan.aiResult}</p>
                   <p className="text-sm text-green-600 font-bold">Confidence: {selectedScan.confidence}</p>
                </div>

                <p className="text-sm font-bold text-gray-700 mb-3">Is this result accurate?</p>
                <div className="flex space-x-3 mb-6">
                   <button className="flex-1 py-3 rounded-2xl bg-green-50 text-green-700 border-2 border-green-200 font-bold flex items-center justify-center hover:bg-green-100 transition-colors">
                     <ThumbsUp className="w-4 h-4 mr-2" /> Correct
                   </button>
                   <button className="flex-1 py-3 rounded-2xl bg-red-50 text-red-700 border-2 border-red-200 font-bold flex items-center justify-center hover:bg-red-100 transition-colors">
                     <ThumbsDown className="w-4 h-4 mr-2" /> Incorrect
                   </button>
                </div>

                <textarea className="w-full flex-1 bg-gray-50 border border-gray-200 rounded-2xl p-4 text-sm outline-none focus:ring-2 focus:ring-green-500" placeholder="Add commands or corrections..."></textarea>

                <button className="w-full bg-gray-900 text-white py-4 rounded-2xl font-bold mt-6 hover:bg-black transition-colors">
                  Complete Review
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default DiagnosisReview;
