import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:firebase_auth/firebase_auth.dart'; // [新增] 用于获取当前用户
import 'cart_checkout_screen.dart'; 

class HerbalStoreScreen extends StatefulWidget {
  @override
  _HerbalStoreScreenState createState() => _HerbalStoreScreenState();
}

class _HerbalStoreScreenState extends State<HerbalStoreScreen> {
  int _cartItemCount = 0;
  int _selectedCategoryIndex = 0;

  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color bgGray = const Color(0xFFF4F6F8);

  final List<String> _categories = ["All", "Herbal Tea", "Raw Herbs", "Supplements", "Equipment"];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGray,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false, 
        title: const Text("Herbal Store", style: TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          _buildCartAction(),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildCategoryList(),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('HerbalProduct')
                  .where('taskStatus', isEqualTo: 'Active') 
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)));
                }
                if (snapshot.hasError) {
                  return Center(child: Text("Error loading products: ${snapshot.error}"));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState("No active products available at the moment.");
                }

                var allProducts = snapshot.data!.docs;
                var filteredProducts = allProducts;
                
                if (_selectedCategoryIndex != 0) {
                  String selectedCat = _categories[_selectedCategoryIndex];
                  filteredProducts = allProducts.where((doc) => doc['category'] == selectedCat).toList();
                }

                if (filteredProducts.isEmpty) {
                  return _buildEmptyState("No products found in this category.");
                }

                return GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, 
                    childAspectRatio: 0.65, 
                    crossAxisSpacing: 16, 
                    mainAxisSpacing: 16, 
                  ),
                  itemCount: filteredProducts.length,
                  itemBuilder: (context, index) {
                    var productData = filteredProducts[index].data() as Map<String, dynamic>;
                    String productId = filteredProducts[index].id;
                    return _buildProductCard(productData, productId);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 核心逻辑：添加到 Firebase 购物车 ====================
  Future<void> _addToCartInFirebase(Map<String, dynamic> product, String productId) async {
    // 1. 获取当前用户 ID (和 Checkout 页面的逻辑保持一致)
    User? currentUser = FirebaseAuth.instance.currentUser;
    String uid = currentUser?.uid ?? "TEST_CUSTOMER_001"; 
    String cartId = uid; 

    // 2. 提取商品基本信息
    String name = product['productName'] ?? 'Unknown Product';
    double price = (product['price'] ?? 0).toDouble();
    int stock = product['stockQuantity'] ?? 0;
    String status = product['taskStatus'] ?? 'Active';

    try {
      // 3. 检查：购物车里是不是已经有这个商品了？
      var existingItemQuery = await FirebaseFirestore.instance
          .collection('CartItem')
          .where('cartID', isEqualTo: cartId)
          .where('productID', isEqualTo: productId)
          .where('orderID', isNull: true)
          .limit(1)
          .get();

      if (existingItemQuery.docs.isNotEmpty) {
        // 【情况 A】：购物车里已经有了这个商品 -> 更新数量和小计
        var existingDoc = existingItemQuery.docs.first;
        int currentQty = existingDoc['quantity'] ?? 0;

        // 防超卖逻辑：如果购物车里的数量已经等于库存上限，不给加了！
        if (currentQty >= stock) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot add more. Only $stock left in stock!'), backgroundColor: Colors.orange)
          );
          return; // 终止执行
        }

        int newQty = currentQty + 1;
        await existingDoc.reference.update({
          'quantity': newQty,
          'subtotal': newQty * price,
        });

      } else {
        // 【情况 B】：购物车里没有这个商品 -> 新建一条记录
        await FirebaseFirestore.instance.collection('CartItem').add({
          'cartID': cartId,
          'productID': productId,
          'productName': name,
          'quantity': 1,
          'subtotal': price,
          'stockQuantity': stock,
          'taskStatus': status,
          'orderID': null, // 还没结账，所以是 null
        });
      }

      // 4. 更新右上角的小角标 UI，并弹出成功提示
      setState(() { _cartItemCount++; }); 
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name added to cart!'),
          duration: const Duration(milliseconds: 1500),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

    } catch (e) {
      print("Error adding to cart: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to add to cart. Check connection.'), backgroundColor: Colors.red)
      );
    }
  }
  // =========================================================================

  // ==================== UI 组件 ====================

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 60, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCartAction() {
    User? currentUser = FirebaseAuth.instance.currentUser;
    // 如果还没登录，默认用测试 ID，和你在其他地方的逻辑保持一致
    String cartId = currentUser?.uid ?? "TEST_CUSTOMER_001";

    // ⚠️ 使用 StreamBuilder 实时监听未结账的商品数量
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('CartItem')
          .where('cartID', isEqualTo: cartId)
          .where('orderID', isNull: true) // 核心：只统计没结账的
          .snapshots(),
      builder: (context, snapshot) {
        // 自动计算当前有多少个未结账商品
        int count = 0;
        if (snapshot.hasData) {
          count = snapshot.data!.docs.length;
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.shopping_cart_outlined, color: Color(0xFF1F2937), size: 28),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => CartCheckoutScreen()));
              },
            ),
            if (count > 0) // 只有大于 0 时才显示红点
              Positioned(
                top: 8,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                  child: Text(
                    '$count',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: bgGray,
          borderRadius: BorderRadius.circular(15),
        ),
        child: const TextField(
          decoration: InputDecoration(
            icon: Icon(Icons.search_rounded, color: Colors.grey),
            hintText: "Search herbs, remedies...",
            hintStyle: TextStyle(color: Colors.grey),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryList() {
    return Container(
      color: Colors.white,
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          bool isSelected = _selectedCategoryIndex == index;
          return GestureDetector(
            onTap: () {
              setState(() { _selectedCategoryIndex = index; });
            },
            child: Container(
              margin: const EdgeInsets.only(right: 12, top: 10, bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? primaryGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? primaryGreen : Colors.grey[300]!),
              ),
              alignment: Alignment.center,
              child: Text(
                _categories[index],
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[600],
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product, String productId) {
    String name = product['productName'] ?? 'Unknown Product';
    double price = (product['price'] ?? 0).toDouble();
    String category = product['category'] ?? 'Uncategorized';
    int stock = product['stockQuantity'] ?? 0;
    
    bool isOutOfStock = stock <= 0;

    IconData categoryIcon = Icons.eco;
    Color iconBgColor = Colors.green;
    
    if (category == 'Herbal Tea') {
      categoryIcon = Icons.emoji_food_beverage;
      iconBgColor = Colors.orange;
    } else if (category == 'Supplements') {
      categoryIcon = Icons.medication;
      iconBgColor = Colors.blue;
    } else if (category == 'Equipment') {
      categoryIcon = Icons.hardware;
      iconBgColor = Colors.grey;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: isOutOfStock ? Colors.grey[200] : iconBgColor.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Center(
                child: Icon(categoryIcon, color: isOutOfStock ? Colors.grey[400] : iconBgColor, size: 50),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.toUpperCase(),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 0.5),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isOutOfStock ? Colors.grey[400] : const Color(0xFF1F2937), height: 1.2),
                ),
                const SizedBox(height: 6),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "RM ${price.toStringAsFixed(2)}",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: isOutOfStock ? Colors.grey[400] : primaryGreen),
                        ),
                        Text(
                          isOutOfStock ? "Out of stock" : "$stock left",
                          style: TextStyle(fontSize: 10, color: isOutOfStock ? Colors.redAccent : Colors.grey[500], fontWeight: FontWeight.bold),
                        )
                      ],
                    ),
                    
                    GestureDetector(
                      // ⚠️ 关键修改：点击时执行新写的 Firebase 写入逻辑
                      onTap: isOutOfStock ? null : () => _addToCartInFirebase(product, productId),
                      
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isOutOfStock ? Colors.grey[300] : primaryGreen,
                          shape: BoxShape.circle,
                          boxShadow: isOutOfStock ? [] : [BoxShadow(color: primaryGreen.withOpacity(0.3), blurRadius: 5, offset: const Offset(0, 2))],
                        ),
                        child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}