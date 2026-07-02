import React, { useState, useEffect } from 'react';
import { Plus, Edit, Trash2, AlertTriangle, CheckCircle, X, Loader2 } from 'lucide-react';
import { collection, getDocs, addDoc, updateDoc, deleteDoc, doc } from 'firebase/firestore';
import { db } from '../firebaseConfig'; // 确保路径正确

// 定义数据库的数据结构
interface Product {
  productID: string;
  productName: string;
  description: string;
  price: number;
  stockQuantity: number;
  category: string;
  taskStatus: string;
}

const HerbalProducts: React.FC = () => {
  // 核心状态管理
  const [products, setProducts] = useState<Product[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  
  // 权限控制：从本地缓存读取当前登录者的角色 (在 Login 页面设置的)
  // User.userRole 登录后统一是 'Admin'，Admin/Doctor 细分要看 Administrator.adminRole
  const currentUserRole = localStorage.getItem('adminRole') || 'Admin';
  const isAdmin = currentUserRole === 'Admin';

  // 弹窗与表单状态
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [formData, setFormData] = useState({
    productName: '',
    description: '',
    price: '',
    stockQuantity: '',
    category: 'Herbal Tea',
    taskStatus: 'Active',
  });

  // 过滤与搜索状态
  const [searchTerm, setSearchTerm] = useState('');
  const [filterCategory, setFilterCategory] = useState('All Categories');

  // 组件加载时获取数据
  useEffect(() => {
    fetchProducts();
  }, []);

  // 1. Read: 从 Firebase 读取数据
  const fetchProducts = async () => {
    setIsLoading(true);
    try {
      const querySnapshot = await getDocs(collection(db, 'HerbalProduct'));
      const fetchedData = querySnapshot.docs.map(doc => ({
        productID: doc.id, // 使用 Firebase 自动生成的 Document ID 作为 productID
        ...doc.data()
      })) as Product[];
      setProducts(fetchedData);
    } catch (error) {
      console.error("Error fetching products:", error);
      alert("Failed to load products. Please check your connection.");
    } finally {
      setIsLoading(false);
    }
  };

  // 2. Create / Update: 提交表单保存到 Firebase
  const handleSaveProduct = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsLoading(true);

    const productPayload = {
      productName: formData.productName,
      description: formData.description,
      price: parseFloat(formData.price),
      stockQuantity: parseInt(formData.stockQuantity, 10),
      category: formData.category,
      taskStatus: formData.taskStatus,
    };

    try {
      if (editingId) {
        // Update 模式
        await updateDoc(doc(db, 'HerbalProduct', editingId), productPayload);
      } else {
        // Create 模式：新建文档后，将文档的 ID 作为 productID 存入
        const docRef = await addDoc(collection(db, 'HerbalProduct'), productPayload);
        await updateDoc(docRef, { productID: docRef.id });
      }
      
      closeModal();
      fetchProducts(); // 刷新列表
    } catch (error) {
      console.error("Error saving product:", error);
      alert("Failed to save product.");
      setIsLoading(false);
    }
  };

  // 3. Delete: 删除商品
  const handleDelete = async (id: string, name: string) => {
    if (window.confirm(`Are you sure you want to delete "${name}"? This action cannot be undone.`)) {
      try {
        setIsLoading(true);
        await deleteDoc(doc(db, 'HerbalProduct', id));
        fetchProducts();
      } catch (error) {
        console.error("Error deleting product:", error);
        alert("Failed to delete product.");
        setIsLoading(false);
      }
    }
  };

  // 打开弹窗进行新建
  const openNewModal = () => {
    setEditingId(null);
    setFormData({ productName: '', description: '', price: '', stockQuantity: '', category: 'Herbal Tea', taskStatus: 'Active' });
    setIsModalOpen(true);
  };

  // 打开弹窗进行编辑
  const openEditModal = (product: Product) => {
    setEditingId(product.productID);
    setFormData({
      productName: product.productName,
      description: product.description,
      price: product.price.toString(),
      stockQuantity: product.stockQuantity.toString(),
      category: product.category,
      taskStatus: product.taskStatus || 'Active',
    });
    setIsModalOpen(true);
  };

  const closeModal = () => setIsModalOpen(false);

  // 过滤逻辑
  const filteredProducts = products.filter(p => {
    const matchSearch = p.productName.toLowerCase().includes(searchTerm.toLowerCase()) || p.productID.toLowerCase().includes(searchTerm.toLowerCase());
    const matchCategory = filterCategory === 'All Categories' || p.category === filterCategory;
    return matchSearch && matchCategory;
  });

  return (
    <div className="space-y-6 animate-fade-in relative">
      
      {/* 顶部操作栏 */}
      <div className="flex justify-between items-center bg-white p-4 rounded-xl shadow-sm border border-gray-100">
        <div className="flex space-x-4">
          <input 
            type="text" 
            placeholder="Search name or ID..." 
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="bg-gray-50 border border-gray-200 text-gray-700 rounded-lg focus:ring-green-500 focus:border-green-500 block w-64 p-2.5 outline-none" 
          />
          <select 
            value={filterCategory}
            onChange={(e) => setFilterCategory(e.target.value)}
            className="bg-gray-50 border border-gray-200 text-gray-700 rounded-lg focus:ring-green-500 outline-none p-2.5"
          >
            <option>All Categories</option>
            <option>Herbal Tea</option>
            <option>Raw Herbs</option>
            <option>Supplements</option>
            <option>Equipment</option>
          </select>
        </div>

        {/* 权限控制：只有 Admin 才能看到添加按钮 */}
        {isAdmin && (
          <button 
            onClick={openNewModal}
            className="flex items-center bg-green-600 hover:bg-green-700 text-white font-medium rounded-lg text-sm px-5 py-2.5 transition-colors shadow-md shadow-green-200"
          >
            <Plus className="w-5 h-5 mr-2" />
            Add New Product
          </button>
        )}
      </div>

      {/* 产品表格 */}
      <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
        {isLoading ? (
          <div className="flex justify-center items-center h-64 text-green-600">
            <Loader2 className="w-10 h-10 animate-spin" />
          </div>
        ) : (
          <table className="w-full text-sm text-left text-gray-500">
            <thead className="text-xs text-gray-700 uppercase bg-gray-50 border-b border-gray-100">
              <tr>
                <th className="px-6 py-4">Product details</th>
                <th className="px-6 py-4">Category</th>
                <th className="px-6 py-4">Price (RM)</th>
                <th className="px-6 py-4">Stock Level</th>
                <th className="px-6 py-4">Status</th>
                {/* 权限控制：如果不是Admin，就隐藏 Actions 这一列 */}
                {isAdmin && <th className="px-6 py-4 text-center">Actions</th>}
              </tr>
            </thead>
            <tbody>
              {filteredProducts.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-6 py-10 text-center text-gray-400 font-medium">
                    No products found in the database.
                  </td>
                </tr>
              ) : (
                filteredProducts.map((item) => (
                  <tr key={item.productID} className="border-b hover:bg-gray-50 transition-colors">
                    <td className="px-6 py-4">
                      <p className="font-bold text-gray-900">{item.productName}</p>
                      <p className="text-xs text-gray-400 font-mono mt-1">ID: {item.productID}</p>
                    </td>
                    <td className="px-6 py-4 font-medium text-gray-600">{item.category}</td>
                    <td className="px-6 py-4 font-bold text-gray-900">{item.price.toFixed(2)}</td>
                    <td className="px-6 py-4">
                      <div className="flex items-center space-x-2">
                        <span className="font-bold text-gray-700">{item.stockQuantity}</span>
                        {/* 根据真实库存数量自动计算徽章颜色 */}
                        <StockBadge quantity={item.stockQuantity} />
                      </div>
                    </td>
                    <td className="px-6 py-4">
                      <span className={`px-2.5 py-1 rounded-full text-xs font-bold ${item.taskStatus === 'Active' ? 'bg-blue-50 text-blue-600' : 'bg-gray-100 text-gray-500'}`}>
                        {item.taskStatus}
                      </span>
                    </td>
                    
                    {/* 权限控制：只有 Admin 能操作编辑和删除 */}
                    {isAdmin && (
                      <td className="px-6 py-4 text-center space-x-3">
                        <button onClick={() => openEditModal(item)} className="text-blue-600 hover:text-blue-900 bg-blue-50 p-2 rounded-lg transition-colors" title="Edit">
                          <Edit className="w-4 h-4" />
                        </button>
                        <button onClick={() => handleDelete(item.productID, item.productName)} className="text-red-600 hover:text-red-900 bg-red-50 p-2 rounded-lg transition-colors" title="Delete">
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </td>
                    )}
                  </tr>
                ))
              )}
            </tbody>
          </table>
        )}
      </div>

      {/* Add / Edit 弹窗 */}
      {isModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-40 backdrop-blur-sm">
          <div className="bg-white rounded-[24px] shadow-2xl w-full max-w-2xl p-8 animate-fade-in">
            <div className="flex justify-between items-center mb-6">
              <h2 className="text-2xl font-bold text-gray-800">
                {editingId ? 'Edit Product' : 'Add New Product'}
              </h2>
              <button onClick={closeModal} className="text-gray-400 hover:bg-gray-100 p-2 rounded-full transition-colors">
                <X className="w-6 h-6" />
              </button>
            </div>

            <form onSubmit={handleSaveProduct} className="space-y-5">
              <div className="grid grid-cols-2 gap-5">
                {/* 字段 1: Product Name */}
                <div>
                  <label className="block text-xs font-bold text-gray-500 uppercase mb-2">Product Name</label>
                  <input required type="text" value={formData.productName} onChange={e => setFormData({...formData, productName: e.target.value})} className="w-full p-3 bg-gray-50 border border-transparent rounded-xl focus:bg-white focus:border-green-500 focus:ring-2 focus:ring-green-200 outline-none" />
                </div>
                {/* 字段 2: Category */}
                <div>
                  <label className="block text-xs font-bold text-gray-500 uppercase mb-2">Category</label>
                  <select required value={formData.category} onChange={e => setFormData({...formData, category: e.target.value})} className="w-full p-3 bg-gray-50 border border-transparent rounded-xl focus:bg-white focus:border-green-500 focus:ring-2 focus:ring-green-200 outline-none">
                    <option>Herbal Tea</option>
                    <option>Raw Herbs</option>
                    <option>Supplements</option>
                    <option>Equipment</option>
                  </select>
                </div>
                {/* 字段 3: Price */}
                <div>
                  <label className="block text-xs font-bold text-gray-500 uppercase mb-2">Price (RM)</label>
                  <input required type="number" step="0.01" min="0" value={formData.price} onChange={e => setFormData({...formData, price: e.target.value})} className="w-full p-3 bg-gray-50 border border-transparent rounded-xl focus:bg-white focus:border-green-500 focus:ring-2 focus:ring-green-200 outline-none" />
                </div>
                {/* 字段 4: Stock Quantity */}
                <div>
                  <label className="block text-xs font-bold text-gray-500 uppercase mb-2">Stock Quantity</label>
                  <input required type="number" min="0" value={formData.stockQuantity} onChange={e => setFormData({...formData, stockQuantity: e.target.value})} className="w-full p-3 bg-gray-50 border border-transparent rounded-xl focus:bg-white focus:border-green-500 focus:ring-2 focus:ring-green-200 outline-none" />
                </div>
              </div>

              {/* 字段 5: Task Status */}
              <div>
                <label className="block text-xs font-bold text-gray-500 uppercase mb-2">Task Status</label>
                <select value={formData.taskStatus} onChange={e => setFormData({...formData, taskStatus: e.target.value})} className="w-full p-3 bg-gray-50 border border-transparent rounded-xl focus:bg-white focus:border-green-500 outline-none">
                  <option value="Active">Active (Visible to customers)</option>
                  <option value="Inactive">Inactive (Hidden from store)</option>
                </select>
              </div>

              {/* 字段 6: Description */}
              <div>
                <label className="block text-xs font-bold text-gray-500 uppercase mb-2">Description</label>
                <textarea rows={3} value={formData.description} onChange={e => setFormData({...formData, description: e.target.value})} className="w-full p-3 bg-gray-50 border border-transparent rounded-xl focus:bg-white focus:border-green-500 focus:ring-2 focus:ring-green-200 outline-none"></textarea>
              </div>

              {/* 提交按钮 */}
              <div className="flex justify-end pt-4">
                <button type="button" onClick={closeModal} className="px-6 py-3 text-gray-500 font-bold hover:bg-gray-100 rounded-xl mr-4 transition-colors">
                  Cancel
                </button>
                <button type="submit" disabled={isLoading} className="px-8 py-3 bg-green-600 hover:bg-green-700 text-white font-bold rounded-xl shadow-lg shadow-green-200 transition-colors disabled:opacity-70">
                  {isLoading ? 'Saving...' : 'Save Product'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};

// 智能库存状态标签：根据你数据库里的 stockQuantity 数字自动变化
const StockBadge = ({ quantity }: { quantity: number }) => {
  if (quantity === 0) {
    return <span className="flex items-center w-max px-2 py-1 rounded text-xs font-bold bg-red-100 text-red-700"><AlertTriangle className="w-3 h-3 mr-1" /> Out of Stock</span>;
  }
  if (quantity <= 20) {
    return <span className="flex items-center w-max px-2 py-1 rounded text-xs font-bold bg-orange-100 text-orange-700"><AlertTriangle className="w-3 h-3 mr-1" /> Low Stock</span>;
  }
  return <span className="flex items-center w-max px-2 py-1 rounded text-xs font-bold bg-green-100 text-green-700"><CheckCircle className="w-3 h-3 mr-1" /> In Stock</span>;
};

export default HerbalProducts;