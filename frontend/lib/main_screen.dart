import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'sensor_provider.dart';

class MainScreen extends StatefulWidget {
  final SensorProvider provider;
  const MainScreen({super.key, required this.provider});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  @override
  void initState() {
    super.initState();
    widget.provider.onFallDetected = _showFallAlert;
    widget.provider.startListening();
  }

  Future<void> _showFallAlert() async {
    late VoidCallback listener;
    void Function(void Function())? dialogSetState;
    listener = () {
      dialogSetState?.call(() {});
    };

    widget.provider.addListener(listener);

    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) {
            dialogSetState = setState;

            final countdownText = widget.provider.emailCountdown > 0
                ? 'I am Ok (${widget.provider.emailCountdown})'
                : 'I am Ok';

            return AlertDialog(
              backgroundColor: Colors.red[900],
              title: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.white),
                  SizedBox(width: 10),
                  Text('FALL DETECTED!', style: TextStyle(color: Colors.white)),
                ],
              ),
              content: const Text(
                'A fall has been detected. Press the button below within 10 seconds to cancel the alert email.',
                style: TextStyle(color: Colors.white),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    widget.provider.dismissAlert();
                    Navigator.pop(context);
                  },
                  child: Text(
                    countdownText,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      widget.provider.removeListener(listener);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Real-time Acceleration'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: Icon(
              widget.provider.isRecording ? Icons.stop : Icons.play_arrow,
              color: widget.provider.isRecording ? Colors.red : Colors.green,
            ),
            onPressed: () {
              setState(() {
                if (widget.provider.isRecording) {
                  widget.provider.stopListening();
                } else {
                  widget.provider.startListening();
                }
              });
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.provider,
        builder: (context, child) {
          return Column(
            children: [
              // Show three separate plots (X, Y, Z) with per-axis auto-scaling
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      Expanded(
                        child: _axisChart(widget.provider.xBuffer, Colors.red, 'X'),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _axisChart(widget.provider.yBuffer, Colors.green, 'Y'),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _axisChart(widget.provider.zBuffer, Colors.blue, 'Z'),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _LegendItem(color: Colors.red, label: 'X Axis'),
                          const SizedBox(width: 20),
                          _LegendItem(color: Colors.green, label: 'Y Axis'),
                          const SizedBox(width: 20),
                          _LegendItem(color: Colors.blue, label: 'Z Axis'),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        widget.provider.isRecording ? 'RECORDING SENSOR DATA' : 'STOPPED',
                        style: TextStyle(
                          color: widget.provider.isRecording ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  LineChartBarData _buildLine(List<double> data, Color color) {
    return LineChartBarData(
      spots: data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
      isCurved: false,
      color: color,
      barWidth: 2,
      dotData: const FlDotData(show: false),
    );
  }

  // Build a single-axis chart with auto-scaled Y range based on data
  Widget _axisChart(List<double> data, Color color, String label) {
    double minY = -1.0, maxY = 1.0;
    if (data.isNotEmpty) {
      minY = data.reduce((a, b) => a < b ? a : b);
      maxY = data.reduce((a, b) => a > b ? a : b);
      if (minY == maxY) {
        // small fixed range around the constant value
        minY = minY - 0.5;
        maxY = maxY + 0.5;
      } else {
        final pad = (maxY - minY) * 0.05; // 5% padding
        minY -= pad;
        maxY += pad;
      }
    }

    final latest = data.isNotEmpty ? data.last : 0.0;
    final latestStr = latest.toStringAsFixed(2);

    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.white24)),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top label row with axis and latest numeric reading
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
            child: Row(
              children: [
                Text('$label Axis', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const Spacer(),
                Text('$latestStr m/s²', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Chart area
          Expanded(
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  _buildLine(data, color),
                ],
              ),
              duration: Duration.zero,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
