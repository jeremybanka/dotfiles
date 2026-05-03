#!/usr/bin/env swift

import AppKit
import Foundation

func notifyThemeMayHaveChanged(_ reason: String) {
	print(reason)
	fflush(stdout)
}

DistributedNotificationCenter.default().addObserver(
	forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
	object: nil,
	queue: .main
) { _ in
	notifyThemeMayHaveChanged("appearance")
}

NSWorkspace.shared.notificationCenter.addObserver(
	forName: NSWorkspace.didWakeNotification,
	object: nil,
	queue: .main
) { _ in
	notifyThemeMayHaveChanged("wake")
}

NSWorkspace.shared.notificationCenter.addObserver(
	forName: NSWorkspace.screensDidWakeNotification,
	object: nil,
	queue: .main
) { _ in
	notifyThemeMayHaveChanged("screens-wake")
}

RunLoop.main.run()
