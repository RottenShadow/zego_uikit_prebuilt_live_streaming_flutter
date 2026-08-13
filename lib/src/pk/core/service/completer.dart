part of 'services.dart';

extension PKServiceCompleter on ZegoUIKitPrebuiltLiveStreamingPKServices {
  Future<void> waitCompleter(String apiName) async {
    if (_completer != null) {
      ZegoLoggerService.logInfo(
        '$apiName, waitCompleter start',
        tag: 'live-streaming-pk',
        subTag: 'service',
      );
      await _completer!.future;
      ZegoLoggerService.logInfo(
        '$apiName, waitCompleter done',
        tag: 'live-streaming-pk',
        subTag: 'service',
      );
    }
    _completer = Completer();
  }

  void completeCompleter(String apiName) {
    ZegoLoggerService.logInfo(
      '$apiName, _completeCompleter',
      tag: 'live-streaming-pk',
      subTag: 'service',
    );
    _completer?.complete();
    _completer = null;
  }

  Future<void> waitRoomAttributesCompleter(String apiName) async {
    if (_roomAttributesCompleter != null) {
      ZegoLoggerService.logInfo(
        '$apiName, waitRoomAttributesCompleter start',
        tag: 'live-streaming-pk',
        subTag: 'service',
      );
      await _roomAttributesCompleter!.future;
      ZegoLoggerService.logInfo(
        '$apiName, waitRoomAttributesCompleter done',
        tag: 'live-streaming-pk',
        subTag: 'service',
      );
    }
    _roomAttributesCompleter = Completer();
  }

  void completeRoomAttributesCompleter(String apiName) {
    ZegoLoggerService.logInfo(
      '$apiName, completeRoomAttributesCompleter',
      tag: 'live-streaming-pk',
      subTag: 'service',
    );
    _roomAttributesCompleter?.complete();
    _roomAttributesCompleter = null;
  }
}
