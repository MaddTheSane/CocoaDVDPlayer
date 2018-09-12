//
//  Controller.swift
//  CocoaDVDPlayer
//
//  Created by C.W. Betts on 8/8/16.
//
//

import Cocoa
import DVDPlayback

/// This is a private struct that's used to pass DVD playback event information
/// from the callback function `MyDVDEventHandler` (which runs in a thread other than
/// the main thread) to the method `handleDVDEvent`, which runs in the main thread and
/// actually does the work.
private struct DVDEvent {
	var eventCode: DVDEventCode
	var eventData1: DVDEventValue
	var eventData2: DVDEventValue
}


/// This is our DVD event callback function. It's always called in a thread other
/// than the main thread. We need to handle the event in the main thread because we
/// may want to update the UI, which involves drawing. Therefore we pass the event
/// information to the `handleDVDEvent` method, which runs in the main thread and
/// actually does the work.
private func myDVDEventHandler(eventCode: DVDEventCode, eventData1: DVDEventValue, eventData2: DVDEventValue, inRefCon: UnsafeMutableRawPointer) {
	let controller = Unmanaged<DVDAppDelegate>.fromOpaque(inRefCon).takeUnretainedValue()
	let event = DVDEvent(eventCode: eventCode, eventData1: eventData1, eventData2: eventData2)
	
	DispatchQueue.main.async() {
		controller.handleDVDEvent(event)
	}
}

/// This function and method handle the fatal error event that we registered to
/// receive in the beginSession method. Typically a fatal error means an I/O problem
/// such as a damaged disc has made it impossible to continue with playback. You
/// should always implement this callback and respond by ending the playback
/// session.
private func myDVDErrorHandler(errorCode: DVDErrorCode, inRefCon: UnsafeMutableRawPointer) {
	let controller = Unmanaged<DVDAppDelegate>.fromOpaque(inRefCon).takeUnretainedValue()
	controller.handleDVD(error: errorCode)
}

@NSApplicationMain
class DVDAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
	@IBOutlet weak var playButton: NSButton!
	@IBOutlet weak var audioControl: NSSlider!
	@IBOutlet weak var sceneText: NSTextField!
	@IBOutlet weak var titleText: NSTextField!
	@IBOutlet weak var controlWindow: NSWindow!
	@IBOutlet weak var timeText: PlaybackTime!
	@IBOutlet weak var videoWindow: VideoWindow!
	
	var bookmarks = [Bookmark]()
	private var volumeURL: URL? = nil
	var dvdState = DVDState.unknown
	/// used to identify the registration of our DVD event callback
	private var eventCallbackID: DVDEventCallBackRef? = nil
	
	/// Our init method defines our initial state and registers for
	/// notifications. The DVD playback session is initialized later, in the method
	/// `applicationDidFinishLaunching`.
	override init() {
		
		/* register for several notifications posted to the shared workspace
		notification center */
		let center = NSWorkspace.shared.notificationCenter
		
		super.init()
		
		center.addObserver(self, selector: #selector(DVDAppDelegate.deviceDidMount(_:)), name: NSWorkspace.didMountNotification, object: nil)
		
		center.addObserver(self, selector: #selector(DVDAppDelegate.machineWillSleep(_:)), name: NSWorkspace.willSleepNotification, object: nil)
		
		center.addObserver(self, selector: #selector(DVDAppDelegate.machineDidWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
		
		/* make sure we're the delegate of the NSApplication instance */
		NSApplication.shared.delegate = self
	}
	
	/* The setAudioVolume message is sent by the two action methods onVolumeUp
	and onVolumeDown, in response to a user request to increase or decrease the
	audio level. The audio level is an integer in the range minLevel (0) to maxLevel
	(255). We change the level by an increment of 16, which is 1/16 of the total
	range. */
	
	func changeAudioVolume(up: Bool) -> UInt16 {
		/* get range and current audio level */
		var minLevel: UInt16 = 0
		var curLevel: UInt16 = 0
		var maxLevel: UInt16 = 0
		DVDGetAudioVolumeInfo(&minLevel, &curLevel, &maxLevel);
		
		/* default action is to maintain the current level */
		var newLevel = curLevel;
		
		/* compute how much we are going to change */
		let delta = (maxLevel - minLevel + 1) / 16;
		
		if up {
			/* compute the next level in the up direction, clamping the value to maxLevel */
			newLevel = min(curLevel + delta, maxLevel);
		} else {
			/* compute the next level in the down direction, clamping the value to minLevel */
			newLevel = max(curLevel - delta, minLevel);
		}
		
		/* set the new audio level */
		let result = DVDSetAudioVolume(newLevel);
		assert(result == noErr, "DVDSetAudioVolume returned \(result)");
		
		/* return the new level, which we use to adjust the audio slider */
		return newLevel;
	}
	
	/// The `deviceDidMount` notification is received when the system mounts a
	/// removable volume. We registered for this notification in our init method. If no
	/// media is playing, we naively assume the user has inserted a new DVD disc and
	/// respond by sending the openMedia message. No harm is done if the volume is not a
	/// DVD, just a few wasted cycles.
	@objc private func deviceDidMount(_ notification: NSNotification) {
		if dvdState != .playing {
			let devicePath = notification.userInfo![NSWorkspace.volumeURLUserInfoKey] as! URL
			NSLog("Device did mount: %@", devicePath as NSURL);
			
			/* DVD volumes have a VIDEO_TS media folder at the root level */
			let mediaPath = devicePath.appendingPathComponent("VIDEO_TS", isDirectory: true)
			_=openMedia(at: mediaPath, isVolume: true)
		}
	}
	
	/// The machineWillSleep notification is received when the system is about to
	/// sleep. We registered for this notification in our init method. We respond
	/// by notifying DVD Playback Services.
	@objc private func machineWillSleep(_ notification: NSNotification) {
		let result = DVDSleep()
		assert(result == 0, "DVDSleep returned \(result)")
	}
	
	/// The machineDidWake notification is received when the system is no longer
	/// sleeping. We registered for this notification in our init method. We respond by
	/// notifying DVD Playback Services.
	@objc private func machineDidWake(_ notification: NSNotification) {
		let result = DVDWakeUp();
		assert(result == 0, "DVDWakeUp returned \(result)");
	}
	
	fileprivate func handleDVDEvent(_ event: DVDEvent) {
		switch event.eventCode {
		case .titleTime:
			timeText.time = (Int32(event.eventData1), Int32(event.eventData2 - event.eventData1))
			
		case .title:
			titleText.integerValue = Int(event.eventData1)
			videoWindow.setWindowSize(.current)
			
		case .PTT:
			sceneText.integerValue = Int(event.eventData1)
			// NSLog(@"Scene changed to %d", [event eventData1]);
			
		case .error:
			handleDVD(error: Int32(event.eventData1))
			
		case .playback:
			dvdState = DVDState(rawValue: OSStatus(event.eventData1)) ?? .unknown
			
			
		case .videoStandard, .displayMode:
			videoWindow.setWindowSize(.current)
			
		default:
			break
		}
	}
	
	/// This function and method handle the fatal error event that we registered to
	/// receive in the beginSession method. Typically a fatal error means an I/O problem
	/// such as a damaged disc has made it impossible to continue with playback. You
	/// should always implement this callback and respond by ending the playback
	/// session.
	func handleDVD(error errorCode: DVDErrorCode) {
		NSLog("fatal error %d", errorCode);
		NSApp.terminate(self)
	}
	
	/// This method determines whether a specified path represents a valid DVD-Video
	/// media folder.
	func isValidMedia(at inPath: URL) -> Bool {
		do {
			let resVals = try inPath.resourceValues(forKeys: [.isDirectoryKey])
			guard let isDirBool = resVals.isDirectory, isDirBool else {
				return false
			}
			var isValid: DarwinBoolean = false
			DVDIsValidMediaURL(inPath as NSURL, &isValid)
			return isValid.boolValue
		} catch {
			return false
		}
	}
	
	/** We send ourself the openMedia message: (1) when the application launches and
	finds removable media, (2) when the `deviceDidMount` notification is received, or
	(3) when the user chooses the menu item Open Media Folder and selects a folder
	to open. In cases 1 and 2, we call `DVDOpenMediaVolumeWithURL`. In case 3, we always call
	`DVDOpenMediaFileWithURL` even if the folder is actually on a DVD disc volume. */
	func openMedia(at inURL: URL, isVolume: Bool) -> Bool {
		var mediaIsOpen = false
		var result = noErr
		if isValidMedia(at: inURL) {
			
			if hasMedia {
				closeMedia()
			}
			
			if isVolume {
				result = DVDOpenMediaVolumeWithURL(inURL as NSURL)
				if result == noErr {
					volumeURL = inURL
				}
			} else {
				result = DVDOpenMediaFileWithURL(inURL as NSURL)
			}
		}
		
		if result == noErr {
			NSLog("Step 5: Open Media");
			NSLog("Media Folder: %@", inURL as NSURL);
			mediaIsOpen = true;
			logMediaInfo()
		}
		
		if Int(result) == kDVDErrordRegionCodeUninitialized {
			/* The drive region code has not been initialized. Refer to the
			readme file for information on handling this situation. */
			displayAlert(message: "noRegionCode", info: "noRegionCodeInfo")
			NSApp.terminate(self)
		}
		
		return mediaIsOpen
	}
	
	/** This method displays a modal alert panel with a short and long text
	message. Both messages should be stored in a Localizable.strings file inside
	the application bundle. You pass in the two string keys that correspond to the
	text you want to display. */
	@discardableResult
	private func displayAlert(message msgKey: String, info infoKey: String) -> NSApplication.ModalResponse {
		let bundle = Bundle(for: type(of: self))
		
		let messageText = bundle.localizedString(forKey: msgKey, value: "No translation", table: "Localizable")
		let informativeText = bundle.localizedString(forKey: infoKey, value: "No translation", table: "Localizable")
		
		let alert = NSAlert()
		alert.alertStyle = .critical
		alert.messageText = messageText
		alert.informativeText = informativeText
		return alert.runModal()
	}
	
	/** This method starts a new playback session, registers our DVD event and DVD
	error handlers, and defines the rate at which timer events arrive. */
	func beginSession() {
		/* start a new playback session */
		
		NSLog("Step 1: Begin Session");
		let aRefCon = Unmanaged<DVDAppDelegate>.passUnretained(self).toOpaque()
		DVDSetFatalErrorCallBack(myDVDErrorHandler, aRefCon)
		var result = DVDInitialize()
		if (result != noErr) {
			/* we can't do anything useful now, so we handle the error and exit */
			NSLog("DVDInitialize returned %d", result);
			if Int(result) == kDVDErrorInitializingLib {
				/* notify user that another client is using the framework */
				displayAlert(message: "frameworkBusy", info: "frameworkBusyInfo")
			}
			NSApp.terminate(self)
		}
		
		/* install our handler for playback events */
		
		var eventCodes: [DVDEventCode] = [
			.displayMode,
			.error,
			/* registering for and handling this event makes the use of
			DVDGetState unnecessary */
			.playback,
			.PTT,
			.title,
			.titleTime,
			.videoStandard,
			];
		
		result = withUnsafeMutablePointer(to: &eventCallbackID) { (body) -> OSStatus in
			// hacky hacky hacky!
			return body.withMemoryRebound(to: DVDEventCallBackRef.self, capacity: 1, { (hi) -> OSStatus in
				return DVDRegisterEventCallBack(myDVDEventHandler, &eventCodes, UInt32(eventCodes.count), aRefCon, hi)
			})
			//return DVDRegisterEventCallBack(myDVDEventHandler, &eventCodes, UInt32(eventCodes.count), aRefCon, unsafeBitCast(body, to: UnsafeMutablePointer<DVDEventCallBackRef>.self))
		}
		if result != noErr {
			print("DVDRegisterEventCallBack returned \(result)")
		}
		
		result = DVDSetFatalErrorCallBack(myDVDErrorHandler, aRefCon)
		if result != noErr {
			print("DVDSetFatalErrorCallBack returned \(result)")
		}
		
		/* Change the period for the recurring kDVDEventTitleTime event to 1000
		milliseconds. This makes it more likely that the playback time advances at
		least one second on each update. */
		
		result = DVDSetTimeEventRate (1000);
		if result != noErr {
			print("DVDSetTimeEventRate returned \(result)")
		}
	}
	
	/** If a playback session is active, this method closes media, unregisters the
	event callback, and ends the session. We send ourself the endSession message
	when the application is about to terminate. */
	func endSession() {
		/* mEventCallBackID is non-zero only if a session is active */
		if let eventCallbackID = eventCallbackID {
			closeMedia()
			NSLog("Step 8: End Session");
			DVDUnregisterEventCallBack(eventCallbackID)
			let result = DVDDispose()
			if result != noErr {
				print("DVDDispose returned \(result)")
			}
			self.eventCallbackID = nil;
		}
	}
	
	/** This method shows how to get information about the open media and the DVD
	drive. The media ID is generated by DVD Playback Services and is not stored
	inside the media itself. CocoaDVDPlayer does not implement the "Change Drive
	Region Code" feature, but the user may want to know what the current drive
	region code is and how many changes remain. */
	func logMediaInfo() {
		guard hasMedia else {
			return
		}
		
		/* retrieve and display the 64-bit media ID */
		var discID = DVDDiscID(0, 0, 0, 0, 0, 0, 0, 0)
		DVDGetMediaUniqueID(withUnsafeMutableBytes(of: &discID) { (did) -> UnsafeMutablePointer<UInt8> in
			return did.bindMemory(to: UInt8.self).baseAddress!
		})
		NSLog("Media ID: %.2x%.2x%.2x%.2x%.2x%.2x%.2x%.2x",
		      discID.0, discID.1, discID.2, discID.3, discID.4, discID.5, discID.6, discID.7);
		
		/* retrieve and display region code information */
		var discRegions: DVDRegionCode = UInt32(kDVDRegionCodeUninitialized)
		var driveRegion: DVDRegionCode = UInt32(kDVDRegionCodeUninitialized)
		var numChangesLeft: Int16 = -1
		DVDGetDiscRegionCode(&discRegions)
		DVDGetDriveRegionCode(&driveRegion, &numChangesLeft)
		NSLog("Disc Regions: 0x%x", discRegions);
		NSLog("Drive Region: 0x%x", driveRegion);
		NSLog("Changes Left: %d", numChangesLeft);
		
		/* DVD Playback Services checks for a region match whenever you open
		media, so this code is redundant. The code is included here to show how
		it's done. */
		if (~driveRegion & ~discRegions) != ~driveRegion {
			NSLog("Warning: region code mismatch");
		}
	}
	
	/** This method clears the title number, scene number, and playing time in the
	Controller window. We send ourself the resetUI message (1) when the application
	is finished launching, (2) when we close a media folder, or (3) when the user
	clicks the Stop button twice in succession. */
	func resetUI() {
		titleText.stringValue = "-"
		sceneText.stringValue = "-"
		timeText.time = (0, 0)
	}
	
	/** This method is a wrapper around the `DVDHasMedia` function. */
	var hasMedia: Bool {
		var hasIntMedia: DarwinBoolean = false
		let result = DVDHasMedia(&hasIntMedia)
		if result != noErr {
			print("DVDHasMedia returned \(result)")
		}
		return hasIntMedia.boolValue
	}
	
	/** We send ourself the closeMedia message (1) when a media folder is open and
	the user closes the folder, (2) when the user selects a new media folder to open
	and another media folder is already open, or (3) when the session is ending. */
	func closeMedia() {
		guard hasMedia else {
			return
		}
		
		if volumeURL != nil {
			let result = DVDCloseMediaVolume()
			if result != noErr {
				print("DVDCloseMediaVolume returned \(result)")
			}
			volumeURL = nil
		} else {
			let result = DVDCloseMediaFile()
			if result != noErr {
				print("DVDCloseMediaFile returned \(result)")
			}
		}
		
		/* clear all information in Controller window */
		resetUI()
		
		/* delete any bookmarks */
		bookmarks.removeAll()
	}
	
	/** After the application finishes launching, we search for mounted volumes that
	might be DVD media. We attempt to open each volume for playback. We can open
	only one media folder at a time, so we stop when we succeed. */
	func searchMountedDVDDisc() -> Bool {
		var foundDVD = false
		
		/* get an array of strings containing the full pathnames of all
		currently mounted removable media */
		guard let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) else {
			return false
		}
		
		for volume in volumes {
			foundDVD = openMedia(at: volume, isVolume: true)
			
			if foundDVD {
				/* we just opened a DVD volume */
				break;
			}
		}
		
		return foundDVD
	}
	
	//MARK: - NSApplicationDelegate methods
	
	/// As the delegate of NSApp (the NSApplication instance), we're automatically
	/// registered to receive these notifications. We use them to begin and end the
	/// playback session cleanly.
	func applicationDidFinishLaunching(_ notification: Notification) {
		beginSession()
		resetUI()
		videoWindow.setupVideoWindow()
		_=searchMountedDVDDisc()
	}
	
	/// Elsewhere in this file, we send ourself the terminate message when an
	/// unrecoverable error occurs. To ensure that we also receive the
	/// applicationWillTerminate message, we need to indicate that it's all right to
	/// quit immediately.
	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		return .terminateNow
	}
	
	/// When this method is called, the application is about to terminate in response
	/// to a user action or because an unrecoverable error occurred.
	func applicationWillTerminate(_ notification: Notification) {
		/* end the playback session */
		endSession()
		
		NSWorkspace.shared.notificationCenter.removeObserver(self)
		NotificationCenter.default.removeObserver(self)
	}
	
	//MARK: - Controller UI actions
	
	/** This method implements the actions for Open/Close Media Folder in the File
	menu. */
	@IBAction func onMediaFolder(_ sender: AnyObject?) {
		/* If media is currently open, the user wants to close it. */
		guard hasMedia else {
			closeMedia()
			return
		}
		
		/* The user wants to open a media folder. We display a modal Open dialog
		that's configured to open a single folder. If the user selects a folder and
		clicks the Open button, we attempt to open the media. */
		
		let panel = NSOpenPanel();
		panel.canChooseFiles = false
		panel.canChooseDirectories = true
		panel.allowsMultipleSelection = false
		
		if panel.runModal() == NSApplication.ModalResponse.OK {
			let folderURL = panel.url!
			_=openMedia(at: folderURL, isVolume: false)
		}
	}
	
	
	/** This method implements the action for the Play button in the Control window.
	It's also invoked in our onKeyDown method if media is paused and the user
	presses the space bar. */
	@IBAction func onPlay(_ sender: AnyObject?) {
		/* If media is open and not playing, we initiate playback. */
		
		guard hasMedia else {
			return
		}
		
		if dvdState != .playing {
			NSLog("Step 6: Play");
			let result = DVDPlay();
			if result != noErr {
				print("DVDPlay returned \(result)")
			}
		}
	}
	
	
	/** This method implements the action for the Pause button in the Control window.
	It's also invoked in our onKeyDown method if media is playing and the user
	presses the space bar. */
	@IBAction func onPause(_ sender: AnyObject?) {
		/* If media is open and not paused, we pause playback. */
		guard hasMedia else {
			return
		}
		if dvdState == .paused {
			let result = DVDPause()
			if result != noErr {
				print("DVDPause returned \(result)")
			}
		}
	}
	
	/** This method implements the action for the Stop button in the Control window.
	If we call DVDStop twice in succession, DVD Playback Services rewinds to the
	beginning of the media. */
	@IBAction func onStop(_ sender: AnyObject?) {
		guard hasMedia else {
			return
		}
		
		if dvdState == .stopped {
			/* we're going to rewind, so we clear the UI information */
			resetUI()
		}
		
		let result = DVDStop()
		if result != noErr {
			print("DVDStop returned \(result)")
		}
	}
	
	/** This method implements the action for the Eject button in the Control window. */
	@IBAction func onEject(_ sender: AnyObject?) {
		/* if mVolumePath is defined, removable media is open */
		
		if let volumeURL = volumeURL {
			closeMedia()
			do {
				try NSWorkspace.shared.unmountAndEjectDevice(at: volumeURL)
			} catch _ {}
		}
	}
	
	
	/** This method implements the action for the Scan Forward button in the Control window. */
	@IBAction func onScanForward(_ sender: AnyObject?) {
		if dvdState == .playing {
			let result = DVDScan(.rate4x, .forward);
			if result != noErr {
				print("DVDScan returned \(result)")
			}
		}
	}
	
	
	/** This method implements the action for the Scan Backward button in the Control window. */
	@IBAction func onScanBackward(_ sender: AnyObject?) {
		if dvdState == .playing {
			let result = DVDScan(.rate4x, .backward);
			if result != noErr {
				print("DVDScan returned \(result)")
			}
		}
	}
	
	/** This method implements the action for the Previous Scene button in the
	Control window. Scene, chapter, and part of title (PTT) all mean the same thing. */
	@IBAction func onPreviousScene(_ sender: AnyObject?) {
		if dvdState == .playing {
			let result = DVDPreviousChapter()
			if result != noErr {
				print("DVDPreviousChapter returned \(result)")
			}
		}
	}
	
	/** This method implements the action for the Next Scene button in the Control window. */
	@IBAction func onNextScene(_ sender: AnyObject?) {
		if dvdState == .playing {
			let result = DVDNextChapter()
			if result != noErr {
				print("DVDNextChapter returned \(result)")
			}
		}
	}
	
	/** This method implements the action for the Menu button in the Control window.
	If a title is playing, we go to the associated menu. If a menu is displayed, we
	go to the associated title. */
	@IBAction func onToggleMenu(_ sender: AnyObject?) {
		guard dvdState == .playing || dvdState == .playingStill || dvdState == .paused else {
			return
		}
		var onMenu: DarwinBoolean = false
		var whichMenu = DVDMenu.none
		var result = DVDIsOnMenu(&onMenu, &whichMenu)
		if result != noErr {
			print("DVDIsOnMenu returned \(result)")
		}
		
		if onMenu.boolValue {
			result = DVDReturnToTitle();
			if result != noErr {
				print("DVDReturnToTitle returned \(result)")
			}
		} else {
			result = DVDGoToMenu(.root);
			if result != noErr {
				print("DVDGoToMenu returned \(result)")
			}
		}
	}
	
	/** This method implements the action for the Next Camera Angle button in the
	Control window. */
	@IBAction func onNextAngle(_ sender: AnyObject?) {
		if dvdState == .playing {
			var numAngles: UInt16 = 0
			var angle: UInt16 = 0
			var result = DVDGetNumAngles(&numAngles);
			result = DVDGetAngle(&angle);
			angle += 1
			if angle > numAngles {
				angle = 1;
			}
			result = DVDSetAngle(angle);
			if result != noErr {
				print("DVDSetAngle returned \(result)")
			}
		}
	}
	
	/** This method implements the action for the New Bookmark button in the Control
	window. Each time the user clicks this button, we add a new bookmark to the
	mBookmarks array. To learn how bookmarks are implemented, see the Bookmark
	class. */
	@IBAction func onNewBookmark(_ sender: AnyObject?) {
		/* bookmarks to still or moving frames are ok */
		if dvdState == .playing || dvdState == .playingStill {
			let bookmark = Bookmark()
			bookmarks.append(bookmark)
		}
	}
	
	/** This method implements the action for the Goto Next Bookmark button in the
	Control window. It simply cycles though the bookmarks in the mBookmarks array. */
	@IBAction func onNextBookmark(_ sender: AnyObject?) {
		struct Next {
			static var value = 0
		}
		let count = bookmarks.count
		if count != 0 {
			/* index of next bookmark in array */
			bookmarks[Next.value].gotoBookmark()
			Next.value += 1;
			if Next.value == count {
				/* reset to first bookmark */
				Next.value = 0;
			}
		}
	}
	
	/// This method implements the action for the (Audio) Volume Up item in the
	/// Controls menu.
	@IBAction func onVolumeDown(_ sender: AnyObject?) {
		let newLevel = changeAudioVolume(up: false)
		audioControl.floatValue = Float(newLevel)
	}
	
	/** This method implements the action for the (Audio) Volume Down item in the
	Controls menu. */
	@IBAction func onVolumeUp(_ sender: AnyObject?) {
		let newLevel = changeAudioVolume(up: true)
		audioControl.floatValue = Float(newLevel)
	}
	
	/// This method implements the action for the (Audio) Mute item in the Controls
	/// menu.
	@IBAction func onMute(_ sender: NSSlider?) {
		var isMuted: DarwinBoolean = false
		var result = DVDIsMuted(&isMuted)
		result = DVDMute(!isMuted.boolValue)
		if result != noErr {
			print("DVDMute returned \(result)")
		}
	}
	
	/// This method implements the action for the audio volume slider control in the
	/// Control window.
	@IBAction func onAudioVolume(_ sender: NSSlider?) {
		let result = DVDSetAudioVolume(UInt16(sender?.floatValue ?? 127))
		if result != noErr {
			print("DVDSetAudioVolume returned \(result)")
		}
	}
	
	/// This method implements the action for the Show/Hide Controller item in the Window
	/// menu.
	@IBAction func onShowController(_ sender: NSSlider?) {
		if controlWindow.isVisible {
			controlWindow.orderOut(self)
		} else {
			controlWindow.orderFront(self)
		}
	}
	
	/** This method implements the action for the Maximum Size item in the Video menu. */
	@IBAction func onVideoMax(_ sender: NSSlider?) {
		videoWindow.setWindowSize(.max)
	}
	
	
	/** This method implements the action for the Normal Size item in the Video menu. */
	@IBAction func onVideoNormal(_ sender: NSSlider?) {
		videoWindow.setWindowSize(.normal)
	}
	
	
	/** This method implements the action for the Small Size item in the Video menu. */
	@IBAction func onVideoSmall(_ sender: NSSlider?) {
		videoWindow.setWindowSize(.small)
	}
	
	/** Both the video window and the control window pass their key down events to
	this method. We want to respond to these events in the same manner, regardless
	of which window is currently the key window. */
	func onKeyDown(with theEvent: NSEvent) -> Bool {
		var keyIsHandled = true
		guard let keyString = theEvent.characters,
			let key = keyString.utf16.first else {
				return false
		}
		var result = noErr
		
		switch key {
		case UInt16(NSUpArrowFunctionKey):
			result = DVDDoUserNavigation(.moveUp)
			
		case UInt16(NSDownArrowFunctionKey):
			result = DVDDoUserNavigation(.moveDown)
			
		case UInt16(NSLeftArrowFunctionKey):
			result = DVDDoUserNavigation(.moveLeft)
			
		case UInt16(NSRightArrowFunctionKey):
			result = DVDDoUserNavigation(.moveRight)
			
		case UInt16(NSCarriageReturnCharacter), UInt16(NSEnterCharacter):
			result = DVDDoUserNavigation(.enter)
			
		case 0x20: //space
			/* space bar toggles between play and pause */
			if dvdState == .playing {
				onPause(self)
			} else if dvdState == .paused {
				onPlay(self)
			}
			
		default:
			keyIsHandled = false
		}
		if result != noErr {
			print("DVDDoUserNavigation returned \(result)")
		}
		
		return keyIsHandled
	}
}
