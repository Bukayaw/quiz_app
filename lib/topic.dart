import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class TopicPage extends StatefulWidget {
  const TopicPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<TopicPage> createState() => _TopicPageState();
}

class _TopicPageState extends State<TopicPage> {
  static const String _apiUrl = 'http://127.0.0.1:8000/topics';

  final _formKey = GlobalKey<FormState>();
  final _topicNameController = TextEditingController();
  List<Map<String, dynamic>> _topics = [];
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  @override
  void dispose() {
    _topicNameController.dispose();
    super.dispose();
  }

  Future<void> _loadTopics() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final response = await http
          .get(Uri.parse('$_apiUrl?include_inactive=true'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['topics'] is! List) {
        throw const FormatException('Unexpected topics response format.');
      }

      final topics = (decoded['topics'] as List<dynamic>)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _topics = topics;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Could not load topics: $error';
      });
    }
  }

  Future<void> _addTopic() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse(_apiUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'topic_name': _topicNameController.text.trim()}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      if (!mounted) return;
      _topicNameController.clear();
      _formKey.currentState!.reset();
      _showMessage('Topic added successfully.');
      await _loadTopics();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not add topic: $error';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editTopic(Map<String, dynamic> topic) async {
    final topicId = topic['topic_id'];
    if (topicId == null) {
      _showMessage('Could not edit topic: topic ID is missing.');
      return;
    }

    final controller = TextEditingController(
      text: topic['topic_name']?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();
    bool saving = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Topic'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Form(
                  key: formKey,
                  child: TextFormField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Topic name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final name = value?.trim() ?? '';
                      if (name.isEmpty) return 'Enter a topic name.';
                      if (name.length > 100) {
                        return 'Topic name must be 100 characters or fewer.';
                      }
                      return null;
                    },
                  ),
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    dialogError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() {
                        saving = true;
                        dialogError = null;
                      });

                      try {
                        final response = await http
                            .put(
                              Uri.parse('$_apiUrl/$topicId'),
                              headers: {'Content-Type': 'application/json'},
                              body: jsonEncode({
                                'topic_name': controller.text.trim(),
                              }),
                            )
                            .timeout(const Duration(seconds: 15));
                        if (response.statusCode != 200) {
                          throw Exception(
                            'HTTP ${response.statusCode}: ${response.body}',
                          );
                        }

                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        if (!mounted) return;
                        _showMessage('Topic updated successfully.');
                        await _loadTopics();
                      } catch (error) {
                        setDialogState(() {
                          saving = false;
                          dialogError = 'Could not update topic: $error';
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
    controller.dispose();
  }

  Future<void> _setTopicEnabled(
    Map<String, dynamic> topic,
    bool isEnabled,
  ) async {
    final topicId = topic['topic_id'];
    if (topicId == null) {
      _showMessage('Could not update topic: topic ID is missing.');
      return;
    }

    try {
      final response = await http
          .patch(
            Uri.parse('$_apiUrl/$topicId/status'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'is_active': isEnabled}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      if (!mounted) return;
      _showMessage(
        isEnabled
            ? 'Topic enabled and now visible to users.'
            : 'Topic disabled and hidden from users.',
      );
      await _loadTopics();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Could not update topic status: $error');
    }
  }

  Future<void> _deleteTopic(Map<String, dynamic> topic) async {
    final topicId = topic['topic_id'];
    if (topicId == null) {
      _showMessage('Could not delete topic: topic ID is missing.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete topic?'),
        content: Text(
          'Delete "${topic['topic_name'] ?? 'this topic'}"? '
          'It will no longer be available to users.',
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
          .delete(Uri.parse('$_apiUrl/$topicId'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      if (!mounted) return;
      _showMessage('Topic deleted successfully.');
      await _loadTopics();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Could not delete topic: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Add a topic',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _topicNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Topic name',
                        hintText: 'For example, Mathematics',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final name = value?.trim() ?? '';
                        if (name.isEmpty) return 'Enter a topic name.';
                        if (name.length > 100) {
                          return 'Topic name must be 100 characters or fewer.';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _saving ? null : _addTopic(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _addTopic,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add),
                      label: Text(_saving ? 'Saving' : 'Add'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  'Topics (${_topics.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh topics',
                  onPressed: _loading ? null : _loadTopics,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_topics.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No topics have been added yet.'),
              )
            else
              ..._topics.map((topic) {
                final isActive = topic['is_active'] != false;
                return Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.topic_outlined,
                      color: isActive ? null : Colors.grey,
                    ),
                    title: Text(topic['topic_name']?.toString() ?? 'Unnamed'),
                    subtitle: Text(
                      'ID: ${topic['topic_id'] ?? '—'} • '
                      '${isActive ? 'Enabled — visible to users' : 'Disabled — hidden from users'}',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: isActive ? 'Disable topic' : 'Enable topic',
                          onPressed: () => _setTopicEnabled(topic, !isActive),
                          icon: Icon(
                            isActive
                                ? Icons.toggle_on
                                : Icons.toggle_off_outlined,
                            color: isActive ? Colors.green : Colors.grey,
                            size: 30,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Edit topic',
                          onPressed: isActive ? () => _editTopic(topic) : null,
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Delete topic',
                          onPressed: () => _deleteTopic(topic),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Topics')),
      body: content,
    );
  }
}
