// Service worker for Firebase Cloud Messaging — shows a browser notification
// when a push arrives while this tab is closed or in the background.
// Vite serves anything in Web/public/ at the site root, so this must live
// here to be reachable at /firebase-messaging-sw.js (required by FCM's web SDK).
importScripts('https://www.gstatic.com/firebasejs/12.15.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.15.0/firebase-messaging-compat.js');

// Same values as Web/firebaseConfig.ts — service workers can't import our
// TypeScript modules, so this one small duplication is unavoidable.
firebase.initializeApp({
  apiKey: "AIzaSyCIylXeCQdawH_S5tl3A0KjPzSYYVP0sdQ",
  authDomain: "tcm-db-2e5b3.firebaseapp.com",
  projectId: "tcm-db-2e5b3",
  storageBucket: "tcm-db-2e5b3.firebasestorage.app",
  messagingSenderId: "689825329356",
  appId: "1:689825329356:web:877999f17715d145b69269",
});

firebase.messaging();
