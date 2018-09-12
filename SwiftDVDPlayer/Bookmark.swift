//
//  Bookmark.swift
//  CocoaDVDPlayer
//
//  Created by C.W. Betts on 8/8/16.
//
//

import Foundation
import DVDPlayback

/// before creating a new bookmark object, media needs to be open and playing
final class Bookmark: Codable {
	private var data = Data()

	/// This method creates a bookmark that represents the current playback
	/// position. We call `DVDGetBookmark` twice: (1) to find out how much memory to
	/// allocate for the bookmark, and (2) to create the bookmark in our allocated
	/// memory.
	init() {
		/* get bookmark size */
		var size: UInt32 = 0
		var result = DVDGetBookmark(nil, &size);
		if result != noErr {
			NSLog("DVDGetBookmark returned %d", result);
		} else {
			/* allocate memory for bookmark data */
			data = Data(count: Int(size))
			
			/* get bookmark to current location */
			result = data.withUnsafeMutableBytes { (ct: UnsafeMutablePointer<UInt8>) -> OSStatus in
				return DVDGetBookmark(ct, &size)
			}
			if (result != noErr) {
				NSLog("DVDGetBookmark returned %d", result);
			}
		}
	}
	
	func gotoBookmark() {
		let dataSize = UInt32(data.count)
		let result = data.withUnsafeMutableBytes { (ct: UnsafeMutablePointer<UInt8>) -> OSStatus in
			return DVDGotoBookmark(ct, dataSize)
		}
		if result != noErr {
			NSLog("DVDGotoBookmark returned %d", result)
		}
	}
}
