import { getMessaging, getToken, onMessage } from 'firebase/messaging';
import { doc, updateDoc } from 'firebase/firestore';
import { auth, db } from './firebaseConfig';
import { serverBaseUrl } from './ipaddress';

// 🔑 去 Firebase Console > Project Settings > Cloud Messaging > Web Push certificates
// 生成一对 key，把下面这串换成你自己的 "Key pair"。不填的话网页端拿不到 FCM token，收不到推送。
const VAPID_KEY = 'PASTE_YOUR_WEB_PUSH_VAPID_KEY_HERE';

// Admin 登录后调用一次：请求浏览器通知权限，把这个浏览器的 FCM token 存进 Firestore，
// 并且监听前台推送（网页开着且在前台时，FCM 不会自动弹通知，要自己弹）。
export async function registerWebPushToken() {
  const uid = auth.currentUser?.uid;
  if (!uid || !('Notification' in window)) return;

  try {
    const permission = await Notification.requestPermission();
    if (permission !== 'granted') return;

    const messaging = getMessaging();
    const token = await getToken(messaging, { vapidKey: VAPID_KEY });
    if (token) {
      await updateDoc(doc(db, 'User', uid), { fcmToken: token });
    }

    onMessage(messaging, (payload) => {
      new Notification(payload.notification?.title || 'New Notification', {
        body: payload.notification?.body,
      });
    });
  } catch (error) {
    console.error('Failed to register web push token:', error);
  }
}

// 触发一次推送：uids 指定收件人，或用 role 群发（例如 role: 'DeliveryMan' 通知某个骑手更方便用 uids）
export async function sendNotification(params: { uids?: string[]; role?: string; title: string; body: string; data?: Record<string, string> }) {
  try {
    await fetch(`${serverBaseUrl}/send-notification`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(params),
    });
  } catch (error) {
    console.error('Failed to send notification:', error);
  }
}
