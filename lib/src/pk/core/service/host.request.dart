part of 'services.dart';

extension PKServiceHostRequest on ZegoUIKitPrebuiltLiveStreamingPKServices {
  /// Send PK invitation to [targetHostIDs].
  Future<ZegoLiveStreamingPKServiceSendRequestResult> sendPKBattleRequest({
    required List<String> targetHostIDs,
    int timeout = 60,
    String customData = '',
    bool isAutoAccept = false,
  }) async {
    if (!_serviceInitialized || !isLiving || !isHost) {
      ZegoLoggerService.logInfo(
        'could not send pk request, '
        'init:$_serviceInitialized, '
        'state:${pkStateNotifier.value}, '
        'is living:$isLiving, '
        'is host:$isHost',
        tag: 'live-streaming-pk',
        subTag: 'service, host, sendPKBattleRequest',
      );

      return ZegoLiveStreamingPKServiceSendRequestResult(
        errorUserIDs: targetHostIDs,
        error: PlatformException(
          code: '-1',
          message: 'could not send pk request, '
              'init:$_serviceInitialized, '
              'state:${pkStateNotifier.value}, '
              'is living:$isLiving, '
              'is host:$isHost',
        ),
      );
    }

    if (targetHostIDs.isEmpty) {
      ZegoLoggerService.logInfo(
        'could not send pk request, '
        'param is invalid, '
        'target host user ids:$targetHostIDs',
        tag: 'live-streaming-pk',
        subTag: 'service, host, sendPKBattleRequest',
      );

      return ZegoLiveStreamingPKServiceSendRequestResult(
        errorUserIDs: targetHostIDs,
        error: PlatformException(
          code: '-1',
          message: 'param is invalid, '
              'target host user ids:$targetHostIDs',
        ),
      );
    }

    final isWaitingRemoteResponse =
        _coreData.remoteUserIDsWaitingResponseFromLocalRequest().isNotEmpty;
    final isWaitingLocalResponse =
        _coreData.isRemoteRequestWaitingLocalResponse();
    final needAddToCurrentSession =
        isInPK || isWaitingRemoteResponse || isWaitingLocalResponse;
    ZegoLoggerService.logInfo(
      'isInPK:$isInPK, '
      'isWaitingRemoteResponse:$isWaitingRemoteResponse, '
      'isWaitingLocalResponse:$isWaitingLocalResponse, ',
      tag: 'live-streaming-pk',
      subTag: 'service, host, sendPKBattleRequest',
    );

    var tempTargetHostUserIDs = List<String>.from(targetHostIDs);
    var restartRequired = false;
    if (needAddToCurrentSession) {
      /// Extending an ongoing PK session (e.g. re-adding a host who just quit).
      /// Do NOT pre-filter with the plugin's local "in invitation" cache here:
      /// right after a host quits this session, the local cache can still
      /// report them as a current member until the quit event propagates,
      /// which would silently drop the re-invite. Let the signaling
      /// plugin/ZIM arbitrate and return per-user errors instead.
      ZegoLoggerService.logInfo(
        'send pk request, '
        'is in pk or waiting response, '
        'skip in-invitation pre-filter, '
        'will add target host user ids:$tempTargetHostUserIDs to '
        'request:$_coreData.currentRequestID',
        tag: 'live-streaming-pk',
        subTag: 'service, host, sendPKBattleRequest',
      );

      /// A host who was part of this session but is no longer a current member
      /// (disconnected and left) cannot be re-added to the existing ZIM call:
      /// the server rejects re-adding a former/terminal member to the same
      /// callID (6000007). Restart the whole session on a fresh callID instead
      /// of extending the old one.
      final currentPKUserIDs =
          _coreData.currentPKUsers.value.map((e) => e.userInfo.id).toList();
      final previousPKUserIDs =
          _coreData.previousPKUsers.value.map((e) => e.userInfo.id).toList();
      restartRequired = tempTargetHostUserIDs.any(
        (userID) =>
            !currentPKUserIDs.contains(userID) &&
            previousPKUserIDs.contains(userID),
      );
      ZegoLoggerService.logInfo(
        'restartRequired:$restartRequired, '
        'currentPKUsers:${_coreData.currentPKUsers.value}, '
        'previousPKUsers:${_coreData.previousPKUsers.value}',
        tag: 'live-streaming-pk',
        subTag: 'service, host, sendPKBattleRequest',
      );
    } else {
      var inInvitationUserIDs = <String>[];
      for (var userID in targetHostIDs) {
        if (ZegoUIKit()
            .getSignalingPlugin()
            .isUserInAdvanceInvitationNow(userID)) {
          inInvitationUserIDs.add(userID);
        }
      }
      tempTargetHostUserIDs.removeWhere(
        (userID) => inInvitationUserIDs.contains(userID),
      );
      if (tempTargetHostUserIDs.isEmpty) {
        ZegoLoggerService.logInfo(
          'could not send pk request, '
          'all user is in PK, '
          'param target host id:$targetHostIDs, '
          'now target host user ids:$tempTargetHostUserIDs, '
          'advance data:${ZegoUIKit().getSignalingPlugin().advanceInvitationToString()}, ',
          tag: 'live-streaming-pk',
          subTag: 'service, host, sendPKBattleRequest',
        );

        return ZegoLiveStreamingPKServiceSendRequestResult(
          errorUserIDs: inInvitationUserIDs,
          error: PlatformException(
            code: '-1',
            message: 'all user is in PK or requesting',
          ),
        );
      }
    }

    return (needAddToCurrentSession && _coreData.currentRequestID.isNotEmpty)
        ? (restartRequired
            ? _restartPKBattleForRejoin(
                _coreData.currentRequestID,
                tempTargetHostUserIDs,
                timeout: timeout,
                customData: customData,
              )
            : _addPKBattleRequest(
                _coreData.currentRequestID,
                tempTargetHostUserIDs,
                timeout: timeout,
                customData: customData,
                isAutoAccept: isAutoAccept,
              ))
        : _sendPKBattleRequest(
            tempTargetHostUserIDs,
            timeout: timeout,
            customData: customData,
            isAutoAccept: isAutoAccept,
          );
  }

  /// A former member of the ongoing session (disconnected and left) cannot be
  /// re-added to the existing ZIM callID, so end the current session for all
  /// participants and re-invite everyone - current members and the rejoining
  /// host - on a fresh callID. Receivers recognize the re-invite as a
  /// re-add of the just-ended session via [PKServiceRequestData.previousRequestID]
  /// and auto-accept it.
  Future<ZegoLiveStreamingPKServiceSendRequestResult> _restartPKBattleForRejoin(
    String previousRequestID,
    List<String> rejoiningHostUserIDs, {
    int timeout = 60,
    String customData = '',
  }) async {
    ZegoLoggerService.logInfo(
      'restart pk battle for rejoin, '
      'previousRequestID:$previousRequestID, '
      'rejoiningHostUserIDs:$rejoiningHostUserIDs, ',
      tag: 'live-streaming-pk',
      subTag: 'service, host, restartPKBattleForRejoin',
    );

    /// End the current session for every participant. The local device also
    /// receives onCallEnded and resets via [_onInvitationEnded], which clears
    /// [currentRequestID] and sets [lastQuitRequestID] to the ended callID.
    final endResult =
        await ZegoUIKit().getSignalingPlugin().endAdvanceInvitation(
              invitationID: previousRequestID,
              data: jsonEncode({
                'code': ZegoLiveStreamingPKBattleRejectCode.reject.index,
                'invitation_id': previousRequestID,
                'invitee_name': ZegoUIKit().getLocalUser().name,
              }),
            );
    if (null != endResult.error) {
      ZegoLoggerService.logError(
        'restart pk battle for rejoin, '
        'end previous session failed, '
        'previousRequestID:$previousRequestID, '
        'error:${endResult.error}',
        tag: 'live-streaming-pk',
        subTag: 'service, host, restartPKBattleForRejoin',
      );
    }

    /// Re-invite the remaining members of the ended session plus the
    /// rejoining host(s) on a fresh callID, auto-accepting on the receiver
    /// side so everyone converges on the new session.
    final currentPKUsers = List<ZegoLiveStreamingPKUser>.from(
      _coreData.currentPKUsers.value,
    );
    var restartInvitees = currentPKUsers
        .map((e) => e.userInfo.id)
        .where((userID) => userID != ZegoUIKit().getLocalUser().id)
        .toList();
    for (final userID in rejoiningHostUserIDs) {
      if (!restartInvitees.contains(userID)) {
        restartInvitees.add(userID);
      }
    }
    restartInvitees.removeWhere(
      (userID) => userID == ZegoUIKit().getLocalUser().id,
    );
    if (restartInvitees.isEmpty) {
      ZegoLoggerService.logError(
        'restart pk battle for rejoin, '
        'no one to re-invite, '
        'currentPKUsers:${_coreData.currentPKUsers.value}, '
        'rejoiningHostUserIDs:$rejoiningHostUserIDs',
        tag: 'live-streaming-pk',
        subTag: 'service, host, restartPKBattleForRejoin',
      );

      return ZegoLiveStreamingPKServiceSendRequestResult(
        requestID: previousRequestID,
        errorUserIDs: rejoiningHostUserIDs,
        error: PlatformException(
          code: '-1',
          message: 'restart pk battle failed, '
              'no one to re-invite',
        ),
      );
    }

    return _sendPKBattleRequest(
      restartInvitees,
      timeout: timeout,
      customData: customData,
      isAutoAccept: true,
      previousRequestID: previousRequestID,
    );
  }

  Future<ZegoLiveStreamingPKServiceSendRequestResult> _sendPKBattleRequest(
    List<String> targetHostUserIDs, {
    int timeout = 60,
    String customData = '',
    bool isAutoAccept = false,
    String? previousRequestID,
  }) async {
    ZegoLoggerService.logInfo(
      'targetHostUserIDs:$targetHostUserIDs, '
      'timeout:$timeout, '
      'isAutoAccept:$isAutoAccept, '
      'customData:$customData, '
      'previousRequestID:$previousRequestID, ',
      tag: 'live-streaming-pk',
      subTag: 'service, host, sendPKBattleRequest',
    );

    final sendResult =
        await ZegoUIKit().getSignalingPlugin().sendAdvanceInvitation(
              inviterID: ZegoUIKit().getLocalUser().id,
              inviterName: ZegoUIKit().getLocalUser().name,
              invitees: targetHostUserIDs,
              timeout: timeout,
              type: ZegoLiveStreamingInvitationType
                  .crossRoomPKBattleRequestV2.value,
              data: jsonEncode(
                PKServiceRequestData(
                  inviter: ZegoUIKit().getLocalUser(),
                  invitees: targetHostUserIDs,
                  liveID: _coreData.roomID,
                  isAutoAccept: isAutoAccept,
                  customData: customData,
                  previousRequestID: previousRequestID,
                ),
              ),
            );
    (sendResult.error == null && sendResult.errorInvitees.isEmpty
        ? ZegoLoggerService.logInfo
        : ZegoLoggerService.logError)(
      'send start request signaling result:$sendResult, '
      'error invitees:${sendResult.errorInvitees.entries.map(
            (entry) => 'user'
                ' ${entry.key}\'s reason is ${entry.value}',
          ).join(',')}',
      tag: 'live-streaming-pk',
      subTag: 'service, host, sendPKBattleRequest',
    );
    if (null != sendResult.error) {
      return ZegoLiveStreamingPKServiceSendRequestResult(
        requestID: sendResult.invitationID,
        errorUserIDs: sendResult.errorInvitees.keys.toList(),
        error: sendResult.error,
      );
    }

    if (sendResult.errorInvitees.length == targetHostUserIDs.length) {
      /// all user failed
      return ZegoLiveStreamingPKServiceSendRequestResult(
        requestID: sendResult.invitationID,
        errorUserIDs: sendResult.errorInvitees.keys.toList(),
        error: PlatformException(
          code: '-1',
          message: 'failed to send pk battle request, '
              '${sendResult.errorInvitees.entries.map(
                    (entry) => 'user '
                        '${entry.key}\'s reason is ${entry.value}',
                  ).join(',')}',
        ),
      );
    }

    ZegoLiveStreamingReporter().report(
      event: ZegoLiveStreamingReporter.eventPKInvite,
      params: {
        ZegoLiveStreamingReporter.eventKeyCallID: sendResult.invitationID,
      },
    );

    _coreData.currentRequestID = sendResult.invitationID;
    _coreData.lastQuitRequestID = '';

    return ZegoLiveStreamingPKServiceSendRequestResult(
      requestID: sendResult.invitationID,
    );
  }

  Future<ZegoLiveStreamingPKServiceSendRequestResult> _addPKBattleRequest(
    String requestID,
    List<String> targetHostUserIDs, {
    int timeout = 60,
    String customData = '',
    bool isAutoAccept = false,
  }) async {
    ZegoLoggerService.logInfo(
      'requestID:$requestID, '
      'targetHostUserIDs:$targetHostUserIDs, '
      'timeout:$timeout, '
      'isAutoAccept:$isAutoAccept, '
      'customData:$customData, ',
      tag: 'live-streaming-pk',
      subTag: 'service, host, addPKBattleRequest',
    );

    final addResult =
        await ZegoUIKit().getSignalingPlugin().addAdvanceInvitation(
              invitationID: requestID,
              inviterID: ZegoUIKit().getLocalUser().id,
              inviterName: ZegoUIKit().getLocalUser().name,
              invitees: targetHostUserIDs,
              type: ZegoLiveStreamingInvitationType
                  .crossRoomPKBattleRequestV2.value,
              data: jsonEncode(
                PKServiceRequestData(
                  inviter: ZegoUIKit().getLocalUser(),
                  invitees: targetHostUserIDs,
                  liveID: _coreData.roomID,
                  isAutoAccept: isAutoAccept,
                  customData: customData,
                ),
              ),
            );
    (addResult.error == null && addResult.errorInvitees.isEmpty
        ? ZegoLoggerService.logInfo
        : ZegoLoggerService.logError)(
      'result:$addResult, '
      'error invitees:${addResult.errorInvitees.entries.map(
            (entry) => 'user'
                ' ${entry.key}\'s reason is ${entry.value}',
          ).join(',')}',
      tag: 'live-streaming-pk',
      subTag: 'service, host, addPKBattleRequest',
    );
    if (null != addResult.error) {
      return ZegoLiveStreamingPKServiceSendRequestResult(
        requestID: addResult.invitationID,
        errorUserIDs: addResult.errorInvitees.keys.toList(),
        error: addResult.error,
      );
    }
    if (addResult.errorInvitees.length == targetHostUserIDs.length) {
      /// all user failed
      return ZegoLiveStreamingPKServiceSendRequestResult(
        requestID: addResult.invitationID,
        errorUserIDs: addResult.errorInvitees.keys.toList(),
        error: PlatformException(
          code: '-1',
          message: 'failed to add pk battle request, '
              '${addResult.errorInvitees.entries.map(
                    (entry) => 'user '
                        '${entry.key}\'s reason is ${entry.value}',
                  ).join(',')}',
        ),
      );
    }

    ZegoLiveStreamingReporter().report(
      event: ZegoLiveStreamingReporter.eventPKInvite,
      params: {
        ZegoLiveStreamingReporter.eventKeyCallID: addResult.invitationID,
      },
    );

    return ZegoLiveStreamingPKServiceSendRequestResult(
      requestID: addResult.invitationID,
    );
  }

  /// Cancel your PK invitation to [targetHostIDs].
  Future<ZegoLiveStreamingPKServiceResult> cancelPKBattleRequest({
    required List<String> targetHostIDs,
    String customData = '',
  }) async {
    final isWaitingRemoteResponse =
        _coreData.remoteUserIDsWaitingResponseFromLocalRequest().isNotEmpty;
    if (!_serviceInitialized ||
        !isLiving ||
        !isHost ||
        !isWaitingRemoteResponse ||

        /// zim, count not cancel if anyone accepted
        ZegoLiveStreamingPKBattleState.inPK == pkStateNotifier.value) {
      ZegoLoggerService.logInfo(
        'could not cancel pk request, '
        'init:$_serviceInitialized, '
        'state:${pkStateNotifier.value}, '
        'is living:$isLiving, '
        'is host:$isHost, '
        'isWaitingRemoteResponse:$isWaitingRemoteResponse, ',
        tag: 'live-streaming-pk',
        subTag: 'service, host, cancelPKBattleRequest',
      );

      return ZegoLiveStreamingPKServiceResult(
        error: PlatformException(
          code: '-1',
          message: 'could not cancel pk request, '
              'init:$_serviceInitialized, '
              'state:${pkStateNotifier.value}, '
              'is living:$isLiving, '
              'is host:$isHost',
        ),
      );
    }

    if (targetHostIDs.isEmpty) {
      ZegoLoggerService.logInfo(
        'could not cancel pk request, '
        'param is invalid, '
        'target host user ids:$targetHostIDs',
        tag: 'live-streaming-pk',
        subTag: 'service, host, cancelPKBattleRequest',
      );

      return ZegoLiveStreamingPKServiceResult(
        error: PlatformException(
          code: '-1',
          message: 'param is invalid, '
              'target host user ids:$targetHostIDs',
        ),
      );
    }

    ZegoLoggerService.logInfo(
      'targetHostUserIDs:$targetHostIDs, '
      'customData:$customData, ',
      tag: 'live-streaming-pk',
      subTag: 'service, host, cancelPKBattleRequest',
    );

    final cancelResult =
        await ZegoUIKit().getSignalingPlugin().cancelAdvanceInvitation(
              invitees: targetHostIDs,
              invitationID: _coreData.currentRequestID,
              data: jsonEncode(<String, String>{
                'custom_data': customData,
              }),
            );
    ((cancelResult.error == null)
        ? ZegoLoggerService.logInfo
        : ZegoLoggerService.logError)(
      'result:$cancelResult, '
      'error invitees:${cancelResult.errorInvitees}',
      tag: 'ZegoLiveStreamingPKBattleService',
      subTag: 'service, host, cancelPKBattleRequest',
    );
    if (null != cancelResult.error) {
      return ZegoLiveStreamingPKServiceResult(error: cancelResult.error);
    }
    if (cancelResult.errorInvitees.length == targetHostIDs.length) {
      /// all user failed
      return ZegoLiveStreamingPKServiceResult(
        error: PlatformException(
          code: '-1',
          message:
              'failed to cancel pk battle request: ${cancelResult.errorInvitees}',
        ),
      );
    }

    ZegoLiveStreamingReporter().report(
      event: ZegoLiveStreamingReporter.eventPKRespond,
      params: {
        ZegoLiveStreamingReporter.eventKeyCallID: cancelResult.invitationID,
        ZegoLiveStreamingReporter.eventKeyAction:
            ZegoLiveStreamingReporter.eventKeyActionCancel,
      },
    );

    _coreData.currentRequestID = '';
    updatePKState(ZegoLiveStreamingPKBattleState.idle);

    return const ZegoLiveStreamingPKServiceResult();
  }

  /// Agree PK invitation from [requestID].
  Future<ZegoLiveStreamingPKServiceResult> acceptPKBattleRequest({
    required String requestID,
    required ZegoLiveStreamingPKUser targetHost,
    int timeout = 60,
    String customData = '',
  }) async {
    final isWaitingLocalResponse =
        _coreData.isRemoteRequestWaitingLocalResponse() ||
            _coreData.isLocalInitiatorWaitingResponse();
    if (!_serviceInitialized ||
        !isLiving ||
        !isHost ||
        !isWaitingLocalResponse) {
      ZegoLoggerService.logInfo(
        'could not accept pk request, '
        'init:$_serviceInitialized, '
        'state:${pkStateNotifier.value}, '
        'is living:$isLiving, '
        'is host:$isHost, '
        'isWaitingLocalResponse:$isWaitingLocalResponse, ',
        tag: 'live-streaming-pk',
        subTag: 'service, host, acceptPKBattleRequest',
      );

      return ZegoLiveStreamingPKServiceResult(
        error: PlatformException(
          code: '-1',
          message: 'could not accept pk request, '
              'init:$_serviceInitialized, '
              'state:${pkStateNotifier.value}, '
              'is living:$isLiving, '
              'is host:$isHost',
        ),
      );
    }

    _coreData.clearRequestReceivedEventInMinimizing();

    /// during the dialog box stay or somethings delay,
    /// the data will be updated,
    /// and here we need to obtain the latest data.
    final sessionHosts = getAcceptedHostsInSession(requestID, ignoreUserIDs: [
      ZegoUIKit().getLocalUser().id,
      targetHost.userInfo.id,
    ]);
    final sessionInitiator =
        ZegoUIKit().getSignalingPlugin().getAdvanceInitiator(requestID);
    if (null != sessionInitiator &&
        sessionInitiator.userID != ZegoUIKit().getLocalUser().id &&
        sessionInitiator.extendedData.isNotEmpty &&
        targetHost.userInfo.id != sessionInitiator.userID) {
      try {
        final initiatorPKRequestData = PKServiceRequestData.fromJson(
          jsonDecode(sessionInitiator.extendedData) as Map<String, dynamic>,
        );
        sessionHosts.add(ZegoLiveStreamingPKUser(
          userInfo: ZegoUIKitUser(
            id: sessionInitiator.userID,
            name: initiatorPKRequestData.inviter.name,
          ),
          liveID: initiatorPKRequestData.liveID,
        ));
      } catch (e) {
        ZegoLoggerService.logInfo(
          'acceptPKBattleRequest, parse initiator extendedData failed:$e',
          tag: 'live-streaming-pk',
          subTag: 'service, host, acceptPKBattleRequest',
        );
      }
    }

    ZegoLoggerService.logInfo(
      'requestID:$requestID, '
      'targetHost:${targetHost.userInfo.id}, '
      'targetHostLiveID:${targetHost.liveID}, '
      'session hosts:$sessionHosts, '
      'timeout:$timeout, '
      'customData:$customData',
      tag: 'live-streaming-pk',
      subTag: 'service, host, acceptPKBattleRequest',
    );

    final acceptResult =
        await ZegoUIKit().getSignalingPlugin().acceptAdvanceInvitation(
              invitationID: requestID,
              inviterID: targetHost.userInfo.id,
              inviterName: targetHost.userInfo.name,
              data: jsonEncode(PKServiceAcceptData(
                name: ZegoUIKit().getLocalUser().name,
                liveID: _coreData.roomID,
              )),
            );
    ((acceptResult.error != null)
            ? ZegoLoggerService.logError
            : ZegoLoggerService.logInfo)
        .call(
      'acceptPKBattleRequest, result:$acceptResult',
      tag: 'live-streaming-pk',
      subTag: 'service, host, acceptPKBattleRequest',
    );

    ZegoLiveStreamingReporter().report(
      event: ZegoLiveStreamingReporter.eventPKRespond,
      params: {
        ZegoLiveStreamingReporter.eventKeyCallID: acceptResult.invitationID,
        ZegoLiveStreamingReporter.eventKeyAction:
            ZegoLiveStreamingReporter.eventKeyActionAccept,
      },
    );

    if (null != acceptResult.error) {
      updatePKState(ZegoLiveStreamingPKBattleState.idle);

      return ZegoLiveStreamingPKServiceResult(error: acceptResult.error);
    }

    updatePKState(ZegoLiveStreamingPKBattleState.loading);
    updatePKUsers([
      ZegoLiveStreamingPKUser(
        userInfo: ZegoUIKit().getLocalUser(),
        liveID: _coreData.roomID,
      ),
      targetHost,
      ...sessionHosts,
    ]);

    return const ZegoLiveStreamingPKServiceResult();
  }

  /// Reject PK invitation from [requestID].
  Future<ZegoLiveStreamingPKServiceResult> rejectPKBattleRequest({
    required String requestID,
    required String targetHostID,
    int timeout = 60,
    String customData = '',
  }) async {
    final isWaitingLocalResponse =
        _coreData.isRemoteRequestWaitingLocalResponse() ||
            _coreData.isLocalInitiatorWaitingResponse();
    if (!_serviceInitialized ||
        !isLiving ||
        !isHost ||
        !isWaitingLocalResponse) {
      ZegoLoggerService.logInfo(
        'could not reject pk request, '
        'init:$_serviceInitialized, '
        'state:${pkStateNotifier.value}, '
        'is living:$isLiving, '
        'is host:$isHost, '
        'isWaitingLocalResponse:$isWaitingLocalResponse, ',
        tag: 'live-streaming-pk',
        subTag: 'service, host, rejectPKBattleRequest',
      );

      return ZegoLiveStreamingPKServiceResult(
        error: PlatformException(
          code: '-1',
          message: 'could not reject pk request, '
              'init:$_serviceInitialized, '
              'state:${pkStateNotifier.value}, '
              'is living:$isLiving, '
              'is host:$isHost',
        ),
      );
    }

    ZegoLoggerService.logInfo(
      'requestID:$requestID, '
      'targetHostID:$targetHostID, '
      'timeout:$timeout, '
      'customData:$customData',
      tag: 'live-streaming-pk',
      subTag: 'service, host, rejectPKBattleRequest',
    );

    _coreData.clearRequestReceivedEventInMinimizing();

    final rejectResult =
        await ZegoUIKit().getSignalingPlugin().refuseAdvanceInvitation(
            invitationID: requestID,
            inviterID: targetHostID,
            data: jsonEncode(PKServiceRejectData(
              code: ZegoLiveStreamingPKBattleRejectCode.reject.index,
              inviterID: targetHostID,
              inviteeName: ZegoUIKit().getLocalUser().name,
            )));
    ((rejectResult.error != null)
            ? ZegoLoggerService.logError
            : ZegoLoggerService.logInfo)
        .call(
      'result:$rejectResult',
      tag: 'live-streaming-pk',
      subTag: 'service, host, rejectPKBattleRequest',
    );

    ZegoLiveStreamingReporter().report(
      event: ZegoLiveStreamingReporter.eventPKRespond,
      params: {
        ZegoLiveStreamingReporter.eventKeyCallID: rejectResult.invitationID,
        ZegoLiveStreamingReporter.eventKeyAction:
            ZegoLiveStreamingReporter.eventKeyActionRefuse,
      },
    );

    updatePKState(ZegoLiveStreamingPKBattleState.idle);

    return ZegoLiveStreamingPKServiceResult(error: rejectResult.error);
  }
}
