import 'package:flutter/material.dart';
import 'dashboard.dart';
import 'examresult.dart';
import 'user_list_page.dart';
import 'question_list_page.dart';
import 'topic.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  String selectedPage = 'Dashboard';

  final List<String> menuItems = [
    'Dashboard',
    'Users',
    'Topics',
    'Questions',
    'Results',
    'Settings',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // FIXED LEFT SIDEBAR
            SizedBox(
              width: 150,
              child: Column(
                children: [
                  SizedBox(
                    height: 60,
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          onPressed: () => Navigator.maybePop(context),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const Expanded(
                          child: Text('Logo', overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(top: 12),
                      children: menuItems.map((item) {
                        final isSelected = selectedPage == item;

                        return ListTile(
                          selected: isSelected,
                          selectedTileColor: Colors.blue.withValues(
                            alpha: 0.10,
                          ),
                          title: Text(
                            item,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isSelected ? Colors.blue : Colors.black87,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          onTap: () {
                            setState(() {
                              selectedPage = item;
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

            const VerticalDivider(width: 1, thickness: 1),

            // RIGHT CONTENT AREA
            Expanded(
              child: Column(
                children: [
                  SizedBox(
                    height: 60,
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          selectedPage == 'Dashboard'
                              ? 'Welcome to Admin Dashboard'
                              : selectedPage,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                  ),

                  const Divider(height: 1),

                  // CONTENT CHANGES WITHOUT HIDING THE SIDEBAR
                  Expanded(child: _buildContent()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (selectedPage) {
      case 'Users':
        return const UserListPage(embedded: true);

      case 'Questions':
        return const QuestionListPage(embedded: true);

      case 'Topics':
        return const TopicPage(embedded: true);

      case 'Results':
        return const ExamResultPage();

      case 'Settings':
        return _buildPlaceholder('Settings');

      case 'Dashboard':
      default:
        return const DashboardPage();
    }
  }

  Widget _buildPlaceholder(String message) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 20, color: Colors.black87),
      ),
    );
  }
}
