#!/usr/bin/env swift

import Foundation

let notificationName = Notification.Name("AppleInterfaceThemeChangedNotification")

DistributedNotificationCenter.default().addObserver(
	forName: notificationName,
	object: nil,
	queue: .main
) { _ in
	print("changed")
	fflush(stdout)
}

RunLoop.main.run()

