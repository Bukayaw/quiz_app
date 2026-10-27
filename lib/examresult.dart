import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ExamResultPage extends StatefulWidget {
  const ExamResultPage({super.key});

  @override
  State<ExamResultPage> createState() => _ExamResultPageState();
}

class _ExamResultPageState extends State<ExamResultPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = true;
  String? _errorMessage;

  String get _apiBaseUrl {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return 'http://127.0.0.1:8000';
    }
    return 'http://10.0.2.2:8000';
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadResults();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {});
  }

  Future<void> _loadResults() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final response = await http
          .get(Uri.parse('$_apiBaseUrl/results'))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['results'] is! List) {
        throw const FormatException('Unexpected results response format.');
      }

      final results = (decoded['results'] as List<dynamic>)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Could not load student results: $error';
      });
    }
  }

  Future<void> _setResultReleased(
    Map<String, dynamic> result,
    bool isReleased,
  ) async {
    final resultId = result['result_id'];
    if (resultId is! num) return;

    setState(() {
      _errorMessage = null;
    });

    try {
      final response = await http
          .patch(
            Uri.parse('$_apiBaseUrl/results/${resultId.toInt()}/release'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'is_released': isReleased}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      if (!mounted) return;
      setState(() {
        result['is_released'] = isReleased;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isReleased
                ? 'Result released to the student.'
                : 'Result hidden from the student.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not update result release status: $error';
      });
    }
  }

  List<Map<String, dynamic>> get _filteredResults {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _results;

    return _results.where((result) {
      final searchableValues = [
        result['result_id'],
        result['student_name'],
        result['student_email'],
        result['exam_name'],
        result['topic_name'],
        result['status'],
      ];
      return searchableValues.any(
        (value) => value?.toString().toLowerCase().contains(query) ?? false,
      );
    }).toList();
  }

  String _formatDate(dynamic value) {
    if (value is! String) return '—';
    final date = DateTime.tryParse(value);
    if (date == null) return '—';
    final localDate = date.toLocal();
    final year = localDate.year.toString().padLeft(4, '0');
    final month = localDate.month.toString().padLeft(2, '0');
    final day = localDate.day.toString().padLeft(2, '0');
    final hour = localDate.hour.toString().padLeft(2, '0');
    final minute = localDate.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  String _formatDuration(dynamic value) {
    if (value is! num || value < 0) return '—';
    final seconds = value.toInt();
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes}m ${remainingSeconds}s';
  }

  String _formatScore(Map<String, dynamic> result) {
    final score = result['score'];
    final total = result['total_questions'];
    final percentage = result['percentage'];
    if (score is! num || total is! num || percentage is! num) return '—';
    return '${score.toInt()} / ${total.toInt()} '
        '(${percentage.toStringAsFixed(1)}%)';
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'passed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'in_progress':
      case 'in progress':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  String _displayStatus(Map<String, dynamic> result) {
    final status = result['status']?.toString() ?? 'Unknown';
    final percentage = result['percentage'];
    final passMark = result['pass_mark'];
    if (status.toLowerCase() == 'completed' &&
        percentage is num &&
        passMark is num) {
      return percentage >= passMark ? 'Passed' : 'Failed';
    }
    return status;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadResults,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final filteredResults = _filteredResults;

    return RefreshIndicator(
      onRefresh: _loadResults,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_results.length} exam result'
                  '${_results.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh results',
                onPressed: _loading ? null : _loadResults,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search student or exam',
              hintText: 'Name, email, exam, topic, or result ID',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: _searchController.clear,
                      icon: const Icon(Icons.clear),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          if (_loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          if (_results.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  children: [
                    Icon(Icons.assignment_outlined, size: 44),
                    SizedBox(height: 12),
                    Text(
                      'No student exam results have been recorded yet.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else if (filteredResults.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No results match your search.',
                textAlign: TextAlign.center,
              ),
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Student')),
                    DataColumn(label: Text('Email')),
                    DataColumn(label: Text('Exam / Topic')),
                    DataColumn(label: Text('Score')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Student visibility')),
                    DataColumn(label: Text('Completed')),
                    DataColumn(label: Text('Duration')),
                    DataColumn(label: Text('Action')),
                  ],
                  rows: filteredResults.map((result) {
                    final status = _displayStatus(result);
                    final examName =
                        result['exam_name']?.toString() ?? 'Exam unavailable';
                    final topicName = result['topic_name']?.toString();
                    final isCompleted =
                        result['status']?.toString().toLowerCase() ==
                        'completed';
                    final isReleased = result['is_released'] == true;

                    return DataRow(
                      cells: [
                        DataCell(
                          SizedBox(
                            width: 160,
                            child: Text(
                              result['student_name']?.toString() ??
                                  'Unknown student',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(result['student_email']?.toString() ?? '—'),
                        ),
                        DataCell(
                          SizedBox(
                            width: 170,
                            child: Text(
                              topicName == null
                                  ? examName
                                  : '$examName\n$topicName',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(Text(_formatScore(result))),
                        DataCell(
                          Chip(
                            label: Text(status),
                            labelStyle: TextStyle(
                              color: _statusColor(status),
                              fontSize: 12,
                            ),
                            side: BorderSide(
                              color: _statusColor(
                                status,
                              ).withValues(alpha: 0.35),
                            ),
                            backgroundColor: _statusColor(
                              status,
                            ).withValues(alpha: 0.08),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        DataCell(
                          Text(
                            isCompleted
                                ? isReleased
                                      ? 'Released'
                                      : 'Waiting for admin'
                                : 'Unavailable',
                          ),
                        ),
                        DataCell(Text(_formatDate(result['completed_at']))),
                        DataCell(
                          Text(_formatDuration(result['duration_seconds'])),
                        ),
                        DataCell(
                          isCompleted
                              ? TextButton.icon(
                                  onPressed: () =>
                                      _setResultReleased(result, !isReleased),
                                  icon: Icon(
                                    isReleased
                                        ? Icons.visibility_off
                                        : Icons.publish,
                                  ),
                                  label: Text(isReleased ? 'Hide' : 'Release'),
                                )
                              : const Text('—'),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
