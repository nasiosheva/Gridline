//
//  LocalNotificationService.swift
//  Gridline
//

import Foundation
import UserNotifications

enum LocalNotificationService {
    static func notifyTerminalEnded(repoName: String, tabName: String, exitCode: Int32?) {
        Task {
            let center = UNUserNotificationCenter.current()
            var settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
                settings = await center.notificationSettings()
            }
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = "\(repoName) — \(tabName)"
            content.body = String(localized: exitCode == 0 ? L10n.Terminal.finishedNotification : L10n.Terminal.failedNotification)
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }
}
