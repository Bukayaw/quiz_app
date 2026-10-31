import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _loading = true;
  String? _errorMessage;
  Map<String, dynamic>? _stats;

  String get _apiBaseUrl {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return 'http://127.0.0.1:8000';
    }
    return 'http://10.0.2.2:8000';
  }

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final response = await http
          .get(Uri.parse('$_apiBaseUrl/dashboard/stats'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected dashboard response format.');
      }

      if (!mounted) return;
      setState(() {
        _stats = decoded;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Could not load dashboard statistics: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _stats == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _stats == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadStats,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final stats = _stats!;
    final cards = <_DashboardMetric>[
      _DashboardMetric(
        title: 'Registered Users',
        value: stats['registered_users'],
        icon: Icons.people_alt_outlined,
        color: Colors.blue,
        backgroundColor: const Color(0xFFE8F4FF),
      ),
      _DashboardMetric(
        title: 'Users Who Took Exams',
        value: stats['exam_takers'],
        icon: Icons.person_outline,
        color: Colors.deepPurple,
        backgroundColor: const Color(0xFFF2ECFF),
      ),
      _DashboardMetric(
        title: 'Exam Attempts',
        value: stats['exam_attempts'],
        icon: Icons.assignment_turned_in_outlined,
        color: Colors.teal,
        backgroundColor: const Color(0xFFE6F7F5),
      ),
      _DashboardMetric(
        title: 'Total Questions',
        value: stats['total_questions'],
        icon: Icons.quiz_outlined,
        color: Colors.orange,
        backgroundColor: const Color(0xFFFFF3E3),
      ),
      _DashboardMetric(
        title: 'Active Topics',
        value: stats['total_topics'],
        icon: Icons.category_outlined,
        color: Colors.green,
        backgroundColor: const Color(0xFFEAF6E8),
      ),
      _DashboardMetric(
        title: 'Active Exams',
        value: stats['total_exams'],
        icon: Icons.edit_document,
        color: Colors.redAccent,
        backgroundColor: const Color(0xFFFFEBED),
      ),
      _DashboardMetric(
        title: 'Passed Students',
        value: stats['passed_students'],
        icon: Icons.emoji_events_outlined,
        color: Colors.green,
        backgroundColor: const Color(0xFFE7F5E8),
      ),
      _DashboardMetric(
        title: 'Failed Students',
        value: stats['failed_students'],
        icon: Icons.highlight_off,
        color: Colors.deepOrange,
        backgroundColor: const Color(0xFFFFECE6),
      ),
      _DashboardMetric(
        title: 'Students Who Have Not Taken an Exam',
        value: stats['students_not_taken_exam'],
        icon: Icons.person_off_outlined,
        color: Colors.blueGrey,
        backgroundColor: const Color(0xFFEEF1F4),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 3
            : constraints.maxWidth >= 600
            ? 2
            : 1;

        return RefreshIndicator(
          onRefresh: _loadStats,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Dashboard Overview',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh statistics',
                    onPressed: _loading ? null : _loadStats,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cards.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  mainAxisExtent: 145,
                ),
                itemBuilder: (context, index) =>
                    _MetricCard(metric: cards[index]),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, chartConstraints) {
                  final pieChart = _PassFailChart(
                    passed: _metricCount(stats['passed_students']),
                    failed: _metricCount(stats['failed_students']),
                  );
                  final barChart = _MetricsBarChart(metrics: cards);

                  if (chartConstraints.maxWidth >= 850) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: pieChart),
                        const SizedBox(width: 16),
                        Expanded(child: barChart),
                      ],
                    );
                  }

                  return Column(
                    children: [pieChart, const SizedBox(height: 16), barChart],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DashboardMetric {
  const _DashboardMetric({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.backgroundColor,
  });

  final String title;
  final dynamic value;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
}

int _metricCount(dynamic value) => value is num ? value.toInt() : 0;

class _PassFailChart extends StatelessWidget {
  const _PassFailChart({required this.passed, required this.failed});

  final int passed;
  final int failed;

  @override
  Widget build(BuildContext context) {
    final total = passed + failed;
    const passedColor = Colors.green;
    const failedColor = Colors.deepOrange;

    return _ChartCard(
      title: 'Exam Results',
      subtitle: 'Latest completed result per student',
      child: Column(
        children: [
          SizedBox(
            height: 190,
            width: 190,
            child: Semantics(
              label: 'Exam results: $passed passed, $failed failed',
              child: CustomPaint(
                painter: _PieChartPainter(
                  passed: passed,
                  failed: failed,
                  passedColor: passedColor,
                  failedColor: failedColor,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$total',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'students',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ChartLegendItem(
                color: passedColor,
                label: 'Passed',
                value: passed,
              ),
              const SizedBox(width: 24),
              _ChartLegendItem(
                color: failedColor,
                label: 'Failed',
                value: failed,
              ),
            ],
          ),
          if (total == 0) ...[
            const SizedBox(height: 12),
            Text(
              'No completed results yet',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ],
      ),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  const _PieChartPainter({
    required this.passed,
    required this.failed,
    required this.passedColor,
    required this.failedColor,
  });

  final int passed;
  final int failed;
  final Color passedColor;
  final Color failedColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final strokeWidth = size.width * 0.15;
    final radius = (size.width - strokeWidth) / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final trackPaint = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, trackPaint);

    final total = passed + failed;
    if (total == 0) return;

    final chartPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;
    final passedSweep = 2 * math.pi * passed / total;

    chartPaint.color = passedColor;
    canvas.drawArc(bounds, -math.pi / 2, passedSweep, false, chartPaint);

    chartPaint.color = failedColor;
    canvas.drawArc(
      bounds,
      -math.pi / 2 + passedSweep,
      2 * math.pi * failed / total,
      false,
      chartPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) =>
      oldDelegate.passed != passed ||
      oldDelegate.failed != failed ||
      oldDelegate.passedColor != passedColor ||
      oldDelegate.failedColor != failedColor;
}

class _ChartLegendItem extends StatelessWidget {
  const _ChartLegendItem({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$label: $value'),
      ],
    );
  }
}

class _MetricsBarChart extends StatelessWidget {
  const _MetricsBarChart({required this.metrics});

  final List<_DashboardMetric> metrics;

  @override
  Widget build(BuildContext context) {
    final maxValue = metrics.fold<int>(
      0,
      (maximum, metric) => _metricCount(metric.value) > maximum
          ? _metricCount(metric.value)
          : maximum,
    );

    return _ChartCard(
      title: 'Dashboard Metrics',
      subtitle: 'Comparison of all nine statistics',
      child: Column(
        children: [
          for (final metric in metrics) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    metric.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade800),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _metricCount(metric.value).toString(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 5),
            LinearProgressIndicator(
              value: maxValue == 0 ? 0 : _metricCount(metric.value) / maxValue,
              minHeight: 7,
              borderRadius: BorderRadius.circular(8),
              color: metric.color,
              backgroundColor: metric.color.withValues(alpha: 0.14),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _DashboardMetric metric;

  @override
  Widget build(BuildContext context) {
    final value = metric.value;

    return Card(
      elevation: 2,
      color: metric.backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: metric.color.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: Colors.white.withValues(alpha: 0.75),
              child: Icon(metric.icon, color: metric.color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value?.toString() ?? '—',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    metric.title,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
