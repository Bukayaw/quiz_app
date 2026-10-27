import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'register_page.dart';

class UserListPage extends StatefulWidget {
  final bool embedded;

  const UserListPage({super.key, this.embedded = false});

  @override
  State<UserListPage> createState() => _UserListPageState();
}

class _UserListPageState extends State<UserListPage> {
  // Windows desktop API address.
  // For Android emulator use http://10.0.2.2:8000/users
  static const String apiUrl = 'http://127.0.0.1:8000/users';

  List<Map<String, dynamic>> users = [];

  bool isLoading = false;
  String? errorMessage;

  final List<String> columns = [
    'Stu_Id',
    'Full Name',
    'Region',
    'Address',
    'Role',
    'Phone',
    'Email',
    'Result',
    'Rank',
    'Actions',
  ];

  @override
  void initState() {
    super.initState();
    fetchUsers();
  }

  // FETCH USERS FROM FASTAPI
  Future<void> fetchUsers() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final response = await http
          .get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception(
          'Server returned ${response.statusCode}: ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final List<dynamic> userList = data['users'] ?? [];

      final loadedUsers = userList.map((item) {
        return Map<String, dynamic>.from(item as Map);
      }).toList();

      if (!mounted) return;

      setState(() {
        users = loadedUsers;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        errorMessage = 'Could not load users: $e';
      });
    }
  }

  // OPEN REGISTER PAGE
  Future<void> addUser() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterPage()),
    );

    if (mounted) {
      fetchUsers();
    }
  }

  Future<void> editUser(Map<String, dynamic> user) async {
    final userId = user['user_id'] ?? user['UserId'];
    if (userId == null) {
      _showMessage('Could not edit this user: user ID is missing.');
      return;
    }

    final controllers = {
      'full_name': TextEditingController(
        text: getValue(user, 'full_name', 'FullName') == '—'
            ? ''
            : getValue(user, 'full_name', 'FullName'),
      ),
      'region': TextEditingController(
        text: getValue(user, 'region', 'Region') == '—'
            ? ''
            : getValue(user, 'region', 'Region'),
      ),
      'address': TextEditingController(
        text: getValue(user, 'address', 'Address') == '—'
            ? ''
            : getValue(user, 'address', 'Address'),
      ),
      'role': TextEditingController(
        text: getValue(user, 'role', 'Role') == '—'
            ? ''
            : getValue(user, 'role', 'Role'),
      ),
      'phone': TextEditingController(
        text: getValue(user, 'phone', 'Phone') == '—'
            ? ''
            : getValue(user, 'phone', 'Phone'),
      ),
      'email': TextEditingController(
        text: getValue(user, 'email', 'Email') == '—'
            ? ''
            : getValue(user, 'email', 'Email'),
      ),
    };
    bool saving = false;
    String? formError;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit User'),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in controllers.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: entry.value,
                        keyboardType: entry.key == 'email'
                            ? TextInputType.emailAddress
                            : TextInputType.text,
                        decoration: InputDecoration(
                          labelText: switch (entry.key) {
                            'full_name' => 'Full name',
                            'region' => 'Region',
                            'address' => 'Address',
                            'role' => 'Role',
                            'phone' => 'Phone',
                            'email' => 'Email',
                            _ => entry.key,
                          },
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  if (formError != null)
                    Text(formError!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final payload = {
                        for (final entry in controllers.entries)
                          entry.key: entry.value.text.trim(),
                      };
                      if (payload.values.any((value) => value.isEmpty)) {
                        setDialogState(() {
                          formError = 'All fields are required.';
                        });
                        return;
                      }

                      setDialogState(() {
                        saving = true;
                        formError = null;
                      });

                      try {
                        final response = await http
                            .put(
                              Uri.parse('$apiUrl/$userId'),
                              headers: {'Content-Type': 'application/json'},
                              body: jsonEncode(payload),
                            )
                            .timeout(const Duration(seconds: 15));
                        if (response.statusCode != 200) {
                          throw Exception(
                            'HTTP ${response.statusCode}: ${response.body}',
                          );
                        }

                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        if (mounted) {
                          _showMessage('User updated successfully.');
                          await fetchUsers();
                        }
                      } catch (e) {
                        setDialogState(() {
                          saving = false;
                          formError = 'Could not update user: $e';
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Update'),
            ),
          ],
        ),
      ),
    );

    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  Future<void> deleteUser(Map<String, dynamic> user) async {
    final userId = user['user_id'] ?? user['UserId'];
    if (userId == null) {
      _showMessage('Could not delete this user: user ID is missing.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete user?'),
        content: Text(
          'Delete ${getValue(user, 'full_name', 'FullName')}? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final response = await http
          .delete(Uri.parse('$apiUrl/$userId'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
      if (!mounted) return;
      _showMessage('User deleted successfully.');
      await fetchUsers();
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not delete user: $e');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // GET VALUES WHILE SUPPORTING DIFFERENT JSON KEY CASING
  String getValue(
    Map<String, dynamic> user,
    String snakeCase,
    String pascalCase,
  ) {
    return (user[snakeCase] ?? user[pascalCase] ?? '—').toString();
  }

  // ONE TABLE CELL
  Widget buildCell(String value) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 12),
        child: Text(
          value,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Colors.black87),
        ),
      ),
    );
  }

  // TABLE HEADER
  Widget buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      color: const Color(0xFFF1F3F5),
      child: Row(
        children: columns.map((column) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
              child: Text(
                column,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // USER DATA ROW
  Widget buildUserRow(Map<String, dynamic> user, int index) {
    final values = [
      getValue(user, 'user_id', 'UserId'),
      getValue(user, 'full_name', 'FullName'),
      getValue(user, 'region', 'Region'),
      getValue(user, 'address', 'Address'),
      getValue(user, 'role', 'Role'),
      getValue(user, 'phone', 'Phone'),
      getValue(user, 'email', 'Email'),
      getValue(user, 'result', 'Result'),
      getValue(user, 'rank', 'Rank'),
    ];

    return Container(
      color: index.isEven ? Colors.white : const Color(0xFFF8F9FA),
      child: Row(
        children: [
          ...values.map(buildCell),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Edit user',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => editUser(user),
                ),
                IconButton(
                  tooltip: 'Delete user',
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                    size: 20,
                  ),
                  onPressed: () => deleteUser(user),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      // BACK, REFRESH AND ADD ICONS
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text('Registered Users'),
        leading: IconButton(
          tooltip: 'Back to Admin',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh users',
            onPressed: fetchUsers,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Add user',
            onPressed: addUser,
            icon: const Icon(Icons.add, size: 30),
          ),
          const SizedBox(width: 8),
        ],
      ),

      // USER TABLE
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Text(
                  'Total users: ${users.length}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          if (errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),

          Expanded(
            child: users.isEmpty
                ? Center(
                    child: isLoading
                        ? const CircularProgressIndicator()
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                errorMessage == null
                                    ? 'No users recorded'
                                    : 'Unable to display users',
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: fetchUsers,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Try Again'),
                              ),
                            ],
                          ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: 1150,
                      height: double.infinity,
                      child: Column(
                        children: [
                          buildTableHeader(),

                          const Divider(
                            height: 1,
                            thickness: 0.5,
                            color: Color(0xFFE0E0E0),
                          ),

                          Expanded(
                            child: ListView.builder(
                              itemCount: users.length,
                              itemBuilder: (context, index) {
                                return Column(
                                  children: [
                                    buildUserRow(users[index], index),
                                    const Divider(
                                      height: 1,
                                      thickness: 0.5,
                                      color: Color(0xFFE0E0E0),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
