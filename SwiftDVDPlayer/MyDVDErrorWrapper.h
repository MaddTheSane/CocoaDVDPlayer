//
//  MyDVDErrorWrapper.h
//  CocoaDVDPlayer
//
//  Created by C.W. Betts on 3/30/26.
//

#import <Foundation/Foundation.h>
#import <DVDPlayback/DVDPlayback.h>


#ifndef MyDVD_ERROR_ENUM
#if ((__cplusplus && __cplusplus >= 201103L && (__has_extension(cxx_strong_enums) || __has_feature(objc_fixed_enum))) || (!__cplusplus && __has_feature(objc_fixed_enum))) && __has_attribute(ns_error_domain)
#define MyDVD_ERROR_ENUM(_domain, _name)     enum _name : OSStatus _name; enum __attribute__((ns_error_domain(_domain))) _name : OSStatus
#else
#define MyDVD_ERROR_ENUM(_domain, _name) NS_ENUM(OSStatus, _name)
#endif
#endif

extern NSErrorDomain const MyDVDErrorDomain;

/// DVDErrorCode - Errors returned by the framework (-70000 to -70099)
typedef MyDVD_ERROR_ENUM(MyDVDErrorDomain, MyDVDErrorCode) {
	///	Catch all error
	MyDVDErrorUnknown = kDVDErrorUnknown,
	///	There was an error initializing the playback framework
	MyDVDErrorInitializingLib = kDVDErrorInitializingLib,
	///	The playback framework has not been initialized.
	MyDVDErrorUninitializedLib = kDVDErrorUninitializedLib,
	///	action is not allowed during playback
	MyDVDErrorNotAllowedDuringPlayback = kDVDErrorNotAllowedDuringPlayback,
	///	A grafport was not set.
	MyDVDErrorUnassignedGrafPort = kDVDErrorUnassignedGrafPort,
	///	Media is already being played.
	MyDVDErrorAlreadyPlaying = kDVDErrorAlreadyPlaying,
	///	The application did not install a callback routine for fatal errors returned by the framework.
	MyDVDErrorNoFatalErrCallBack = kDVDErrorNoFatalErrCallBack,
	///	The framework has already been notified to sleep.
	MyDVDErrorIsAlreadySleeping = kDVDErrorIsAlreadySleeping,
	///	DVDWakeUp was called when the framework was not asleep.
	MyDVDErrorDontNeedWakeup = kDVDErrorDontNeedWakeup,
	///	Time code is outside the valid range for the current title.
	MyDVDErrorTimeOutOfRange = kDVDErrorTimeOutOfRange,
	///	The operation was not allowed by the media at this time.
	MyDVDErrorUserActionNoOp = kDVDErrorUserActionNoOp,
	///	The DVD drive is not available.
	MyDVDErrorMissingDrive = kDVDErrorMissingDrive,
	///	The current system configuration is not supported.
	MyDVDErrorNotSupportedConfiguration = kDVDErrorNotSupportedConfiguration,
	///	The operation is not supported. For example, trying to slow mo backwards.
	MyDVDErrorNotSupportedFunction = kDVDErrorNotSupportedFunction,
	///	The media was not valid for playback.
	MyDVDErrorNoValidMedia = kDVDErrorNoValidMedia,
	///	The invalid parameter was passed.
	MyDVDErrorWrongParam = kDVDErrorWrongParam,
	///	A valid graphics device is not available.
	MyDVDErrorMissingGraphicsDevice = kDVDErrorMissingGraphicsDevice,
	///	A graphics device error was encountered.
	MyDVDErrorGraphicsDevice = kDVDErrorGraphicsDevice,
	///	The framework is already open (probably by another process).
	MyDVDErrorPlaybackOpen = kDVDErrorPlaybackOpen,
	///	The region code was not valid.
	MyDVDErrorInvalidRegionCode = kDVDErrorInvalidRegionCode,
	///	The region manager was not properly installed or missing from the system.
	MyDVDErrorRgnMgrInstall = kDVDErrorRgnMgrInstall,
	///	The disc region code and the drive region code do not match.
	MyDVDErrorMismatchedRegionCode = kDVDErrorMismatchedRegionCode,
	///	The drive does not have any region changes left.
	MyDVDErrorNoMoreRegionSets = kDVDErrorNoMoreRegionSets,
	///	The drive region code was not initialized.
	MyDVDErrordRegionCodeUninitialized = kDVDErrordRegionCodeUninitialized,
	///	The user attempting to change the region code could not be authenticated.
	MyDVDErrorAuthentification = kDVDErrorAuthentification,
	///	The video driver does not have enough video memory available to playback the media.
	MyDVDErrorOutOfVideoMemory = kDVDErrorOutOfVideoMemory,
	///	An appropriate audio output device could not be found.
	MyDVDErrorNoAudioOutputDevice = kDVDErrorNoAudioOutputDevice,
	///	A system error was encountered.
	MyDVDErrorSystem = kDVDErrorSystem,
	///	The user has made a selection not supported in the current menu.
	MyDVDErrorNavigation = kDVDErrorNavigation,
	///	invalid bookmark version
	MyDVDErrorInvalidBookmarkVersion = kDVDErrorInvalidBookmarkVersion,
	///	invalid bookmark size
	MyDVDErrorInvalidBookmarkSize = kDVDErrorInvalidBookmarkSize,
	///	invalid bookmark for media
	MyDVDErrorInvalidBookmarkForMedia = kDVDErrorInvalidBookmarkForMedia,
	///	no valid last play bookmark
	MyDVDErrorNoValidBookmarkForLastPlay = kDVDErrorNoValidBookmarkForLastPlay,
	///	invalid display authentication: e.g. HDCP failure, ...
	MyDVDErrorDisplayAuthentification = kDVDErrorDisplayAuthentification,
};
