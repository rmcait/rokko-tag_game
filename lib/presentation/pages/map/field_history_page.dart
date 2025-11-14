import 'package:flutter/material.dart';
import 'package:tag_game/data/services/field_service.dart';

import 'field_preview_page.dart'; // 次に作るプレビュー画面

class FieldHistoryPage extends StatelessWidget {
  const FieldHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('保存したフィールド'),
      ),
      body: StreamBuilder<List<FieldArea>>(
        stream: FieldService().watchFields(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final fields = snapshot.data!;
          if (fields.isEmpty) {
            return const Center(child: Text('保存されたフィールドはありません'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: fields.length,
            itemBuilder: (_, i) {
              final field = fields[i];
              return Card(
                child: ListTile(
                  title: Text(field.name),
                  subtitle: Text(
                    '頂点数: ${field.vertices.length}   作成日: ${field.createdAt ?? "-"}',
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FieldPreviewPage(field: field),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}