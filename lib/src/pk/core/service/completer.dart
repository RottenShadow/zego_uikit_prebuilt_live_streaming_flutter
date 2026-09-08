part of 'services.dart';

extension PKServiceCompleter on ZegoUIKitPrebuiltLiveStreamingPKServices {
  Future<void> waitCompleter(String apiName) async {
    final completer = Completer<void>();
    _completerQueue.add(completer);
    if (_completerQueue.length > 1) {
      ZegoLoggerService.logInfo(
        '$apiName, waitCompleter start (queue length: ${_completerQueue.length})',
        tag: 'live-streaming-pk',
        subTag: 'service',
      );
      await _completerQueue[_completerQueue.length - 2].future;
      ZegoLoggerService.logInfo(
        '$apiName, waitCompleter done',
        tag: 'live-streaming-pk',
        subTag: 'service',
      );
    }
  }

  void completeCompleter(String apiName) {
    ZegoLoggerService.logInfo(
      '$apiName, _completeCompleter',
      tag: 'live-streaming-pk',
      subTag: 'service',
    );
    if (_completerQueue.isNotEmpty) {
      final activeCompleter = _completerQueue.removeAt(0);
      if (!activeCompleter.isCompleted) {
        activeCompleter.complete();
      }
    }
  }

  Future<void> waitRoomAttributesCompleter(String apiName) async {
    final completer = Completer<void>();
    _roomAttributesCompleterQueue.add(completer);
    if (_roomAttributesCompleterQueue.length > 1) {
      ZegoLoggerService.logInfo(
        '$apiName, waitRoomAttributesCompleter start (queue length: ${_roomAttributesCompleterQueue.length})',
        tag: 'live-streaming-pk',
        subTag: 'service',
      );
      await _roomAttributesCompleterQueue[_roomAttributesCompleterQueue.length - 2].future;
      ZegoLoggerService.logInfo(
        '$apiName, waitRoomAttributesCompleter done',
        tag: 'live-streaming-pk',
        subTag: 'service',
      );
    }
  }

  void completeRoomAttributesCompleter(String apiName) {
    ZegoLoggerService.logInfo(
      '$apiName, completeRoomAttributesCompleter',
      tag: 'live-streaming-pk',
      subTag: 'service',
    );
    if (_roomAttributesCompleterQueue.isNotEmpty) {
      final activeCompleter = _roomAttributesCompleterQueue.removeAt(0);
      if (!activeCompleter.isCompleted) {
        activeCompleter.complete();
      }
    }
  }
}
