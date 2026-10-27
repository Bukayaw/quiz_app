import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class UserRecord {
  final int userId;
  final String fullName;
  final String region;
  final String address;
  final String role;
  final String phone;
  final String email;

  UserRecord({
    required this.userId,
    required this.fullName,
    required this.region,
    required this.address,
    required this.role,
    required this.phone,
    required this.email,
  });

  factory UserRecord.fromJson(Map<String, dynamic> json) {
    return UserRecord(
      userId: json['user_id'] as int,
      fullName: json['full_name'] ?? '',
      region: json['region'] ?? '',
      address: json['address'] ?? '',
      role: json['role'] ?? '',
      phone: json['phone'] ?? '',
      email: json['email'] ?? '',
    );
  }
}

class UsersTable extends StatefulWidget {
  const UsersTable({super.key});

  @override
  State<UsersTable> createState() => _UsersTableState();
}

class _UsersTableState extends State<UsersTable> {
  List<UserRecord> users = [];
  bool isLoading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    loadUsers();
  }

  Future<void> loadUsers() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final response = await http
          .get(Uri.parse('http://127.0.0.1:8000/users'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      final List<dynamic> userList = decoded['users'];

      final fetchedUsers = userList.map((item) {
        return UserRecord.fromJson(Map<String, dynamic>.from(item));
      }).toList();

      if (!mounted) return;

      setState(() {
        users = fetchedUsers;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Refresh users',
              onPressed: loadUsers,
              icon: const Icon(Icons.refresh),
            ),
            const SizedBox(width: 8),
            Text('Total users: ${users.length}'),
          ],
        ),
        const Divider(),

        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Failed to load users: $errorMessage'),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: loadUsers,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : users.isEmpty
              ? const Center(child: Text('No users to display'))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Stu_Id')),
                        DataColumn(label: Text('Full Name')),
                        DataColumn(label: Text('Region')),
                        DataColumn(label: Text('Address')),
                        DataColumn(label: Text('Role')),
                        DataColumn(label: Text('Phone')),
                        DataColumn(label: Text('Email')),
                        DataColumn(label: Text('Password')),
                        DataColumn(label: Text('Result')),
                        DataColumn(label: Text('Rank')),
                      ],
                      rows: users.map((user) {
                        return DataRow(
                          cells: [
                            DataCell(Text('${user.userId}')),
                            DataCell(Text(user.fullName)),
                            DataCell(Text(user.region)),
                            DataCell(Text(user.address)),
                            DataCell(Text(user.role)),
                            DataCell(Text(user.phone)),
                            DataCell(Text(user.email)),

                            // Never display password hashes.
                            const DataCell(Text('••••••')),

                            // These need quiz-result data from
                            // a separate backend endpoint.
                            const DataCell(Text('—')),
                            const DataCell(Text('—')),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
