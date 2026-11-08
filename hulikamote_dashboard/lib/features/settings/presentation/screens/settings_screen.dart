import 'package:flutter/material.dart';
import 'package:hulikamote_dashboard/core/utils/app_toast.dart';

import 'package:http/http.dart' as http;
import '../../../../core/constants/api_constants.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _deleteAllData(BuildContext context) async {
    final bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Data'),
        content: const Text('Are you sure you want to delete all violation records? This action cannot be undone and will sync across all devices.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    try {
      final response = await http.delete(Uri.parse('${ApiConstants.baseUrl}/settings/violations'));
      if (response.statusCode == 200) {
        if (context.mounted) {
          AppToast.show(context, 'All violations deleted successfully.', isError: false);
        }
      } else {
        throw Exception('Failed to delete');
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.show(context, 'Error: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Danger Zone', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Delete All Data'),
            subtitle: const Text('Wipes all violation history from the database.'),
            trailing: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => _deleteAllData(context),
              child: const Text('Wipe Data', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
