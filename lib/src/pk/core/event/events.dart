part of '../service/services.dart';

extension ZegoUIKitPrebuiltLiveStreamingPKEventsV2
    on ZegoUIKitPrebuiltLiveStreamingPKServices {
  bool get rootNavigator => _coreData.prebuiltConfig?.rootNavigator ?? false;

  ZegoUIKitPrebuiltLiveStreamingInnerText get innerText =>
      _coreData.prebuiltConfig?.innerText ??
      ZegoUIKitPrebuiltLiveStreamingInnerText();

  void initEvents() {
    if (_eventInitialized) {
      ZegoLoggerService.logInfo(
        'had already init',
        tag: 'live-streaming-pk',
        subTag: 'pk event',
      );

      return;
    }

    _eventInitialized = true;

    ZegoLoggerService.logInfo(
      'init',
      tag: 'live-streaming-pk',
      subTag: 'pk event',
    );

    _initHeartBeatTimer();
    _coreData.hostManager?.notifier.addListener(_onHostUpdated);

    _listenEvents();
    queryRoomProperties();
  }

  void _onHostUpdated() {
    if (isHost) {
      _initHeartBeatTimer();
    }
  }

  void onWaitingQueryRoomProperties(
    ZegoSignalingPluginRoomStateChangedEvent event,
  ) {
    ZegoLoggerService.logInfo(
      'onWaitingQueryRoomProperties, event:$event',
      tag: 'live-streaming-pk',
      subTag: 'pk event',
    );

    _waitingQueryRoomPropertiesSubscription?.cancel();
    queryRoomProperties();
  }

  void queryRoomProperties() {
    ZegoLoggerService.logInfo(
      'queryRoomProperties',
      tag: 'live-streaming-pk',
      subTag: 'pk event',
    );

    final signalingRoomState = ZegoUIKit().getSignalingPlugin().getRoomState();
    if (ZegoSignalingPluginRoomState.connected != signalingRoomState) {
      ZegoLoggerService.logInfo(
        'room state($signalingRoomState) is not connected, wait...',
        tag: 'live-streaming-pk',
        subTag: 'pk event',
      );

      _waitingQueryRoomPropertiesSubscription = ZegoUIKit()
          .getSignalingPlugin()
          .getRoomStateStream()
          .listen(onWaitingQueryRoomProperties);
    } else {
      ZegoUIKit()
          .getSignalingPlugin()
          .queryRoomProperties(
            roomID: ZegoUIKit().getSignalingPlugin().getRoomID(),
          )
          .then((result) async {
        ZegoLoggerService.logInfo(
          'queryRoomProperties done: $result',
          tag: 'live-streaming-pk',
          subTag: 'pk event',
        );

        /// Express room reconnects before ZIM user login. ZIM APIs
        /// (deleteRoomProperties, callQuit) fail with 6000121 if called
        /// before login completes. Wait for connection state = connected.
        await _waitForSignalingConnected();

        if (isHost) {
          /// The PK recovery logic below handles two cases:
          /// 1. App killed during PK — pkState is idle on restart, tear down
          ///    stale mixer/streams/state via teardownPKFromRoomProperties.
          /// 2. Host disconnected for 30s+ — heartbeat timer removed remote
          ///    hosts, set pkState idle, and quit the ZIM invitation. On
          ///    reconnection, complete the teardown here.
          ///
          /// An audience/viewer must NOT run this recovery, otherwise it would
          /// tear down the PK room properties (and notify the invitation) for
          /// every other participant while a PK is still ongoing.
          ///
          /// Guard with pkState == idle to avoid destroying active PK
          /// properties during the race where the deferred query fires after
          /// the acceptance flow has already written pk_users to the room.
          if (result.properties.containsKey(roomPropKeyRequestID)) {
            if (pkStateNotifier.value == ZegoLiveStreamingPKBattleState.idle) {
              ZegoLoggerService.logInfo(
                'room property contain pk keys, teardown',
                tag: 'live-streaming-pk',
                subTag: 'pk event',
              );

              await teardownPKFromRoomProperties();
            }
          } else if (pkStateNotifier.value !=
              ZegoLiveStreamingPKBattleState.idle) {
            /// PK keys were already deleted by other hosts while we were
            /// offline. Tear down the local mixer/task/state so the host
            /// doesn't remain stuck in a stale PK state.
            ZegoLoggerService.logInfo(
              'room property missing pk keys but local state is '
              '${pkStateNotifier.value}, teardown',
              tag: 'live-streaming-pk',
              subTag: 'pk event',
            );

            await teardownPKFromRoomProperties();
          }

          /// Only delete PK room properties when idle to avoid destroying
          /// properties written by an active PK acceptance flow.
          if (pkStateNotifier.value == ZegoLiveStreamingPKBattleState.idle) {
            await ZegoUIKit().getSignalingPlugin().deleteRoomProperties(
                  roomID: ZegoUIKit().getSignalingPlugin().getRoomID(),
                  keys: [
                    roomPropKeyRequestID,
                    roomPropKeyHost,
                    roomPropKeyPKUsers
                  ],
                  showErrorLog: false,
                );
          }
        }
      });
    }
  }

  /// Waits for the signaling connection state to reach [ZegoSignalingPluginConnectionState.connected].
  /// Express room can reconnect before ZIM user login completes, so ZIM APIs
  /// (deleteRoomProperties, callQuit) fail with 6000121 if called too early.
  Future<void> _waitForSignalingConnected({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final currentState =
        ZegoUIKit().getSignalingPlugin().getConnectionState();
    if (currentState == ZegoSignalingPluginConnectionState.connected) {
      return;
    }

    ZegoLoggerService.logInfo(
      'signaling not connected ($currentState), waiting...',
      tag: 'live-streaming-pk',
      subTag: 'pk event',
    );

    final completer = Completer<void>();
    final timer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      final state =
          ZegoUIKit().getSignalingPlugin().getConnectionState();
      if (state == ZegoSignalingPluginConnectionState.connected) {
        if (timer.isActive) timer.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });

    Future.delayed(timeout, () {
      if (timer.isActive) timer.cancel();
      if (!completer.isCompleted) {
        ZegoLoggerService.logInfo(
          'wait for signaling connected timed out, proceeding anyway',
          tag: 'live-streaming-pk',
          subTag: 'pk event',
        );
        completer.complete();
      }
    });

    return completer.future;
  }

  void uninitEvents() {
    if (!_eventInitialized) {
      ZegoLoggerService.logInfo(
        'not init before',
        tag: 'live-streaming-pk',
        subTag: 'pk event',
      );

      return;
    }

    _eventInitialized = false;
    ZegoLoggerService.logInfo(
      'uninit',
      tag: 'live-streaming-pk',
      subTag: 'pk event',
    );

    _coreData.hostManager?.notifier.removeListener(_onHostUpdated);
    _heartBeatTimer?.cancel();
    _heartBeatTimer = null;
    _waitingQueryRoomPropertiesSubscription?.cancel();
    for (final subscription in _eventSubscriptions) {
      subscription?.cancel();
    }
  }

  void _onInvitationUserStateChanged(
    ZegoSignalingPluginInvitationUserStateChangedEvent event,
  ) {
    ZegoLoggerService.logInfo(
      'onInvitationUserStateChanged, event:$event, '
      'currentRequestID:${_coreData.currentRequestID}, '
      'lastQuitRequestID:${_coreData.lastQuitRequestID}, '
      'pkState:${pkStateNotifier.value}, '
      'initiator:${ZegoUIKit().getSignalingPlugin().getAdvanceInitiator(event.invitationID)?.userID}, '
      'currentPKUsers:[${_coreData.currentPKUsers.value.map((u) => u.userInfo.id).join(',')}]',
      tag: 'live-streaming-pk',
      subTag: 'pk event',
    );

    if (null ==
        ZegoUIKit()
            .getSignalingPlugin()
            .getAdvanceInitiator(event.invitationID)) {
      /// a->b, b->c;
      /// in c event, a is initiator, b is inviter

      ZegoLoggerService.logInfo(
        'event is not advance invitation',
        tag: 'live-streaming-pk',
        subTag: 'pk event',
      );

      return;
    }

    final requestID = event.invitationID;
    if (_coreData.currentRequestID.isNotEmpty &&
        requestID != _coreData.currentRequestID &&
        requestID != _coreData.lastQuitRequestID) {
      ZegoLoggerService.logInfo(
        'onInvitationUserStateChanged: ignoring stale requestID:$requestID (active:${_coreData.currentRequestID})',
        tag: 'live-streaming-pk',
        subTag: 'pk event',
      );
      return;
    }

    /// Skip the invitation-map snapshot when any user in this event is
    /// leaving (quit / offline). The map may not yet reflect the departure,
    /// so trusting it here would re-add the user who is about to be removed
    /// by the specific handler below (_onInvitationUserQuit / Offline).
    final isUserLeaving = event.callUserList.any(
      (u) =>
          u.state == ZegoSignalingPluginInvitationUserState.quited ||
          u.state == ZegoSignalingPluginInvitationUserState.offline,
    );

    // If a user accepted (re-joined), clear them from quitRequestUserIDs so
    // getPKUsersFromInvitationMap won't exclude them via the initiator filter.
    // Without this, a remote host that never sent/received the re-invitation
    // would keep the user in quitRequestUserIDs and hide them.
    for (final u in event.callUserList) {
      if (u.state == ZegoSignalingPluginInvitationUserState.accepted) {
        _coreData.quitRequestUserIDs.remove(u.userID);
      }
    }

    final pkUsersFromMap = getPKUsersFromInvitationMap(requestID);
    if (pkUsersFromMap.length >= 2 && !isUserLeaving) {
      final localAccepted = pkUsersFromMap.any(
        (u) => u.userInfo.id == ZegoUIKit().getLocalUser().id,
      );
      if (!localAccepted) {
        ZegoLoggerService.logInfo(
          '_onInvitationUserStateChanged, '
          'local user not in PK users from map, skipping update',
          tag: 'live-streaming-pk',
          subTag: 'pk event',
        );
        return;
      }
      if (pkStateNotifier.value == ZegoLiveStreamingPKBattleState.idle) {
        updatePKState(ZegoLiveStreamingPKBattleState.loading);
      }
      updatePKUsers(pkUsersFromMap);
    }

    for (var userInfo in event.callUserList) {
      if (userInfo.userID == ZegoUIKit().getLocalUser().id) {
        _onLocalInvitationUserStateChanged(event.invitationID, userInfo);
      } else {
        _onRemoteInvitationUserStateChanged(event.invitationID, userInfo);
      }
    }
  }

  void _onLocalInvitationUserStateChanged(
    String requestID,
    ZegoSignalingPluginInvitationUserInfo userInfo,
  ) {
    ZegoLoggerService.logInfo(
      '_onLocalInvitationUserStateChanged, user info:$userInfo',
      tag: 'live-streaming-pk',
      subTag: 'pk event',
    );

    switch (userInfo.state) {
      case ZegoSignalingPluginInvitationUserState.timeout:
        updatePKState(ZegoLiveStreamingPKBattleState.idle);

        popupRequestReceivedDialog();
        break;
      case ZegoSignalingPluginInvitationUserState.accepted:
        if (ZegoUIKit()
                .getSignalingPlugin()
                .getAdvanceInitiator(requestID)
                ?.userID !=
            ZegoUIKit().getLocalUser().id) {
          /// a->b, b->c;
          /// in c event, a is initiator, b is inviter
          ///
          /// invitee accept, need to update to pk state, because only update to loading
          /// when call acceptPKBattleRequest->startPKBattle
          updatePKState(ZegoLiveStreamingPKBattleState.inPK);
        }
        break;
      case ZegoSignalingPluginInvitationUserState.inviting:
      case ZegoSignalingPluginInvitationUserState.rejected:
      case ZegoSignalingPluginInvitationUserState.cancelled:
      case ZegoSignalingPluginInvitationUserState.offline:
      case ZegoSignalingPluginInvitationUserState.received:
      case ZegoSignalingPluginInvitationUserState.ended:
      case ZegoSignalingPluginInvitationUserState.unknown:
      case ZegoSignalingPluginInvitationUserState.notYetReceived:
      case ZegoSignalingPluginInvitationUserState.beCanceled:
        break;
      case ZegoSignalingPluginInvitationUserState.quited:
        _coreData.events?.pk.onUserQuited?.call(
            ZegoLiveStreamingPKBattleUserQuitEvent(
              requestID: requestID,
              fromHost: ZegoUIKit().getLocalUser(),
            ),
            () {});
        break;
    }
  }

  void _onRemoteInvitationUserStateChanged(
    String requestID,
    ZegoSignalingPluginInvitationUserInfo remoteUserInfo,
  ) {
    /// a->b, b->c;
    /// in c event, a is initiator, b is inviter
    final sessionInitiator =
        ZegoUIKit().getSignalingPlugin().getAdvanceInitiator(requestID);

    ZegoLoggerService.logInfo(
      '_onRemoteInvitationUserStateChanged, '
      'sessionInitiator:$sessionInitiator, '
      'user info:$remoteUserInfo, ',
      tag: 'live-streaming-pk',
      subTag: 'pk event',
    );

    var extendedDataMap = <String, dynamic>{};
    try {
      extendedDataMap =
          jsonDecode(remoteUserInfo.extendedData) as Map<String, dynamic>? ??
              {};
    } catch (e) {
      ZegoLoggerService.logInfo(
        'extendedData is not a json:${remoteUserInfo.extendedData}',
        tag: 'live-streaming-pk',
        subTag: 'pk event',
      );
    }

    switch (remoteUserInfo.state) {
      case ZegoSignalingPluginInvitationUserState.unknown:
        break;
      case ZegoSignalingPluginInvitationUserState.inviting:
        break;
      case ZegoSignalingPluginInvitationUserState.accepted:
        final tempSessionHost = _getSessionHostNameAndLiveIDFromExtendedData(
          remoteUserInfo.extendedData,
        );
        final String fromLiveID = tempSessionHost.fromLiveID;
        final fromHost = ZegoUIKitUser(
          id: remoteUserInfo.userID,
          name: tempSessionHost.name,
        );

        /// It may not be a self-initiated request and may also receive remote reject/agree, so it needs to be distinguished.
        ///
        /// a->b, b->c;
        /// in c event, a is initiator, b is inviter
        var isRequestFromLocal =
            ZegoUIKit().getLocalUser().id == sessionInitiator?.userID;
        if (isRequestFromLocal) {
          _onInvitationAccepted(
              ZegoLiveStreamingOutgoingPKBattleRequestAcceptedEvent(
            requestID: requestID,
            fromHost: fromHost,
            fromLiveID: fromLiveID,
          ));
        } else {
          /// invitees(other room's host) accept, update connected users
          final pkUsersFromMap = getPKUsersFromInvitationMap(requestID);
          final users = pkUsersFromMap.isNotEmpty
              ? List<ZegoLiveStreamingPKUser>.from(pkUsersFromMap)
              : List<ZegoLiveStreamingPKUser>.from(
                  _coreData.currentPKUsers.value,
                );
          // Always ensure the accepting user is present — the invitation map
          // on this device may not yet reflect the acceptance when the event
          // fires (ZIM updates are async), so getPKUsersFromInvitationMap can
          // return a stale list missing the user who just accepted.
          if (!users.any((u) => u.userInfo.id == remoteUserInfo.userID)) {
            users.add(
              ZegoLiveStreamingPKUser(
                userInfo: fromHost,
                liveID: fromLiveID,
              ),
            );
          }
          updatePKUsers(users);
        }
        break;
      case ZegoSignalingPluginInvitationUserState.rejected:
        bool isRequestFromLocal = false;
        try {
          final pkRejectData = PKServiceRejectData.fromJson(
            jsonDecode(remoteUserInfo.extendedData) as Map<String, dynamic>? ??
                {},
          );
          isRequestFromLocal =
              ZegoUIKit().getLocalUser().id == pkRejectData.inviterID;
        } catch (e) {
          debugPrint(
              'reject extended data, not a json:${remoteUserInfo.extendedData}');
        }

        if (isRequestFromLocal) {
          final int refuseCode = extendedDataMap['code'] ??
              ZegoLiveStreamingPKBattleRejectCode.reject.index;
          final String fromHostUserName = extendedDataMap['invitee_name'] ?? '';
          _onInvitationRefused(
              ZegoLiveStreamingOutgoingPKBattleRequestRejectedEvent(
            requestID: requestID,
            fromHost: ZegoUIKitUser(
                id: remoteUserInfo.userID, name: fromHostUserName),
            refuseCode: refuseCode,
          ));
        }
        break;
      case ZegoSignalingPluginInvitationUserState.cancelled:
        // do nothing
        break;
      case ZegoSignalingPluginInvitationUserState.received:
        // do nothing
        break;
      case ZegoSignalingPluginInvitationUserState.timeout:
        _onInvitationResponseTimeout(
          ZegoLiveStreamingOutgoingPKBattleRequestTimeoutEvent(
            requestID: requestID,
            fromHost: ZegoUIKitUser(id: remoteUserInfo.userID, name: ''),
          ),
        );
        break;
      case ZegoSignalingPluginInvitationUserState.offline:
        _onInvitationUserOffline(
          ZegoLiveStreamingPKBattleUserOfflineEvent(
            requestID: requestID,
            fromHost: ZegoUIKitUser(id: remoteUserInfo.userID, name: ''),
          ),
        );
        break;
      case ZegoSignalingPluginInvitationUserState.quited:
        final String fromHostUserName = extendedDataMap['invitee_name'] ?? '';
        _onInvitationUserQuit(
          ZegoLiveStreamingPKBattleUserQuitEvent(
            requestID: requestID,
            fromHost: ZegoUIKitUser(
              id: remoteUserInfo.userID,
              name: fromHostUserName,
            ),
          ),
        );
        break;
      case ZegoSignalingPluginInvitationUserState.ended:
        // TODO: Handle this case.
        break;
      case ZegoSignalingPluginInvitationUserState.notYetReceived:
        // TODO: Handle this case.
        break;
      case ZegoSignalingPluginInvitationUserState.beCanceled:
        // TODO: Handle this case.
        break;
    }
  }

  void _initHeartBeatTimer() {
    _heartBeatTimer?.cancel();
    _heartBeatTimer = null;

    _heartBeatTimer = Timer.periodic(
      const Duration(milliseconds: 2500),
      (timer) {
        final now = DateTime.now();
        final tempBrokenIDs = <String>[];
        final alreadyBrokenIDs = <String>[];
        for (var pkUser in _coreData.currentPKUsers.value) {
          if (ZegoUIKit().getLocalUser().id == pkUser.userInfo.id ||
              null == pkUser.heartbeat) {
            continue;
          }

          final offlineSeconds = now.difference(pkUser.heartbeat!).inSeconds;
          if (offlineSeconds >
              (_coreData.prebuiltConfig?.pkBattle.userDisconnectedSecond ??
                  60)) {
            alreadyBrokenIDs.add(pkUser.userInfo.id);

            _coreData.events?.pk.onUserDisconnected?.call(
              pkUser.toUIKitUser,
            );
          } else if (offlineSeconds >
                  (_coreData.prebuiltConfig?.pkBattle.userReconnectingSecond ??
                      5) &&
              !(pkUser.heartbeatBrokenNotifier.value)) {
            ZegoLoggerService.logInfo(
              'heartbeat timer, ${pkUser.userInfo.id} heartbeat had broken,'
              'heartbeat: ${pkUser.heartbeat}, '
              'now:$now, mute audio',
              tag: 'live-streaming-pk',
              subTag: 'pk event',
            );

            ZegoUIKit().muteUserAudio(pkUser.userInfo.id, true);

            tempBrokenIDs.add(pkUser.userInfo.id);
            pkUser.heartbeatBrokenNotifier.value = true;

            _coreData.events?.pk.onUserReconnecting?.call(
              pkUser.toUIKitUser,
            );
          }
        }
        if (tempBrokenIDs.isNotEmpty) {
          ZegoLoggerService.logInfo(
            'heartbeat timer, temp broken user:$tempBrokenIDs, ',
            tag: 'live-streaming-pk',
            subTag: 'pk event',
          );
        }

        if (alreadyBrokenIDs.isNotEmpty) {
          final localHostID = _coreData.hostManager?.notifier.value?.id;
          final isLocalHostBroken =
              localHostID != null && alreadyBrokenIDs.contains(localHostID);

          ZegoLoggerService.logInfo(
            'heartbeat timer, $alreadyBrokenIDs heartbeat had broken so long, remove from pk,'
            ' isLocalHostBroken:$isLocalHostBroken,',
            tag: 'live-streaming-pk',
            subTag: 'pk event',
          );

          for (final id in alreadyBrokenIDs) {
            _coreData.quitRequestUserIDs.add(id);
          }

          List<ZegoLiveStreamingPKUser> updatedPKUsers;
          if (isLocalHostBroken) {
            updatedPKUsers = <ZegoLiveStreamingPKUser>[];
          } else {
            updatedPKUsers = List<ZegoLiveStreamingPKUser>.from(
              _coreData.currentPKUsers.value,
            )..removeWhere(
                (pkUser) => alreadyBrokenIDs.contains(pkUser.userInfo.id),
              );
          }

          /// If only the local host remains after removing broken-heartbeat
          /// users, send an empty list so that [hostOnPKUsersChanged] routes
          /// to [disconnectedHostOnPKUsersChanged] and sets pkState idle
          /// immediately — the actual teardown (mixer, streams, room props)
          /// is deferred to [queryRoomProperties] on reconnection.
          if (updatedPKUsers.length == 1 &&
              updatedPKUsers.first.userInfo.id == localHostID) {
            updatedPKUsers = <ZegoLiveStreamingPKUser>[];
          }

          updatePKUsers(updatedPKUsers);
        }
      },
    );
  }

  void _listenEvents() {
    if (_coreData.prebuiltConfig?.plugins.isEmpty ?? true) {
      ZegoLoggerService.logInfo(
        'listen, but plugin is empty',
        tag: 'live-streaming-pk',
        subTag: 'pk event',
      );
    }

    ZegoLoggerService.logInfo(
      'listen',
      tag: 'live-streaming-pk',
      subTag: 'pk event',
    );

    _eventSubscriptions
      ..add(ZegoUIKit().getReceiveSEIStream().where((event) {
        return event.typeIdentifier ==
            ZegoUIKitInnerSEIType.mixerDeviceState.name;
      }).listen(_onReceiveSEIEvent))
      ..add(ZegoUIKit()
          .getSignalingPlugin()
          .getRoomPropertiesStream()
          .listen(_onRoomAttributesUpdated))
      ..add(ZegoUIKit()
          .getSignalingPlugin()
          .getInvitationUserStateChangedStream()
          .listen(_onInvitationUserStateChanged))
      ..add(ZegoUIKit()
          .getSignalingPlugin()
          .getAdvanceInvitationReceivedStream()
          .where((params) => ZegoInvitationTypeExtension.isPKType(
              (params['type'] as int?) ?? -1))
          .map((params) {
        ZegoLoggerService.logInfo(
          'params:$params',
          tag: 'live-streaming-pk',
          subTag: 'pk event, on invitation received',
        );

        final String requestID = params['invitation_id']!;
        final int timeoutSecond = params['timeout_second']!;
        final int createTimestampSecond = params['create_timestamp_second']!;

        final sessionHosts = _parseSessionHosts(
          requestID,
          params['session_invitees']! as List<Map<String, dynamic>>? ?? [],
        );

        final ZegoUIKitUser inviter = params['inviter']!;
        String inviterLiveID = '';

        /// a->b, b->c;
        /// in c event, a is initiator, b is inviter
        final initiatorPKRequestData = PKServiceRequestData.fromJson(
            jsonDecode(params['data']!) as Map<String, dynamic>);
        _coreData.invitationDataCache[requestID] = params['data']!;
        _coreData.quitRequestUserIDs.clear();
        if (initiatorPKRequestData.inviter.id == inviter.id) {
          inviterLiveID = initiatorPKRequestData.liveID;
        } else {
          ///  a->b, b->c, find b(second inviter)
          for (var sessionHost in sessionHosts) {
            if (sessionHost.id != inviter.id) {
              continue;
            }

            if (sessionHost.customData.isEmpty) {
              continue;
            }

            final tempSessionHost =
                _getSessionHostNameAndLiveIDFromExtendedData(
              sessionHost.customData,
            );
            inviterLiveID = tempSessionHost.fromLiveID;
            inviter.name = tempSessionHost.name;
          }
        }

        return ZegoLiveStreamingIncomingPKBattleRequestReceivedEvent(
          fromLiveID: inviterLiveID,
          fromHost: inviter,
          startTimestampSecond: createTimestampSecond,
          timeoutSecond: timeoutSecond,
          isAutoAccept: initiatorPKRequestData.isAutoAccept,
          customData: initiatorPKRequestData.customData,
          requestID: requestID,
          sessionHosts: sessionHosts,
        );
      }).listen(_onInvitationReceived))
      ..add(ZegoUIKit()
          .getSignalingPlugin()
          .getAdvanceInvitationCanceledStream()
          .where((params) => ZegoInvitationTypeExtension.isPKType(
              (params['type'] as int?) ?? -1))
          .map((params) {
        ZegoLoggerService.logInfo(
          'onInvitationCanceled, params:$params, ',
          tag: 'live-streaming-pk',
          subTag: 'pk event',
        );

        final ZegoUIKitUser fromHost = params['inviter']!;
        final String requestID = params['invitation_id']!;
        return ZegoLiveStreamingIncomingPKBattleRequestCancelledEvent(
          requestID: requestID,
          fromHost: fromHost,
          customData: 'customData',
        );
      }).listen(_onInvitationCanceled))
      ..add(ZegoUIKit()
          .getSignalingPlugin()
          .getAdvanceInvitationTimeoutStream()
          .where(
            (params) => ZegoInvitationTypeExtension.isPKType(
                (params['type'] as int?) ?? -1),
          )
          .map((params) {
        ZegoLoggerService.logInfo(
          'onInvitationTimeout, params:$params',
          tag: 'live-streaming-pk',
          subTag: 'pk event',
        );

        final ZegoUIKitUser fromHost = params['inviter']!;
        final String requestID = params['invitation_id']!;
        return ZegoLiveStreamingIncomingPKBattleRequestTimeoutEvent(
          requestID: requestID,
          fromHost: fromHost,
        );
      }).listen(_onInvitationTimeout))
      ..add(ZegoUIKit()
          .getSignalingPlugin()
          .getAdvanceInvitationEndedStream()
          .where(
            (params) => ZegoInvitationTypeExtension.isPKType(
                (params['type'] as int?) ?? -1),
          )
          .map((params) {
        ZegoLoggerService.logInfo(
          'on invitation ended, params:$params, ',
          tag: 'live-streaming-pk',
          subTag: 'pk event',
        );

        final String requestID = params['invitation_id']!;
        final ZegoUIKitUser fromHost = params['inviter']!;
        final int endTime = params['end_time']!;

        final extendedDataMap =
            jsonDecode(params['data']!) as Map<String, dynamic>;
        final int endCode = extendedDataMap['code'] ??
            ZegoLiveStreamingPKBattleRejectCode.reject.index;

        /// a->b, b->c;
        /// in c event, a is initiator, b is inviter
        var isRequestFromLocal = ZegoUIKit().getLocalUser().id ==
            ZegoUIKit()
                .getSignalingPlugin()
                .getAdvanceInitiator(requestID)
                ?.userID;

        return ZegoLiveStreamingPKBattleEndedEvent(
          isRequestFromLocal: isRequestFromLocal,
          requestID: requestID,
          fromHost: fromHost,
          time: endTime,
          code: endCode,
        );
      }).listen(_onInvitationEnded));
  }

  void _onReceiveSEIEvent(ZegoUIKitReceiveSEIEvent event) {
    final pkUserIndex = _coreData.currentPKUsers.value.indexWhere(
      (pkUser) => pkUser.userInfo.id == event.senderID,
    );
    if (-1 == pkUserIndex) {
      return;
    }

    var pkUser = _coreData.currentPKUsers.value.elementAt(pkUserIndex);
    pkUser.heartbeat = DateTime.now();

    if (pkUser.heartbeatBrokenNotifier.value) {
      /// user reconnected
      ZegoLoggerService.logInfo(
        'received ${pkUser.userInfo.id} sei, un-mute audio',
        tag: 'live-streaming-pk',
        subTag: 'pk event',
      );

      ZegoUIKit().muteUserAudio(pkUser.userInfo.id, false);

      _coreData.events?.pk.onUserReconnected?.call(
        pkUser.toUIKitUser,
      );
    }
    pkUser.heartbeatBrokenNotifier.value = false;

    // debugPrint('_onReceiveSEIEvent $event');
  }

  Future<void> _onRoomAttributesUpdated(
    ZegoSignalingPluginRoomPropertiesUpdatedEvent event,
  ) async {
    ZegoLoggerService.logInfo(
      'onRoomAttributesUpdated, event:$event',
      tag: 'live-streaming-pk',
      subTag: 'pk event',
    );
    _coreData.updatePropertyHostID(event);

    /// Room-attribute driven PK updates are serialized so that a delete
    /// (PK end) and a later re-set (PK restart) can never interleave.
    return waitRoomAttributesCompleter('onRoomAttributesUpdated')
        .then((_) async {
      try {
        await handleRoomAttributesUpdated(event);
      } finally {
        completeRoomAttributesCompleter('onRoomAttributesUpdated');
      }
    }).catchError((Object error) {
      ZegoLoggerService.logError(
        'onRoomAttributesUpdated error:$error',
        tag: 'live-streaming-pk',
        subTag: 'pk event',
      );
    });
  }

  Future<void> handleRoomAttributesUpdated(
    ZegoSignalingPluginRoomPropertiesUpdatedEvent event,
  ) async {
    final pkPropsInDelete =
        event.deleteProperties.containsKey(roomPropKeyPKUsers) ||
            event.deleteProperties.containsKey(roomPropKeyRequestID);
    if (pkPropsInDelete) {
      /// PK is over: the room properties that drive PK were explicitly deleted
      /// (the host/backend ended the PK by removing them). Every participant
      /// (viewer and host) must leave the PK view.
      ///
      /// Only an explicit delete (or an explicitly empty pk_users list below)
      /// may end the PK. A partial update that merely lacks the PK keys (e.g.
      /// the backend updating "host"/"r_id" or reordering on its own) must NOT
      /// tear the ongoing PK down, otherwise the host layout would flip back to
      /// the normal audio/video view and the other PK hosts would wrongly
      /// appear as co-hosts.
      if (pkStateNotifier.value != ZegoLiveStreamingPKBattleState.idle) {
        await teardownPKFromRoomProperties();
      }
      return;
    }

    if (event.setProperties.containsKey(roomPropKeyPKUsers)) {
      if (isHost) {
        /// wait start
        if (!_coreData.startedByLocalNotifier.value) {
          final completer = Completer<void>();
          void onLiveStartedByLocal() {
            if (_coreData.startedByLocalNotifier.value) {
              completer.complete();
            }
            _coreData.startedByLocalNotifier
                .removeListener(onLiveStartedByLocal);
          }

          _coreData.startedByLocalNotifier.addListener(onLiveStartedByLocal);
          ZegoLoggerService.logInfo(
            'onRoomAttributesUpdated, waiting for startedByLocalNotifier',
            tag: 'live-streaming-pk',
            subTag: 'pk event',
          );
          await completer.future;
          ZegoLoggerService.logInfo(
            'onRoomAttributesUpdated, startedByLocalNotifier change to '
            'true, check liveStatusNotifier',
            tag: 'live-streaming-pk',
            subTag: 'pk event',
          );
        }
      }

      /// ---------------------------------------------------------------------------
      /// FIX: liveStatusNotifier wait — both host and audience.
      ///
      /// Previously this wait was inside `if (isHost)`.  Audiences joining
      /// an in-progress PK would receive pk_users via room attributes BEFORE
      /// live_status arrived via roomExtraInfo.  `onPKUsersChanged` bailed
      /// on `!isLiving` and nobody re-triggered when isLiving became true.
      ///
      /// The original deadlock (audience awaits forever) is already prevented
      /// by the `value != living` check: if the notifier is already living
      /// when we enter, the wait is skipped entirely.
      /// ---------------------------------------------------------------------------
      if (_coreData.liveStatusNotifier.value != LiveStatus.living) {
        final completer = Completer<void>();
        void onLiveStatusChanged() {
          if (_coreData.liveStatusNotifier.value == LiveStatus.living) {
            completer.complete();
          }
          _coreData.liveStatusNotifier.removeListener(onLiveStatusChanged);
        }

        _coreData.liveStatusNotifier.addListener(onLiveStatusChanged);
        ZegoLoggerService.logInfo(
          'onRoomAttributesUpdated, waiting for liveStatusNotifier',
          tag: 'live-streaming-pk',
          subTag: 'pk event',
        );

        await completer.future;
        ZegoLoggerService.logInfo(
          'onRoomAttributesUpdated, liveStatusNotifier change to living, startPK',
          tag: 'live-streaming-pk',
          subTag: 'pk event',
        );
      }

      if (_coreData.currentRequestID.isNotEmpty) {
        final invitationPKUsers =
            getPKUsersFromInvitationMap(_coreData.currentRequestID);
        if (invitationPKUsers.length >= 2) {
          // The room-attribute snapshot published by the evicting host is the
          // authoritative removal signal: it reflects a quit/offline that ZIM
          // may not yet have propagated to this device. Intersect the invitation
          // map result with the snapshot IDs so a user absent from the snapshot
          // is also excluded here, preventing the remove→re-add oscillation.
          final snapshotIDs =
              (jsonDecode(event.setProperties[roomPropKeyPKUsers] ?? '[]')
                      as List<dynamic>)
                  .map((e) {
                    final m = e as Map<String, dynamic>;
                    final userInfo = m['user_info'] as Map<String, dynamic>?;
                    return userInfo?['id']?.toString() ?? '';
                  })
                  .where((id) => id.isNotEmpty)
                  .toSet();
          final reconciled = snapshotIDs.isEmpty
              ? invitationPKUsers
              : invitationPKUsers
                  .where((u) => snapshotIDs.contains(u.userInfo.id))
                  .toList();
          final toUpdate =
              reconciled.length >= 2 ? reconciled : invitationPKUsers;
          ZegoLoggerService.logInfo(
            'onRoomAttributesUpdated: using invitation map hosts ($toUpdate) '
            'intersected with snapshot IDs ($snapshotIDs)',
            tag: 'live-streaming-pk',
            subTag: 'pk event',
          );
          updatePKUsers(toUpdate, fromRoomProps: true);
          return;
        }
      }

      final updatedPKUsers =
          (jsonDecode(event.setProperties[roomPropKeyPKUsers] ?? '')
                  as List<dynamic>)
              .map(
                (userJson) => ZegoLiveStreamingPKUser.fromJson(userJson),
              )
              .where((user) => user.liveID.isNotEmpty)
              .toList();

      if (updatedPKUsers.length < 2) {
        /// PK is over: a PK requires at least 2 hosts. pk_users was either
        /// overwritten with an empty list instead of being deleted, or
        /// transiently holds a single host (only the local host remains).
        if (pkStateNotifier.value != ZegoLiveStreamingPKBattleState.idle) {
          await teardownPKFromRoomProperties();
        }
        return;
      }

      final processedPKUsers =
          isHost ? reconcileHostPKUsers(updatedPKUsers) : updatedPKUsers;
      if (isHost &&
          _isUninvitedReAdd(
            localState: pkStateNotifier.value,
            currentRequestID: _coreData.currentRequestID,
            updatedPKUsers: processedPKUsers,
          )) {
        ZegoLoggerService.logInfo(
          'onRoomAttributesUpdated, dropping uninvited re-add for local user',
          tag: 'live-streaming-pk',
          subTag: 'pk event',
        );
        return;
      }
      updatePKUsers(processedPKUsers, fromRoomProps: true);
    }
  }

  Future<void> teardownPKFromRoomProperties() async {
    await ZegoUIKit().muteUserAudioVideo(
      _coreData.hostManager?.notifier.value?.id ?? '',
      false,
    );
    await _mixer.stopPlayStream();

    if (isHost) {
      /// The async [disconnectedHostOnPKUsersChanged] chain will not run once
      /// the pk state is reset to idle below, so tear the host side down
      /// directly: stop playing other room streams and the mixer task.
      for (final hostID in List.from(_coreData.playingHostIDs)) {
        if (ZegoUIKit().getLocalUser().id == hostID) {
          continue;
        }
        await ZegoUIKit().stopPlayAnotherRoomAudioVideo(hostID);
      }
      _coreData.playingHostIDs.clear();
      await _mixer.stopTask();

      _coreData.lastQuitRequestID = _coreData.currentRequestID;
      _coreData.currentRequestID = '';
    }

    updatePKUsers([]);
    updatePKState(ZegoLiveStreamingPKBattleState.idle);

    _coreData.events?.onStateUpdated?.call(
      isLiving ? ZegoLiveStreamingState.living : ZegoLiveStreamingState.idle,
    );
  }

  /// Keep the local LIVE creator in an ongoing PK even when a backend snapshot
  /// transiently omits it, and guarantee the local host's preview is rendered
  /// first in its own room. Mirrors the backend's cumulative/ordering updates
  /// without treating a partial snapshot as a reason to leave the PK.
  List<ZegoLiveStreamingPKUser> reconcileHostPKUsers(
    List<ZegoLiveStreamingPKUser> updatedPKUsers,
  ) {
    if (pkStateNotifier.value == ZegoLiveStreamingPKBattleState.idle &&
        _coreData.currentRequestID.isEmpty) {
      /// local host is not part of an ongoing PK, honor the backend list as-is
      return updatedPKUsers;
    }

    final localUserID = ZegoUIKit().getLocalUser().id;
    final reconciled = removeDuplicatePKUsers(updatedPKUsers);
    final localIndex =
        reconciled.indexWhere((e) => e.userInfo.id == localUserID);
    if (-1 == localIndex) {
      reconciled.insert(
        0,
        ZegoLiveStreamingPKUser(
          userInfo: ZegoUIKit().getLocalUser(),
          liveID: _coreData.roomID,
        ),
      );
    } else if (0 != localIndex) {
      final localUser = reconciled.removeAt(localIndex);
      reconciled.insert(0, localUser);
    }

    return reconciled;
  }

  List<ZegoLiveStreamingPKUser> getAcceptedHostsInSession(
    String requestID, {
    List<String> ignoreUserIDs = const [],
  }) {
    final sessionHosts =
        ZegoUIKit().getSignalingPlugin().getAdvanceInvitees(requestID);
    sessionHosts.removeWhere(
      (user) {
        if (ignoreUserIDs.contains(user.userID)) {
          return true;
        }

        /// remove not accepted
        return user.state != AdvanceInvitationState.accepted;
      },
    );

    return sessionHosts.map((sessionHost) {
      final tempSessionHost = _getSessionHostNameAndLiveIDFromExtendedData(
        sessionHost.extendedData,
      );
      return ZegoLiveStreamingPKUser(
        userInfo: ZegoUIKitUser(
          id: sessionHost.userID,
          name: tempSessionHost.name,
        ),
        liveID: tempSessionHost.fromLiveID,
      );
    }).toList();
  }

  void _onInvitationReceived(
    ZegoLiveStreamingIncomingPKBattleRequestReceivedEvent event,
  ) async {
    ZegoLoggerService.logInfo(
      'event:$event, state:${pkStateNotifier.value}',
      tag: 'live-streaming-pk',
      subTag: 'pk event, on invitation received',
    );

    if (!isLiving || !isHost) {
      ZegoLoggerService.logInfo(
        '_onInvitationReceived, '
        'isLiving:$isLiving, '
        'isHost:$isHost, '
        'auto reject with code '
        '${ZegoLiveStreamingPKBattleRejectCode.hostStateError.index}',
        tag: 'live-streaming-pk',
        subTag: 'pk event, on invitation received',
      );

      await ZegoUIKit().getSignalingPlugin().refuseAdvanceInvitation(
          invitationID: event.requestID,
          inviterID: event.fromHost.id,
          data: jsonEncode({
            'code': ZegoLiveStreamingPKBattleRejectCode.hostStateError.index,
            'invitation_id': event.requestID,
            'invitee_name': ZegoUIKit().getLocalUser().name,
          }));

      return;
    }

    /// A re-add to the very session the local host is in / just left is NOT a
    /// "busy with another PK" situation: the host was/is part of this session,
    /// so it must be allowed to rejoin instead of being auto-rejected as busy.
    /// Note: [event.requestID] is compared BEFORE [_coreData.currentRequestID]
    /// is overwritten below. [lastQuitRequestID] covers a re-add arriving while
    /// the host is still tearing the just-left session down, at which point
    /// [currentRequestID] has already been cleared.
    final isReAddToCurrentSession = event.requestID.isNotEmpty &&
        (event.requestID == _coreData.currentRequestID ||
            event.requestID == _coreData.lastQuitRequestID);

    if (pkStateNotifier.value != ZegoLiveStreamingPKBattleState.idle &&
        !isReAddToCurrentSession) {
      final ret =
          await ZegoUIKit().getSignalingPlugin().refuseAdvanceInvitation(
                invitationID: event.requestID,
                inviterID: event.fromHost.id,
                data: jsonEncode({
                  'code': ZegoLiveStreamingPKBattleRejectCode.busy.index,
                  'invitation_id': event.requestID,
                  'invitee_name': ZegoUIKit().getLocalUser().name,
                }),
              );

      ((ret.error != null)
              ? ZegoLoggerService.logError
              : ZegoLoggerService.logInfo)
          .call(
        'busy(${pkStateNotifier.value}), '
        'auto reject, ret:$ret',
        tag: 'live-streaming-pk',
        subTag: 'pk event, on invitation received',
      );

      return;
    }

    /// The host is still tearing down the PK it just left. Reset the
    /// transitional state so the invite dialog can show and
    /// [acceptPKBattleRequest] can pass its response-waiting guard.
    if (isReAddToCurrentSession &&
        pkStateNotifier.value != ZegoLiveStreamingPKBattleState.idle) {
      updatePKState(ZegoLiveStreamingPKBattleState.idle);
    }

    /// reject/accept/quit invitation need this [event.requestID]
    _coreData.currentRequestID = event.requestID;
    _coreData.lastQuitRequestID = '';

    event.isAutoAccept
        ? autoAcceptReceivedInvitation(event)
        : waitForeProcessingReceivedInvitation(event);
  }

  Future<void> autoAcceptReceivedInvitation(
    ZegoLiveStreamingIncomingPKBattleRequestReceivedEvent event,
  ) async {
    defaultAction() async {
      await acceptPKBattleRequest(
        requestID: event.requestID,
        targetHost: ZegoLiveStreamingPKUser(
          userInfo: event.fromHost,
          liveID: event.fromLiveID,
        ),
      );
    }

    if (null != _coreData.events?.pk.onIncomingRequestReceived) {
      _coreData.events?.pk.onIncomingRequestReceived
          ?.call(event, defaultAction);
    } else {
      await defaultAction.call();
    }
  }

  Future<void> waitForeProcessingReceivedInvitation(
    ZegoLiveStreamingIncomingPKBattleRequestReceivedEvent event,
  ) async {
    /// check if minimizing
    _coreData.clearRequestReceivedEventInMinimizing();
    if (ZegoLiveStreamingMiniOverlayMachine().isMinimizing) {
      ZegoLoggerService.logInfo(
        'is minimizing now, cache the event:$event',
        tag: 'live-streaming-pk',
        subTag: 'pk event',
      );

      _coreData.cacheRequestReceivedEventInMinimizing(event);

      return;
    }

    defaultAction() async {
      await showRequestReceivedDialog(event).then((isAccepted) async {
        if (isAccepted) {
          await acceptPKBattleRequest(
            requestID: event.requestID,
            targetHost: ZegoLiveStreamingPKUser(
              userInfo: event.fromHost,
              liveID: event.fromLiveID,
            ),
          );
        } else {
          await rejectPKBattleRequest(
            requestID: event.requestID,
            targetHostID: event.fromHost.id,
          );
        }
      });
    }

    if (null != _coreData.events?.pk.onIncomingRequestReceived) {
      _coreData.events?.pk.onIncomingRequestReceived
          ?.call(event, defaultAction);
    } else {
      await defaultAction.call();
    }
  }

  void restorePKBattleRequestReceivedEventFromMinimizing() {
    if (null ==
        _coreData.pkBattleRequestReceivedEventInMinimizingNotifier.value) {
      ZegoLoggerService.logInfo(
        'restore pk battle request from minimizing, event is null',
        tag: 'live-streaming-pk',
        subTag: 'pk event',
      );
      return;
    }

    ZegoLoggerService.logInfo(
      'restore pk battle request from minimizing',
      tag: 'live-streaming-pk',
      subTag: 'pk event',
    );
    _onInvitationReceived(
      _coreData.pkBattleRequestReceivedEventInMinimizingNotifier.value!,
    );
  }

  void _onInvitationAccepted(
    ZegoLiveStreamingOutgoingPKBattleRequestAcceptedEvent event,
  ) async {
    ZegoLoggerService.logInfo(
      'on invitation accepted, event:$event, ',
      tag: 'live-streaming-pk',
      subTag: 'pk event',
    );

    /// Only the very first acceptance may start the PK from idle. Any other
    /// state (including the transient [loading] set by the first accept)
    /// means a PK session is already being assembled, so a second/third
    /// acceptance must append to the existing host list instead of resetting
    /// it. Using `isInPK` here would let a concurrent second accept land while
    /// still `loading` and overwrite the first host, dropping them from the
    /// layout.
    final pkUsersFromMap = getPKUsersFromInvitationMap(event.requestID);

    if (pkStateNotifier.value == ZegoLiveStreamingPKBattleState.idle) {
      /// first invitee(other room's host) accept, start pk, update layout

      updatePKState(ZegoLiveStreamingPKBattleState.loading);

      final users = pkUsersFromMap.isNotEmpty
          ? List<ZegoLiveStreamingPKUser>.from(pkUsersFromMap)
          : [
              ZegoLiveStreamingPKUser(
                userInfo: ZegoUIKit().getLocalUser(),
                liveID: _coreData.roomID,
              ),
              ZegoLiveStreamingPKUser(
                userInfo: event.fromHost,
                liveID: event.fromLiveID,
              ),
            ];
      if (!users.any((u) => u.userInfo.id == event.fromHost.id)) {
        users.add(
          ZegoLiveStreamingPKUser(
            userInfo: event.fromHost,
            liveID: event.fromLiveID,
          ),
        );
      }
      updatePKUsers(users);
    } else {
      /// invitees(other room's host) accept, update connected users
      final users = pkUsersFromMap.isNotEmpty
          ? List<ZegoLiveStreamingPKUser>.from(pkUsersFromMap)
          : List<ZegoLiveStreamingPKUser>.from(
              _coreData.currentPKUsers.value,
            );
      if (!users.any((u) => u.userInfo.id == event.fromHost.id)) {
        users.add(
          ZegoLiveStreamingPKUser(
            userInfo: event.fromHost,
            liveID: event.fromLiveID,
          ),
        );
      }
      updatePKUsers(users);
    }

    _coreData.events?.pk.onOutgoingRequestAccepted?.call(event, () {});
  }

  void _onInvitationCanceled(
    ZegoLiveStreamingIncomingPKBattleRequestCancelledEvent event,
  ) {
    ZegoLoggerService.logInfo(
      'onInvitationCanceled, event:$event',
      tag: 'live-streaming-pk',
      subTag: 'pk event',
    );

    updatePKState(ZegoLiveStreamingPKBattleState.idle);

    _coreData.lastQuitRequestID = event.requestID;
    _coreData.currentRequestID = '';

    popupRequestReceivedDialog();

    _coreData.clearRequestReceivedEventInMinimizing();

    _coreData.events?.pk.onIncomingRequestCancelled?.call(event, () {});
  }

  void _onInvitationRefused(
      ZegoLiveStreamingOutgoingPKBattleRequestRejectedEvent event) {
    var message = '';
    if (event.refuseCode == ZegoLiveStreamingPKBattleRejectCode.busy.index) {
      message = 'The host is busy.';
    } else if (event.refuseCode ==
        ZegoLiveStreamingPKBattleRejectCode.hostStateError.index) {
      message =
          "Failed to initiated the PK battle cause the host hasn't started a livestream.";
    } else if (event.refuseCode ==
        ZegoLiveStreamingPKBattleRejectCode.reject.index) {
      message = 'The host rejected your request.';
    }
    ZegoLoggerService.logInfo(
      'onInvitationRefused, '
      'event:$event, '
      'message:$message, '
      'remaining number of participants in the PK session:${ZegoUIKit().getSignalingPlugin().getAdvanceInvitees(event.requestID)}, ',
      tag: 'live-streaming-pk',
      subTag: 'pk event',
    );

    _checkNullToIdle(event.requestID);

    defaultAction() {
      showOutgoingPKBattleRequestRejectedDialog(event);
    }

    if (null != _coreData.events?.pk.onOutgoingRequestRejected) {
      _coreData.events?.pk.onOutgoingRequestRejected?.call(
        event,
        defaultAction,
      );
    } else {
      defaultAction.call();
    }
  }

  Future<void> _checkNullToIdle(String requestID) async {
    final invitees =
        ZegoUIKit().getSignalingPlugin().getAdvanceInvitees(requestID);
    if (invitees.isEmpty) {
      return;
    }

    final connectingInvitees = invitees
        .where((invitee) =>
            AdvanceInvitationState.waiting == invitee.state ||
            AdvanceInvitationState.accepted == invitee.state)
        .toList();

    if (connectingInvitees.isEmpty) {
      await quitPKBattle(requestID: requestID);

      _coreData.currentRequestID = '';
      updatePKState(ZegoLiveStreamingPKBattleState.idle);
    }
  }

  void _onInvitationTimeout(
      ZegoLiveStreamingIncomingPKBattleRequestTimeoutEvent event) {
    ZegoLoggerService.logInfo(
      'onInvitationTimeout, '
      'event:$event, '
      'remaining number of participants in the PK session:${ZegoUIKit().getSignalingPlugin().getAdvanceInvitees(event.requestID)}, ',
      tag: 'live-streaming-pk',
      subTag: 'pk event',
    );

    _checkNullToIdle(event.requestID);

    _coreData.clearRequestReceivedEventInMinimizing();

    defaultAction() {
      popupRequestReceivedDialog();
    }

    if (null != _coreData.events?.pk.onIncomingRequestTimeout) {
      _coreData.events?.pk.onIncomingRequestTimeout?.call(
        event,
        defaultAction,
      );
    } else {
      defaultAction.call();
    }
  }

  void _onInvitationResponseTimeout(
    ZegoLiveStreamingOutgoingPKBattleRequestTimeoutEvent event,
  ) {
    ZegoLoggerService.logInfo(
      'onInvitationResponseTimeout, '
      'event:$event, '
      'remaining number of participants in the PK session:${ZegoUIKit().getSignalingPlugin().getAdvanceInvitees(event.requestID)}, ',
      tag: 'live-streaming-pk',
      subTag: 'pk event',
    );

    _checkNullToIdle(event.requestID);

    _coreData.events?.pk.onOutgoingRequestTimeout?.call(event, () {});
  }

  void _onInvitationEnded(ZegoLiveStreamingPKBattleEndedEvent event) {
    ZegoLoggerService.logInfo(
      'on invitation ended, event:$event, ',
      tag: 'live-streaming-pk',
      subTag: 'pk event',
    );

    updatePKUsers([]);

    _coreData.lastQuitRequestID = event.requestID;
    _coreData.currentRequestID = '';
    _coreData.invitationDataCache.remove(event.requestID);
    _coreData.quitRequestUserIDs.clear();

    defaultAction() {
      showPKBattleEndedDialog(event);
    }

    if (null != _coreData.events?.pk.onEnded) {
      _coreData.events?.pk.onEnded?.call(
        event,
        defaultAction,
      );
    } else {
      defaultAction.call();
    }
  }

  void _onInvitationUserOffline(
      ZegoLiveStreamingPKBattleUserOfflineEvent event) {
    ZegoLoggerService.logInfo(
      '_onInvitationUserOffline, '
      'event:$event, '
      'remaining number of participants in the PK session:${ZegoUIKit().getSignalingPlugin().getAdvanceInvitees(event.requestID)}, ',
      tag: 'live-streaming-pk',
      subTag: 'pk event',
    );

    if (_coreData.currentRequestID.isNotEmpty &&
        event.requestID != _coreData.currentRequestID &&
        event.requestID != _coreData.lastQuitRequestID) {
      ZegoLoggerService.logInfo(
        '_onInvitationUserOffline: ignoring stale requestID:${event.requestID}',
        tag: 'live-streaming-pk',
        subTag: 'pk event',
      );
      return;
    }

    _coreData.quitRequestUserIDs.add(event.fromHost.id);

    final pkUsersFromMap = getPKUsersFromInvitationMap(event.requestID);
    final users = pkUsersFromMap.isNotEmpty
        ? pkUsersFromMap
        : List<ZegoLiveStreamingPKUser>.from(
            _coreData.currentPKUsers.value,
          );
    updatePKUsers(
      users..removeWhere((u) => u.userInfo.id == event.fromHost.id),
    );

    _checkNullToIdle(event.requestID);

    _coreData.events?.pk.onUserOffline?.call(event, () {});
  }

  void _onInvitationUserQuit(
      ZegoLiveStreamingPKBattleUserQuitEvent event) async {
    ZegoLoggerService.logInfo(
      '_onInvitationUserQuit, '
      'event:$event, '
      'remaining number of participants in the PK session:${ZegoUIKit().getSignalingPlugin().getAdvanceInvitees(event.requestID)}, ',
      tag: 'live-streaming-pk',
      subTag: 'pk event',
    );

    if (_coreData.currentRequestID.isNotEmpty &&
        event.requestID != _coreData.currentRequestID &&
        event.requestID != _coreData.lastQuitRequestID) {
      ZegoLoggerService.logInfo(
        '_onInvitationUserQuit: ignoring stale requestID:${event.requestID}',
        tag: 'live-streaming-pk',
        subTag: 'pk event',
      );
      return;
    }

    _coreData.quitRequestUserIDs.add(event.fromHost.id);

    final pkUsersFromMap = getPKUsersFromInvitationMap(event.requestID);
    final users = pkUsersFromMap.isNotEmpty
        ? pkUsersFromMap
        : List<ZegoLiveStreamingPKUser>.from(
            _coreData.currentPKUsers.value,
          );
    updatePKUsers(
      users..removeWhere((u) => u.userInfo.id == event.fromHost.id),
    );

    await _checkNullToIdle(event.requestID);

    _coreData.events?.pk.onUserQuited?.call(event, () {});
  }

  List<ZegoLiveStreamingIncomingPKBattleRequestUser> _parseSessionHosts(
    String requestID,
    List<Map<String, dynamic>> sessionHostParamList,
  ) {
    var sessionHosts = <ZegoLiveStreamingIncomingPKBattleRequestUser>[];

    /// session hosts
    for (var sessionHostParam in sessionHostParamList) {
      final String sessionHostID = sessionHostParam['invitee_id'] ?? '';
      final state = sessionHostParam['state']
              as ZegoSignalingPluginInvitationUserState? ??
          ZegoSignalingPluginInvitationUserState.unknown;

      final tempSessionHost = _getSessionHostNameAndLiveIDFromExtendedData(
        sessionHostParam['data'] ?? '',
      );
      var sessionHost = ZegoLiveStreamingIncomingPKBattleRequestUser(
        id: sessionHostID,
        name: tempSessionHost.name,
        fromLiveID: tempSessionHost.fromLiveID,
        state: state,
        customData: sessionHostParam['data'],
      );

      sessionHosts.add(sessionHost);
    }

    return sessionHosts;
  }

  ZegoLiveStreamingIncomingPKBattleRequestUser
      _getSessionHostNameAndLiveIDFromExtendedData(String extendedData) {
    if (extendedData.isEmpty) {
      return ZegoLiveStreamingIncomingPKBattleRequestUser();
    }

    /// session host's name and live id

    var user = ZegoLiveStreamingIncomingPKBattleRequestUser();
    try {
      final acceptData = ZegoUIKitAdvanceInvitationAcceptProtocol.fromJson(
          jsonDecode(extendedData));
      final pkAcceptData = PKServiceAcceptData.fromJson(
        jsonDecode(acceptData.customData) as Map<String, dynamic>? ?? {},
      );
      user.fromLiveID = pkAcceptData.liveID;
      user.name = pkAcceptData.name;
    } catch (e) {
      try {
        final pkAcceptData = PKServiceAcceptData.fromJson(
          jsonDecode(extendedData) as Map<String, dynamic>? ?? {},
        );
        user.fromLiveID = pkAcceptData.liveID;
        user.name = pkAcceptData.name;
      } catch (e) {
        debugPrint(
            '_getSessionHostNameAndLiveIDFromExtendedData, not a json:$extendedData');
      }
    }

    return user;
  }
}
