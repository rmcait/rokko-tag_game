import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ルーム参加画面。6桁のパーティID入力UIを提供する。
class RoomJoinPage extends StatefulWidget {
  const RoomJoinPage({super.key});

  @override
  State<RoomJoinPage> createState() => _RoomJoinPageState();
}

class _RoomJoinPageState extends State<RoomJoinPage> {
  static const int _roomCodeLength = 6;
  late final TextEditingController _codeController;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _handleJoin() {
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('パーティID ${_codeController.text} で参加します（未実装）'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ルームに参加'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'パーティID',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _codeController,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  fontSize: 32,
                  letterSpacing: 8,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: '000000',
                  filled: true,
                  fillColor: Colors.grey.shade200,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 24),
                ),
                inputFormatters: [
                  _RoomCodeInputFormatter(),
                  LengthLimitingTextInputFormatter(_roomCodeLength),
                ],
              ),
              const Spacer(),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _codeController,
                builder: (context, value, child) {
                  final isCodeComplete = value.text.length == _roomCodeLength;
                  return SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isCodeComplete ? _handleJoin : null,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        // 例
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        disabledBackgroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.12),
                      ),
                      child: const Text(
                        '参加',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 入力を半角数字のみに正規化するフォーマッター。
class _RoomCodeInputFormatter extends TextInputFormatter {
  static const int _asciiZero = 0x30;
  static const int _asciiNine = 0x39;
  static const int _zenkakuZero = 0xFF10;
  static const int _zenkakuNine = 0xFF19;

  bool _isAsciiDigit(int codeUnit) =>
      codeUnit >= _asciiZero && codeUnit <= _asciiNine;

  bool _isZenkakuDigit(int codeUnit) =>
      codeUnit >= _zenkakuZero && codeUnit <= _zenkakuNine;

  int? _normalize(int codeUnit) {
    if (_isAsciiDigit(codeUnit)) {
      return codeUnit;
    }
    if (_isZenkakuDigit(codeUnit)) {
      return codeUnit - _zenkakuZero + _asciiZero;
    }
    return null;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final buffer = StringBuffer();
    var selectionIndex = 0;

    for (var i = 0; i < newValue.text.length; i++) {
      final normalizedCode = _normalize(newValue.text.codeUnitAt(i));
      if (normalizedCode != null) {
        buffer.writeCharCode(normalizedCode);
        if (i < newValue.selection.end) {
          selectionIndex++;
        }
      }
    }

    final normalizedText = buffer.toString();
    return TextEditingValue(
      text: normalizedText,
      selection: TextSelection.collapsed(offset: selectionIndex),
    );
  }
}
