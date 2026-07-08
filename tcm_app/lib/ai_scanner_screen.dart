import 'package:flutter/material.dart';

class AIScannerScreen extends StatefulWidget {
  @override
  _AIScannerScreenState createState() => _AIScannerScreenState();
}

class _AIScannerScreenState extends State<AIScannerScreen> {
  bool _isScanning = false;
  bool _showResult = false;
  String? _selectedSource;

  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color bgGray = const Color(0xFFF4F6F8);

  void _retakePhoto() {
    setState(() {
      _isScanning = false;
      _showResult = false;
      _selectedSource = null;
    });
  }

  void _startAIAnalysis(String source) {
    Navigator.pop(context);
    setState(() {
      _selectedSource = source;
      _isScanning = true;
      _showResult = false;
    });

    // Simulated AI processing delay
    Future.delayed(const Duration(milliseconds: 2500), () {
      setState(() {
        _isScanning = false;
        _showResult = true;
      });
    });
  }

  void _showPhotoSourceOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Select Photo Source", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
              const SizedBox(height: 24),
              _buildSourceTile(Icons.camera_rounded, "Take Photo (Camera)", "Camera"),
              const SizedBox(height: 12),
              _buildSourceTile(Icons.photo_library_rounded, "Upload from Gallery", "Gallery"),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSourceTile(IconData icon, String title, String source) {
    return ListTile(
      leading: Icon(icon, color: primaryGreen),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      onTap: () => _startAIAnalysis(source),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      tileColor: bgGray,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGray,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1F2937)),
          onPressed: () => Navigator.pop(context), // Assumes there's a previous route to pop back to
        ),
        title: const Text(
          "AI Tongue Scanner",
          style: TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Center(
                child: Text(
                  _showResult ? "Analysis Complete" : "Align your tongue within the frame",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 24),

              Center(child: _buildCameraViewfinder()),

              const SizedBox(height: 32),

              // Bottom area switches between the start button, scanning indicator, and results
              if (!_showResult && !_isScanning)
                Center(child: _buildStartButton()),

              if (_isScanning)
                Center(child: _buildScanningIndicator()),

              // Order: diagnosis card -> recommendations -> action buttons
              if (_showResult) ...[
                _buildDiagnosisResultCard(),
                const SizedBox(height: 24),
                _buildRecommendationSection(),
                const SizedBox(height: 32),
                _buildActionButtons(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraViewfinder() {
    return Container(
      height: 350,
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.face_retouching_natural_rounded, color: Colors.white.withOpacity(0.1), size: 150),

          Positioned(top: 20, left: 20, child: _buildCorner(isTopLeft: true)),
          Positioned(top: 20, right: 20, child: _buildCorner(isTopRight: true)),
          Positioned(bottom: 20, left: 20, child: _buildCorner(isBottomLeft: true)),
          Positioned(bottom: 20, right: 20, child: _buildCorner(isBottomRight: true)),

          if (_isScanning)
            Container(
              decoration: BoxDecoration(
                color: primaryGreen.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCorner({bool isTopLeft = false, bool isTopRight = false, bool isBottomLeft = false, bool isBottomRight = false}) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: isTopLeft || isTopRight ? primaryGreen : Colors.transparent, width: 4),
          bottom: BorderSide(color: isBottomLeft || isBottomRight ? primaryGreen : Colors.transparent, width: 4),
          left: BorderSide(color: isTopLeft || isBottomLeft ? primaryGreen : Colors.transparent, width: 4),
          right: BorderSide(color: isTopRight || isBottomRight ? primaryGreen : Colors.transparent, width: 4),
        ),
      ),
    );
  }

  Widget _buildStartButton() {
    return ElevatedButton.icon(
      onPressed: _showPhotoSourceOptions,
      icon: const Icon(Icons.add_photo_alternate_rounded, color: Colors.white),
      label: const Text("Select Photo Source", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryGreen,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        elevation: 5,
        shadowColor: primaryGreen.withOpacity(0.5),
      ),
    );
  }

  Widget _buildScanningIndicator() {
    return Column(
      children: [
        CircularProgressIndicator(color: primaryGreen, strokeWidth: 4),
        const SizedBox(height: 16),
        Text("Analyzing from ${_selectedSource ?? 'source'}...", style: TextStyle(color: primaryGreen, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildDiagnosisResultCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("AI Diagnosis", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(10)),
                child: Text("94% Match", style: TextStyle(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const Divider(height: 30, thickness: 1, color: Color(0xFFEEEEEE)),
          Column(
            children: [
              _buildResultRow("Tongue Color", "Pale Red", Colors.red[400]!),
              const SizedBox(height: 12),
              // _buildResultRow("Coating Thickness", "Thick", Colors.orange[400]!),
              // const SizedBox(height: 12),
              // _buildResultRow("Coating Color", "Yellowish", Colors.yellow[700]!),
            ],
          ),
          const SizedBox(height: 24),
          const Text("Detected Pattern:", style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              Chip(label: const Text("Heatiness", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.orange[400], side: BorderSide.none),
              // Chip(label: const Text("Spleen Def.", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: primaryGreen, side: BorderSide.none),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultRow(String label, String value, Color dotColor) {
    return Center(
      child: SizedBox(
        width: 250,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                const SizedBox(width: 12),
                Text(label, style: const TextStyle(color: Color(0xFF4B5563), fontSize: 15)),
              ],
            ),
            Text(value, style: const TextStyle(color: Color(0xFF1F2937), fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // UI representation of the CARS recommendation logic
  Widget _buildRecommendationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: Colors.orange[400], size: 20),
            const SizedBox(width: 8),
            const Text("Recommended for You", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
          ],
        ),
        const SizedBox(height: 6),
        const Text("Herbs filtered to balance Damp-Heat", style: TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 16),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none, // Prevents the card shadow from being clipped
          child: Row(
            children: [
              _buildProductCard("Chrysanthemum Tea", "Clears Heat & Detox", "RM 15.00"),
              const SizedBox(width: 16),
              _buildProductCard("Barley & Winter Melon", "Removes Dampness", "RM 22.00"),
              const SizedBox(width: 16),
              _buildProductCard("Herbal Cooling Jelly", "Soothes Stomach", "RM 10.50"),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProductCard(String name, String tag, String price) {
    return Container(
      width: 150,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 100,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Icon(Icons.spa_rounded, color: primaryGreen.withOpacity(0.5), size: 40),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Corresponds to the Health Tag concept from the thesis
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(4)),
                  child: Text(tag, style: TextStyle(color: Colors.orange[800], fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1F2937))),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(price, style: TextStyle(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 13)),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: primaryGreen, shape: BoxShape.circle),
                      child: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white, size: 14),
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

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Sent to Doctor for Review!'), backgroundColor: primaryGreen));
            },
            icon: const Icon(Icons.medical_services_rounded, color: Colors.white),
            label: const Text("Request Doctor Review", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              elevation: 3,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _retakePhoto,
            icon: Icon(Icons.replay_rounded, color: primaryGreen),
            label: Text("Retake Photo", style: TextStyle(color: primaryGreen, fontSize: 16, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: primaryGreen, width: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
        ),
      ],
    );
  }
}