import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final regionController = TextEditingController();
  final addressController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  bool obscurePassword = true;
  String? registrationMessage;
  bool registrationSucceeded = false;

  String get apiBaseUrl {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return 'http://127.0.0.1:8000';
    }
    return 'http://10.0.2.2:8000';
  }

  @override
  void dispose() {
    nameController.dispose();
    regionController.dispose();
    addressController.dispose();
    phoneController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  String? validateName(String? value) {
    final name = value?.trim() ?? '';

    if (name.isEmpty) {
      return 'Please enter your full name';
    }

    if (name.length < 6) {
      return 'Full name must be at least 6 characters';
    }

    if (!RegExp(r'^[a-zA-Z ]+$').hasMatch(name)) {
      return 'Use English letters and spaces only';
    }

    return null;
  }

  String? validateRegion(String? value) {
    final region = value?.trim() ?? '';

    if (region.isEmpty) {
      return 'Please enter your region';
    }

    if (region.length < 4) {
      return 'Region must be at least 4 characters';
    }

    return null;
  }

  String? validateAddress(String? value) {
    final address = value?.trim() ?? '';

    if (address.isEmpty) {
      return 'Please enter your address';
    }

    if (address.length < 4) {
      return 'Address must be at least 4 characters';
    }

    return null;
  }

  String? validatePhone(String? value) {
    final phone = value?.trim() ?? '';

    if (!RegExp(r'^[79][0-9]{8}$').hasMatch(phone)) {
      return 'Enter 9 digits starting with 9 or 7';
    }

    return null;
  }

  String? validateEmail(String? value) {
    final email = value?.trim() ?? '';

    if (email.isEmpty) {
      return 'Please enter your email';
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address';
    }

    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.length < 8) {
      return 'Password must be at least 8 characters';
    }

    return null;
  }

  Future<void> registerUser() async {
    setState(() {
      registrationMessage = null;
      registrationSucceeded = false;
    });

    if (!_formKey.currentState!.validate()) {
      setState(() {
        registrationMessage = 'Please correct the highlighted fields.';
      });
      return;
    }

    setState(() => isLoading = true);

    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/users/register'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'full_name': nameController.text.trim(),
              'region': regionController.text.trim(),
              'address': addressController.text.trim(),
              'phone': '+251${phoneController.text.trim()}',
              'email': emailController.text.trim(),
              'password': passwordController.text,
            }),
          )
          .timeout(const Duration(seconds: 20));

      final dynamic decoded = response.body.isEmpty
          ? null
          : jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 201) {
        final Map<String, dynamic> data = decoded is Map<String, dynamic>
            ? decoded
            : {};

        final userId = data['user_id']?.toString() ?? 'Generated';

        // Clear the form after successful registration.
        _formKey.currentState!.reset();
        nameController.clear();
        regionController.clear();
        addressController.clear();
        phoneController.clear();
        emailController.clear();
        passwordController.clear();

        setState(() {
          obscurePassword = true;
          registrationSucceeded = true;
          registrationMessage =
              'Registration successful. User ID: $userId. You can now log in.';
        });
      } else {
        final dynamic detail = decoded is Map<String, dynamic>
            ? decoded['detail']
            : null;

        String message;

        if (detail is List) {
          message = detail
              .map(
                (item) => item is Map
                    ? (item['msg'] ?? 'Invalid input').toString()
                    : item.toString(),
              )
              .join('\n');
        } else {
          message = detail?.toString() ?? 'Registration failed.';
        }

        setState(() {
          registrationMessage =
              'Registration failed (${response.statusCode}): $message';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          registrationMessage =
              'Exception (${error.runtimeType}): $error\n'
              'Request URL: $apiBaseUrl/users/register';
        });
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  InputDecoration fieldDecoration(
    String label, {
    String? hint,
    Widget? prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefix,
      suffixIcon: suffix,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    );
  }

  Widget buildTextField({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
    TextInputType keyboardType = TextInputType.text,
    Widget? prefix,
    Widget? suffix,
    bool obscureText = false,
    int? maxLength,
    String? hint,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLength: maxLength,
      validator: validator,
      decoration: fieldDecoration(
        label,
        hint: hint,
        prefix: prefix,
        suffix: suffix,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Registration'), centerTitle: true),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.person_add_alt_1,
                          size: 58,
                          color: Colors.blue,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Create Account',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Enter your information below',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        buildTextField(
                          controller: nameController,
                          label: 'Full Name',
                          hint: 'Enter your full name',
                          prefix: const Icon(Icons.person_outline),
                          validator: validateName,
                        ),

                        const SizedBox(height: 16),

                        buildTextField(
                          controller: regionController,
                          label: 'Region',
                          hint: 'Enter your region',
                          prefix: const Icon(Icons.map_outlined),
                          validator: validateRegion,
                        ),

                        const SizedBox(height: 16),

                        buildTextField(
                          controller: addressController,
                          label: 'Address',
                          hint: 'Enter your address',
                          prefix: const Icon(Icons.location_on_outlined),
                          validator: validateAddress,
                        ),

                        const SizedBox(height: 16),

                        buildTextField(
                          controller: phoneController,
                          label: 'Phone Number',
                          hint: '912345678',
                          prefix: const Padding(
                            padding: EdgeInsets.only(left: 12, right: 8),
                            child: Center(
                              widthFactor: 1,
                              child: Text(
                                '+251',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                          keyboardType: TextInputType.phone,
                          maxLength: 9,
                          validator: validatePhone,
                        ),

                        const SizedBox(height: 8),

                        buildTextField(
                          controller: emailController,
                          label: 'Email',
                          hint: 'example@email.com',
                          prefix: const Icon(Icons.email_outlined),
                          keyboardType: TextInputType.emailAddress,
                          validator: validateEmail,
                        ),

                        const SizedBox(height: 16),

                        buildTextField(
                          controller: passwordController,
                          label: 'Password',
                          prefix: const Icon(Icons.lock_outline),
                          obscureText: obscurePassword,
                          suffix: IconButton(
                            onPressed: () {
                              setState(() {
                                obscurePassword = !obscurePassword;
                              });
                            },
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                          ),
                          validator: validatePassword,
                        ),

                        // const SizedBox(height: 16),
                        // const ListTile(
                        //   contentPadding: EdgeInsets.zero,
                        //   leading: Icon(Icons.access_time),
                        //   title: Text('Created At'),
                        //   subtitle: Text(
                        //     'Automatically recorded by SQL Server',
                        //   ),
                        // ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : registerUser,
                            child: isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Register',
                                    style: TextStyle(fontSize: 16),
                                  ),
                          ),
                        ),

                        if (registrationMessage != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: registrationSucceeded
                                  ? Colors.green.shade50
                                  : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: registrationSucceeded
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  registrationSucceeded
                                      ? Icons.check_circle
                                      : Icons.error,
                                  color: registrationSucceeded
                                      ? Colors.green.shade700
                                      : Colors.red.shade700,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    registrationMessage!,
                                    style: TextStyle(
                                      color: registrationSucceeded
                                          ? Colors.green.shade900
                                          : Colors.red.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 12),

                        TextButton(
                          onPressed: isLoading
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Back to Previous Page'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
