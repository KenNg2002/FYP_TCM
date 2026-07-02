import React, { useState, useEffect } from 'react';
import { Package, Truck, CheckCircle, MapPin, Loader2, Megaphone } from 'lucide-react';
// ⚠️ 移除了 addDoc，因为 Admin 不再负责创建 Task 了
import { collection, query, orderBy, onSnapshot, doc, updateDoc } from 'firebase/firestore';
import { db } from '../firebaseConfig';

interface OrderData {
  id: string;
  orderID: string;
  customerID: string;
  shippingAddress: string;
  totalAmount: number;
  orderStatus: string; 
  orderDate?: any;
}

const OrdersDelivery: React.FC = () => {
  const [orders, setOrders] = useState<OrderData[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  // 监听所有订单
  useEffect(() => {
    const q = query(collection(db, 'Order'), orderBy('orderDate', 'desc'));
    
    const unsubscribe = onSnapshot(q, (snapshot) => {
      const fetchedOrders: OrderData[] = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      })) as OrderData[];
      
      setOrders(fetchedOrders);
      setIsLoading(false);
    }, (error) => {
      console.error("Error fetching orders:", error);
      setIsLoading(false);
    });

    return () => unsubscribe();
  }, []);

  // 🚀 终极极简广播模式 (Broadcast Model)
  const handleMarkReadyAndBroadcast = async (orderId: string) => {
    try {
      // 唯一动作：只把 Order 表的状态改成 ReadyToPickUp！
      // 剩下的插入 DeliveryTask 的工作，交给抢到单的 Rider App 去做！
      const orderRef = doc(db, 'Order', orderId);
      await updateDoc(orderRef, {
        orderStatus: 'ReadyToPickUp' 
      });
      
    } catch (error) {
      console.error("Error broadcasting order:", error);
      alert("Failed to broadcast this order to riders.");
    }
  };

  // 兜底：管理员强制完单
  const handleMarkCompleted = async (orderId: string) => {
    try {
      const orderRef = doc(db, 'Order', orderId);
      await updateDoc(orderRef, {
        orderStatus: 'Completed'
      });
    } catch (error) {
      console.error("Error completing order:", error);
    }
  };

  const pendingCount = orders.filter(o => o.orderStatus === 'Pending').length;
  const activeCount = orders.filter(o => o.orderStatus === 'Delivering' || o.orderStatus === 'ReadyToPickUp').length;
  const completedCount = orders.filter(o => o.orderStatus === 'Completed').length;

  return (
    <div className="space-y-6 animate-fade-in">
      {/* 顶部统计卡片 */}
      <div className="grid grid-cols-3 gap-6">
        <div className="bg-white p-4 rounded-xl shadow-sm border border-orange-100 border-l-4 border-l-orange-500 flex items-center justify-between">
          <div><p className="text-sm text-gray-500">Preparing / Pending</p><p className="text-2xl font-bold text-gray-900">{isLoading ? '-' : pendingCount}</p></div>
          <Package className="w-8 h-8 text-orange-200" />
        </div>
        <div className="bg-white p-4 rounded-xl shadow-sm border border-blue-100 border-l-4 border-l-blue-500 flex items-center justify-between">
          <div><p className="text-sm text-gray-500">Active / Broadcasting</p><p className="text-2xl font-bold text-gray-900">{isLoading ? '-' : activeCount}</p></div>
          <Megaphone className="w-8 h-8 text-blue-200" />
        </div>
        <div className="bg-white p-4 rounded-xl shadow-sm border border-green-100 border-l-4 border-l-green-500 flex items-center justify-between">
          <div><p className="text-sm text-gray-500">Completed</p><p className="text-2xl font-bold text-gray-900">{isLoading ? '-' : completedCount}</p></div>
          <CheckCircle className="w-8 h-8 text-green-200" />
        </div>
      </div>

      <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="p-4 border-b border-gray-100 bg-gray-50 flex justify-between items-center">
          <h2 className="font-bold text-gray-800 text-lg">Orders Dispatch Hub</h2>
        </div>
        
        {isLoading ? (
          <div className="flex justify-center items-center h-40">
            <Loader2 className="w-8 h-8 animate-spin text-green-600" />
          </div>
        ) : orders.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-40 text-gray-400">
            <Package className="w-10 h-10 mb-2 opacity-50" />
            <p>No orders found.</p>
          </div>
        ) : (
          <table className="w-full text-sm text-left text-gray-500">
            <thead className="text-xs text-gray-700 uppercase bg-white border-b border-gray-100">
              <tr>
                <th className="px-6 py-4">Order Details</th>
                <th className="px-6 py-4">Delivery Address</th>
                <th className="px-6 py-4">Status</th>
                <th className="px-6 py-4">Action</th>
              </tr>
            </thead>
            <tbody>
              {orders.map((order) => (
                <tr key={order.id} className="border-b hover:bg-gray-50 transition-colors">
                  
                  <td className="px-6 py-4">
                    <p className="font-bold text-gray-900">{order.orderID || order.id}</p>
                    <p className="text-xs text-gray-500 font-medium mt-1">Total: RM {order.totalAmount?.toFixed(2)}</p>
                  </td>
                  
                  <td className="px-6 py-4 max-w-[250px]">
                    <div className="flex items-start">
                      <MapPin className="w-4 h-4 text-red-400 mr-2 mt-0.5 flex-shrink-0" />
                      <span className="text-gray-700 whitespace-pre-line text-xs">{order.shippingAddress}</span>
                    </div>
                  </td>
                  
                  <td className="px-6 py-4">
                    <OrderStatusBadge status={order.orderStatus} />
                  </td>
                  
                  <td className="px-6 py-4 min-w-[200px]">
                    {/* 状态 1：刚下单，等 Admin 准备好餐品后广播 */}
                    {order.orderStatus === 'Pending' ? (
                      <button 
                        onClick={() => handleMarkReadyAndBroadcast(order.id)}
                        className="bg-orange-500 hover:bg-orange-600 text-white shadow-sm font-bold py-2 px-4 rounded-lg transition-all text-xs flex items-center active:scale-95"
                      >
                        <Megaphone className="w-3 h-3 mr-2" /> Mark Ready & Broadcast
                      </button>

                    // 状态 2：已经广播出去了，等骑手在手机上抢单
                    ) : order.orderStatus === 'ReadyToPickUp' ? (
                      <div className="flex flex-col gap-1">
                        <span className="text-orange-600 text-xs font-bold flex items-center bg-orange-50 px-3 py-1.5 rounded-full w-fit border border-orange-100 shadow-inner">
                          <Loader2 className="w-3 h-3 mr-1.5 animate-spin" /> Broadcasting to Riders...
                        </span>
                        <span className="text-[10px] text-gray-400 ml-1">Waiting for a rider to accept</span>
                      </div>

                    // 状态 3：有骑手抢单了，正在送货 (这时候 Rider 已经偷偷创建好 DeliveryTask 了)
                    ) : order.orderStatus === 'Delivering' ? (
                      <div className="flex flex-col items-start gap-2">
                        <span className="px-3 py-1.5 bg-blue-50 text-blue-700 rounded-full text-xs font-bold border border-blue-100 flex items-center shadow-inner">
                          <Truck className="w-3 h-3 mr-1.5" /> Claimed & On the Way
                        </span>
                        <button 
                          onClick={() => handleMarkCompleted(order.id)}
                          className="text-[10px] uppercase font-bold text-gray-400 hover:text-green-600 underline transition-colors ml-1"
                        >
                          Force Complete (Admin)
                        </button>
                      </div>

                    // 状态 4：已送达
                    ) : (
                      <span className="text-green-600 text-xs font-bold flex items-center bg-green-50 px-3 py-1.5 rounded-full w-fit border border-green-100">
                        <CheckCircle className="w-4 h-4 mr-1.5" /> Order Completed
                      </span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
};

// 状态徽章 UI
const OrderStatusBadge = ({ status }: { status: string }) => {
  let color = 'bg-gray-100 text-gray-700 border-gray-200';
  if (status === 'Pending') color = 'bg-red-50 text-red-700 border-red-200';
  if (status === 'ReadyToPickUp') color = 'bg-orange-50 text-orange-700 border-orange-200';
  if (status === 'Delivering') color = 'bg-blue-50 text-blue-700 border-blue-200';
  if (status === 'Completed') color = 'bg-green-50 text-green-700 border-green-200';
  
  const displayStatus = status === 'ReadyToPickUp' ? 'Broadcasting' : status;

  return (
    <span className={`px-3 py-1 rounded-full text-xs font-bold border ${color}`}>
      {displayStatus}
    </span>
  );
};

export default OrdersDelivery;