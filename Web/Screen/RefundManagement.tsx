import React, { useEffect, useState } from 'react';
import { PackageX, Undo2, CheckCircle, XCircle, Loader2, Camera, Ban } from 'lucide-react';
import { collection, query, where, onSnapshot, doc, getDocs, updateDoc, writeBatch, increment, serverTimestamp } from 'firebase/firestore';
import { db } from '../firebaseConfig';
import { serverBaseUrl } from '../ipaddress';
import { sendNotification } from '../notifications';

interface OrderData {
  id: string;
  orderID: string;
  customerID: string;
  totalAmount: number;
  orderStatus: string;
  stripePaymentIntentId?: string | null;
  cancellationReason?: string;
  refundReason?: string;
  refundProofPhoto?: string;
}

const RefundManagement: React.FC = () => {
  const [orders, setOrders] = useState<OrderData[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [processingId, setProcessingId] = useState<string | null>(null);
  const [selectedProofUrl, setSelectedProofUrl] = useState<string | null>(null);
  const [rejectingOrder, setRejectingOrder] = useState<OrderData | null>(null);
  const [rejectReasonText, setRejectReasonText] = useState('');

  useEffect(() => {
    const q = query(collection(db, 'Order'), where('orderStatus', 'in', ['Cancellation Pending', 'Refund Pending']));
    const unsubscribe = onSnapshot(q, (snapshot) => {
      const fetched: OrderData[] = snapshot.docs.map(d => ({ id: d.id, ...d.data() })) as OrderData[];
      setOrders(fetched);
      setIsLoading(false);
    }, (error) => {
      console.error("Error fetching refund/cancellation requests:", error);
      setIsLoading(false);
    });

    return () => unsubscribe();
  }, []);

  // 下单时曾扣过库存，取消/退款批准后要把这些库存加回去
  const restoreStock = async (orderId: string) => {
    const itemsSnap = await getDocs(query(collection(db, 'CartItem'), where('orderID', '==', orderId)));
    if (itemsSnap.empty) return;

    const batch = writeBatch(db);
    itemsSnap.docs.forEach(itemDoc => {
      const data = itemDoc.data();
      if (data.productID && data.quantity) {
        batch.update(doc(db, 'HerbalProduct', data.productID), { stockQuantity: increment(data.quantity) });
      }
    });
    await batch.commit();
  };

  // 如果是 Stripe 卡付款，真正呼叫后台退钱；COD 订单没有 stripePaymentIntentId，直接跳过
  const refundStripeChargeIfNeeded = async (order: OrderData) => {
    if (!order.stripePaymentIntentId) return;

    const response = await fetch(`${serverBaseUrl}/refund-charge`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ paymentIntentId: order.stripePaymentIntentId }),
    });
    const json = await response.json();
    if (!json.success) throw new Error(json.error || 'Stripe refund failed');
  };

  const handleApproveCancellation = async (order: OrderData) => {
    setProcessingId(order.id);
    try {
      await refundStripeChargeIfNeeded(order);
      await restoreStock(order.id);
      await updateDoc(doc(db, 'Order', order.id), {
        orderStatus: 'Cancelled & Refunded',
        refundDecisionTime: serverTimestamp(),
      });

      sendNotification({ uids: [order.customerID], title: 'Cancellation Approved', body: `Your order ${order.orderID || order.id} has been cancelled and refunded.`, data: { orderId: order.id } });
    } catch (error) {
      console.error("Error approving cancellation:", error);
      alert(`Failed to approve this cancellation: ${(error as Error).message}`);
    } finally {
      setProcessingId(null);
    }
  };

  const handleApproveRefund = async (order: OrderData) => {
    setProcessingId(order.id);
    try {
      await refundStripeChargeIfNeeded(order);
      await restoreStock(order.id);
      await updateDoc(doc(db, 'Order', order.id), {
        orderStatus: 'Refunded',
        refundDecisionTime: serverTimestamp(),
      });

      sendNotification({ uids: [order.customerID], title: 'Refund Approved', body: `Your refund for order ${order.orderID || order.id} has been approved.`, data: { orderId: order.id } });
    } catch (error) {
      console.error("Error approving refund:", error);
      alert(`Failed to approve this refund: ${(error as Error).message}`);
    } finally {
      setProcessingId(null);
    }
  };

  const handleRejectRefund = async () => {
    if (!rejectingOrder || !rejectReasonText.trim()) return;
    setProcessingId(rejectingOrder.id);
    try {
      await updateDoc(doc(db, 'Order', rejectingOrder.id), {
        orderStatus: 'Completed',
        rejectionReason: rejectReasonText.trim(),
        refundDecisionTime: serverTimestamp(),
      });

      sendNotification({ uids: [rejectingOrder.customerID], title: 'Refund Rejected', body: `Your refund request for order ${rejectingOrder.orderID || rejectingOrder.id} was rejected: ${rejectReasonText.trim()}`, data: { orderId: rejectingOrder.id } });

      setRejectingOrder(null);
      setRejectReasonText('');
    } catch (error) {
      console.error("Error rejecting refund:", error);
      alert("Failed to reject this refund request.");
    } finally {
      setProcessingId(null);
    }
  };

  const cancellationRequests = orders.filter(o => o.orderStatus === 'Cancellation Pending');
  const refundRequests = orders.filter(o => o.orderStatus === 'Refund Pending');

  return (
    <div className="space-y-6 animate-fade-in relative">
      <div className="bg-white p-8 rounded-[30px] shadow-sm border border-gray-100">
        <h2 className="text-2xl font-black text-gray-800 flex items-center">
          <Undo2 className="w-7 h-7 mr-3 text-red-500" /> Cancellations & Refunds
        </h2>
        <p className="text-gray-400 text-sm mt-2">Review customer cancellation and post-delivery refund requests.</p>
      </div>

      {isLoading ? (
        <div className="flex justify-center items-center h-40">
          <Loader2 className="w-8 h-8 animate-spin text-green-600" />
        </div>
      ) : (
        <>
          {/* 通道 A：发货前取消 */}
          <div className="bg-white rounded-[30px] shadow-sm border border-gray-100 p-8">
            <h3 className="font-bold text-gray-800 text-lg flex items-center mb-1">
              <PackageX className="w-5 h-5 mr-2 text-orange-500" /> Cancellation Requests
            </h3>
            <p className="text-xs text-gray-400 mb-6">Order hasn't been prepared yet — safe to cancel and refund.</p>

            {cancellationRequests.length === 0 ? (
              <p className="text-sm text-gray-400 italic">No pending cancellation requests.</p>
            ) : (
              <div className="space-y-4">
                {cancellationRequests.map(order => (
                  <div key={order.id} className="border border-orange-100 bg-orange-50/40 rounded-2xl p-5 flex justify-between items-start gap-4">
                    <div>
                      <p className="font-bold text-gray-900">{order.orderID || order.id}</p>
                      <p className="text-sm text-gray-600 mt-1">Total: RM {order.totalAmount?.toFixed(2)}</p>
                      <p className="text-sm text-gray-700 mt-2"><span className="font-bold">Reason:</span> {order.cancellationReason || 'No reason provided'}</p>
                    </div>
                    <button
                      disabled={processingId === order.id}
                      onClick={() => handleApproveCancellation(order)}
                      className="bg-green-600 hover:bg-green-700 disabled:opacity-50 text-white shadow-sm font-bold py-2 px-4 rounded-lg transition-all text-xs flex items-center active:scale-95 flex-shrink-0"
                    >
                      {processingId === order.id ? <Loader2 className="w-3 h-3 mr-2 animate-spin" /> : <CheckCircle className="w-3 h-3 mr-2" />}
                      Approve
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* 通道 B：送达后售后退款 */}
          <div className="bg-white rounded-[30px] shadow-sm border border-gray-100 p-8">
            <h3 className="font-bold text-gray-800 text-lg flex items-center mb-1">
              <Ban className="w-5 h-5 mr-2 text-red-500" /> Refund Requests
            </h3>
            <p className="text-xs text-gray-400 mb-6">Order was already delivered — review the evidence before deciding.</p>

            {refundRequests.length === 0 ? (
              <p className="text-sm text-gray-400 italic">No pending refund requests.</p>
            ) : (
              <div className="space-y-4">
                {refundRequests.map(order => (
                  <div key={order.id} className="border border-red-100 bg-red-50/30 rounded-2xl p-5 flex justify-between items-start gap-4">
                    <div className="flex gap-4">
                      {order.refundProofPhoto && (
                        <button
                          onClick={() => setSelectedProofUrl(order.refundProofPhoto!)}
                          className="group relative w-20 h-20 rounded-xl overflow-hidden border border-gray-200 shadow-sm hover:shadow-md transition-shadow flex-shrink-0"
                        >
                          <img src={order.refundProofPhoto} alt="Refund proof" className="w-full h-full object-cover" />
                          <span className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                            <Camera className="w-5 h-5 text-white" />
                          </span>
                        </button>
                      )}
                      <div>
                        <p className="font-bold text-gray-900">{order.orderID || order.id}</p>
                        <p className="text-sm text-gray-600 mt-1">Total: RM {order.totalAmount?.toFixed(2)}</p>
                        <p className="text-sm text-gray-700 mt-2"><span className="font-bold">Reason:</span> {order.refundReason || 'No reason provided'}</p>
                      </div>
                    </div>
                    <div className="flex flex-col gap-2 flex-shrink-0">
                      <button
                        disabled={processingId === order.id}
                        onClick={() => handleApproveRefund(order)}
                        className="bg-green-600 hover:bg-green-700 disabled:opacity-50 text-white shadow-sm font-bold py-2 px-4 rounded-lg transition-all text-xs flex items-center active:scale-95"
                      >
                        {processingId === order.id ? <Loader2 className="w-3 h-3 mr-2 animate-spin" /> : <CheckCircle className="w-3 h-3 mr-2" />}
                        Approve
                      </button>
                      <button
                        disabled={processingId === order.id}
                        onClick={() => { setRejectingOrder(order); setRejectReasonText(''); }}
                        className="bg-white border border-gray-200 hover:bg-gray-50 disabled:opacity-50 text-gray-600 font-bold py-2 px-4 rounded-lg transition-all text-xs flex items-center active:scale-95"
                      >
                        <XCircle className="w-3 h-3 mr-2" /> Reject
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </>
      )}

      {/* 大图预览 */}
      {selectedProofUrl && (
        <div className="fixed inset-0 bg-gray-900/60 backdrop-blur-md z-50 flex justify-center items-center p-4">
          <div className="bg-white w-full max-w-lg rounded-[30px] shadow-2xl p-6 relative animate-zoom-in">
            <button onClick={() => setSelectedProofUrl(null)} className="absolute top-5 right-5 text-gray-300 hover:text-gray-600">
              <XCircle className="w-8 h-8" />
            </button>
            <h2 className="text-lg font-black text-gray-800 mb-4">Refund Evidence</h2>
            <img src={selectedProofUrl} alt="Refund proof full size" className="w-full rounded-2xl border border-gray-100 object-contain max-h-[70vh]" />
          </div>
        </div>
      )}

      {/* 驳回理由 */}
      {rejectingOrder && (
        <div className="fixed inset-0 bg-gray-900/60 backdrop-blur-md z-50 flex justify-center items-center p-4">
          <div className="bg-white w-full max-w-md rounded-[30px] shadow-2xl p-8 relative animate-zoom-in">
            <h2 className="text-lg font-black text-gray-800 mb-2">Reject Refund Request</h2>
            <p className="text-xs text-gray-400 mb-4">Order {rejectingOrder.orderID || rejectingOrder.id} will go back to "Completed". Let the customer know why.</p>
            <textarea
              autoFocus
              value={rejectReasonText}
              onChange={(e) => setRejectReasonText(e.target.value)}
              placeholder="e.g. Photo does not show any damage to the product."
              className="w-full min-h-[100px] p-4 bg-gray-50 border border-transparent rounded-xl text-sm focus:bg-white focus:border-red-400 focus:ring-2 focus:ring-red-100 outline-none transition-all resize-y"
            />
            <div className="flex justify-end gap-3 mt-6">
              <button onClick={() => setRejectingOrder(null)} className="text-gray-500 font-bold text-sm px-4 py-2 hover:text-gray-700">Cancel</button>
              <button
                disabled={!rejectReasonText.trim() || processingId === rejectingOrder.id}
                onClick={handleRejectRefund}
                className="bg-red-500 hover:bg-red-600 disabled:opacity-40 disabled:cursor-not-allowed text-white font-bold text-sm px-5 py-2 rounded-xl flex items-center"
              >
                {processingId === rejectingOrder.id ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : null}
                Confirm Reject
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default RefundManagement;
