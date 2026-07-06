import React, { useState, useEffect } from 'react';
import { Package, Truck, CheckCircle, MapPin, Loader2, Bike, Camera, XCircle, Send, Store } from 'lucide-react';
import { collection, query, orderBy, where, onSnapshot, doc, writeBatch, serverTimestamp } from 'firebase/firestore';
import { db } from '../firebaseConfig';
import { sendNotification } from '../notifications';

interface OrderData {
  id: string;
  orderID: string;
  customerID: string;
  shippingAddress: string;
  totalAmount: number;
  orderStatus: string;
  deliveryMethod?: string;
  orderDate?: any;
}

interface DeliveryTaskData {
  taskID: string;
  orderID: string;
  deliverymanID: string;
  taskStatus: string;
  proofOfDeliveryPhoto?: string;
}

interface RiderInfo {
  id: string;
  username: string;
}

const OrdersDelivery: React.FC = () => {
  const [orders, setOrders] = useState<OrderData[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [taskByOrderId, setTaskByOrderId] = useState<Record<string, DeliveryTaskData>>({});
  const [selectedProofUrl, setSelectedProofUrl] = useState<string | null>(null);
  const [onlineRiderIds, setOnlineRiderIds] = useState<string[]>([]);
  const [riderNames, setRiderNames] = useState<Record<string, string>>({});
  const [selectedRiderByOrder, setSelectedRiderByOrder] = useState<Record<string, string>>({});

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

  // 监听所有配送任务，拿到分配的骑手 + 送达凭证照片
  useEffect(() => {
    const unsubscribe = onSnapshot(collection(db, 'DeliveryTask'), (snapshot) => {
      const map: Record<string, DeliveryTaskData> = {};
      snapshot.docs.forEach(docSnap => {
        const data = docSnap.data() as DeliveryTaskData;
        if (data.orderID) map[data.orderID] = data;
      });
      setTaskByOrderId(map);
    }, (error) => {
      console.error("Error fetching delivery tasks:", error);
    });

    return () => unsubscribe();
  }, []);

  // 监听当前在线的骑手名单（Admin 只能派单给 Online 的骑手）
  useEffect(() => {
    const q = query(collection(db, 'DeliveryMan'), where('currentAvailability', '==', 'Online'));
    const unsubscribe = onSnapshot(q, (snapshot) => {
      setOnlineRiderIds(snapshot.docs.map(d => d.id));
    }, (error) => {
      console.error("Error fetching online riders:", error);
    });

    return () => unsubscribe();
  }, []);

  // 监听所有骑手账号的姓名，用于把 ID 显示成名字
  useEffect(() => {
    const q = query(collection(db, 'User'), where('userRole', '==', 'DeliveryMan'));
    const unsubscribe = onSnapshot(q, (snapshot) => {
      const map: Record<string, string> = {};
      snapshot.docs.forEach(docSnap => {
        map[docSnap.id] = docSnap.data().username || docSnap.id;
      });
      setRiderNames(map);
    }, (error) => {
      console.error("Error fetching rider names:", error);
    });

    return () => unsubscribe();
  }, []);

  const onlineRiders: RiderInfo[] = onlineRiderIds.map(id => ({ id, username: riderNames[id] || id }));

  // 第一阶段：Admin 把订单指派给指定的在线骑手
  const handleAssignRider = async (order: OrderData) => {
    const riderId = selectedRiderByOrder[order.id];
    if (!riderId) return;

    try {
      const taskRef = doc(collection(db, 'DeliveryTask'));
      const batch = writeBatch(db);

      batch.set(taskRef, {
        taskID: taskRef.id,
        orderID: order.id,
        deliverymanID: riderId,
        taskStatus: 'Assigned',
        pickupLocation: 'TCM Clinic HQ',
        dropoffLocation: order.shippingAddress,
        proofOfDeliveryPhoto: '',
        assignedTime: serverTimestamp(),
        startTime: null,
        completedTime: null,
      });
      batch.update(doc(db, 'Order', order.id), { orderStatus: 'Assigned' });

      await batch.commit();

      sendNotification({ uids: [riderId], title: 'New Delivery Task', body: `You've been assigned order ${order.orderID || order.id}.`, data: { orderId: order.id } });
      sendNotification({ uids: [order.customerID], title: 'Order Assigned', body: `Your order ${order.orderID || order.id} has been assigned to a rider.`, data: { orderId: order.id } });
    } catch (error) {
      console.error("Error assigning rider:", error);
      alert("Failed to assign this order to the rider.");
    }
  };

  // Self Pickup 专属：不需要指派骑手，Admin 直接标记好可以让客人来取
  const handleMarkReadyForPickup = async (order: OrderData) => {
    try {
      await writeBatch(db)
        .update(doc(db, 'Order', order.id), { orderStatus: 'ReadyForPickup' })
        .commit();

      sendNotification({ uids: [order.customerID], title: 'Ready for Pickup', body: `Your order ${order.orderID || order.id} is ready — come collect it at TCM Clinic HQ!`, data: { orderId: order.id } });
    } catch (error) {
      console.error("Error marking order ready for pickup:", error);
      alert("Failed to mark this order as ready for pickup.");
    }
  };

  // Self Pickup 专属：客人到店取走后，Admin 点这个结单（全程没有 DeliveryTask，不用同步骑手数据）
  const handleMarkPickedUp = async (order: OrderData) => {
    try {
      await writeBatch(db)
        .update(doc(db, 'Order', order.id), { orderStatus: 'Completed' })
        .commit();

      sendNotification({ uids: [order.customerID], title: 'Order Completed', body: `Your order ${order.orderID || order.id} has been picked up. Thank you!`, data: { orderId: order.id } });
    } catch (error) {
      console.error("Error marking order picked up:", error);
    }
  };

  // 兜底：管理员强制完单（同时把对应的 DeliveryTask 也标记完成，避免数据不一致）
  const handleMarkCompleted = async (order: OrderData) => {
    try {
      const batch = writeBatch(db);
      batch.update(doc(db, 'Order', order.id), { orderStatus: 'Completed' });

      const task = taskByOrderId[order.id];
      if (task?.taskID) {
        batch.update(doc(db, 'DeliveryTask', task.taskID), {
          taskStatus: 'Completed',
          completedTime: serverTimestamp()
        });
      }

      await batch.commit();

      sendNotification({ uids: [order.customerID], title: 'Order Completed', body: `Your order ${order.orderID || order.id} has been marked as completed.`, data: { orderId: order.id } });
    } catch (error) {
      console.error("Error completing order:", error);
    }
  };

  const pendingCount = orders.filter(o => o.orderStatus === 'Pending').length;
  const activeCount = orders.filter(o => ['Assigned', 'Delivering', 'ReadyForPickup'].includes(o.orderStatus)).length;
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
          <div><p className="text-sm text-gray-500">Active / In Progress</p><p className="text-2xl font-bold text-gray-900">{isLoading ? '-' : activeCount}</p></div>
          <Bike className="w-8 h-8 text-blue-200" />
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
                <th className="px-6 py-4">Proof of Delivery</th>
                <th className="px-6 py-4">Action</th>
              </tr>
            </thead>
            <tbody>
              {orders.map((order) => {
                const task = taskByOrderId[order.id];
                const assignedRiderName = task?.deliverymanID ? (riderNames[task.deliverymanID] || task.deliverymanID) : null;

                return (
                  <tr key={order.id} className="border-b hover:bg-gray-50 transition-colors">

                    <td className="px-6 py-4">
                      <p className="font-bold text-gray-900">{order.orderID || order.id}</p>
                      <p className="text-xs text-gray-500 font-medium mt-1">Total: RM {order.totalAmount?.toFixed(2)}</p>
                    </td>

                    <td className="px-6 py-4 max-w-[250px]">
                      <div className="flex items-start">
                        {order.deliveryMethod === 'Self Pickup' ? (
                          <Store className="w-4 h-4 text-purple-400 mr-2 mt-0.5 flex-shrink-0" />
                        ) : (
                          <MapPin className="w-4 h-4 text-red-400 mr-2 mt-0.5 flex-shrink-0" />
                        )}
                        <span className="text-gray-700 whitespace-pre-line text-xs">{order.shippingAddress}</span>
                      </div>
                    </td>

                    <td className="px-6 py-4">
                      <OrderStatusBadge status={order.orderStatus} />
                    </td>

                    <td className="px-6 py-4">
                      {task?.proofOfDeliveryPhoto ? (
                        <button
                          onClick={() => setSelectedProofUrl(task.proofOfDeliveryPhoto!)}
                          className="group relative w-14 h-14 rounded-xl overflow-hidden border border-gray-200 shadow-sm hover:shadow-md transition-shadow"
                        >
                          <img src={task.proofOfDeliveryPhoto} alt="Delivery proof" className="w-full h-full object-cover" />
                          <span className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                            <Camera className="w-5 h-5 text-white" />
                          </span>
                        </button>
                      ) : (
                        <span className="text-xs text-gray-300">—</span>
                      )}
                    </td>

                    <td className="px-6 py-4 min-w-[220px]">
                      {/* 状态 1：刚下单。Self Pickup 直接标记备货完成；一般配送则指派给一位在线骑手 */}
                      {order.orderStatus === 'Pending' && order.deliveryMethod === 'Self Pickup' ? (
                        <button
                          onClick={() => handleMarkReadyForPickup(order)}
                          className="bg-purple-500 hover:bg-purple-600 text-white shadow-sm font-bold py-2 px-4 rounded-lg transition-all text-xs flex items-center active:scale-95"
                        >
                          <Store className="w-3 h-3 mr-2" /> Mark Ready for Pickup
                        </button>

                      ) : order.orderStatus === 'Pending' ? (
                        onlineRiders.length === 0 ? (
                          <span className="text-[11px] text-gray-400 italic">No riders online right now</span>
                        ) : (
                          <div className="flex items-center gap-2">
                            <select
                              value={selectedRiderByOrder[order.id] || ''}
                              onChange={(e) => setSelectedRiderByOrder(prev => ({ ...prev, [order.id]: e.target.value }))}
                              className="text-xs border border-gray-200 rounded-lg px-2 py-2 bg-white focus:outline-none focus:border-orange-400"
                            >
                              <option value="" disabled>Select rider</option>
                              {onlineRiders.map(r => (
                                <option key={r.id} value={r.id}>{r.username}</option>
                              ))}
                            </select>
                            <button
                              disabled={!selectedRiderByOrder[order.id]}
                              onClick={() => handleAssignRider(order)}
                              className="bg-orange-500 hover:bg-orange-600 disabled:opacity-40 disabled:cursor-not-allowed text-white shadow-sm font-bold py-2 px-3 rounded-lg transition-all text-xs flex items-center active:scale-95"
                            >
                              <Send className="w-3 h-3 mr-1.5" /> Assign
                            </button>
                          </div>
                        )

                      // 状态 2a：Self Pickup 已备货完成，等客人上门取货
                      ) : order.orderStatus === 'ReadyForPickup' ? (
                        <div className="flex flex-col gap-1">
                          <span className="text-purple-600 text-xs font-bold flex items-center bg-purple-50 px-3 py-1.5 rounded-full w-fit border border-purple-100 shadow-inner">
                            <Store className="w-3 h-3 mr-1.5" /> Ready for Customer Pickup
                          </span>
                          <button
                            onClick={() => handleMarkPickedUp(order)}
                            className="text-[10px] uppercase font-bold text-gray-400 hover:text-green-600 underline transition-colors ml-1"
                          >
                            Mark Picked Up
                          </button>
                        </div>

                      // 状态 2b：已指派给骑手，等骑手点击 "开始配送"
                      ) : order.orderStatus === 'Assigned' ? (
                        <div className="flex flex-col gap-1">
                          <span className="text-orange-600 text-xs font-bold flex items-center bg-orange-50 px-3 py-1.5 rounded-full w-fit border border-orange-100 shadow-inner">
                            <Bike className="w-3 h-3 mr-1.5" /> Assigned to {assignedRiderName || 'Rider'}
                          </span>
                          <span className="text-[10px] text-gray-400 ml-1">Waiting for rider to start delivery</span>
                        </div>

                      // 状态 3：骑手已出发，正在送货
                      ) : order.orderStatus === 'Delivering' ? (
                        <div className="flex flex-col items-start gap-2">
                          <span className="px-3 py-1.5 bg-blue-50 text-blue-700 rounded-full text-xs font-bold border border-blue-100 flex items-center shadow-inner">
                            <Truck className="w-3 h-3 mr-1.5" /> {assignedRiderName || 'Rider'} is On the Way
                          </span>
                          <button
                            onClick={() => handleMarkCompleted(order)}
                            className="text-[10px] uppercase font-bold text-gray-400 hover:text-green-600 underline transition-colors ml-1"
                          >
                            Force Complete (Admin)
                          </button>
                        </div>

                      // 状态 4：已送达
                      ) : order.orderStatus === 'Completed' ? (
                        <span className="text-green-600 text-xs font-bold flex items-center bg-green-50 px-3 py-1.5 rounded-full w-fit border border-green-100">
                          <CheckCircle className="w-4 h-4 mr-1.5" /> Order Completed
                        </span>

                      // 状态 5：客户申请取消/售后，去 "Cancellations & Refunds" 页面处理
                      ) : order.orderStatus === 'Cancellation Pending' || order.orderStatus === 'Refund Pending' ? (
                        <span className="text-[11px] text-gray-400 italic">Awaiting review in Cancellations & Refunds</span>

                      // 状态 6：已经取消/退款完成
                      ) : (
                        <span className="text-gray-400 text-xs font-bold flex items-center bg-gray-50 px-3 py-1.5 rounded-full w-fit border border-gray-100">
                          <XCircle className="w-4 h-4 mr-1.5" /> {order.orderStatus}
                        </span>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>

      {selectedProofUrl && (
        <div className="fixed inset-0 bg-gray-900/60 backdrop-blur-md z-50 flex justify-center items-center p-4">
          <div className="bg-white w-full max-w-lg rounded-[30px] shadow-2xl p-6 relative animate-zoom-in">
            <button onClick={() => setSelectedProofUrl(null)} className="absolute top-5 right-5 text-gray-300 hover:text-gray-600">
              <XCircle className="w-8 h-8" />
            </button>
            <h2 className="text-lg font-black text-gray-800 mb-4">Proof of Delivery</h2>
            <img src={selectedProofUrl} alt="Delivery proof full size" className="w-full rounded-2xl border border-gray-100 object-contain max-h-[70vh]" />
          </div>
        </div>
      )}
    </div>
  );
};

// 状态徽章 UI
const OrderStatusBadge = ({ status }: { status: string }) => {
  let color = 'bg-gray-100 text-gray-700 border-gray-200';
  if (status === 'Pending') color = 'bg-red-50 text-red-700 border-red-200';
  if (status === 'Assigned') color = 'bg-orange-50 text-orange-700 border-orange-200';
  if (status === 'ReadyForPickup') color = 'bg-purple-50 text-purple-700 border-purple-200';
  if (status === 'Delivering') color = 'bg-blue-50 text-blue-700 border-blue-200';
  if (status === 'Completed') color = 'bg-green-50 text-green-700 border-green-200';
  if (status === 'Cancellation Pending' || status === 'Refund Pending') color = 'bg-yellow-50 text-yellow-700 border-yellow-200';
  if (status === 'Cancelled & Refunded' || status === 'Refunded') color = 'bg-gray-100 text-gray-600 border-gray-200';

  const displayStatus = status === 'ReadyForPickup' ? 'Ready for Pickup' : status;

  return (
    <span className={`px-3 py-1 rounded-full text-xs font-bold border ${color}`}>
      {displayStatus}
    </span>
  );
};

export default OrdersDelivery;
