import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';

class TrainingReportWidget extends StatefulWidget {
  final String modelName;
  final String? run;   // a specific run folder (e.g. train2); null = latest
  const TrainingReportWidget({super.key, required this.modelName, this.run});

  @override
  State<TrainingReportWidget> createState() => _TrainingReportWidgetState();
}

class _TrainingReportWidgetState extends State<TrainingReportWidget> {
  List<dynamic> _data = [];
  Map<String, dynamic>? _metadata;
  String? _runFolder;
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _fetchReport();
  }

  Future<void> _fetchReport() async {
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:8000/api/train/report/${widget.modelName}${widget.run != null ? '?run=${widget.run}' : ''}'));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        setState(() {
          _metadata = json['metadata'];
          _runFolder = json['run_folder'];
          if (json['status'] == 'success') {
            _data = json['data'];
            _isLoading = false;
          } else {
            _error = json['message'] ?? 'No training history yet.';
            _isLoading = false;
          }
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return SizedBox(
      height: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_metadata != null)
            Card(
              color: Colors.blueGrey.withOpacity(0.1),
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.psychology, color: Colors.blueAccent),
                        const SizedBox(width: 8),
                        Text(
                          _metadata!['category']?.toUpperCase() ?? 'UNCATEGORIZED',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent),
                        ),
                        const Spacer(),
                        if (_runFolder != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(4)),
                            child: Text("Latest Run: $_runFolder", style: const TextStyle(fontSize: 12, color: Colors.white70)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_metadata!['purpose'] ?? '', style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
            
          if (_error.isNotEmpty) Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error))),
          if (_error.isEmpty && _data.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(16), child: Text("No data points available."))),
          
          if (_data.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Training Metrics (mAP50)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.refresh), onPressed: () {
                  setState(() => _isLoading = true);
                  _fetchReport();
                }),
              ],
            ),
            const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: true),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(value.toInt().toString(), style: const TextStyle(fontSize: 10)),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: _getMapSpots(),
                    isCurved: true,
                    color: Colors.blueAccent,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: Colors.blueAccent.withOpacity(0.2)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text("Epoch")),
                    DataColumn(label: Text("Box Loss")),
                    DataColumn(label: Text("Cls Loss")),
                    DataColumn(label: Text("mAP50")),
                    DataColumn(label: Text("mAP50-95")),
                  ],
                  rows: _data.map((row) {
                    return DataRow(
                      cells: [
                        DataCell(Text(row['epoch'].toString())),
                        DataCell(Text(double.tryParse(row['train/box_loss'].toString())?.toStringAsFixed(4) ?? '-')),
                        DataCell(Text(double.tryParse(row['train/cls_loss'].toString())?.toStringAsFixed(4) ?? '-')),
                        DataCell(Text(double.tryParse(row['metrics/mAP50(B)'].toString())?.toStringAsFixed(4) ?? '-')),
                        DataCell(Text(double.tryParse(row['metrics/mAP50-95(B)'].toString())?.toStringAsFixed(4) ?? '-')),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          ], // close the spread array
        ],
      ),
    );
  }

  List<FlSpot> _getMapSpots() {
    List<FlSpot> spots = [];
    for (var i = 0; i < _data.length; i++) {
      var row = _data[i];
      var x = double.tryParse(row['epoch'].toString()) ?? i.toDouble();
      var y = double.tryParse(row['metrics/mAP50(B)'].toString()) ?? 0.0;
      spots.add(FlSpot(x, y));
    }
    return spots;
  }
}
