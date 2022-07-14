//
//  VideoWindow.swift
//  CocoaDVDPlayer
//
//  Created by C.W. Betts on 8/8/16.
//
//

import Cocoa
import DVDPlayback

class VideoWindow: NSWindow {
	enum PlaybackSize: Int {
		case current = 0
		case small
		case normal
		case max
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		
		/* register for notifications */
		
		NotificationCenter.default.addObserver(self, selector: #selector(VideoWindow.windowDidMove(_:)), name: NSWindow.didMoveNotification, object: nil)
		
		NotificationCenter.default.addObserver(self, selector: #selector(VideoWindow.frameDidChange(_:)), name: NSView.frameDidChangeNotification, object: nil)
		
		/* we want to respond to mouse movements -- see sendEvent */
		acceptsMouseMovedEvents = true
		
		/* display a black background before media starts playing */
		backgroundColor = NSColor.black
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

	/// This method overrides NSWindow to handle button mouse-overs and mouse-clicks
	/// in the window.
	override func sendEvent(_ theEvent: NSEvent) {
		/* index of selected button in DVD menu */
		var index = Int32(kDVDButtonIndexNone)
		
		
		/* get mouse location */
		var location = theEvent.locationInWindow
		location.y = self.frame.size.height - location.y
		var err = noErr
		
		switch theEvent.type {
		case .mouseMoved:
			err = DVDDoMenuCGMouseOver(&location, &index)
			break
		case .leftMouseDown:
			err = DVDDoMenuCGClick(&location, &index)
			break
		default:
			break
		}
		_ = err
		
		/* sync the cursor */
		let cursor: NSCursor
		if Int(index) != kDVDButtonIndexNone {
			cursor = NSCursor.pointingHand
		} else {
			cursor = NSCursor.arrow
		}
		cursor.set()
		
		/* pass the event back to NSWindow for additional handling */
		super.sendEvent(theEvent)
	}
	
	/** This method returns a number that represents the aspect ratio of the
	current title. */
	private var titleAspectRatio: CGFloat {
		struct Ratios {
			static let standard: CGFloat = 4.0 / 3.0
			static let wide: CGFloat = 16.0 / 9.0
		}
		var ratio = Ratios.standard
		
		var format: DVDAspectRatio = .ratioUninitialized
		DVDGetAspectRatio(&format)
		
		switch format {
		case .ratio4x3, .ratio4x3PanAndScan, .ratioUninitialized:
			ratio = Ratios.standard
			
		case .ratio16x9, .ratioLetterBox:
			ratio = Ratios.wide
		}
		
		return ratio
	}

	/// This method sets the video window state in DVD Playback Services. The
	/// setupVideoWindow message is sent by the Controller object during playback
	/// session initialization.
	func setupVideoWindow() {
		NSLog("Step 2: Set Video Window")
		
		let result = DVDSetVideoWindowID(UInt32(windowNumber))
		if result != noErr {
			print("DVDSetVideoWindowID returned \(result)")
		}
		
		setVideoDisplay()
		
		/* set initial bounds of video area in window */
		setVideoBounds()
	}

	/** This method finds the native video size of the current title and adjusts the
	width so the aspect ratio is correct (this is arbitrary -- we could also adjust
	the height.) This information is needed when the user chooses either the small
	or the normal window size from the Video menu. */
	func getVideoSize() -> NSSize {
		/* get the native height and width of the media */
		var width: UInt16 = 720
		var height: UInt16 = 480
		DVDGetNativeVideoSize(&width, &height)
		
		var size = NSSize()
		size.height = CGFloat(height)
		/* adjust the width using the current aspect ratio */
		size.width = size.height * titleAspectRatio
		
		return size
	}
	
	/// This method sets the dimensions of the window's content area and positions
	/// the window on the screen. The setWindowSize message is sent (1) when the user
	/// chooses one of the 3 standard sizes in the Video menu, (2) when the user resizes
	/// the window manually, and (3) when the aspect ratio of the playback title
	/// changes.
	func setWindowSize(_ inSize: PlaybackSize) {
		/* get the aspect ratio of the current title */
		let titleRatio = titleAspectRatio
		
		/* get the bounding rectangle of the display for this window, excluding
		menu bar and dock */
		let screenBounds = screen!.visibleFrame
		
		/* create and initialize a rectangle for the new content area */
		let frame = self.frame
		var topLeft = NSPoint(x: frame.origin.x, y: frame.origin.y + frame.size.height)
		var bounds = contentView!.bounds.size
		
		/* now compute the new bounds */
		switch inSize {
		case .current:
			/* apply the aspect ratio to the new size */
			bounds.width = bounds.height * titleRatio
			if bounds.width > screenBounds.size.width {
				bounds.width = screenBounds.size.width
				bounds.height = screenBounds.size.width * (1.0 / titleRatio)
			}
			
		case .normal:
			bounds = getVideoSize()
			
		case .small:
			bounds = getVideoSize()
			bounds.width /= 2
			bounds.height /= 2
			
		case .max:
			/* find the largest frame that fits inside the display bounds */
			let screenRatio = screenBounds.size.width / screenBounds.size.height
			if screenRatio >= titleRatio {
				bounds.height = screenBounds.size.height
				bounds.width = screenBounds.size.height * titleRatio
			} else {
				bounds.width = screenBounds.size.width
				bounds.height = screenBounds.size.width * (1.0 / titleRatio)
			}
			
			/* move window to top left corner of screen */
			topLeft.x = screenBounds.origin.x
			topLeft.y = screenBounds.size.height + screenBounds.origin.y
		}

		disableFlushing()
		setContentSize(bounds)
		setFrameTopLeftPoint(topLeft)
		enableFlushing()
	}

	/// This method finds the display ID for our window and notifies DVD Playback
	/// Services. The setVideoDisplay message is sent (1) when CocoaDVDPlayer finishes
	/// launching and the Controller object sends us the setupVideoWindow message, and
	/// (2) when the user moves the window to a new location.
	func setVideoDisplay() {
		struct curDisplay {
			static var value: CGDirectDisplayID = 0
		}
		
		/* get the ID of the display that contains the largest part of the window */
		let newDisplay = (self.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
		
		/* if the display has changed, set the new display */
		if newDisplay != curDisplay.value {
			NSLog("Step 3: Set Video Display")
			var isSupported: DarwinBoolean = false
			let result = DVDSwitchToDisplay(newDisplay, &isSupported)
			if result != noErr {
				print("DVDSwitchToDisplay returned \(result)")
			}
			
			if isSupported.boolValue {
				curDisplay.value = newDisplay
			} else {
				NSLog("video display %d not supported", newDisplay)
			}
		}
	}

	/// This method finds our video area (that is, our content view) and passes it to
	/// DVD Playback Services. The setVideoBounds message is sent (1) when
	/// CocoaDVDPlayer finishes launching and the Controller object sends us the
	/// setupVideoWindow message, (2) when the user resizes our window frame, and (3)
	/// when the aspect ratio of the title changes.
	func setVideoBounds() {
		NSLog("Step 4: Set Video Bounds")
		
		let content = self.contentView!.bounds
		let frame = self.frame
		
		var bounds = CGRect(x: 0, y: frame.size.height - content.size.height, width: content.size.width, height: content.size.height)
		let result = DVDSetVideoCGBounds(&bounds)
		
		if result != noErr {
			print("DVDSetVideoCGBounds returned \(result)")
		}
	}

	//MARK: - NSWindow notifications
	
	@objc func frameDidChange(_ notification: NSNotification) {
		if (notification.object as AnyObject) === contentView {
			setWindowSize(.current)
			setVideoBounds()
		}
	}
	
	@objc func windowDidMove(_ notification: NSNotification) {
		if (notification.object as AnyObject) === self {
			setVideoDisplay()
		}
	}
}
