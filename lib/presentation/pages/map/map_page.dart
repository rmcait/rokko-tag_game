import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:tag_game/data/services/field_service.dart';
import 'package:tag_game/presentation/pages/map/field_history_page.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  GoogleMapController? _mapController;
  LatLng? _currentLatLng;
  bool _isLoading = true;
  String? _errorMessage;

  /// ユーザーがタップした頂点（最大4つ）
  final List<LatLng> _points = [];

  /// マーカーとポリゴン
  final Set<Marker> _markers = {};
  final Set<Polygon> _polygons = {};

  // 「名前をつけて保存するかどうか」のトグル
  bool _saveAsTemplate = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  Future<void> _loadCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _errorMessage = '位置情報サービスが無効です。端末の設定を確認してください。';
          _isLoading = false;
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _errorMessage = '位置情報の権限が許可されていません。';
          _isLoading = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentLatLng = LatLng(position.latitude, position.longitude);
        _isLoading = false;
        _errorMessage = null;
      });

      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_currentLatLng!, 16),
      );
    } catch (e) {
      setState(() {
        _errorMessage = '位置情報取得に失敗しました: $e';
        _isLoading = false;
      });
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (_currentLatLng != null) {
      controller.moveCamera(
        CameraUpdate.newLatLngZoom(_currentLatLng!, 16),
      );
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm =
        !_isLoading && _errorMessage == null && _points.length == 4;

    Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_errorMessage != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = null;
                  });
                  _loadCurrentLocation();
                },
                child: const Text('再試行'),
              ),
            ],
          ),
        ),
      );
    } else {
      body = Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: _currentLatLng ?? const LatLng(35.681236, 139.767125),
              zoom: 16,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            onTap: _onMapTap,
            markers: _markers,
            polygons: _polygons,
          ),
          // 履歴ボタン（マップ右上）
          Positioned(
            right: 16,
            top: 16,
            child: FloatingActionButton.small(
              heroTag: 'field_history',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FieldHistoryPage(),
                  ),
                );
              },
              child: const Icon(Icons.history),
            ),
          ),
          // ガイドカード
          Positioned(
            left: 16,
            right: 16,
            bottom: 60,
            child: _buildGuideCard(),
          ),
          // ズームボタン（＋ / −）
          Positioned(
            right: 16,
            bottom: 10,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'zoom_in',
                  onPressed: _onZoomIn,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoom_out',
                  onPressed: _onZoomOut,
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('フィールドを設定'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadCurrentLocation,
            icon: const Icon(Icons.my_location),
            tooltip: '現在地を再取得',
          ),
          if (_points.isNotEmpty && !_isLoading && _errorMessage == null)
            IconButton(
              onPressed: _resetField,
              icon: const Icon(Icons.refresh),
              tooltip: 'フィールドをリセット',
            ),
        ],
      ),
      body: body,
      bottomNavigationBar: (!_isLoading && _errorMessage == null)
          ? SafeArea(
              minimum: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_points.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _undoLastPoint,
                        icon: const Icon(Icons.undo),
                        label: const Text('最後の頂点を取り消す'),
                      ),
                    ),
                  ElevatedButton.icon(
                    onPressed: canConfirm ? _onConfirmPressed : null,
                    icon: const Icon(Icons.check),
                    label: Text(
                      canConfirm
                          ? 'この4点でフィールドを確定'
                          : 'フィールドの頂点を4点タップしてください（${_points.length}/4）',
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  /// 下部のガイドカード（注意書き付き）
  Widget _buildGuideCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.touch_app),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _points.isEmpty
                        ? 'マップをタップして1点目を置いてください'
                        : 'マップ上をタップして残りの頂点を置いてください（${_points.length}/4）',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '※ マーカーは長押しで位置を微調整できます。',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _saveAsTemplate,
                  onChanged: (v) {
                    setState(() {
                      _saveAsTemplate = v ?? false;
                    });
                  },
                ),
                const Expanded(
                  child: Text(
                    '名前をつけて保存',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  /// 地図タップ時：最大4点まで追加
  void _onMapTap(LatLng position) {
    if (_points.length >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('頂点は4点までです。リセットしてやり直してください。')),
      );
      return;
    }

    setState(() {
      _points.add(position);
      _rebuildMarkers();
      _updatePolygon();
    });
  }

  /// ポリゴンを再描画（3点以上で描画）
  void _updatePolygon() {
    _polygons.clear();

    if (_points.length < 3) return;

    final List<LatLng> polygonPoints = List.from(_points);
    polygonPoints.add(_points.first); // 図形を閉じる

    _polygons.add(
      Polygon(
        polygonId: const PolygonId('field'),
        points: polygonPoints,
        strokeWidth: 2,
        strokeColor: Colors.deepPurple,
        fillColor: Colors.deepPurple.withOpacity(0.15),
      ),
    );
  }

  /// マーカーを_pointsから作り直す（ドラッグ後もこれを使う）
  void _rebuildMarkers() {
    _markers.clear();
    for (var i = 0; i < _points.length; i++) {
      final point = _points[i];
      _markers.add(
        Marker(
          markerId: MarkerId('p$i'),
          position: point,
          infoWindow: InfoWindow(title: '頂点 ${i + 1}'),
          draggable: true,
          onDragEnd: (newPosition) {
            setState(() {
              _points[i] = newPosition;
              _rebuildMarkers();
              _updatePolygon();
            });
          },
        ),
      );
    }
  }

  /// フィールドを全部リセット
  void _resetField() {
    setState(() {
      _points.clear();
      _markers.clear();
      _polygons.clear();
    });
  }

  /// 最後の頂点だけ消す（Undo）
  void _undoLastPoint() {
    if (_points.isEmpty) return;
    setState(() {
      _points.removeLast();
      _rebuildMarkers();
      _updatePolygon();
    });
  }

  /// ズームイン
  void _onZoomIn() {
    _mapController?.animateCamera(CameraUpdate.zoomIn());
  }

  /// ズームアウト
  void _onZoomOut() {
    _mapController?.animateCamera(CameraUpdate.zoomOut());
  }

  /// 確定：4点を前の画面へ返す
  Future<void> _onConfirmPressed() async {
    if (_points.length != 4) return;

    // 保存しない（一回限り）の場合
    if (!_saveAsTemplate) {
      Navigator.of(context).pop(_points);
      return;
    }

    // 保存ありの場合：名前を聞く
    final name = await _showFieldNameDialog();
    if (name == null || name.isEmpty) {
      return; // キャンセルされたら何もしない
    }

    // 共通コレクションに保存
    await FieldService().createField(
      name: name,
      vertices: _points,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('フィールド「$name」を保存しました')),
    );

    // 呼び出し元にも座標を返す
    Navigator.of(context).pop(_points);
  }

  Future<String?> _showFieldNameDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('フィールド名を入力'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '例：六甲公園 北側エリア',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, controller.text.trim());
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }
}