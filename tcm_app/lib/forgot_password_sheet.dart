import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'ipaddress.dart';

Future<void> showForgotPasswordSheet(BuildContext context, {required Color primaryColor, String? initialEmail}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _ForgotPasswordSheetContent(primaryColor: primaryColor, initialEmail: initialEmail ?? ''),
    ),
  );
}

class _ForgotPasswordSheetContent extends StatefulWidget {
  final Color primaryColor;
  final String initialEmail;
  const _ForgotPasswordSheetContent({required this.primaryColor, required this.initialEmail});

  @override
  State<_ForgotPasswordSheetContent> createState() => _ForgotPasswordSheetContentState();
}

class _ForgotPasswordSheetContentState extends State<_ForgotPasswordSheetContent> {
  late final TextEditingController _emailController = TextEditingController(text: widget.initialEmail);
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _resetFormKey = GlobalKey<FormState>();

  bool _isEmailStep = true;
  bool _isSubmitting = false;
  String? _emailError;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _emailError = 'Please enter your email address');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _emailError = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$serverBaseUrl/request-password-reset'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      final result = jsonDecode(response.body);
      if (result['success'] == true) {
        setState(() => _isEmailStep = false);
      } else {
        setState(() => _emailError = result['error'] ?? 'Failed to send reset code. Please try again.');
      }
    } catch (e) {
      setState(() => _emailError = 'Could not reach the server. Please try again.');
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  Future<void> _confirmReset() async {
    if (!_resetFormKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final response = await http.post(
        Uri.parse('$serverBaseUrl/confirm-password-reset'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _emailController.text.trim(),
          'code': _codeController.text.trim(),
          'newPassword': _newPasswordController.text,
        }),
      );
      final result = jsonDecode(response.body);
      if (!mounted) return;
      if (result['success'] == true) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Password reset successfully! Please sign in with your new password.'), backgroundColor: widget.primaryColor));
      } else {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['error'] ?? 'Failed to reset password.'), backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not reach the server. Please try again.'), backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: _isEmailStep ? _buildEmailStep() : _buildResetStep(),
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
    );
  }

  Widget _buildEmailStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHandle(),
        const Text("Reset Password", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF212121))),
        const SizedBox(height: 8),
        const Text("Enter your account email and we'll send you a 6-digit reset code.", style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Email Address',
            prefixIcon: const Icon(Icons.email_outlined),
            errorText: _emailError,
            fillColor: const Color(0xFFF4F6F8),
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _requestCode,
            style: ElevatedButton.styleFrom(backgroundColor: widget.primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
            child: _isSubmitting
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : const Text('Send Code', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      ],
    );
  }

  Widget _buildResetStep() {
    return Form(
      key: _resetFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHandle(),
          const Text("Enter Reset Code", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF212121))),
          const SizedBox(height: 8),
          Text("Enter the code sent to ${_emailController.text.trim()} and choose a new password.", style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          TextFormField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Reset Code',
              prefixIcon: const Icon(Icons.pin_outlined),
              fillColor: const Color(0xFFF4F6F8),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter the code from your email' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _newPasswordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'New Password',
              prefixIcon: const Icon(Icons.lock_outline),
              fillColor: const Color(0xFFF4F6F8),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            ),
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
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Confirm New Password',
              prefixIcon: const Icon(Icons.lock_outline),
              fillColor: const Color(0xFFF4F6F8),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Please confirm your new password';
              if (v != _newPasswordController.text) return 'Passwords do not match';
              return null;
            },
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              TextButton(
                onPressed: _isSubmitting ? null : () => setState(() => _isEmailStep = true),
                child: const Text('Back'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _confirmReset,
                style: ElevatedButton.styleFrom(backgroundColor: widget.primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                child: _isSubmitting
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Reset Password', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
