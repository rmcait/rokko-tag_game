import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
      body = GoogleMap(
        onMapCreated: _onMapCreated,
        initialCameraPosition: CameraPosition(
          target: _currentLatLng ?? const LatLng(35.681236, 139.767125),
          zoom: 16,
        ),
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('現在地マップ'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadCurrentLocation,
            icon: const Icon(Icons.my_location),
            tooltip: '現在地を再取得',
          ),
        ],
      ),
      body: body,
    );
  }
}
