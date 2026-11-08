import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:hulikamote_dashboard/core/utils/app_toast.dart';

class CloudReleaserWidget extends StatefulWidget {
  const CloudReleaserWidget({super.key});

  @override
  State<CloudReleaserWidget> createState() => _CloudReleaserWidgetState();
}

class _CloudReleaserWidgetState extends State<CloudReleaserWidget> {
  List<dynamic> _models = [];
  Set<String> _selectedPaths = {};
  bool _isLoading = true;
  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    _fetchModels(syncGithub: false);
  }

  Future<void> _fetchModels({bool syncGithub = false}) async {
    setState(() => _isLoading = true);
    try {
      final uri = Uri.parse('http://127.0.0.1:8000/api/train/local-models?sync_github=$syncGithub');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        setState(() {
          _models = json['data'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _publishSelected() async {
    if (_selectedPaths.isEmpty) return;
    
    setState(() => _isPublishing = true);
    try {
      final uri = Uri.parse('http://127.0.0.1:8000/api/train/release/batch');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'model_paths': _selectedPaths.toList()}),
      );
      
      if (response.statusCode == 200) {
        AppToast.show(context, "Batch upload completed successfully!");
        setState(() => _selectedPaths.clear());
        _fetchModels(syncGithub: true);
      } else {
        final err = jsonDecode(response.body)['detail'] ?? 'Unknown Error';
        AppToast.show(context, "Upload Error: $err", isError: true);
      }
    } catch (e) {
      AppToast.show(context, "Upload Error: $e", isError: true);
    } finally {
      setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Cloud Release Manager", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              OutlinedButton.icon(
                icon: const Icon(Icons.sync),
                label: const Text("Scan GitHub Status"),
                onPressed: () => _fetchModels(syncGithub: true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text("Select historical models from your local drive to publish directly to GitHub Releases.", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          
          Expanded(
            child: Card(
              color: Colors.black45,
              child: Builder(
                builder: (context) {
                  // Group models by category
                  final Map<String, List<dynamic>> groupedModels = {};
                  for (var model in _models) {
                    final cat = model['category'] as String;
                    groupedModels.putIfAbsent(cat, () => []).add(model);
                  }
                  
                  if (groupedModels.isEmpty) {
                    return const Center(child: Text("No models found.", style: TextStyle(color: Colors.grey)));
                  }

                  return ListView.builder(
                    itemCount: groupedModels.length,
                    itemBuilder: (context, index) {
                      final category = groupedModels.keys.elementAt(index);
                      final categoryModels = groupedModels[category]!;
                      
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            color: Colors.black26,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            margin: const EdgeInsets.only(top: 8),
                            child: Text(
                              category.toUpperCase(), 
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 14, letterSpacing: 1.2),
                            ),
                          ),
                          ...categoryModels.map((model) {
                            final path = model['path'] as String;
                            final isPublished = model['is_published'] == true;
                            final isSelected = _selectedPaths.contains(path) && !isPublished;
                            
                            final date = DateTime.fromMillisecondsSinceEpoch((model['timestamp'] * 1000).toInt());
                            final formattedDate = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
                            
                            return CheckboxListTile(
                              value: isPublished ? true : isSelected,
                              onChanged: isPublished ? null : (val) {
                                setState(() {
                                  if (val == true) _selectedPaths.add(path);
                                  else _selectedPaths.remove(path);
                                });
                              },
                              title: Text(
                                model['name'], 
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isPublished ? Colors.green : Colors.white,
                                )
                              ),
                              subtitle: Text("${model['size_mb']} MB • Modified: $formattedDate"),
                              secondary: isPublished 
                                  ? const Icon(Icons.check_circle, color: Colors.green)
                                  : const Icon(Icons.psychology),
                              activeColor: isPublished ? Colors.green : Colors.blueAccent,
                            );
                          }).toList(),
                        ],
                      );
                    },
                  );
                }
              ),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              icon: _isPublishing 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                  : const Icon(Icons.cloud_upload),
              label: Text(_isPublishing ? "Publishing..." : "Publish Selected to GitHub (${_selectedPaths.length})"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
              onPressed: (_isPublishing || _selectedPaths.isEmpty) ? null : _publishSelected,
            ),
          )
        ],
      ),
    );
  }
}
