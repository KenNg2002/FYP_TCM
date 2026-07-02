// src/firebaseConfig.ts
import { initializeApp } from "firebase/app";
import { getAuth } from "firebase/auth";
import { getFirestore } from "firebase/firestore"; 

// 这是你专属的真实 Firebase 配置 (从截图提取)
export const firebaseConfig = {
  apiKey: "AIzaSyCIylXeCQdawH_S5tl3A0KjPzSYYVP0sdQ",
  authDomain: "tcm-db-2e5b3.firebaseapp.com",
  projectId: "tcm-db-2e5b3",
  storageBucket: "tcm-db-2e5b3.firebasestorage.app",
  messagingSenderId: "689825329356",
  appId: "1:689825329356:web:877999f17715d145b69269",
  measurementId: "G-G33Y0Z7K6E"
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);

// Initialize Firebase Authentication (用于 Admin 登录)
export const auth = getAuth(app);

// Initialize Cloud Firestore (后续开发商品和订单管理会用到)
export const db = getFirestore(app);