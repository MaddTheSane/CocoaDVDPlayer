//
//  ControlWindow.swift
//  CocoaDVDPlayer
//
//  Created by C.W. Betts on 8/8/16.
//
//

import Cocoa

class ControlWindow: NSWindow {
	/// This method takes care of some initialization tasks that supercede settings
	/// in the nib. 
	override func awakeFromNib() {
		super.awakeFromNib()
		/* position window in lower left corner of display */
		setFrameOrigin(screen!.visibleFrame.origin)
		
		/* behave like a floating window */
		hidesOnDeactivate = true
	}
	
	/// This method passes any key down events to our delegate, the Controller
	/// object, for handling.
	override func keyDown(with theEvent: NSEvent) {
		let eventHandled = (self.delegate as! DVDAppDelegate).onKeyDown(with: theEvent)
		
		if eventHandled {
			flushBufferedKeyEvents()
		} else {
			super.keyDown(with: theEvent)
		}
	}
}
