import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> showChangePasswordSheet(BuildContext context, {required Color primaryColor}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _ChangePasswordSheetContent(primaryColor: primaryColor),
    ),
  );
}

class _ChangePasswordSheetContent extends StatefulWidget {
  final Color primaryColor;
  const _ChangePasswordSheetContent({required this.primaryColor});

  @override
  State<_ChangePasswordSheetContent> createState() => _ChangePasswordSheetContentState();
}

class _ChangePasswordSheetContentState extends State<_ChangePasswordSheetContent> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final credential = EmailAuthProvider.credential(email: user.email!, password: _currentPasswordController.text);
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(_newPasswordController.text);

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Password changed successfully!'), backgroundColor: widget.primaryColor));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      String errorMessage = 'Failed to change password. Please try again.';
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        errorMessage = 'Current password is incorrect.';
      } else if (e.code == 'requires-recent-login') {
        errorMessage = 'Please log out and back in, then retry.';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage), backgroundColor: Colors.redAccent));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to change password: $e'), backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            ),
            const Text("Change Password", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF212121))),
            const SizedBox(height: 20),
            _buildField(controller: _currentPasswordController, label: "Current Password", validator: (v) => (v == null || v.isEmpty) ? 'Please enter your current password' : null),
            const SizedBox(height: 16),
            _buildField(
              controller: _newPasswordController,
              label: "New Password",
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please enter a new password';
                if (v.length < 8) return 'Password must be at least 8 characters long';
                if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Password must contain an uppercase letter';
                if (!RegExp(r'[a-z]').hasMatch(v)) return 'Password must contain a lowercase letter';
                if (!RegExp(r'\d').hasMatch(v)) return 'Password must contain a number';
                if (!RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=~`\[\]\\/;' r"']").hasMatch(v)) {
                  return 'Password must contain a special character';
                }
                return null;
              },
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('At least 8 chars with uppercase, lowercase, number & symbol.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            const SizedBox(height: 16),
            _buildField(
              controller: _confirmPasswordController,
              label: "Confirm New Password",
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please confirm your new password';
                if (v != _newPasswordController.text) return 'Passwords do not match';
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(backgroundColor: widget.primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                child: _isSubmitting
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : const Text("Update Password", style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({required TextEditingController controller, required String label, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      obscureText: true,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
        fillColor: const Color(0xFFF4F6F8),
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }
}
