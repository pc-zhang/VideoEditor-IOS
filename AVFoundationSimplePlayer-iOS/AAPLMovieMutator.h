/*
	Copyright (C) 2015 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	'AAPLMovieMutator' wraps AVMutableMovie to implement cut, copy, and paste and provides an interface for interacting with the AVMutableMovie. This class uses an AVMutableMovie as an internal pasteboard to keep track of edits, and this class uses the general NSPasteboard to move movie header data to other documents.
 */

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

static NSString* const movieWasMutated = @"movieWasMutatedNotificationName";
typedef void (^ImageGenerationCompletionHandler)(UIImage *);

@interface AAPLMovieMutator : NSObject

- (instancetype)initWithMovie:(AVAsset *)movie;
- (AVPlayerItem *)makePlayerItem;
- (AVVideoComposition *)makeVideoComposition;
- (BOOL)cutTimeRange:(CMTimeRange)range error:(NSError *)error;
- (BOOL)copyTimeRange:(CMTimeRange)range error:(NSError *)error;
- (BOOL)pasteAtTime:(CMTime)time error:(NSError *)error;
- (void)generateImages:(NSUInteger)numberOfImages withCompletionHandler:(ImageGenerationCompletionHandler)completionHandler;
- (CMTime)timePercentageThroughMovie:(float)percentage;
- (BOOL)writeMovieToURL:(NSURL *)outputURL fileType:(NSString *)fileType error:(NSError *)error;

@end
