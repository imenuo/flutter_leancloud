//
// Created by Kainan Zhu on 2018/8/30.
//

import Foundation
import AVOSCloud
import AVOSCloudIM

extension AVIMConversation {
    func toFlutterDictionary() -> [String: Any?] {
        return [
            "conversationId": self.conversationId,
            "members": self.members,
            "lastMessage": self.lastMessage?.toFlutterDictionary(),
            "lastMessageAt": self.lastMessageAt?.millisecondsSince1970,
            "unreadMessagesCount": self.unreadMessagesCount,
        ]
    }
}

extension AVIMMessageStatus {
    var statusCode: Int? {
        get {
            switch self {
            case .none:
                return 0
            case .sending:
                return 1
            case .sent:
                return 2
            case .delivered:
                return 3
            case .failed:
                return 4
            default:
                return nil
            }
        }
    }
}

extension AVIMMessage {
    func toFlutterDictionary() -> [String: Any?] {
        return [
            "content": self.content,
            "conversationId": self.conversationId,
            "from": self.clientId, // TODO add this to document
            "messageId": self.messageId,
            "timestamp": self.sendTimestamp,
            "deliveredAt": self.deliveredTimestamp,
            "updateAt": self.updatedAt?.millisecondsSince1970,
            "status": self.status.statusCode,
        ]
    }
}

extension AVIMCachePolicy {
    static func fromFlutterInt(_ value: Int?) -> AVIMCachePolicy? {
        switch value {
        case 0:
            return AVIMCachePolicy.cacheElseNetwork
        case 1:
            return AVIMCachePolicy.cacheOnly
        case 2:
            return AVIMCachePolicy.cacheThenNetwork
        case 3:
            return AVIMCachePolicy.ignoreCache
        case 4:
            return AVIMCachePolicy.networkElseCache
        case 5:
            return AVIMCachePolicy.networkOnly
        default:
            return nil
        }
    }
}

class ClientDelegate: NSObject, AVIMClientDelegate {
    private let plugin: SwiftFlutterLeanCloudPlugin

    init(with plugin: SwiftFlutterLeanCloudPlugin) {
        self.plugin = plugin
    }

    func imClientPaused(_ imClient: AVIMClient) {
        let data: [String: Any?] = [
            "clientId": imClient.clientId
        ]

        self.plugin.channel.invokeMethod("avIMClient_clientEventHandler_onConnectionPaused", arguments: data)
    }

    func imClientResuming(_ imClient: AVIMClient) {
        imClientResumed(imClient)
    }

    func imClientResumed(_ imClient: AVIMClient) {
        let data: [String: Any?] = [
            "clientId": imClient.clientId,
        ]

        self.plugin.channel.invokeMethod("avIMClient_clientEventHandler_onConnectionResumed", arguments: data)
    }

    func imClientClosed(_ imClient: AVIMClient, error: Error?) {
    }

    func conversation(_ conversation: AVIMConversation, didReceiveCommonMessage message: AVIMMessage) {
        let data: [String: Any?] = [
            "clientId": conversation.clientId,
            "message": message.toFlutterDictionary(),
            "conversation": conversation.toFlutterDictionary(),
        ]

        self.plugin.channel.invokeMethod("avIMClient_messageHandler_onMessage", arguments: data)
    }

    func conversation(_ conversation: AVIMConversation, didUpdateForKey key: AVIMConversationUpdatedKey) {
        if key == AVIMConversationUpdatedKey.unreadMessagesCount {
            let data: [String: Any?] = [
                "clientId": conversation.clientId,
                "conversation": conversation.toFlutterDictionary(),
            ]

            self.plugin.channel.invokeMethod("avIMClient_conversationEventHandler_onUnreadMessagesCountUpdated",
                    arguments: data)
        }
    }
}

class AVIMClientMethodCallHandler: SubMethodCallHandler {
    private static var clientCache: [String: AVIMClient] = [:]
    
    private let plugin: SwiftFlutterLeanCloudPlugin
    private let clientDelegate: AVIMClientDelegate
  
    static func getClient(clientId: String) -> AVIMClient {
        var client = clientCache[clientId]
        if client == nil {
            client = AVIMClient.init(clientId: clientId)
            clientCache[clientId] = client
        }
        return client!
    }
    
    init(with plugin: SwiftFlutterLeanCloudPlugin) {
        self.plugin = plugin
        self.clientDelegate = ClientDelegate(with: plugin)
    }

    func onMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) -> Bool {
        if !call.method.starts(with: "avIMClient_") {
            return false
        }

        let method = call.method["avIMClient_".endIndex...]
        switch method {
        case "registerMessageHandler":
            result(nil)
        case "unregisterMessageHandler":
            result(nil)
        case "getInstance":
            getInstance(call, result)
        case "queryConversations":
            queryConversations(call, result)
        default:
            result(FlutterMethodNotImplemented)
        }

        return true
    }

    private func getInstance(_ call: FlutterMethodCall, _ result: (Any?) -> Void) {
        if call.arguments == nil {
            return result(FlutterError(code: "INVALID_ARGS", message: "clientId cannot be nil", details: nil))
        }
        let clientId = call.arguments as! String
        let client = AVIMClientMethodCallHandler.getClient(clientId: clientId)
        client.delegate = self.clientDelegate
        result(nil)
    }

    private func queryConversations(_ call: FlutterMethodCall, _ result: @escaping (Any?) -> Void) {
        let args = call.arguments as! [String: Any?]
        let clientId = args["clientId"] as! String
        let client = AVIMClientMethodCallHandler.getClient(clientId: clientId)
        let ids = args["ids"] as! [String]
        let refreshLastMessage = args["refreshLastMessage"] as! Bool
        let cachePolicy = AVIMCachePolicy.fromFlutterInt(args["cachePolicy"] as! Int?)
        let limit = args["limit"] as! Int

        let query = client.conversationQuery()
        query.limit = limit
        query.whereKey("objectId", containedIn: ids)
        if refreshLastMessage {
            query.option = AVIMConversationQueryOption.withMessage
        }
        if let cachePolicy = cachePolicy {
            query.cachePolicy = cachePolicy
        }
        query.findConversations(callback: { (conversations, error) in
            if let error = error {
                return result(FlutterError(code: "ERROR", message: "cannot query conversations",
                        details: error.localizedDescription))
            }
            if conversations == nil {
                return result(FlutterError(code: "ERROR", message: "assertion failed: conversation should not be null",
                        details: nil))
            }
            result(conversations?.map({ $0.toFlutterDictionary() }))
        })
    }
}

class AVIMConversationMethodCallHandler: SubMethodCallHandler {
    private func internalGetConversation(in clientId: String, forId conversationId: String,
                                         callback: @escaping (AVIMConversation?, Error?) -> Void) -> Void {
        let client = AVIMClientMethodCallHandler.getClient(clientId: clientId)
        let conversation = client.conversation(forId: conversationId)
        if let conversation = conversation {
            debugPrint("got AVIMConversation from cache")
            return callback(conversation, nil)
        }
        let query = client.conversationQuery()
        query.getConversationById(conversationId, callback: { (conversation, error) in
            debugPrint("got AVIMConversation from network")
            callback(conversation, error)
        })
    }

    func onMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) -> Bool {
        if !call.method.starts(with: "avIMConversation_") {
            return false
        }

        let method = call.method["avIMConversation_".endIndex...]
        switch method {
        case "queryMessages":
            queryMessages(call, result)
        case "sendMessage":
            sendMessage(call, result)
        case "read":
            read(call, result)
        default:
            result(FlutterMethodNotImplemented)
        }

        return true
    }

    private func read(_ call: FlutterMethodCall, _ result: @escaping (Any?) -> Void) {
        let args = call.arguments as! [String: Any?]
        let clientId = args["clientId"] as! String
        let conversationId = args["conversationId"] as! String

        internalGetConversation(in: clientId, forId: conversationId, callback: { (conversation, error) in
            if let error = error {
                return result(FlutterError(code: "ERROR", message: "cannot get conversation", details: error.localizedDescription))
            }
            if let conversation = conversation {
                conversation.readInBackground()
                return result(nil)
            } else {
                return result(FlutterError(code: "ERROR", message: "cannot get conversation", details: nil))
            }
        })
    }

    private func sendMessage(_ call: FlutterMethodCall, _ result: @escaping (Any?) -> Void) {
        let args = call.arguments as! [String: Any?]
        let clientId = args["clientId"] as! String
        let conversationId = args["conversationId"] as! String
        let content = args["content"] as! String

        internalGetConversation(in: clientId, forId: conversationId, callback: { (conversation, error) in
            if let error = error {
                return result(FlutterError(code: "ERROR", message: "cannot get conversation", details: error.localizedDescription))
            }
            if let conversation = conversation {
                let message = AVIMMessage(content: content)
                conversation.send(message, callback: { (succeeded, error) in
                    if let error = error {
                        let error = error as NSError
                        let exception: [String: Any?] = [
                            "code": error.code,
                            "appCode": error.code,
                            "message": error.userInfo[NSLocalizedFailureReasonErrorKey],
                        ]
                        let data: [String: Any?] = [
                            "message": message.toFlutterDictionary(),
                            "exception": exception,
                        ]
                        return result(FlutterError(code: "ERROR", message: "send message failed", details: data))
                    }
                    return result(message.toFlutterDictionary())
                })
            } else {
                return result(FlutterError(code: "ERROR", message: "cannot get conversation", details: nil))
            }
        })
    }

    private func queryMessages(_ call: FlutterMethodCall, _ result: @escaping (Any?) -> Void) {
        let args = call.arguments as! [String: Any?]
        let clientId = args["clientId"] as! String
        let conversationId = args["conversationId"] as! String
        let msgId = args["msgId"] as! String?
        let timestamp = args["timestamp"] as! Int64?
        let limit = args["limit"] as! Int

        func callback(_ messages: [AVIMMessage]?, _ error: Error?) {
            if let error = error {
                return result(FlutterError(code: "ERROR", message: "cannot query messages",
                        details: error.localizedDescription))
            }
            if let messages = messages {
                return result(messages.map({ $0.toFlutterDictionary() }))
            } else {
                return result(FlutterError(code: "ERROR", message: "assertion failed: msgs should not be nil",
                        details: nil))
            }
        }

        internalGetConversation(in: clientId, forId: conversationId, callback: { (conversation, error) in
            if let error = error {
                return result(FlutterError(code: "ERROR", message: "cannot get conversation",
                        details: error.localizedDescription))
            }
            if let conversation = conversation {
                if let msgId = msgId, let timestamp = timestamp {
                    conversation.queryMessages(beforeId: msgId, timestamp: timestamp, limit: UInt(limit),
                            callback: callback)
                } else {
                    conversation.queryMessages(withLimit: UInt(limit), callback: callback)
                }
            } else {
                return result(FlutterError(code: "ERROR", message: "cannot get conversation", details: nil))
            }
        })
    }
}
