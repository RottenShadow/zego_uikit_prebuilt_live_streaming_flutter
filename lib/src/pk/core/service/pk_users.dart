part of 'services.dart';

extension PKServiceConnectedUsers on ZegoUIKitPrebuiltLiveStreamingPKServices {
  List<ZegoLiveStreamingPKUser> get removedPKUsersCompareCurrent {
    List<ZegoLiveStreamingPKUser> removedUsers = [];

    final currentPKUserIDs =
        _coreData.currentPKUsers.value.map((e) => e.userInfo.id).toList();
    for (var user in _coreData.previousPKUsers.value) {
      if (!currentPKUserIDs.contains(user.userInfo.id)) {
        removedUsers.add(user);
      }
    }

    return removedUsers;
  }

  List<ZegoLiveStreamingPKUser> get addedPKUsersCompareCurrent {
    List<ZegoLiveStreamingPKUser> addedUsers = [];

    final previousPKUserIDs =
        _coreData.previousPKUsers.value.map((e) => e.userInfo.id).toList();
    for (var user in _coreData.currentPKUsers.value) {
      if (!previousPKUserIDs.contains(user.userInfo.id)) {
        addedUsers.add(user);
      }
    }

    return addedUsers;
  }

  List<ZegoLiveStreamingPKUser> removeDuplicatePKUsers(
    List<ZegoLiveStreamingPKUser> updatedPKUsers,
  ) {
    List<ZegoLiveStreamingPKUser> distinctPKUsers = [];
    for (var user in updatedPKUsers) {
      bool isDuplicate = false;
      for (var distinctUser in distinctPKUsers) {
        if (user.userInfo.id == distinctUser.userInfo.id) {
          isDuplicate = true;
          break;
        }
      }

      if (!isDuplicate) {
        distinctPKUsers.add(user);
      }
    }

    return distinctPKUsers;
  }

  ZegoLiveStreamingPKUser? parsePKUserFromSignalingUser(
    AdvanceInvitationUser signalingUser,
  ) {
    final localUser = ZegoUIKit().getLocalUser();
    if (signalingUser.userID == localUser.id) {
      return ZegoLiveStreamingPKUser(
        userInfo: localUser,
        liveID: _coreData.roomID,
      );
    }

    String name = signalingUser.userID;
    String liveID = '';

    if (signalingUser.extendedData.isNotEmpty) {
      try {
        final requestData = PKServiceRequestData.fromJson(
          jsonDecode(signalingUser.extendedData) as Map<String, dynamic>,
        );
        if (requestData.inviter.name.isNotEmpty) {
          name = requestData.inviter.name;
        }
        if (requestData.liveID.isNotEmpty) {
          liveID = requestData.liveID;
        }
      } catch (_) {
        final hostInfo = _getSessionHostNameAndLiveIDFromExtendedData(
          signalingUser.extendedData,
        );
        if (hostInfo.name.isNotEmpty) {
          name = hostInfo.name;
        }
        if (hostInfo.fromLiveID.isNotEmpty) {
          liveID = hostInfo.fromLiveID;
        }
      }
    }

    return ZegoLiveStreamingPKUser(
      userInfo: ZegoUIKitUser(id: signalingUser.userID, name: name),
      liveID: liveID,
    );
  }

  /// Rebuilds the current PK users list directly from the Signaling Plugin's
  /// active Advance Invitation Map. This is the source-of-truth for PK hosts
  /// in a session [requestID].
  List<ZegoLiveStreamingPKUser> getPKUsersFromInvitationMap(String requestID) {
    if (requestID.isEmpty) {
      return [];
    }

    final pkUsers = <ZegoLiveStreamingPKUser>[];

    // 1. Check Initiator
    final initiator =
        ZegoUIKit().getSignalingPlugin().getAdvanceInitiator(requestID);
    if (initiator != null &&
        initiator.state != AdvanceInvitationState.rejected) {
      final user = parsePKUserFromSignalingUser(initiator);
      if (user != null) {
        pkUsers.add(user);
      }
    }

    // 2. Check Accepted Invitees
    final invitees =
        ZegoUIKit().getSignalingPlugin().getAdvanceInvitees(requestID);
    for (final invitee in invitees) {
      if (invitee.state == AdvanceInvitationState.accepted) {
        final user = parsePKUserFromSignalingUser(invitee);
        if (user != null) {
          pkUsers.add(user);
        }
      }
    }

    // Deduplicate
    final distinctUsers = removeDuplicatePKUsers(pkUsers);

    // If local user is host and in PK, ensure local host is first
    if (isHost) {
      final localID = ZegoUIKit().getLocalUser().id;
      final localIdx =
          distinctUsers.indexWhere((u) => u.userInfo.id == localID);
      if (localIdx > 0) {
        final localUser = distinctUsers.removeAt(localIdx);
        distinctUsers.insert(0, localUser);
      }
    }

    return distinctUsers;
  }

  void updatePKUsers(
    List<ZegoLiveStreamingPKUser> tempUpdatedPKUsers, {
    bool fromRoomProps = false,
  }) {
    var updatedPKUsers = removeDuplicatePKUsers(tempUpdatedPKUsers);

    final currentPKUserIDs =
        _coreData.currentPKUsers.value.map((e) => e.userInfo.id).toList();
    final updatedPKUserIDs = updatedPKUsers.map((e) => e.userInfo.id).toList();
    if (!const DeepCollectionEquality().equals(
      currentPKUserIDs,
      updatedPKUserIDs,
    )) {
      _coreData.previousPKUsers.value =
          List<ZegoLiveStreamingPKUser>.from(_coreData.currentPKUsers.value);
      for (var pkUser in updatedPKUsers) {
        pkUser.heartbeat = DateTime.now();

        if (pkUser.heartbeatBrokenNotifier.value) {
          ZegoLoggerService.logInfo(
            'un-mute ${pkUser.userInfo.id} audio',
            tag: 'live-streaming-pk',
            subTag: 'service, connect-users, update pk users',
          );

          ZegoUIKit().muteUserAudio(pkUser.userInfo.id, false);

          _coreData.events?.pk.onUserReconnected?.call(
            pkUser.toUIKitUser,
          );
        }
        pkUser.heartbeatBrokenNotifier.value = false;
      }

      ZegoLoggerService.logInfo(
        'previous:${_coreData.previousPKUsers.value}, '
        'current:$updatedPKUsers, '
        'current details:$updatedPKUsers, '
        'fromRoomProps:$fromRoomProps, ',
        tag: 'live-streaming-pk',
        subTag: 'service, connect-users, update pk users',
      );
      _coreData.pkUsersUpdateFromRoomProps = fromRoomProps;
      _coreData.currentPKUsers.value = updatedPKUsers;
    }
  }

  void listenPKUserChanged() {
    ZegoLoggerService.logInfo(
      'listenPKUserChanged',
      tag: 'live-streaming-pk',
      subTag: 'service, connect-users',
    );

    removeListenPKUserChanged();

    _coreData.connectingPKUsers.addListener(onConnectingPKUsersChanged);
    _coreData.currentPKUsers.addListener(onPKUsersChanged);
  }

  void removeListenPKUserChanged() {
    ZegoLoggerService.logInfo(
      'removeListenPKUserChanged',
      tag: 'live-streaming-pk',
      subTag: 'service, connect-users',
    );

    _coreData.connectingPKUsers.removeListener(onConnectingPKUsersChanged);
    _coreData.currentPKUsers.removeListener(onPKUsersChanged);
  }

  void onConnectingPKUsersChanged() {
    ZegoLoggerService.logInfo(
      'onConnectingPKUsersChanged:${_coreData.connectingPKUsers.value}',
      tag: 'live-streaming-pk',
      subTag: 'service, connect-users',
    );
  }

  Future<void> onPKUsersChanged() async {
    ZegoLoggerService.logInfo(
      'onPKUsersChanged, '
      'pk users:${_coreData.currentPKUsers.value}, '
      'isLiving;$isLiving, ',
      tag: 'live-streaming-pk',
      subTag: 'service, connect-users',
    );

    if (!isLiving) {
      return;
    }

    /// Capture synchronously while the notifier fires; a later update can
    /// overwrite the flag before the async chain below runs.
    final fromRoomProps = _coreData.pkUsersUpdateFromRoomProps;

    return waitCompleter('onPKUsersChanged').then((_) async {
      isHost
          ? await hostOnPKUsersChanged(fromRoomProps: fromRoomProps)
          : await audienceOnPKUsersChanged(fromRoomProps: fromRoomProps);
    }).then((_) {
      completeCompleter('onPKUsersChanged');
    });
  }

  Future<void> hostOnPKUsersChanged({bool fromRoomProps = false}) async {
    final isLocalHostInPK = -1 !=
        _coreData.currentPKUsers.value.indexWhere(
            (pkUser) => pkUser.userInfo.id == ZegoUIKit().getLocalUser().id);

    ZegoLoggerService.logInfo(
      'hostOnPKUsersChanged,'
      'isLocalHostInPK:$isLocalHostInPK, '
      'pk users:${_coreData.currentPKUsers.value}',
      tag: 'live-streaming-pk',
      subTag: 'service, connect-users',
    );

    return isLocalHostInPK
        ? await connectedHostOnPKUsersChanged(fromRoomProps: fromRoomProps)
        : await disconnectedHostOnPKUsersChanged();
  }

  Future<void> connectedHostOnPKUsersChanged({
    bool fromRoomProps = false,
  }) async {
    final onlyLocalInPK = _coreData.currentPKUsers.value.length == 1 &&
        _coreData.currentPKUsers.value.first.userInfo.id ==
            ZegoUIKit().getLocalUser().id;

    ZegoLoggerService.logInfo(
      'onlyLocalInPK:$onlyLocalInPK, '
      'pk users:${_coreData.currentPKUsers.value}, '
      'previousPKUsers:${_coreData.previousPKUsers.value}, '
      'addedPKUsersCompareCurrent:$addedPKUsersCompareCurrent, '
      'removedPKUsersCompareCurrent:$removedPKUsersCompareCurrent, '
      'playing user id:${_coreData.playingHostIDs}',
      tag: 'live-streaming-pk',
      subTag: 'service, connect-users, connectedHostOnPKUsersChanged',
    );

    if (fromRoomProps &&
        _isUninvitedReAdd(
          localState: pkStateNotifier.value,
          currentRequestID: _coreData.currentRequestID,
          updatedPKUsers: _coreData.currentPKUsers.value,
        )) {
      ZegoLoggerService.logInfo(
        'connectedHostOnPKUsersChanged, dropping uninvited re-add for local user',
        tag: 'live-streaming-pk',
        subTag: 'service, connect-users, connectedHostOnPKUsersChanged',
      );
      return;
    }

    if (!isInPK) {
      /// not in pk now, init pk
      updatePKState(ZegoLiveStreamingPKBattleState.inPK);

      final isMicrophoneOn = ZegoUIKit()
          .getMicrophoneStateNotifier(ZegoUIKit().getLocalUser().id)
          .value;
      ZegoUIKit().turnMicrophoneOn(isMicrophoneOn, muteMode: true);
    }

    /// update mixer layout
    await _mixer.updateTask(List.from(_coreData.currentPKUsers.value));

    /// start play other room user stream
    ZegoLoggerService.logInfo(
      'try play ${_coreData.currentPKUsers.value}\'s stream',
      tag: 'live-streaming-pk',
      subTag: 'service, connect-users, connectedHostOnPKUsersChanged',
    );
    for (var user in _coreData.currentPKUsers.value) {
      if (ZegoUIKit().getLocalUser().id == user.userInfo.id) {
        continue;
      }

      if (_coreData.playingHostIDs.contains(user.userInfo.id)) {
        ZegoLoggerService.logInfo(
          '${user.userInfo.id} is playing, ignore',
          tag: 'live-streaming-pk',
          subTag: 'service, connect-users, connectedHostOnPKUsersChanged',
        );
        continue;
      }

      ZegoLoggerService.logInfo(
        'start play ${user.userInfo.id}',
        tag: 'live-streaming-pk',
        subTag: 'service, connect-users, connectedHostOnPKUsersChanged',
      );
      _coreData.playingHostIDs.add(user.userInfo.id);

      final targetStreamID = ZegoUIKit().getGeneratedStreamID(
        user.userInfo.id,
        user.liveID,
        ZegoStreamType.main,
      );
      ZegoLiveStreamingReporter().report(
        event: ZegoLiveStreamingReporter.eventPKStartPlay,
        params: {
          ZegoLiveStreamingReporter.eventKeyCallID: _coreData.currentRequestID,
          ZegoLiveStreamingReporter.eventKeyStreamID: targetStreamID,
        },
      );
      await ZegoUIKit().startPlayAnotherRoomAudioVideo(
          user.liveID, user.userInfo.id, userName: user.userInfo.name,
          onPlayerStateUpdated: (
        ZegoUIKitPlayerState state,
        int errorCode,
        Map<String, dynamic> extendedData,
      ) {
        if (ZegoUIKitPlayerState.playing == state) {
          ZegoLiveStreamingReporter().report(
            event: ZegoLiveStreamingReporter.eventPKStartPlayFinished,
            params: {
              ZegoLiveStreamingReporter.eventKeyCallID:
                  _coreData.currentRequestID,
              ZegoLiveStreamingReporter.eventKeyStreamID: targetStreamID,
              ZegoLiveStreamingReporter.eventKeyError: errorCode,
            },
          );
        }
      });
    }

    /// stop play other room user stream
    ZegoLoggerService.logInfo(
      'try stop $removedPKUsersCompareCurrent\'s stream',
      tag: 'live-streaming-pk',
      subTag: 'service, connect-users, connectedHostOnPKUsersChanged',
    );
    for (var user in removedPKUsersCompareCurrent) {
      if (!_coreData.playingHostIDs.contains(user.userInfo.id)) {
        ZegoLoggerService.logInfo(
          '${user.userInfo.id} is not playing, ignore',
          tag: 'live-streaming-pk',
          subTag: 'service, connect-users, connectedHostOnPKUsersChanged',
        );
        continue;
      }

      ZegoLoggerService.logInfo(
        'stop play ${user.userInfo.id}',
        tag: 'live-streaming-pk',
        subTag: 'service, connect-users, connectedHostOnPKUsersChanged',
      );
      _coreData.playingHostIDs.remove(user.userInfo.id);
      await ZegoUIKit().stopPlayAnotherRoomAudioVideo(
        user.userInfo.id,
      );
    }

    /// Publish the authoritative PK layout to THIS host's own room so its
    /// own audience (who cannot see the invitation map) renders the PK.
    ///
    /// Every connected host writes only to its own room (_coreData.roomID),
    /// so no two hosts ever contend on the same room attribute. The value is
    /// always read from the invitation map (getPKUsersFromInvitationMap) at
    /// write time, NOT from the _coreData.currentPKUsers snapshot, so a
    /// locally-initiated change (invitation accepted/quit/offline) can never
    /// echo a stale or partial list. Updates driven by a room-attributes
    /// snapshot (fromRoomProps == true) must NOT echo back - the source has
    /// already published them and re-writing with isForce: true only spams
    /// the room attributes (and can loop with the backend).
    if (!fromRoomProps && _coreData.currentRequestID.isNotEmpty) {
      final fullPKUsers = getPKUsersFromInvitationMap(
        _coreData.currentRequestID,
      );
      if (fullPKUsers.length >= 2) {
        await ZegoUIKit().getSignalingPlugin().updateRoomProperties(
          roomID: _coreData.roomID,
          roomProperties: {
            roomPropKeyRequestID: _coreData.currentRequestID,
            roomPropKeyHost: ZegoUIKit().getLocalUser().id,
            roomPropKeyPKUsers: jsonEncode(fullPKUsers),
          },
          isForce: true,
          isUpdateOwner: true,
        );
      }
    }

    if (onlyLocalInPK && !fromRoomProps) {
      /// all leave but only local
      await quitPKBattle(requestID: _coreData.currentRequestID);
    }
  }

  Future<void> disconnectedHostOnPKUsersChanged() async {
    ZegoLoggerService.logInfo(
      'pk users:${_coreData.currentPKUsers.value}',
      tag: 'live-streaming-pk',
      subTag: 'service, connect-users, hostDisconnectedOnPKUsersChanged',
    );

    if (pkStateNotifier.value != ZegoLiveStreamingPKBattleState.idle) {
      /// ready to quit pk state

      final isMicrophoneOn = ZegoUIKit()
          .getMicrophoneStateNotifier(ZegoUIKit().getLocalUser().id)
          .value;
      ZegoUIKit().turnMicrophoneOn(isMicrophoneOn, muteMode: true);

      /// stop play other room user stream
      for (var hostID in _coreData.playingHostIDs) {
        if (ZegoUIKit().getLocalUser().id == hostID) {
          continue;
        }
        await ZegoUIKit().stopPlayAnotherRoomAudioVideo(hostID);
      }
      _coreData.playingHostIDs.clear();

      /// stop mixer
      await _mixer.stopTask();

      /// delete room property, notify the host info && layout
      await ZegoUIKit().getSignalingPlugin().deleteRoomProperties(
        roomID: _coreData.roomID,
        keys: [roomPropKeyRequestID, roomPropKeyHost, roomPropKeyPKUsers],
      );

      if (_coreData.currentRequestID.isNotEmpty) {
        await quitPKBattle(requestID: _coreData.currentRequestID);
      }

      updatePKState(ZegoLiveStreamingPKBattleState.idle);
    }
  }

  Future<void> audienceOnPKUsersChanged({
    bool fromRoomProps = false,
  }) async {
    ZegoLoggerService.logInfo(
      'pk users:${_coreData.currentPKUsers.value}',
      tag: 'live-streaming-pk',
      subTag: 'service, connect-users, audienceOnPKUsersChanged',
    );

    final onlyLocalHostInPK = _coreData.currentPKUsers.value.length == 1 &&
        _coreData.currentPKUsers.value.first.userInfo.id ==
            _coreData.hostManager?.notifier.value?.id;
    if (_coreData.currentPKUsers.value.isEmpty || onlyLocalHostInPK) {
      ZegoLoggerService.logInfo(
        'pk users is empty or only local room host, not in pk, '
        'onlyLocalHostInPK:$onlyLocalHostInPK, '
        'state:${pkStateNotifier.value}, ',
        tag: 'live-streaming-pk',
        subTag: 'service, connect-users, audienceOnPKUsersChanged',
      );

      /// The audience no longer has any PK host to show. If we were still in
      /// PK (or loading), tear down the mixer stream and reset the state,
      /// otherwise the audience can be stuck showing an empty/black PK view.
      if (pkStateNotifier.value != ZegoLiveStreamingPKBattleState.idle) {
        if (_coreData.currentPKUsers.value.isEmpty) {
          await _mixer.stopPlayStream();
        }

        updatePKState(ZegoLiveStreamingPKBattleState.idle);
      }

      return;
    }

    /// A backend reorder (or duplicate rewrite) changes only the order of the
    /// very same hosts: [currentPKUsers] has already been updated so the PK
    /// overlay follows, but the mix stream must NOT be restarted - restarting
    /// it on every backend room-attribute update is what caused the UI
    /// flicker.
    final isPureOrderChange = _coreData.currentPKUsers.value.isNotEmpty &&
        addedPKUsersCompareCurrent.isEmpty &&
        removedPKUsersCompareCurrent.isEmpty;
    if (isPureOrderChange &&
        pkStateNotifier.value != ZegoLiveStreamingPKBattleState.idle) {
      ZegoLoggerService.logInfo(
        'only pk host order changed, skip mix playback restart, '
        'fromRoomProps:$fromRoomProps, '
        'pk users:${_coreData.currentPKUsers.value}',
        tag: 'live-streaming-pk',
        subTag: 'service, connect-users, audienceOnPKUsersChanged',
      );

      return;
    }

    /// hide invite join co-host dialog
    if (_coreData
            .hostManager?.connectManager?.isInvitedToJoinCoHostDlgVisible ??
        false) {
      _coreData.hostManager?.connectManager!.isInvitedToJoinCoHostDlgVisible =
          false;

      Navigator.of(
        _coreData.contextQuery!(),
        rootNavigator: _coreData.prebuiltConfig?.rootNavigator ?? false,
      ).pop();
    }

    /// hide co-host end request dialog
    if (_coreData.hostManager?.connectManager?.isEndCoHostDialogVisible ??
        false) {
      _coreData.hostManager?.connectManager!.isEndCoHostDialogVisible = false;

      Navigator.of(
        _coreData.contextQuery!(),
        rootNavigator: _coreData.prebuiltConfig?.rootNavigator ?? false,
      ).pop();
    }

    /// cancel audience's co-host request
    if (ZegoLiveStreamingAudienceConnectState.connecting ==
        _coreData.hostManager?.connectManager?.audienceLocalConnectStateNotifier
            .value) {
      _coreData.hostManager?.connectManager?.updateAudienceConnectState(
        ZegoLiveStreamingAudienceConnectState.idle,
      );
      ZegoUIKit().getSignalingPlugin().cancelInvitation(
        invitees: [
          _coreData.hostManager?.notifier.value?.id ?? _coreData.propertyHostID
        ],
        data: '',
      );
    } else if (ZegoLiveStreamingAudienceConnectState.connected ==
        _coreData.hostManager?.connectManager?.audienceLocalConnectStateNotifier
            .value) {
      _coreData.hostManager?.connectManager?.updateAudienceConnectState(
        ZegoLiveStreamingAudienceConnectState.idle,
      );

      final dialogInfo = _coreData.innerText!.coHostEndCauseByHostStartPK;
      showLiveDialog(
        context: context,
        rootNavigator: _coreData.prebuiltConfig?.rootNavigator ?? false,
        title: dialogInfo.title,
        content: dialogInfo.message,
        rightButtonText: dialogInfo.confirmButtonName,
      );
    }

    /// pk process
    ZegoLiveStreamingReporter().report(
      event: ZegoLiveStreamingReporter.eventPKStartPlay,
      params: {
        ZegoLiveStreamingReporter.eventKeyCallID: _coreData.currentRequestID,
        ZegoLiveStreamingReporter.eventKeyStreamID: _mixer.mixerID,
      },
    );
    await _mixer.startPlayStream(
      List.from(_coreData.currentPKUsers.value),
      onPlayerStateUpdated: (
        ZegoUIKitPlayerState state,
        int errorCode,
        Map<String, dynamic> extendedData,
      ) {
        if (ZegoUIKitPlayerState.playing == state) {
          ZegoLiveStreamingReporter().report(
            event: ZegoLiveStreamingReporter.eventPKStartPlayFinished,
            params: {
              ZegoLiveStreamingReporter.eventKeyCallID:
                  _coreData.currentRequestID,
              ZegoLiveStreamingReporter.eventKeyStreamID: _mixer.mixerID,
              ZegoLiveStreamingReporter.eventKeyError: errorCode,
            },
          );
        }
      },
    );

    final mixAudioVideoLoaded =
        ZegoUIKit().getMixAudioVideoLoadedNotifier(_mixer.mixerID);
    if (mixAudioVideoLoaded.value) {
      /// load done
      updatePKState(ZegoLiveStreamingPKBattleState.inPK);
      ZegoUIKit().muteUserAudioVideo(
        _coreData.hostManager?.notifier.value?.id ?? _coreData.propertyHostID,
        true,
      );
    } else {
      updatePKState(ZegoLiveStreamingPKBattleState.loading);

      /// Only attach to the latest notifier instance. A re-entrant
      /// [audienceOnPKUsersChanged] may have been called again, and attaching
      /// to a stale instance would leave the state stuck in loading forever.
      if (_mixAudioVideoLoadedNotifier != mixAudioVideoLoaded) {
        _mixAudioVideoLoadedNotifier
            ?.removeListener(onMixAudioVideoLoadStatusChanged);
        _mixAudioVideoLoadedNotifier = mixAudioVideoLoaded;
        mixAudioVideoLoaded.addListener(onMixAudioVideoLoadStatusChanged);
      }
    }
  }

  void onMixAudioVideoLoadStatusChanged() {
    final mixAudioVideoLoaded = _mixAudioVideoLoadedNotifier;
    _mixAudioVideoLoadedNotifier = null;
    mixAudioVideoLoaded?.removeListener(onMixAudioVideoLoadStatusChanged);

    if (true != mixAudioVideoLoaded?.value) {
      /// not loaded yet, keep the loading state
      return;
    }

    if (pkStateNotifier.value != ZegoLiveStreamingPKBattleState.idle) {
      updatePKState(ZegoLiveStreamingPKBattleState.inPK);

      ZegoUIKit().muteUserAudioVideo(
        _coreData.hostManager?.notifier.value?.id ?? _coreData.propertyHostID,
        true,
      );
    }
  }
}

/// ponytail: defend against backend misfires that re-add the local host to a
/// `pk_users` echo after they quit. Returns true when the local user is named
/// in [updatedPKUsers] but is NOT in the signaling invitation set (i.e. was
/// never actually invited/accepted into the active [currentRequestID]).
bool _isUninvitedReAdd({
  required ZegoLiveStreamingPKBattleState localState,
  required String currentRequestID,
  required List<ZegoLiveStreamingPKUser> updatedPKUsers,
}) {
  if (localState != ZegoLiveStreamingPKBattleState.idle) {
    return false;
  }
  if (currentRequestID.isEmpty) {
    return true;
  }
  final localID = ZegoUIKit().getLocalUser().id;
  if (!updatedPKUsers.any((u) => u.userInfo.id == localID)) {
    return false;
  }
  final invitees = ZegoUIKit()
      .getSignalingPlugin()
      .getAdvanceInvitees(currentRequestID);
  final locallyInvited = invitees.any(
    (u) =>
        u.userID == localID &&
        (u.state == AdvanceInvitationState.waiting ||
            u.state == AdvanceInvitationState.accepted),
  );
  return !locallyInvited;
}
