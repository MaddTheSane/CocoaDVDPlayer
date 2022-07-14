//
//  PlaybackTime.swift
//  CocoaDVDPlayer
//
//  Created by C.W. Betts on 8/8/16.
//
//

import Cocoa

class PlaybackTime: NSTextField {
	private enum PlaybackTimeBase {
		case elapsed
		case remaining
	}
	
	/// default is to display elapsed time
	private var timeBase = PlaybackTimeBase.elapsed
	
	var time: (elapsed: Int32, remaining: Int32) = (0,0) {
		didSet {
			setTimeText()
		}
	}
	
	/// When the user clicks the mouse in the playback time field, this method
	/// responds by toggling the time base between elapsed and remaining time.
	override func mouseDown(with theEvent: NSEvent) {
		if timeBase == .elapsed {
			timeBase = .remaining
		} else {
			timeBase = .elapsed
		}
		
		setTimeText()
		super.mouseDown(with: theEvent)
	}

	/// This method updates the text used to display the time in the control
	/// window. 
	private func setTimeText() {
		var time: UInt32
		let format: String
		
		if timeBase == .elapsed {
			time = UInt32(self.time.elapsed + 500) / 1000
			format = "%02u:%02u:%02u"
		} else {
			time = UInt32(self.time.remaining + 500) / 1000
			format = "-%02u:%02u:%02u"
		}
		
		let hours = time / 3600
		time -= hours * 3600
		let mins = time / 60
		let secs = time % 60
		
		let timeString = String(format: format, hours, mins, secs)
		stringValue = timeString
		
		needsDisplay = true
	}
}
