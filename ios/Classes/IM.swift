//
// Created by Kainan Zhu on 2018/8/30.
//

import Foundation
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
            "from": nil, // TODO add this to document
            "messageId": self.messageId,
            "timestamp": self.sendTimestamp,
            "deliveredAt": self.deliveredTimestamp,
            "updateAt": self.updatedAt?.millisecondsSince1970,
            "status": self.status.statusCode,
        ]
    }
}

class ClientDelegate: NSObject, AVIMClientDelegate {
    private let plugin: FlutterLeanCloudPlugin

    init(with plugin: FlutterLeanCloudPlugin) {
        self.plugin = plugin
    }

    func imClientPaused(_ imClient: AVIMClient) {

    }

    func imClientResuming(_ imClient: AVIMClient) {
    }

    func imClientResumed(_ imClient: AVIMClient) {
    }

    func imClientClosed(_ imClient: AVIMClient, error: Error?) {
    }
}

class AVIMClientMethodCallHandler: SubMethodCallHandler {
    private let plugin: FlutterLeanCloudPlugin
    private let clientDelegate: AVIMClientDelegate

    init(with plugin: FlutterLeanCloudPlugin) {
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
            break
        case "unregisterMessageHandler":
            break
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
        let client = AVIMClient(clientId: clientId)
        client.delegate = self.clientDelegate
        result(nil)
    }

    private func queryConversations(_ call: FlutterMethodCall, _ result: @escaping (Any?) -> Void) {
        let args = call.arguments as! [String: Any?]
        let clientId = args["clientId"] as! String
        let client = AVIMClient(clientId: clientId)
        let ids = args["ids"] as! [String]
        let refreshLastMessage = args["refreshLastMessage"] as! Bool

        let query = client.conversationQuery()
        query.whereKey("objectId", containedIn: ids)
        if refreshLastMessage {
            query.option = AVIMConversationQueryOption.withMessage
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
        let client = AVIMClient(clientId: clientId)
        let conversation = client.conversation(forId: conversationId)
        if let conversation = conversation {
            return callback(conversation, nil)
        }
        let query = client.conversationQuery()
        query.getConversationById(conversationId, callback: callback)
    }

    func onMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) -> Bool {
        if !call.method.starts(with: "avIMConversation_") {
            return false
        }

        let method = call.method["avIMConversation".endIndex...]
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

    private func read(_ call: FlutterMethodCall, _ result: (Any?) -> Void) {
        let args = call.arguments as! [String: Any?]
        let clientId = args["clientId"] as! String
        let conversationId = args["conversationId"] as! String

        internalGetConversation(in: clientId, forId: conversationId, callback: {(conversation, error) in
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
