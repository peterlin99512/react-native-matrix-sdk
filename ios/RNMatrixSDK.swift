import Foundation
import MatrixSDK

@objc(RNMatrixSDK)
class RNMatrixSDK: RCTEventEmitter {
    var E_MATRIX_ERROR: String! = "E_MATRIX_ERROR";
    var E_NETWORK_ERROR: String! = "E_NETWORK_ERROR";
    var E_UNEXPECTED_ERROR: String! = "E_UNKNOWN_ERROR";

    var mxSession: MXSession!
    var mxCredentials: MXCredentials!
    var mxHomeServer: URL!

    var roomEventsListeners: [String: Any] = [:]
    var roomPaginationTokens: [String : String] = [:]
    var globalListener: Any?
    var additionalTypes: [String] = []


    @objc
    override func supportedEvents() -> [String]! {
        var supportedTypes = ["matrix.room.backwards",
                              "matrix.room.forwards",
                              "m.fully_read",
                              MXEventType.roomName.identifier,
                              MXEventType.roomTopic.identifier,
                              MXEventType.roomAvatar.identifier,
                              MXEventType.roomMember.identifier,
                              MXEventType.roomCreate.identifier,
                              MXEventType.roomJoinRules.identifier,
                              MXEventType.roomPowerLevels.identifier,
                              MXEventType.roomAliases.identifier,
                              MXEventType.roomCanonicalAlias.identifier,
                              MXEventType.roomEncrypted.identifier,
                              MXEventType.roomEncryption.identifier,
                              MXEventType.roomGuestAccess.identifier,
                              MXEventType.roomHistoryVisibility.identifier,
                              MXEventType.roomKey.identifier,
                              MXEventType.roomForwardedKey.identifier,
                              MXEventType.roomKeyRequest.identifier,
                              MXEventType.roomMessage.identifier,
                              MXEventType.roomMessageFeedback.identifier,
                              MXEventType.roomRedaction.identifier,
                              MXEventType.roomThirdPartyInvite.identifier,
                              MXEventType.roomTag.identifier,
                              MXEventType.presence.identifier,
                              MXEventType.typing.identifier,
                              MXEventType.callInvite.identifier,
                              MXEventType.callCandidates.identifier,
                              MXEventType.callAnswer.identifier,
                              MXEventType.callHangup.identifier,
                              MXEventType.reaction.identifier,
                              MXEventType.receipt.identifier,
                              MXEventType.roomTombStone.identifier,
                              MXEventType.keyVerificationStart.identifier,
                              MXEventType.keyVerificationAccept.identifier,
                              MXEventType.keyVerificationKey.identifier,
                              MXEventType.keyVerificationMac.identifier,
                              MXEventType.keyVerificationCancel.identifier]
        // add any additional types the user provided
        supportedTypes += additionalTypes
        return supportedTypes;
    }

    @objc(setAdditionalEventTypes:)
    func setAdditionalEventTypes(types: [String]) {
        additionalTypes = types
    }


    @objc(configure:)
    func configure(url: String) {
        self.mxHomeServer = URL(string: url)
    }

    @objc(login:password:resolver:rejecter:)
    func login(username: String, password: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        // don't relogin if user is already login
        if self.mxCredentials != nil {
            resolve([
                "home_server": unNil(value: self.mxCredentials?.homeServer),
                "user_id": unNil(value: self.mxCredentials?.userId),
                "access_token": unNil(value: self.mxCredentials?.accessToken),
                "device_id": unNil(value: self.mxCredentials?.deviceId),
            ])
            return
        }

        // New user login
        let dummyCredentials = MXCredentials(homeServer: self.mxHomeServer.absoluteString, userId: nil, accessToken: nil)

        let restClient = MXRestClient.init(credentials: dummyCredentials, unrecognizedCertificateHandler: nil)
        let session = MXSession(matrixRestClient: restClient)

        session?.matrixRestClient.login(username: username, password: password, completion: { (credentials) in
            if credentials.isSuccess {
                self.mxCredentials = credentials.value
                resolve([
                    "home_server": unNil(value: self.mxCredentials?.homeServer),
                    "user_id": unNil(value: self.mxCredentials?.userId),
                    "access_token": unNil(value: self.mxCredentials?.accessToken),
                    "device_id": unNil(value: self.mxCredentials?.deviceId),
                ])
            } else {
                reject(self.E_MATRIX_ERROR, nil, credentials.error)
            }
        })
    }

    @objc(setCredentials:deviceId:userId:homeServer:refreshToken:)
    func setCredentials(accessToken: String, deviceId: String, userId: String, homeServer: String, refreshToken: String) {
        let mxCredentials = MXCredentials()
        mxCredentials.accessToken = accessToken
        mxCredentials.deviceId = deviceId
        mxCredentials.userId = userId
        mxCredentials.homeServer = homeServer
        self.mxCredentials = mxCredentials;
    }

    @objc(startSession:rejecter:)
    func startSession(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        // when session is set and connected return the connected session
        if mxSession != nil && (mxSession.state == MXSessionStateInitialised || mxSession.state == MXSessionStateRunning) {
            // TODO: refactor to getMyUser and reuse
            let user = self.mxSession.myUser
            resolve([
                "user_id": unNil(value: user?.userId),
                "display_name": unNil(value: user?.displayname),
                "avatar": unNil(value: user?.avatarUrl),
                "last_active": unNil(value: user?.lastActiveAgo),
                "status": unNil(value: user?.statusMsg),
            ])
            return
        }


        // Create a matrix client
        let mxRestClient = MXRestClient(credentials: self.mxCredentials, unrecognizedCertificateHandler: nil)

        // Create a matrix session
        mxSession = MXSession(matrixRestClient: mxRestClient)!

        // Make the matrix session open the file store
        // This will preload user's messages and other data
        let store = MXFileStore()

        mxSession.setStore(store) { (response) in
            guard response.isSuccess else {
                reject(self.E_MATRIX_ERROR, nil, response.error)
                return
            }

            // Launch mxSession: it will sync with the homeserver from the last stored data
            // Then it will listen to new coming events and update its data
            let filter: MXFilterJSONModel = MXFilterJSONModel.init(fromJSON: filterLeftRooms)
            self.mxSession.start(withSyncFilter: filter, completion: { (response) in
                guard response.isSuccess else {
                    reject(self.E_MATRIX_ERROR, nil, response.error)
                    return
                }

                // TODO: refactor to getMyUser and reuse
                let user = self.mxSession.myUser

                resolve([
                    "user_id": unNil(value: user?.userId),
                    "display_name": unNil(value: user?.displayname),
                    "avatar": unNil(value: user?.avatarUrl),
                    "last_active": unNil(value: user?.lastActiveAgo),
                    "status": unNil(value: user?.statusMsg),
                ])
            })
        }
    }


    @objc(createRoom:isDirect:isTrustedPrivateChat:name:resolver:rejecter:)
    func createRoom(userIds: NSArray, isDirect: Bool, isTrustedPrivateChat: Bool, name: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(nil, "client is not connected yet", nil)
            return
        }

        var preset: MXRoomPreset? = nil
        if isTrustedPrivateChat {
            preset = MXRoomPreset.trustedPrivateChat
        }

        let arrayUserIds: [String] = userIds.compactMap({ $0 as? String })
        let params: MXRoomCreationParameters = MXRoomCreationParameters()
        params.isDirect = isDirect
        params.visibility = MXRoomDirectoryVisibility.private.identifier
        params.inviteArray = arrayUserIds
        params.preset = preset?.identifier
        params.name = name

        mxSession.createRoom(parameters: params) { response in
            if response.isSuccess {
                response.value?.setJoinRule(MXRoomJoinRule.public, completion: { (responseRoomJoinRule) in
                    response.value?.setHistoryVisibility(MXRoomHistoryVisibility.shared, completion: { (responsePreview) in
                        var roomDict = convertMXRoomToDictionary(room: response.value, members: nil)
                        roomDict["members"] = arrayUserIds.map({ (userId) -> [String: String?] in
                            return [
                                "userId": userId,
                                "avatarUrl": nil,
                                "name": nil,
                                "membership": "join"
                            ];
                        })
                        resolve(roomDict)
                    })
                })
            } else {
                reject(nil, nil, response.error)
            }
        }
    }

    @objc(updateRoomName:newName:resolver:rejecter:)
    func updateRoomName(roomId: String, newName: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(nil, "client is not connected yet", nil)
            return
        }
        let room = mxSession.room(withRoomId: roomId)

        if room == nil {
            reject(E_MATRIX_ERROR, "Room not found", nil)
            return
        }

        room?.setName(newName, completion: { (response) in
            if response.isSuccess {
                resolve(nil)
            } else {
                reject(self.E_MATRIX_ERROR, "There was an issue while performing updateRoomName request", response.error)
            }
        })
    }

    @objc(joinRoom:resolver:rejecter:)
    func joinRoom(roomId: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(nil, "client is not connected yet", nil)
            return
        }

        mxSession.joinRoom(roomId) { (response) in
            if response.isSuccess {
                let room = response.value
                room?.members(completion: { (members) in
                    guard members.isSuccess else {
                        reject(self.E_MATRIX_ERROR, "Couldn't retrieve room member list after joining. The join itself was successful!", members.error);
                        return
                    }
                    resolve(convertMXRoomToDictionary(room: response.value, members: members.value ?? nil))
                    return
                })
            } else {
                reject(self.E_MATRIX_ERROR, nil, response.error)
                return
            }
        }
        return
    }

    @objc(leaveRoom:resolver:rejecter:)
    func leaveRoom(roomId: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(E_MATRIX_ERROR, "client is not connected yet", nil)
            return
        }

        let room = mxSession.room(withRoomId: roomId)

        if room == nil {
            reject(E_MATRIX_ERROR, "Room not found", nil)
            return
        }

        room?.leave(completion: { (response) in
            if response.isFailure {
                reject(self.E_MATRIX_ERROR, "Failed to leave room", response.error)
                return;
            }
            resolve(nil)
        })
    }

    @objc(removeUserFromRoom:userId:resolver:rejecter:)
    func removeUserFromRoom(roomId: String, userId: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(E_MATRIX_ERROR, "client is not connected yet", nil)
            return
        }

        let room = mxSession.room(withRoomId: roomId)

        if room == nil {
            reject(E_MATRIX_ERROR, "Room not found", nil)
            return
        }

        room?.kickUser(userId, reason: "", completion: { (response) in
            if response.isFailure {
                reject(self.E_MATRIX_ERROR, "Failed to remove user from room", response.error)
                return;
            }
            resolve(nil)
        })
    }

    @objc(changeUserPermission:userId:setAdmin:resolver:rejecter:)
    func changeUserPermission(roomId: String, userId: String, setAdmin: Bool, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(E_MATRIX_ERROR, "client is not connected yet", nil)
            return
        }

        let room = mxSession.room(withRoomId: roomId)

        if room == nil {
            reject(E_MATRIX_ERROR, "Room not found", nil)
            return
        }

        let power = setAdmin ? 100 : 0
        room?.setPowerLevel(ofUser: userId, powerLevel: power, completion: { (response) in
            if response.isFailure {
                reject(self.E_MATRIX_ERROR, "Failed to make user admin for room", response.error)
                return;
            }
            resolve(nil)
        })
    }

    @objc(inviteUserToRoom:userId:resolver:rejecter:)
    func inviteUserToRoom(roomId: String, userId: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(E_MATRIX_ERROR, "client is not connected yet", nil)
            return
        }

        let room = mxSession.room(withRoomId: roomId)

        if room == nil {
            reject(E_MATRIX_ERROR, "Room not found", nil)
            return
        }

        let invite: MXRoomInvitee = MXRoomInvitee.userId(userId)
        room?.invite(invite, completion: { (response) in
            if response.isFailure {
                reject(self.E_MATRIX_ERROR, "Failed to invite user to room", response.error)
                return;
            }
            resolve(nil)
        })
    }

    @objc(getInvitedRooms:rejecter:)
    func getInvitedRooms(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(nil, "client is not connected yet", nil)
            return
        }

        let rooms = mxSession.invitedRooms()?.map({
            (r: MXRoom) -> [String: Any?] in
            let room = mxSession.room(withRoomId: r.roomId)

            return convertMXRoomToDictionary(room: room, members: nil)
        })

        resolve(rooms ?? [])
    }

    @objc(getPublicRooms:resolver:rejecter:)
    func getPublicRooms(url: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        let homeServerUrl = URL(string: url)!
        let mxRestClient = MXRestClient(homeServer: homeServerUrl, unrecognizedCertificateHandler: nil)
        // TODO: make limit definable through user
        mxRestClient.publicRooms(onServer: self.mxHomeServer.absoluteString, limit: nil) { (response) in
            switch response {
            case let .success(rooms):
                let data = rooms.chunk.map { [
                    "id": $0.roomId!,
                    "aliases": unNil(value: $0.aliases) ?? [],
                    "name": unNil(value: $0.name) ?? "",
                    "guestCanJoin": $0.guestCanJoin,
                    "numJoinedMembers": $0.numJoinedMembers,
                    ] }

                resolve(data)
                break
            case let .failure(error):
                reject(nil, nil, error)
                break
            }
        }
    }

    @objc(getUnreadEventTypes:rejecter:)
    func getUnreadEventTypes(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(nil, "client is not connected yet", nil)
            return
        }

        resolve(mxSession.unreadEventTypes)
    }

    @objc(getLastEventsForAllRooms:rejecter:)
    func getLastEventsForAllRooms(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(nil, "client is not connected yet", nil)
            return
        }

        let recentEvents = mxSession.roomsSummaries()

        let response = recentEvents.map({
            (roomLastEvent: [MXRoomSummary]) -> [[String: Any]] in
            roomLastEvent.map { (summary) -> [String: Any] in
                return convertMXEventToDictionary(event: summary.lastMessageEvent)
            }
        })

        resolve(response)
    }

    @objc(getJoinedRooms:rejecter:)
    func getJoinedRooms(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(nil, "client is not connected yet", nil)
            return
        }

        let rooms = mxSession.rooms

        if (rooms.count <= 0) {
            resolve([])
            return;
        }

        var roomsAsDict: [[String: Any?]] = [[String: Any?]]()

        for index in 0...rooms.count - 1 {
            let room = rooms[index]
            room.members { (membersRes) in
                if membersRes.isSuccess {
                    roomsAsDict.append(convertMXRoomToDictionary(room: room, members: membersRes.value ?? nil))
                } else {
                    print("Cant retrieve member list for room " + room.roomId + ". Won't add to list of lest rooms!")
                }

                // check if end of list and return if so
                if index == rooms.count-1 {
                    resolve(roomsAsDict)
                }
            }
        }
    }

    @objc(getLeftRooms:rejecter:)
    func getLeftRooms(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(nil, "client is not connected yet", nil)
            return
        }

        let model: MXFilterJSONModel  = MXFilterJSONModel.init(fromJSON: filterLeftRooms)

        mxSession.matrixRestClient.setFilter(model, success: { (response) in
            self.mxSession.matrixRestClient.sync(fromToken: nil, serverTimeout: 10, clientTimeout: 30000, setPresence: nil, filterId: response) { (roomFilterRes) in
                if roomFilterRes.isSuccess {
                    if roomFilterRes.value?.rooms.leave == nil {
                        resolve([])
                        return
                    }
                    if roomFilterRes.value?.rooms.leave.count ?? 0 <= 0 {
                        resolve([])
                        return
                    }

                    var rooms: [MXRoom] = [MXRoom]()

                    roomFilterRes.value?.rooms.leave.keys.forEach({ (roomId) in
                        var room = self.mxSession.room(withRoomId: roomId)

                        if room == nil {
                            room = self.mxSession.getOrCreateRoom(roomId, notify: false)

                            let roomSync = roomFilterRes.value?.rooms.leave[roomId]
                            room?.liveTimeline({ (liveTimeline) in
                                room?.handleJoinedRoomSync(roomSync)
                                room?.summary.handleJoinedRoomSync(roomSync)
                            })
                        }

                        rooms.append(room!)
                    })

                    var roomsAsDict: [[String: Any?]] = [[String: Any?]]()
                    var pendingRequests = [String]()
                    rooms.forEach { (room) in
                        pendingRequests.append(room.roomId)
                    }

                    if rooms.count <= 0 {
                        resolve([])
                        return
                    }

                    for index in 0...rooms.count - 1 {
                        let room = rooms[index]
                        room.members { (membersRes) in
                            if membersRes.isSuccess {
                                roomsAsDict.append(convertMXRoomToDictionary(room: room, members: membersRes.value ?? nil))
                            } else {
                                print("Cant retrieve member list for room " + room.roomId + ". Won't add to list of lest rooms!")
                            }

                            // remove the room id from the pending requests
                            pendingRequests = pendingRequests.filter { $0 != room.roomId }

                            // check if end of list and return if so
                            if pendingRequests.count == 0 {
                                resolve(roomsAsDict)
                            }
                        }
                    }
                } else {
                    reject(self.E_MATRIX_ERROR, "Can't get left rooms", roomFilterRes.error);
                }
            }
        }) { (error) in
            reject(self.E_MATRIX_ERROR, "Can't set filter to get left rooms", error);
        }
    }

    @objc(listenToRoom:resolver:rejecter:)
    func listenToRoom(roomId: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(nil, "client is not connected yet", nil)
            return
        }

        let room = mxSession.room(withRoomId: roomId)

        if room == nil {
            reject(nil, "Room not found", nil)
            return
        }

        if roomEventsListeners[roomId] != nil {
            reject(nil, "Only allow 1 listener to 1 room for now. Room id: " + roomId, nil)
            return
        }

        room?.liveTimeline({ (timeline) in
            let listener = timeline?.listenToEvents {
                event, direction, _ in
                switch direction {
                case .backwards:
                    if self.bridge != nil {
                        self.sendEvent(
                            withName: "matrix.room.backwards",
                            body: convertMXEventToDictionary(event: event)
                        )
                    }
                    break
                case .forwards:
                    if self.bridge != nil {
                        self.sendEvent(
                            withName: "matrix.room.forwards",
                            body: convertMXEventToDictionary(event: event)
                        )
                    }
                    break
                }
            }

            self.roomEventsListeners[roomId] = listener

            resolve(nil)
        })
    }

    @objc(unlistenToRoom:resolver:rejecter:)
    func unlistenToRoom(roomId: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(nil, "client is not connected yet", nil)
            return
        }

        let room = mxSession.room(withRoomId: roomId)

        if room == nil {
            reject(nil, "Room not found", nil)
            return
        }

        if roomEventsListeners[roomId] == nil {
            reject(nil, "No listener for this room. Room id: " + roomId, nil)
            return
        }

        room?.liveTimeline({ (timeline) in
            timeline?.removeListener(self.roomEventsListeners[roomId])
            self.roomEventsListeners[roomId] = nil

            resolve(nil)
        })
    }

    @objc(listen:rejecter:)
    func listen(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(E_MATRIX_ERROR, "client is not connected yet", nil)
            return
        }

        if self.globalListener != nil {
            reject(E_MATRIX_ERROR, "You already started listening, only one global listener is supported. You maybe forget to call `unlisten()`", nil)
            return
        }

        // additionalObject: additional contect for the event. In case of room event, `customObject` is a `RoomState` instance. In the case of a presence, `customObject` is `nil`.
        self.globalListener = mxSession.listenToEvents { (event: MXEvent, timelineDirection: MXTimelineDirection, additionalObject) in
            // Only listen to future events
            if timelineDirection == .forwards && self.bridge != nil {
                self.sendEvent(
                    withName: event.type,
                    body: convertMXEventToDictionary(event: event)
                )
            }
        }


        resolve(["success": true])
    }

    @objc
    func unlisten() {
        if mxSession != nil && globalListener != nil {
            mxSession.removeListener(globalListener)
            globalListener = nil
        }
    }

    @objc(backPaginate:perPage:initHistory:resolver:rejecter:)
    func backPaginate(roomId: String, perPage: NSNumber, initHistory: Bool, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(nil, "client is not connected yet", nil)
            return
        }

        let room = mxSession.room(withRoomId: roomId)

        if room == nil {
            reject(nil, "Room not found", nil)
            return
        }

        room?.liveTimeline({ (timeline) in
            if initHistory {
                timeline?.resetPagination();
            }
            timeline?.paginate(UInt(truncating: perPage), direction: MXTimelineDirection.backwards, onlyFromStore: false, completion: { (response) in
                resolve(nil)
            })
        })
    }

    @objc(canBackPaginate:resolver:rejecter:)
    func canBackPaginate(roomId: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(nil, "client is not connected yet", nil)
            return
        }

        let room = mxSession.room(withRoomId: roomId)

        if room == nil {
            reject(nil, "Room not found", nil)
            return
        }

        room?.liveTimeline({ (timeline) in
            resolve(timeline?.canPaginate(MXTimelineDirection.backwards))
        })
    }

    @objc(loadMessagesInRoom:perPage:initialLoad:resolver:rejecter:)
    func loadMessagesInRoom(roomId: String, perPage: NSNumber, initialLoad: Bool, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        var fromToken = ""
        if(!initialLoad) {
            fromToken = roomPaginationTokens[roomId] ?? ""
            if(fromToken.isEmpty) {
                print("Warning: trying to load not initial messages, but the SDK has no token set for this room currently. You need to run with initialLoad: true first!")
            }
        }

        getMessages(roomId: roomId, from: fromToken, direction: "backwards", limit: perPage, resolve: resolve, reject: reject)
    }

    @objc(getMessages:from:direction:limit:resolver:rejecter:)
    func getMessages(roomId: String, from: String, direction: String, limit: NSNumber, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(nil, "client is not connected yet", nil)
            return
        }

        let roomEventFilter = MXRoomEventFilter()
        let timelimeDirection = direction == "backwards" ? MXTimelineDirection.backwards : MXTimelineDirection.forwards

        mxSession.matrixRestClient.messages(forRoom: roomId, from: from, direction: timelimeDirection, limit: UInt(truncating: limit), filter: roomEventFilter) { response in
            if response.error != nil {
                reject(nil, nil, response.error)
                return
            }

            let results = response.value?.chunk.map {
                $0.map( {
                    convertMXEventToDictionary(event: $0 as MXEvent)
                } )
            }

            // Store pagination token
            self.roomPaginationTokens[roomId] = response.value?.end

            resolve(results)
        }
    }

    @objc(searchMessagesInRoom:searchTerm:nextBatch:beforeLimit:afterLimit:resolver:rejecter:)
    func searchMessagesInRoom(roomId: String, searchTerm: String, nextBatch: String, beforeLimit: NSNumber, afterLimit: NSNumber, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(nil, "client is not connected yet", nil)
            return
        }

        let roomEventFilter = MXRoomEventFilter()
        roomEventFilter.rooms = [roomId]

        mxSession.matrixRestClient.searchMessages(withPattern: searchTerm, roomEventFilter: roomEventFilter, beforeLimit: UInt(beforeLimit), afterLimit: UInt(afterLimit), nextBatch: nextBatch) { results in
            if results.isFailure {
                reject(nil, nil, results.error)
                return
            }

            if results.value == nil || results.value?.results == nil {
                resolve([
                    "count": 0,
                    "next_batch": nil,
                    "results": [],
                ])
                return
            }

            let events = results.value?.results.map({ (result: MXSearchResult) -> [String: Any] in
                let context = result.context
                let eventsBefore = context?.eventsBefore ?? []
                let eventsAfter = context?.eventsAfter ?? []

                return [
                    "event": convertMXEventToDictionary(event: result.result),
                    "context": [
                        "before": eventsBefore.map(convertMXEventToDictionary) as Any,
                        "after": eventsAfter.map(convertMXEventToDictionary) as Any,
                    ],
                    "token": [
                        "start": unNil(value: context?.start),
                        "end": unNil(value: context?.end),
                    ],
                ]
            })

            resolve([
                "next_batch": unNil(value: results.value?.nextBatch),
                "count": unNil(value: results.value?.count),
                "results": events,
            ])
        }
    }

    @objc(sendMessageToRoom:messageType:data:resolver:rejecter:)
    func sendMessageToRoom(roomId: String, messageType: String, data: [String: Any], resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(nil, "client is not connected yet", nil)
            return
        }

        let room = mxSession.room(withRoomId: roomId)

        if room == nil {
            reject(nil, "Room not found", nil)
            return
        }

        mxSession.matrixRestClient.sendMessage(toRoom: roomId, messageType: convertStringToMXMessageType(type: messageType), content: data) { (response) in
            if(response.isFailure) {
                reject(self.E_MATRIX_ERROR, nil, response.error)
                return
            }

            resolve(["success": response.value])
        }
    }

    @objc(sendEventToRoom:eventType:data:resolver:rejecter:)
    func sendEventToRoom(roomId: String, eventType: String, data: [String: Any], resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(nil, "client is not connected yet", nil)
            return
        }

        let room = mxSession.room(withRoomId: roomId)

        if room == nil {
            reject(nil, "Room not found", nil)
            return
        }

        mxSession.matrixRestClient.sendEvent(toRoom: roomId, eventType: MXEventType.custom(eventType), content: data, txnId: UUID().uuidString) { (response) in
            if(response.isFailure) {
                reject(self.E_MATRIX_ERROR, nil, response.error)
                return
            }

            resolve(["success": response.value])
        }
    }

    @objc(markRoomAsRead:resolver:rejecter:)
    func markRoomAsRead(roomId: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(nil, "client is not connected yet", nil)
            return
        }

        let room = mxSession.room(withRoomId: roomId)

        if room == nil {
            reject(nil, "Room not found", nil)
            return
        }

        room?.markAllAsRead()
        resolve(nil)
    }

    @objc(sendReadReceipt:eventId:resolver:rejecter:)
    func sendReadReceipt(roomId: String, eventId: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(nil, "client is not connected yet", nil)
            return
        }

        mxSession.matrixRestClient.sendReadReceipt(toRoom: roomId, forEvent: eventId) { response in
            if response.error != nil {
                reject(nil, nil, response.error)
                return
            }

            resolve(["success": response.value])
        }
    }

    @objc(registerPushNotifications:appId:pushServiceUrl:token:resolver:rejecter:)
    func registerPushNotifications(displayName: String, appId: String, pushServiceUrl: String, token: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil && mxSession.myUser != nil {
            reject(E_MATRIX_ERROR, "client is not connected yet", nil)
            return
        }

        let tag = calculateTag(session: self.mxSession)
        let skr: Data = Utilities.data(fromHexString: token)
        let b64Token = (skr.base64EncodedString())

        mxSession.matrixRestClient.setPusher(pushKey: b64Token, kind: MXPusherKind.http, appId: appId, appDisplayName: displayName, deviceDisplayName: UIDevice.current.name, profileTag: tag, lang: Locale.current.languageCode ?? "en", data: ["url": pushServiceUrl], append: false) { response in
            if response.error != nil {
                reject(nil, nil, response.error)
                return
            }

            resolve(["success": response.value])
        }
    }

    @objc(setUserDisplayName:resolver:rejecter:)
    func setUserDisplayName(displayName: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(E_MATRIX_ERROR, "client is not connected yet", nil)
            return
        }

        if (self.mxSession.myUser != nil) {
            self.mxSession.myUser.setDisplayName(displayName, success: {
                resolve(true)
            }) { (error) in
                reject(self.E_MATRIX_ERROR, "Failed to update display name", error)
            }
        } else {
            reject(E_MATRIX_ERROR, "Matrix session wasn't ready to change user display name yet", nil)
        }
    }

    @objc(uploadContent:fileName:mimeType:uploadId:resolver:rejecter:)
    func uploadContent(fileUri: String, fileName: String, mimeType: String, uploadId: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(E_MATRIX_ERROR, "client is not connected yet", nil)
            return
        }

        let mediaLoader = MXMediaManager.prepareUploader(withMatrixSession: mxSession, initialRange: 0, andRange: 1.0)
        let nsdata = NSData(contentsOfFile: fileUri)
        mediaLoader?.uploadData(Data(referencing: nsdata!), filename: fileName, mimeType: mimeType, success: { (url) in
            resolve([
                uploadId: url
            ])
        }, failure: { (error) in
            reject(nil, "Failed to upload", error)
        })
    }

    @objc(contentGetDownloadableUrl:resolver:rejecter:)
    func contentGetDownloadableUrl(matrixContentUri: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(E_MATRIX_ERROR, "client is not connected yet", nil)
            return
        }

        let url = mxSession.mediaManager.url(ofContent: matrixContentUri)
        if ((url) != nil) {
            resolve(url)
        } else {
            reject(nil, "Failed to get content uri", nil)
        }
    }

    @objc(downloadContent:mimeType:folder:resolver:rejecter:)
    func downloadContent(matrixContentUri: String, mimeType: String, folder: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(E_MATRIX_ERROR, "client is not connected yet", nil)
            return
        }

        let mediaLoader = mxSession.mediaManager.downloadMedia(fromMatrixContentURI: matrixContentUri, withType: mimeType, inFolder: folder, success: { (fileUri) in
            resolve(fileUri)
        }) { (e) in
            reject(nil, "Failed to download", e)
        }

        print("[DOWNLOAD NATIVE IOS] download url: " + (mediaLoader?.downloadMediaURL ?? "NO DOWNLOAD URL"))
    }

    @objc(sendTyping:isTyping:timeout:resolver:rejecter:)
    func sendTyping(roomId: String, isTyping: Bool, timeout: NSNumber, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(E_MATRIX_ERROR, "client is not connected yet", nil)
            return
        }
        let timeoutConv = isTyping ? TimeInterval(timeout.doubleValue) : 1

        mxSession.room(withRoomId: roomId)?.sendTypingNotification(typing: isTyping, timeout: timeoutConv, completion: { (response: MXResponse<Void>) in
            if response.error != nil {
                reject(nil, nil, response.error)
                return
            }

            resolve(["success": response.value])
        })
    }

    @objc(updatePresence:resolver:rejecter:)
    func updatePresence(isOnline: Bool, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if mxSession == nil {
            reject(E_MATRIX_ERROR, "client is not connected yet", nil)
            return
        }

        let presence: MXPresence = isOnline ? MXPresenceOnline : MXPresenceOffline
        mxSession.myUser.setPresence(presence, andStatusMessage: "", success: {
            resolve(["success": "true"])
        }) { (error) in
            reject(self.E_MATRIX_ERROR, "Failed to update presence", error)
        }
    }
}

internal func calculateTag(session: MXSession) -> String {
    var tag = "mobile_" + String(abs(session.myUserId.hashValue))

    if(tag.count > 32) {
        tag = String(abs(tag.hashValue))
    }

    return tag
}

internal func unNil(value: Any?) -> Any? {
    guard let value = value else {
        return nil
    }
    return value
}

internal func convertMXRoomToDictionary(room: MXRoom?, members: MXRoomMembers?) -> [String: Any?] {
    let lastMessage = room?.summary?.lastMessageEvent ?? nil
    let isLeft = room?.summary?.membership == MXMembership.leave
    var membersDict: [[String: String?]]? = [[String: String?]]()
    if members !== nil {
        membersDict = members?.members.map({ (roomMember) -> [String: String?] in
            return convertMXRoomMemberToDictionary(member: roomMember)
        })
    }

    return [
        "room_id": unNil(value: room?.roomId),
        "name": unNil(value: room?.summary?.displayname),
        "notification_count": unNil(value: room?.summary?.notificationCount),
        "highlight_count": unNil(value: room?.summary?.highlightCount),
        "is_direct": room?.isDirect, //unNil(value: room?.summary.isDirect),
        "last_message": convertMXEventToDictionary(event: lastMessage),
        "isLeft": isLeft,
        "members": membersDict,
    ]
}

internal func convertMXEventToDictionary(event: MXEvent?) -> [String: Any] {
    return [
        "event_type": unNil(value: event?.type) as Any,
        "event_id": unNil(value: event?.eventId) as Any,
        "room_id": unNil(value: event?.roomId) as Any,
        "sender_id": unNil(value: event?.sender) as Any,
        "age": unNil(value: event?.age) as Any,
        "content": unNil(value: event?.content) as Any,
        "ts": unNil(value: event?.originServerTs) as Any,
    ]
}

internal func convertMXRoomMemberToDictionary(member: MXRoomMember) -> [String: String?] {
    return [
        "userId": member.userId,
        "avatarUrl": member.avatarUrl,
        "name": member.displayname,
        "membership": membershipToString(membership: member.membership)
    ]
}

internal func membershipToString(membership: MXMembership) -> String {
    switch membership {
    case .leave:
        return "leave"
    case .ban:
        return "ban"
    case .invite:
        return "invite"
    default:
        return "join"
    }
}

internal func convertStringToMXMessageType(type: String) -> MXMessageType {
    switch type {
    case "image":
        return MXMessageType.image
    case "video":
        return MXMessageType.video
    case "file":
        return MXMessageType.file
    case "audio":
        return MXMessageType.audio
    case "emote":
        return MXMessageType.emote
    case "location":
        return MXMessageType.location
    default:
        return MXMessageType.text
    }
}

let filterLeftRooms: [String: Any] = [
    "room": [
        "timeline": [
            "limit": 1
        ],
        "include_leave": true,
        "state": [
            "lazy_load_members": true
        ]
    ]
];
