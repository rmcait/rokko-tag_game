import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:tag_game/data/services/field_service.dart';
import 'map_page.dart';

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
                  onTap: () async {
                    // 1. 編集用 MapPage を開く
                    final result = await Navigator.of(context).push<List<LatLng>>(
                      MaterialPageRoute(
                        builder: (_) => MapPage(
                          initialPoints: field.vertices,
                          isEditing: true,
                        ),
                      ),
                    );

                    // 2. キャンセル or 不正ならそのまま
                    if (result == null || result.length != 4) {
                      return;
                    }

                    // 3. 呼び出し元（MapPage 新規）へ返す
                    Navigator.of(context).pop(result);
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