//
//  LocalNotificationService.swift
//  Gridline
//

import Foundation
import UserNotifications

@MainActor
enum LocalNotificationAuthorizationStatus: Equatable {
    case notDetermined
    case authorized
    case provisional
    case denied

    static func map(_ status: UNAuthorizationStatus) -> Self {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .provisional: .provisional
        case .denied: .denied
        @unknown default: .denied
        }
    }
}

@MainActor
protocol LocalNotificationClient {
    func authorizationStatus() async -> LocalNotificationAuthorizationStatus
    func requestAuthorization() async
    func add(_ request: UNNotificationRequest) async
}

@MainActor
private struct SystemLocalNotificationClient: LocalNotificationClient {
    func authorizationStatus() async -> LocalNotificationAuthorizationStatus {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return LocalNotificationAuthorizationStatus.map(status)
    }

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func add(_ request: UNNotificationRequest) async {
        try? await UNUserNotificationCenter.current().add(request)
    }
}

@MainActor
enum LocalNotificationService {
    static func makeContent(repoName: String, tabName: String, exitCode: Int32?) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "\(repoName) — \(tabName)"
        content.body = String(localized: exitCode == 0 ? L10n.Terminal.finishedNotification : L10n.Terminal.failedNotification)
        content.sound = .default
        return content
    }

    static func notifyTerminalEnded(repoName: String, tabName: String, exitCode: Int32?) async {
        await notifyTerminalEnded(
            repoName: repoName,
            tabName: tabName,
            exitCode: exitCode,
            using: SystemLocalNotificationClient()
        )
    }

    static func notifyTerminalEnded(
        repoName: String,
        tabName: String,
        exitCode: Int32?,
        using client: any LocalNotificationClient
    ) async {
        var status = await client.authorizationStatus()
        if status == .notDetermined {
            await client.requestAuthorization()
            status = await client.authorizationStatus()
        }
        guard status == .authorized || status == .provisional else { return }

        let content = makeContent(repoName: repoName, tabName: tabName, exitCode: exitCode)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        await client.add(request)
    }
}
