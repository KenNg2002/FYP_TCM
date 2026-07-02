import React from 'react';
import { Chart as ChartJS, CategoryScale, LinearScale, BarElement, PointElement, LineElement, Title, Tooltip, Legend, ArcElement } from 'chart.js';
import { Bar, Doughnut } from 'react-chartjs-2';
import { ArrowUpRight, ShoppingBag, Activity } from 'lucide-react';

ChartJS.register(CategoryScale, LinearScale, BarElement, PointElement, LineElement, ArcElement, Title, Tooltip, Legend);

export const DashboardCharts = () => {
  const options = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: { legend: { position: 'bottom' as const, labels: { boxWidth: 10, font: { weight: 'bold' as any } } } }
  };

  const revenueData = {
    labels: ['Week 1', 'Week 2', 'Week 3', 'Week 4'],
    datasets: [{
      label: 'Weekly Revenue (RM)',
      data: [5200, 6800, 5900, 6680],
      backgroundColor: '#22c55e',
      borderRadius: 12,
    }],
  };

  const aiDiagnosisData = {
    labels: ['Heatiness (热气)', 'Coldness (寒气)', 'Neutral (平和)'],
    datasets: [{
      data: [680, 240, 200],
      backgroundColor: ['#ef4444', '#3b82f6', '#10b981'],
      borderWidth: 0,
    }],
  };

  return (
    <div className="space-y-8">
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 bg-white p-8 rounded-[35px] border border-gray-100 shadow-sm">
          <h3 className="text-lg font-black text-gray-800 uppercase tracking-tight mb-6">Revenue Analysis (April 2026)</h3>
          <div className="h-80"><Bar data={revenueData} options={options} /></div>
        </div>

        <div className="bg-white p-8 rounded-[35px] border border-gray-100 shadow-sm text-center">
          <h3 className="text-lg font-black text-gray-800 uppercase tracking-tight mb-6">AI Diagnosis Ratio</h3>
          <div className="h-80"><Doughnut data={aiDiagnosisData} options={options} /></div>
        </div>
      </div>

      <div className="bg-white p-8 rounded-[35px] border border-gray-100 shadow-sm">
        <div className="flex justify-between items-center mb-8">
          <div>
            <h3 className="text-xl font-black text-gray-800 uppercase tracking-tight">Product Performance & AI Correlation</h3>
            <p className="text-xs text-gray-400 font-bold mt-1">April 2026 Monthly Insight</p>
          </div>
          <div className="flex space-x-2">
             <span className="bg-green-50 text-green-600 px-3 py-1 rounded-lg text-[10px] font-black border border-green-100">Top Conversion</span>
          </div>
        </div>

        <div className="grid grid-cols-6 gap-4 px-6 py-3 bg-gray-50 rounded-2xl mb-4 text-[10px] font-black text-gray-400 uppercase tracking-widest">
          <div className="col-span-2">Product Name & Category</div>
          <div className="text-center">Linked AI Diagnosis</div>
          <div className="text-center">Units Sold</div>
          <div className="text-center">Revenue</div>
          <div className="text-right">Conversion</div>
        </div>

        <div className="space-y-3">
          <ProductAnalysisRow
            name="Cooling Herbal Tea"
            category="Herbal Tea"
            diagnosis="Heatiness (热气)"
            sales="156"
            revenue="RM 2,340"
            conversion="82%"
            isHot={true}
          />
          <ProductAnalysisRow
            name="Premium Goji Berries"
            category="Raw Herbs"
            diagnosis="Neutral (平和)"
            sales="122"
            revenue="RM 3,050"
            conversion="68%"
          />
          <ProductAnalysisRow
            name="Ginger Essence Oil"
            category="Supplements"
            diagnosis="Coldness (寒气)"
            sales="98"
            revenue="RM 2,940"
            conversion="74%"
          />
          <ProductAnalysisRow
            name="Red Dates Detox Pack"
            category="General Care"
            diagnosis="Neutral (平和)"
            sales="84"
            revenue="RM 1,260"
            conversion="55%"
          />
        </div>
      </div>
    </div>
  );
};

const ProductAnalysisRow = ({ name, category, diagnosis, sales, revenue, conversion, isHot }: any) => (
  <div className="grid grid-cols-6 gap-4 px-6 py-5 rounded-[25px] border border-gray-50 hover:border-green-200 hover:bg-green-50/30 transition-all items-center group">
    <div className="col-span-2 flex items-center space-x-4">
      <div className={`p-3 rounded-2xl ${isHot ? 'bg-red-50 text-red-500' : 'bg-blue-50 text-blue-500'}`}>
        <ShoppingBag className="w-5 h-5" />
      </div>
      <div>
        <p className="font-black text-gray-800 text-sm">{name}</p>
        <p className="text-[10px] text-gray-400 font-bold uppercase">{category}</p>
      </div>
    </div>

    <div className="flex justify-center">
      <span className={`px-3 py-1 rounded-full text-[10px] font-black uppercase tracking-tighter ${
        diagnosis.includes('Heat') ? 'bg-red-100 text-red-600' :
        diagnosis.includes('Cold') ? 'bg-blue-100 text-blue-600' : 'bg-green-100 text-green-600'
      }`}>
        {diagnosis}
      </span>
    </div>

    <div className="text-center font-black text-gray-700">{sales}</div>
    <div className="text-center font-black text-gray-900">{revenue}</div>

    <div className="flex justify-end items-center text-green-600 font-black space-x-1">
      <span>{conversion}</span>
      <ArrowUpRight className="w-3 h-3" />
    </div>
  </div>
);
