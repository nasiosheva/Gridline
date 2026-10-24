import SwiftUI

struct GridlineSettingsView: View {
    @AppStorage(GridlinePreferences.scrollbackLimitKey)
    private var scrollbackLimit = GridlinePreferences.defaultScrollbackLimit

    var body: some View {
        Form {
            Section(L10n.Settings.terminal) {
                Picker(L10n.Settings.scrollbackLimit, selection: $scrollbackLimit) {
                    ForEach(GridlinePreferences.scrollbackLimitOptions, id: \.self) { limit in
                        Text(limit.formatted()).tag(limit)
                    }
                }
                Text(L10n.Settings.scrollbackChangeInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.Settings.diagnostics) {
                Label(L10n.Settings.diagnosticsInfo, systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 440)
        .onChange(of: scrollbackLimit) { _, newLimit in
            NotificationCenter.default.post(
                name: GridlinePreferences.scrollbackLimitChanged,
                object: nil,
                userInfo: [GridlinePreferences.scrollbackLimitUserInfoKey: newLimit]
            )
        }
    }
}
