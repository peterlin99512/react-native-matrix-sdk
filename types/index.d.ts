declare interface MXCredentials {
  user_id: string;
  home_server: string;
  access_token: string;
  refresh_token: string | undefined;
  device_id: string;
}

declare interface MXSessionAttributes {
  user_id: string;
  display_name: string;
  avatar: string;
  last_active: number;
  status: string;
}

declare interface MXRoomMember {
  membership: 'join' | 'invite' | 'leave' | 'ban' | 'kick';
  userId: string;
  name: string;
  avatarUrl: string;
}

declare interface MXMessageEvent {
  event_type: string;
  event_id: string;
  room_id: string;
  sender_id: string;
  /**
   *  The age of the event in milliseconds.
   *  As home servers clocks may be not synchronised, this relative value may be more accurate.
   *  It is computed by the user's home server each time it sends the event to a client.
   *  Then, the SDK updates it each time the property is read (this doesn't work reliable yet).
   */
  age: number;
  /**
   *  The timestamp in ms since Epoch generated by the origin homeserver when it receives the event
   *  from the client.
   */
  ts: number;
  content: any;
}

declare interface MXRoomAttributes {
  room_id: string;
  name: string;
  notification_count: number;
  highlight_count: number;
  is_direct: boolean;
  last_message: MXMessageEvent;
  isLeft: boolean;
  members: MXRoomMember[];
}

declare interface PublicRoom {
  id: string;
  aliases: string;
  name: string;
  guestCanJoin: boolean;
  numJoinedMembers: number;
}

declare interface MessagesFromRoom {
  start: string;
  end: string;
  results: [string];
}

declare interface SuccessResponse {
  success: string;
}

/**
 * The key is the upload it, the value is the mxc uri.
 */
declare interface SuccessUploadResponse {
  [key: string]: string
}

declare module 'react-native-matrix-sdk' {
  import {EventSubscriptionVendor} from "react-native";

  export interface MatrixSDKStatic extends EventSubscriptionVendor {
    /**
     * Call this to add additional custom event types that your client
     * needs to support. This is for iOS only, android will emit the custom events
     * with out the need for calling this.
     * @param types
     */
    setAdditionalEventTypes(types: string[]): void;

    configure(host: string): void;

    /**
     * When you already obtained the credentials using {@see login}, instead of logging in on e.g. every app start,
     * you can pass the credentials here. This will save you one login request.
     */
    setCredentials(accessToken: string, deviceId: string, userId: string, homeServer: string, refreshToken?: string): void;

    /**
     * Logging the user in by username and password.
     * @param username
     * @param password
     */
    login(username: string, password: string): Promise<MXCredentials>;
    startSession(): Promise<MXSessionAttributes>;

    /**
     * Creates a new room with userIds
     * @param userIds doesn't need to include the user's own ID
     * @param isDirect shall be used when a room with only two participants is a 1-1 conversation
     * @param isTrustedPrivateChat join_rules is set to invite. history_visibility is set to shared. All invitees are given the same power level as the room creator.
     * @param name an optional name for the room
     */
    createRoom(userIds: Array<string>, isDirect: boolean, isTrustedPrivateChat: boolean, name: string): Promise<MXRoomAttributes>;

    /**
     * Updates the name of a room
     * @param roomId
     * @param newName
     */
    updateRoomName(roomId: string, newName: string);

    joinRoom(roomId: string): Promise<MXRoomAttributes>;

    /**
     * roomId to leave
     * @param roomId
     */
    leaveRoom(roomId: string): Promise<void>;

    /**
     * Remove a certain user from a room
     * @param roomId
     * @param userId
     */
    removeUserFromRoom(roomId: string, userId: string): Promise<void>;

    /**
     * Set a user of a room to admin (kick, ban, invite)
     * @param roomId
     * @param userId
     * @param setAdmin
     */
    changeUserPermission(roomId: string, userId: string, setAdmin: boolean): Promise<void>;

    /**
     * Invited a new user to a room
     * @param roomId
     * @param userId
     */
    inviteUserToRoom(roomId: string, userId: string): Promise<void>;

    getInvitedRooms(): Promise<MXRoomAttributes[]>;
    getPublicRooms(url: string): Promise<PublicRoom[]>;
    getUnreadEventTypes(): Promise<string[]>;
    getLastEventsForAllRooms(): Promise<MXMessageEvent[]>;
    getJoinedRooms(): Promise<MXRoomAttributes[]>;
    getLeftRooms(): Promise<MXRoomAttributes[]>;
    listenToRoom(roomId: string): Promise<void>;
    unlistenToRoom(roomId: string): Promise<void>;
    listenToRoom(roomId: string): Promise<void>;
    listen(): Promise<SuccessResponse>;
    unlisten(): void;

    /**
     * This requests messages in direction backwards (past). You need to have a backwards listener in order
     * to receive the messages.
     * @param roomId
     * @param perPage number of entries to return max
     * @param initHistory Reset the back state so that future history requests start over from live.
     *                    Must be called when opening a room if interested in history.
     */
    backPaginate(roomId: string, perPage: number, initHistory: boolean): Promise<MXMessageEvent[]>;

    /**
     * Requests room history from server.
     * @param roomId
     * @param perPage
     * @param initialLoad set to true on first request (initial request, newest messages), any additional calls with false to get further room history
     */
    loadMessagesInRoom(roomId: string, perPage: number, initialLoad: boolean): Promise<MXMessageEvent[]>;

    /**
     * Returns true when back pagination is (still) possible.
     * @param roomId
     */
    canBackPaginate(roomId: string): Promise<boolean>;

    searchMessagesInRoom(roomId: string, searchTerm: string, nextBatch: string, beforeLimit: string, afterLimit: string);
    getMessages(roomId: string, from: string, direction: string, limit: number): Promise<MessagesFromRoom>;

    /**
     * Sends an m.room.message event to a room
     * @param roomId
     * @param messageType the message type (text, image, video, etc - see specifications)
     * @param data
     */
    sendMessageToRoom(roomId: string, messageType: string, data: any): Promise<SuccessResponse>;

    /**
     * Sends an event to a room
     * @param roomId
     * @param eventType
     * @param data
     */
    sendEventToRoom(roomId: string, eventType: string, data: any): Promise<SuccessResponse>;

    sendReadReceipt(roomId: string, eventId: string): Promise<SuccessResponse>;

    /**
     * Marks the whole room as read.
     * @param roomId
     */
    markRoomAsRead(roomId: string): Promise<void>;

    /**
     * Adds a new pusher (service) to the user at the matrix homeserver. The matrix homeserver will
     * use this pusher service to broadcast (push) notifications to the user's device (using FCM, APNS).
     * @param appDisplayName
     * @param appId
     * @param pushServiceUrl
     * @param token (FCM ID, or APNS device token)
     */
    registerPushNotifications(appDisplayName: string, appId: string, pushServiceUrl: string, token: string): Promise<void>;

    /**
     * Updates the user's display name
     * @param displayName new display name
     */
    setUserDisplayName(displayName: string): Promise<void>;

    /**
     * Returns for a matrix content uri (mxc://...) the downloadable
     * server url of the content. Currently doesn't support encryption.
     * @param matrixContentUrl The matrix content url to resolve
     */
    contentGetDownloadableUrl(matrixContentUrl: String): Promise<string>

    /**
     * Uploads content to the matrix content repository of the connected homeserver.
     * @return {@see #SuccessUploadResponse}
     * @param fileUri the absolute file path to the file to be uploaded
     * @param fileName the file name of the file
     * @param mimeType like "audio/aac", "image/jpeg"
     * @param uploadId an upload id for reference.
     */
    uploadContent(fileUri: string, fileName: string, mimeType: string, uploadId: string): Promise<SuccessUploadResponse>

    /**
     * Sends m.typing event into the specified room that the user is typing.
     * @param roomId
     * @param isTyping whether the user is typing or not
     * @param timeout in ms
     */
    sendTyping(roomId: string, isTyping: boolean, timeout: number): Promise<void>;
  }

  const MatrixSDK: MatrixSDKStatic;

  export default MatrixSDK;
}
