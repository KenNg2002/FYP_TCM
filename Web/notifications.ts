import { getMessaging, getToken, onMessage } from 'firebase/messaging';
import { doc, updateDoc } from 'firebase/firestore';
import { auth, db } from './firebaseConfig';
import { serverBaseUrl } from './ipaddress';

// Generate a key pair in Firebase Console > Project Settings > Cloud Messaging >
// Web Push certificates and paste it below. Without it, the web app can't get an
// FCM token and won't receive push notifications.
const VAPID_KEY = 'PASTE_YOUR_WEB_PUSH_VAPID_KEY_HERE';

// Call once after admin login: requests browser notification permission, saves this
// browser's FCM token to Firestore, and listens for foreground pushes (FCM doesn't
// auto-display a notification while the page is open and in the foreground, so we
// show one manually).
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

// Sends a push: pass uids for specific recipients, or role to broadcast to a group
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
