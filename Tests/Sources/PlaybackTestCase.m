//
//  Copyright (c) SRG SSR. All rights reserved.
//
//  License information is available from the LICENSE file.
//

#import "MediaPlayerBaseTestCase.h"
#import "TestMacros.h"
#import "XCTestCase+MediaPlayerTests.h"

#import <libextobjc/libextobjc.h>
#import <MAKVONotificationCenter/MAKVONotificationCenter.h>
#import <SRGMediaPlayer/SRGMediaPlayer.h>
#import <XCTest/XCTest.h>

static NSURL *OnDemandTestURL(void)
{
    return [NSURL URLWithString:@"http://devimages.apple.com.edgekey.net/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8"];
}

static NSURL *ShortNonStreamedTestURL(void)
{
    return [NSURL URLWithString:@"http://techslides.com/demos/sample-videos/small.mp4"];
}

static NSURL *LiveTestURL(void)
{
    return [NSURL URLWithString:@"http://tagesschau-lh.akamaihd.net/i/tagesschau_1@119231/master.m3u8?dw=0"];
}

static NSURL *DVRTestURL(void)
{
    return [NSURL URLWithString:@"http://tagesschau-lh.akamaihd.net/i/tagesschau_1@119231/master.m3u8"];
}

static NSURL *AudioOverHTTPTestURL(void)
{
    return [NSURL URLWithString:@"https://rtsww-a-d.rts.ch/la-1ere/programmes/c-est-pas-trop-tot/2017/c-est-pas-trop-tot_20170628_full_c-est-pas-trop-tot_007d77e7-61fb-4aef-9491-5e6b07f7f931-128k.mp3"];
}

@interface PlaybackTestCase : MediaPlayerBaseTestCase

@property (nonatomic) SRGMediaPlayerController *mediaPlayerController;

@end

@implementation PlaybackTestCase

#pragma mark Setup and teardown

- (void)setUp
{
    self.mediaPlayerController = [[SRGMediaPlayerController alloc] init];
}

- (void)tearDown
{
    // Always ensure the player gets deallocated between tests
    [self.mediaPlayerController reset];
    self.mediaPlayerController = nil;
}

#pragma mark Tests

- (void)testDeallocationWhileIdle
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-unsafe-retained-assign"
    __weak SRGMediaPlayerController *weakMediaPlayerController = self.mediaPlayerController;
    
    // Do not retain the controller anymore, and force an autorelease pool collection. The weak reference must be nilled
    // automatically if the controller is correctly deallocated
    @autoreleasepool {
        self.mediaPlayerController = nil;
    }
    
    XCTAssertNil(weakMediaPlayerController);
#pragma clang diagnostic pop
}

- (void)testDeallocationWhilePlaying
{
    // If the player controller is not retained, its player and all associated resources (including the player layer) must
    // be automatically discarded
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-unsafe-retained-assign"
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    __weak SRGMediaPlayerController *weakMediaPlayerController = self.mediaPlayerController;
    [self.mediaPlayerController playURL:OnDemandTestURL()];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // When no reference retains the player, playback must gracefully stop. Deallocation will occur right afterwards.
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStateIdle;
    }];
    
    // Ensure the player is correctly deallocated
    __weak AVPlayer *weakPlayer = self.mediaPlayerController.player;
    [self expectationForPredicate:[NSPredicate predicateWithBlock:^BOOL(id _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
        return weakPlayer == nil;
    }] evaluatedWithObject:self /* unused, but a non-nil argument is required  */ handler:nil];
    
    // Do not retain the controller anymore, and force an autorelease pool collection. The weak reference must be nilled
    // automatically if the controller is correctly deallocated
    @autoreleasepool {
        self.mediaPlayerController = nil;
    }
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    XCTAssertNil(weakMediaPlayerController);
#pragma clang diagnostic pop
}

- (void)testInitialPlayerState
{
    SRGMediaPlayerController *mediaPlayerController = [[SRGMediaPlayerController alloc] init];
    XCTAssertEqual(mediaPlayerController.playbackState, SRGMediaPlayerPlaybackStateIdle);
    TestAssertIndefiniteTime(mediaPlayerController.seekStartTime);
    TestAssertIndefiniteTime(mediaPlayerController.seekTargetTime);
}

- (void)testPrepare
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePreparing);
        XCTAssertFalse([notification.userInfo[SRGMediaPlayerSelectedKey] boolValue]);
        return YES;
    }];
    
    [self.mediaPlayerController prepareToPlayURL:OnDemandTestURL() atTime:kCMTimeZero withSegments:nil userInfo:nil completionHandler:^{
        // Upon completion handler entry, the state is always preparing
        XCTAssertEqual(self.mediaPlayerController.playbackState, SRGMediaPlayerPlaybackStatePreparing);
    }];
    
    TestAssertIndefiniteTime(self.mediaPlayerController.seekStartTime);
    TestAssertIndefiniteTime(self.mediaPlayerController.seekTargetTime);
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // After completion handler execution, the player state is updated. Since nothing is done in the completion handler,
    // the player must be paused
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        // Check the next notification
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePaused);
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPreviousPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePreparing);
        XCTAssertFalse([notification.userInfo[SRGMediaPlayerSelectedKey] boolValue]);
        return YES;
    }];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testPrepareAndPlay
{
    XCTestExpectation *preparationExpectation = [self expectationWithDescription:@"Playing"];
    
    [self.mediaPlayerController prepareToPlayURL:OnDemandTestURL() atTime:kCMTimeZero withSegments:nil userInfo:nil completionHandler:^{
        // Upon completion handler entry, the state is always preparing
        XCTAssertEqual(self.mediaPlayerController.playbackState, SRGMediaPlayerPlaybackStatePreparing);
        
        // If we now play, the player must immediately be in the playing state
        [self.mediaPlayerController play];
        XCTAssertEqual(self.mediaPlayerController.playbackState, SRGMediaPlayerPlaybackStatePlaying);
        
        [preparationExpectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testMultiplePrepare
{
    [self.mediaPlayerController prepareToPlayURL:OnDemandTestURL() atTime:kCMTimeZero withSegments:nil userInfo:nil completionHandler:^{
        XCTFail(@"The completion handler must not be called since a second prepare must cancel the first");
    }];
    
    XCTestExpectation *preparationExpectation = [self expectationWithDescription:@"Prepared"];
    
    [self.mediaPlayerController prepareToPlayURL:OnDemandTestURL() atTime:kCMTimeZero withSegments:nil userInfo:nil completionHandler:^{
        XCTAssertEqual(self.mediaPlayerController.playbackState, SRGMediaPlayerPlaybackStatePreparing);
        [preparationExpectation fulfill];
    }];
    
   [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testWithoutPrepare
{
    // Playing does not alter the state of the player since it has not been prepared
    [self.mediaPlayerController play];
    XCTAssertEqual(self.mediaPlayerController.playbackState, SRGMediaPlayerPlaybackStateIdle);
}

- (void)testPrepareToTimeOutsideMedia
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePreparing);
        XCTAssertFalse([notification.userInfo[SRGMediaPlayerSelectedKey] boolValue]);
        return YES;
    }];
    
    [self.mediaPlayerController prepareToPlayURL:OnDemandTestURL() atTime:CMTimeMakeWithSeconds(24. * 60. * 60., NSEC_PER_SEC) withSegments:nil userInfo:nil completionHandler:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // After completion handler execution, the player state is updated. Since nothing is done in the completion handler,
    // the player must be paused
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePaused);
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPreviousPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePreparing);
        XCTAssertFalse([notification.userInfo[SRGMediaPlayerSelectedKey] boolValue]);
        return YES;
    }];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testPlay
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePreparing);
        XCTAssertFalse([notification.userInfo[SRGMediaPlayerSelectedKey] boolValue]);
        return YES;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL()];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        // The player must have transitioned directly to the playing state without going through the paused state
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePlaying);
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPreviousPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePreparing);
        XCTAssertFalse([notification.userInfo[SRGMediaPlayerSelectedKey] boolValue]);
        return YES;
    }];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testOnDemandPlaybackStartAtTime
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL() atTime:CMTimeMakeWithSeconds(20., NSEC_PER_SEC) withSegments:nil userInfo:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // Check we started at the specified location
    XCTAssertTrue(CMTIME_COMPARE_INLINE(self.mediaPlayerController.currentTime, ==, CMTimeMakeWithSeconds(20., NSEC_PER_SEC)));
}

- (void)testDVRPlaybackDefaultStart
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:DVRTestURL() atTime:kCMTimeZero withSegments:nil userInfo:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // Check we started near the end
    XCTAssertTrue(CMTIME_COMPARE_INLINE(self.mediaPlayerController.currentTime, >, CMTimeSubtract(self.mediaPlayerController.currentTime, CMTimeMakeWithSeconds(60., NSEC_PER_SEC))));
}

- (void)testDVRPlaybackStartAtTime
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:DVRTestURL() atTime:CMTimeMakeWithSeconds(20., NSEC_PER_SEC) withSegments:nil userInfo:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // Check we started at the specified location
    XCTAssertTrue(CMTIME_COMPARE_INLINE(self.mediaPlayerController.currentTime, ==, CMTimeMakeWithSeconds(20., NSEC_PER_SEC)));
}

- (void)testVideoTrackInLastPosition
{
    // The video track is not always located first in the tracks list.
    [self expectationForPredicate:[NSPredicate predicateWithBlock:^BOOL(SRGMediaPlayerController * _Nullable mediaPlayerController, NSDictionary<NSString *,id> * _Nullable bindings) {
        return mediaPlayerController.mediaType != SRGMediaPlayerMediaTypeUnknown;
    }] evaluatedWithObject:self.mediaPlayerController handler:nil];
    
    [self.mediaPlayerController playURL:[NSURL URLWithString:@"http://download.blender.org/peach/bigbuckbunny_movies/BigBuckBunny_640x360.m4v"]];
    
    [self waitForExpectationsWithTimeout:40. handler:nil];
    
    XCTAssertEqual(self.mediaPlayerController.mediaType, SRGMediaPlayerMediaTypeVideo);
}

- (void)testLiveAACPlayback
{
    [self expectationForPredicate:[NSPredicate predicateWithBlock:^BOOL(SRGMediaPlayerController * _Nullable mediaPlayerController, NSDictionary<NSString *,id> * _Nullable bindings) {
        return mediaPlayerController.streamType != SRGMediaPlayerStreamTypeUnknown;
    }] evaluatedWithObject:self.mediaPlayerController handler:nil];
    
    [self.mediaPlayerController playURL:[NSURL URLWithString:@"http://stream.srg-ssr.ch/m/la-1ere/aacp_96"]];
    
    [self waitForExpectationsWithTimeout:40. handler:nil];
    
    XCTAssertEqual(self.mediaPlayerController.streamType, SRGMediaPlayerStreamTypeLive);
}

- (void)testHTTPAudioPlay
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePreparing);
        XCTAssertFalse([notification.userInfo[SRGMediaPlayerSelectedKey] boolValue]);
        return YES;
    }];
    
    [self.mediaPlayerController playURL:AudioOverHTTPTestURL()];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        // The player must have transitioned directly to the playing state without going through the paused state
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePlaying);
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPreviousPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePreparing);
        XCTAssertFalse([notification.userInfo[SRGMediaPlayerSelectedKey] boolValue]);
        return YES;
    }];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testFastPlayPausePlay
{
    // Play the media. Two events expected: Preparing and playing
    __block NSInteger count1 = 0;
    id eventObserver1 = [[NSNotificationCenter defaultCenter] addObserverForName:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        ++count1;
    }];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL()];
    
    [self waitForExpectationsWithTimeout:30. handler:^(NSError * _Nullable error) {
        [[NSNotificationCenter defaultCenter] removeObserver:eventObserver1];
    }];
    
    // Two events expected: preparing and playing
    XCTAssertEqual(count1, 2);

    __block NSInteger count2 = 0;
    id eventObserver2 = [[NSNotificationCenter defaultCenter] addObserverForName:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        ++count2;
    }];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePaused;
    }];
    
    [self.mediaPlayerController pause];
    
    [self waitForExpectationsWithTimeout:30. handler:^(NSError * _Nullable error) {
        [[NSNotificationCenter defaultCenter] removeObserver:eventObserver2];
    }];
    
    // One event expected: paused
    XCTAssertEqual(count2, 1);
    
    __block NSInteger count3 = 0;
    id eventObserver3 = [[NSNotificationCenter defaultCenter] addObserverForName:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        ++count3;
    }];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController play];
    
    [self waitForExpectationsWithTimeout:30. handler:^(NSError * _Nullable error) {
        [[NSNotificationCenter defaultCenter] removeObserver:eventObserver3];
    }];
    
    // One event expected: playing
    XCTAssertEqual(count3, 1);
    
    [self expectationForElapsedTimeInterval:3. withHandler:nil];
    
    id eventObserver4 = [[NSNotificationCenter defaultCenter] addObserverForName:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        // Also see http://stackoverflow.com/questions/14565405/avplayer-pauses-for-no-obvious-reason and
        // the demo project https://github.com/defagos/radars/tree/master/unexpected-player-rate-changes
        NSLog(@"[AVPlayer probable bug]: Unexpected state change to %@. Fast play - pause sequences can induce unexpected rate changes "
              "captured via KVO in our implementation. Those changes do not harm but cannot be tested reliably", @(self.mediaPlayerController.playbackState));
    }];
    
    [self waitForExpectationsWithTimeout:30. handler:^(NSError * _Nullable error) {
        [[NSNotificationCenter defaultCenter] removeObserver:eventObserver4];
    }];
}

- (void)testFastPlaySeek
{
    // Play the media. Two events expected: Preparing and playing
    __block NSInteger count1 = 0;
    id eventObserver1 = [[NSNotificationCenter defaultCenter] addObserverForName:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        ++count1;
    }];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        if ([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying) {
            TestAssertEqualTimeInSeconds(self.mediaPlayerController.currentTime, 0);
            return YES;
        }
        else {
            return NO;
        }
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL()];
    
    [self waitForExpectationsWithTimeout:30. handler:^(NSError * _Nullable error) {
        [[NSNotificationCenter defaultCenter] removeObserver:eventObserver1];
    }];
    
    TestAssertIndefiniteTime(self.mediaPlayerController.seekStartTime);
    TestAssertIndefiniteTime(self.mediaPlayerController.seekTargetTime);
    
    // Two events expected: preparing and playing
    XCTAssertEqual(count1, 2);
    
    __block NSInteger count2 = 0;
    id eventObserver2 = [[NSNotificationCenter defaultCenter] addObserverForName:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        ++count2;
    }];
    
    __block BOOL seekReceived = NO;
    __block BOOL playReceived = NO;
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        if ([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStateSeeking) {
            XCTAssertFalse(seekReceived);
            XCTAssertFalse(playReceived);
            TestAssertEqualTimeInSeconds(self.mediaPlayerController.currentTime, 0);
            seekReceived = YES;
        }
        else if ([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying) {
            XCTAssertFalse(playReceived);
            TestAssertEqualTimeInSeconds(self.mediaPlayerController.currentTime, 2);
            playReceived = YES;
        }
        
        return seekReceived && playReceived;
    }];
    
    [self.mediaPlayerController seekPreciselyToTime:CMTimeMakeWithSeconds(2., NSEC_PER_SEC) withCompletionHandler:nil];
    
    TestAssertEqualTimeInSeconds(self.mediaPlayerController.seekStartTime, 0);
    TestAssertEqualTimeInSeconds(self.mediaPlayerController.seekTargetTime, 2);
    
    [self waitForExpectationsWithTimeout:30. handler:^(NSError * _Nullable error) {
        [[NSNotificationCenter defaultCenter] removeObserver:eventObserver2];
    }];
    
    TestAssertIndefiniteTime(self.mediaPlayerController.seekStartTime);
    TestAssertIndefiniteTime(self.mediaPlayerController.seekTargetTime);
    
    // Two events expected: seek and play
    XCTAssertEqual(count2, 2);
    
    [self expectationForElapsedTimeInterval:3. withHandler:nil];
    
    id eventObserver3 = [[NSNotificationCenter defaultCenter] addObserverForName:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        // Also see http://stackoverflow.com/questions/14565405/avplayer-pauses-for-no-obvious-reason and
        // the demo project https://github.com/defagos/radars/tree/master/unexpected-player-rate-changes
        NSLog(@"[AVPlayer probable bug]: Unexpected state change to %@. Fast play - pause sequences can induce unexpected rate changes "
              "captured via KVO in our implementation. Those changes do not harm but cannot be tested reliably", @(self.mediaPlayerController.playbackState));
    }];
    
    [self waitForExpectationsWithTimeout:30. handler:^(NSError * _Nullable error) {
        [[NSNotificationCenter defaultCenter] removeObserver:eventObserver3];
    }];
}

- (void)testFastPlayPauseSeek
{
    // Play the media. Two events expected: Preparing and playing
    __block NSInteger count1 = 0;
    id eventObserver1 = [[NSNotificationCenter defaultCenter] addObserverForName:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        ++count1;
    }];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        if ([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying) {
            TestAssertEqualTimeInSeconds(self.mediaPlayerController.currentTime, 0);
            return YES;
        }
        else {
            return NO;
        }
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL()];
    
    [self waitForExpectationsWithTimeout:30. handler:^(NSError * _Nullable error) {
        [[NSNotificationCenter defaultCenter] removeObserver:eventObserver1];
    }];
    
    TestAssertIndefiniteTime(self.mediaPlayerController.seekStartTime);
    TestAssertIndefiniteTime(self.mediaPlayerController.seekTargetTime);
    
    // Two events expected: preparing and playing
    XCTAssertEqual(count1, 2);
    
    __block NSInteger count2 = 0;
    id eventObserver2 = [[NSNotificationCenter defaultCenter] addObserverForName:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        ++count2;
    }];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePaused;
    }];
    
    [self.mediaPlayerController pause];
    
    [self waitForExpectationsWithTimeout:30. handler:^(NSError * _Nullable error) {
        [[NSNotificationCenter defaultCenter] removeObserver:eventObserver2];
    }];
    
    TestAssertIndefiniteTime(self.mediaPlayerController.seekStartTime);
    TestAssertIndefiniteTime(self.mediaPlayerController.seekTargetTime);
    
    // One event expected: paused
    XCTAssertEqual(count2, 1);
    
    __block NSInteger count3 = 0;
    id eventObserver3 = [[NSNotificationCenter defaultCenter] addObserverForName:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        ++count3;
    }];
    
    __block BOOL seekReceived = NO;
    __block BOOL pauseReceived = NO;
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        SRGMediaPlayerPlaybackState playerPlaybackState = [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue];
        if (playerPlaybackState == SRGMediaPlayerPlaybackStateSeeking) {
            XCTAssertFalse(seekReceived);
            XCTAssertFalse(pauseReceived);
            TestAssertEqualTimeInSeconds(self.mediaPlayerController.currentTime, 0);
            seekReceived = YES;
        }
        else if (playerPlaybackState == SRGMediaPlayerPlaybackStatePaused) {
            XCTAssertFalse(pauseReceived);
            TestAssertEqualTimeInSeconds(self.mediaPlayerController.currentTime, 2);
            pauseReceived = YES;
        }
        else {
            XCTFail(@"Unexpected playback state %@", @(playerPlaybackState));
        }
        
        return seekReceived && pauseReceived;
    }];
    
    [self.mediaPlayerController seekEfficientlyToTime:CMTimeMakeWithSeconds(2., NSEC_PER_SEC) withCompletionHandler:nil];
    
    TestAssertEqualTimeInSeconds(self.mediaPlayerController.seekStartTime, 0);
    TestAssertEqualTimeInSeconds(self.mediaPlayerController.seekTargetTime, 2);
    
    [self waitForExpectationsWithTimeout:30. handler:^(NSError * _Nullable error) {
        [[NSNotificationCenter defaultCenter] removeObserver:eventObserver3];
    }];
    
    TestAssertIndefiniteTime(self.mediaPlayerController.seekStartTime);
    TestAssertIndefiniteTime(self.mediaPlayerController.seekTargetTime);
    
    // Two events expected: seek and pause
    XCTAssertEqual(count3, 2);
    
    [self expectationForElapsedTimeInterval:3. withHandler:nil];
    
    id eventObserver4 = [[NSNotificationCenter defaultCenter] addObserverForName:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        // Also see http://stackoverflow.com/questions/14565405/avplayer-pauses-for-no-obvious-reason and
        // the demo project https://github.com/defagos/radars/tree/master/unexpected-player-rate-changes
        NSLog(@"[AVPlayer probable bug]: Unexpected state change to %@. Fast play - pause sequences can induce unexpected rate changes "
              "captured via KVO in our implementation. Those changes do not harm but cannot be tested reliably", @(self.mediaPlayerController.playbackState));
    }];
    
    [self waitForExpectationsWithTimeout:30. handler:^(NSError * _Nullable error) {
        [[NSNotificationCenter defaultCenter] removeObserver:eventObserver4];
    }];
}

- (void)testStreamedMediaPlaythrough
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePreparing);
        XCTAssertFalse([notification.userInfo[SRGMediaPlayerSelectedKey] boolValue]);
        return YES;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL()];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePlaying);
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPreviousPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePreparing);
        XCTAssertFalse([notification.userInfo[SRGMediaPlayerSelectedKey] boolValue]);
        return YES;
    }];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // Seek to the end (media is too long to be entirely played through :) )
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController seekEfficientlyToTime:CMTimeSubtract(CMTimeRangeGetEnd(self.mediaPlayerController.timeRange), CMTimeMake(3., NSEC_PER_SEC)) withCompletionHandler:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStateEnded);
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPreviousPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePlaying);
        XCTAssertFalse([notification.userInfo[SRGMediaPlayerSelectedKey] boolValue]);
        return YES;
    }];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testNonStreamedMediaPlaythrough
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePreparing);
        XCTAssertFalse([notification.userInfo[SRGMediaPlayerSelectedKey] boolValue]);
        return YES;
    }];
    
    [self.mediaPlayerController playURL:ShortNonStreamedTestURL()];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePlaying);
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPreviousPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePreparing);
        XCTAssertFalse([notification.userInfo[SRGMediaPlayerSelectedKey] boolValue]);
        return YES;
    }];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStateEnded);
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPreviousPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePlaying);
        XCTAssertFalse([notification.userInfo[SRGMediaPlayerSelectedKey] boolValue]);
        return YES;
    }];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testPlayAtStreamEnd
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL()];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // Seek to the end (media is too long to be entirely played through :) ) and wait until playback ends
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStateEnded;
    }];
    
    [self.mediaPlayerController seekEfficientlyToTime:CMTimeSubtract(CMTimeRangeGetEnd(self.mediaPlayerController.timeRange), CMTimeMake(3., NSEC_PER_SEC)) withCompletionHandler:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // Play at the end. Expect restart at the beginning of the stream with no seek events
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePlaying);
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPreviousPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStateEnded);
        return YES;
    }];
    
    [self.mediaPlayerController play];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testPauseAtStreamEnd
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL()];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // Seek to the end (media is too long to be entirely played through :) ) and wait until playback ends
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStateEnded;
    }];
    
    [self.mediaPlayerController seekEfficientlyToTime:CMTimeSubtract(CMTimeRangeGetEnd(self.mediaPlayerController.timeRange), CMTimeMake(3., NSEC_PER_SEC)) withCompletionHandler:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    id eventObserver = [[NSNotificationCenter defaultCenter] addObserverForName:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        XCTFail(@"Pausing when the stream already ended must be a no-op");
    }];
    
    // Pause at the end. Nothing must happen, the player has already a rate of 0
    [self expectationForElapsedTimeInterval:3. withHandler:nil];
    
    [self.mediaPlayerController pause];
    
    [self waitForExpectationsWithTimeout:30. handler:^(NSError * _Nullable error) {
        [[NSNotificationCenter defaultCenter] removeObserver:eventObserver];
    }];
}

- (void)testLivePause
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:LiveTestURL()];
    
    [self waitForExpectationsWithTimeout:20. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePaused);
        XCTAssertFalse([notification.userInfo[SRGMediaPlayerSelectedKey] boolValue]);
        return YES;
    }];
    
    [self.mediaPlayerController pause];
    
    [self waitForExpectationsWithTimeout:20. handler:nil];
}

- (void)testMediaInformationWhenPreparingToPlay
{
    XCTAssertEqual(self.mediaPlayerController.mediaType, SRGMediaPlayerMediaTypeUnknown);
    XCTAssertEqual(self.mediaPlayerController.streamType, SRGMediaPlayerStreamTypeUnknown);
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePreparing);
        XCTAssertEqual(self.mediaPlayerController.mediaType, SRGMediaPlayerMediaTypeUnknown);
        XCTAssertEqual(self.mediaPlayerController.streamType, SRGMediaPlayerStreamTypeUnknown);
        return YES;
    }];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Prepared"];
    
    [self.mediaPlayerController prepareToPlayURL:OnDemandTestURL() atTime:kCMTimeZero withSegments:nil userInfo:nil completionHandler:^{
        XCTAssertEqual(self.mediaPlayerController.mediaType, SRGMediaPlayerMediaTypeVideo);
        XCTAssertEqual(self.mediaPlayerController.streamType, SRGMediaPlayerStreamTypeOnDemand);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testOnDemandProperties
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL()];
    
    [self waitForExpectationsWithTimeout:20. handler:nil];
    
    XCTAssertEqual(self.mediaPlayerController.streamType, SRGMediaPlayerStreamTypeOnDemand);
    XCTAssertFalse(self.mediaPlayerController.live);
    XCTAssertNil(self.mediaPlayerController.date);
}

- (void)testLiveProperties
{
    [self expectationForPredicate:[NSPredicate predicateWithBlock:^BOOL(SRGMediaPlayerController * _Nullable mediaPlayerController, NSDictionary<NSString *,id> * _Nullable bindings) {
        return mediaPlayerController.streamType != SRGMediaPlayerStreamTypeUnknown;
    }] evaluatedWithObject:self.mediaPlayerController handler:nil];
    
    [self.mediaPlayerController playURL:LiveTestURL()];
    
    [self waitForExpectationsWithTimeout:20. handler:nil];
    
    XCTAssertEqual(self.mediaPlayerController.streamType, SRGMediaPlayerStreamTypeLive);
    XCTAssertTrue(self.mediaPlayerController.live);
    XCTAssertTrue([[NSDate date] timeIntervalSinceDate:self.mediaPlayerController.date] < 0.1);
}

- (void)testDVRProperties
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:DVRTestURL()];
    
    [self waitForExpectationsWithTimeout:20. handler:nil];
    
    XCTAssertEqual(self.mediaPlayerController.streamType, SRGMediaPlayerStreamTypeDVR);
    XCTAssertTrue(self.mediaPlayerController.live);
    XCTAssertNotNil(self.mediaPlayerController.date);
    
    // Seek 10 seconds in the past. The default live tolerance is 30 seconds, we still must be in live conditions
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController seekPreciselyToTime:CMTimeSubtract(CMTimeRangeGetEnd(self.mediaPlayerController.timeRange), CMTimeMakeWithSeconds(10., NSEC_PER_SEC)) withCompletionHandler:nil];
    
    [self waitForExpectationsWithTimeout:20. handler:nil];
    
    XCTAssertTrue(self.mediaPlayerController.live);
    XCTAssertTrue([[NSDate date] timeIntervalSinceDate:self.mediaPlayerController.date] > 8);
    
    // Seek 40 seconds in the past. We now are outside the tolerance and therefore not live anymore
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController seekPreciselyToTime:CMTimeSubtract(CMTimeRangeGetEnd(self.mediaPlayerController.timeRange), CMTimeMakeWithSeconds(40., NSEC_PER_SEC)) withCompletionHandler:nil];
    
    [self waitForExpectationsWithTimeout:20. handler:nil];
    
    XCTAssertFalse(self.mediaPlayerController.live);
    XCTAssertTrue([[NSDate date] timeIntervalSinceDate:self.mediaPlayerController.date] > 38);
}

- (void)testLiveTolerance
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    self.mediaPlayerController.liveTolerance = 50.;
    [self.mediaPlayerController playURL:DVRTestURL()];
    
    [self waitForExpectationsWithTimeout:20. handler:nil];
    
    XCTAssertEqual(self.mediaPlayerController.streamType, SRGMediaPlayerStreamTypeDVR);
    XCTAssertTrue(self.mediaPlayerController.live);
    
    // Seek 40 seconds in the past. The live tolerance has been set to 50 seconds, we still must be live
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController seekPreciselyToTime:CMTimeSubtract(CMTimeRangeGetEnd(self.mediaPlayerController.timeRange), CMTimeMakeWithSeconds(10., NSEC_PER_SEC)) withCompletionHandler:nil];
    
    [self waitForExpectationsWithTimeout:20. handler:nil];
    
    XCTAssertTrue(self.mediaPlayerController.live);
    
    // Seek 60 seconds in the past. We now are outside the tolerance and therefore not live anymore
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController seekPreciselyToTime:CMTimeSubtract(CMTimeRangeGetEnd(self.mediaPlayerController.timeRange), CMTimeMakeWithSeconds(60., NSEC_PER_SEC)) withCompletionHandler:nil];
    
    [self waitForExpectationsWithTimeout:20. handler:nil];
    
    XCTAssertFalse(self.mediaPlayerController.live);
}

- (void)testMinimumDVRWindowLength
{
    // Use an extremeley long window length to be sure it is far greater than the stream length (which could vary since
    // it is not managed by us)
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    self.mediaPlayerController.minimumDVRWindowLength = 24. * 60. * 60.;
    [self.mediaPlayerController playURL:DVRTestURL()];
    
    [self waitForExpectationsWithTimeout:20. handler:nil];
    
    XCTAssertEqual(self.mediaPlayerController.streamType, SRGMediaPlayerStreamTypeLive);
    XCTAssertTrue(self.mediaPlayerController.live);
}

- (void)testPlayWithHTTP403Error
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackDidFailNotification object:self.mediaPlayerController handler:^BOOL (NSNotification *notification) {
        NSError *error = notification.userInfo[SRGMediaPlayerErrorKey];
        XCTAssertEqualObjects(error.domain, SRGMediaPlayerErrorDomain);
        XCTAssertEqual(error.code, SRGMediaPlayerErrorPlayback);
        XCTAssertEqual(self.mediaPlayerController.playbackState, SRGMediaPlayerPlaybackStateIdle);
        XCTAssertFalse([notification.userInfo[SRGMediaPlayerSelectedKey] boolValue]);
        return YES;
    }];
  
    [self.mediaPlayerController playURL:[NSURL URLWithString:@"http://httpbin.org/status/403"]];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testPrepareWithHTTP404Error
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackDidFailNotification object:self.mediaPlayerController handler:^BOOL (NSNotification *notification) {
        NSError *error = notification.userInfo[SRGMediaPlayerErrorKey];
        XCTAssertEqualObjects(error.domain, SRGMediaPlayerErrorDomain);
        XCTAssertEqual(error.code, SRGMediaPlayerErrorPlayback);
        XCTAssertEqual(self.mediaPlayerController.playbackState, SRGMediaPlayerPlaybackStateIdle);
        XCTAssertFalse([notification.userInfo[SRGMediaPlayerSelectedKey] boolValue]);
        return YES;
    }];
    
    NSURL *URL = [NSURL URLWithString:@"http://httpbin.org/status/404"];
    [self.mediaPlayerController prepareToPlayURL:URL atTime:kCMTimeZero withSegments:nil userInfo:nil completionHandler:^{
        XCTFail(@"The completion handler must not be called when the media could not be loaded");
    }];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testSeekWhilePaused
{
    XCTestExpectation *seekFinishedExpectation = [self expectationWithDescription:@"Seek finished"];
    
    // Wait until the player is in the paused state to seek
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        if ([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] != SRGMediaPlayerPlaybackStatePaused) {
            return NO;
        }
        
        TestAssertIndefiniteTime(self.mediaPlayerController.seekStartTime);
        TestAssertIndefiniteTime(self.mediaPlayerController.seekTargetTime);
        
        [self.mediaPlayerController seekToTime:CMTimeMakeWithSeconds(30., NSEC_PER_SEC) withToleranceBefore:kCMTimePositiveInfinity toleranceAfter:kCMTimePositiveInfinity completionHandler:^(BOOL finished) {
            // No seek could have interrupted this one
            XCTAssertTrue(finished);
            
            // The player must still be paused after the seek
            XCTAssertEqual(self.mediaPlayerController.playbackState, SRGMediaPlayerPlaybackStatePaused);
            
            TestAssertIndefiniteTime(self.mediaPlayerController.seekStartTime);
            TestAssertIndefiniteTime(self.mediaPlayerController.seekTargetTime);
            [seekFinishedExpectation fulfill];
        }];
        
        TestAssertEqualTimeInSeconds(self.mediaPlayerController.seekStartTime, 2);
        TestAssertEqualTimeInSeconds(self.mediaPlayerController.seekTargetTime, 30);
        return YES;
    }];
    
    [self.mediaPlayerController prepareToPlayURL:OnDemandTestURL() atTime:CMTimeMakeWithSeconds(2., NSEC_PER_SEC) withSegments:nil userInfo:nil completionHandler:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testSeekWhilePlaying
{
    XCTestExpectation *seekFinishedExpectation = [self expectationWithDescription:@"Seek finished"];
    
    // Wait until the player is in the playing state to seek
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        if ([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] != SRGMediaPlayerPlaybackStatePlaying) {
            return NO;
        }
        
        TestAssertIndefiniteTime(self.mediaPlayerController.seekStartTime);
        TestAssertIndefiniteTime(self.mediaPlayerController.seekTargetTime);
        
        [self.mediaPlayerController seekToTime:CMTimeMakeWithSeconds(30., NSEC_PER_SEC) withToleranceBefore:kCMTimePositiveInfinity toleranceAfter:kCMTimePositiveInfinity completionHandler:^(BOOL finished) {
            // No seek could have interrupted this one
            XCTAssertTrue(finished);
            
            // The player must still be playing after the seek
            XCTAssertEqual(self.mediaPlayerController.playbackState, SRGMediaPlayerPlaybackStatePlaying);
            
            TestAssertIndefiniteTime(self.mediaPlayerController.seekStartTime);
            TestAssertIndefiniteTime(self.mediaPlayerController.seekTargetTime);
            [seekFinishedExpectation fulfill];
        }];
        
        TestAssertEqualTimeInSeconds(self.mediaPlayerController.seekStartTime, 2);
        TestAssertEqualTimeInSeconds(self.mediaPlayerController.seekTargetTime, 30);
        return YES;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL() atTime:CMTimeMakeWithSeconds(2., NSEC_PER_SEC) withSegments:nil userInfo:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testSeekNotification
{
    // Wait until the player is in the playing state to seek
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL()];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerSeekNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual(self.mediaPlayerController.playbackState, SRGMediaPlayerPlaybackStateSeeking);
        TestAssertEqualTimeInSeconds([notification.userInfo[SRGMediaPlayerSeekTimeKey] CMTimeValue], 30);
        TestAssertEqualTimeInSeconds([notification.userInfo[SRGMediaPlayerLastPlaybackTimeKey] CMTimeValue], 0);
        return YES;
    }];
    
    [self.mediaPlayerController seekToTime:CMTimeMakeWithSeconds(30., NSEC_PER_SEC) withToleranceBefore:kCMTimePositiveInfinity toleranceAfter:kCMTimePositiveInfinity completionHandler:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testSeekWithoutPrepare
{
    [self.mediaPlayerController seekToTime:CMTimeMakeWithSeconds(30., NSEC_PER_SEC) withToleranceBefore:kCMTimePositiveInfinity toleranceAfter:kCMTimePositiveInfinity completionHandler:^(BOOL finished) {
        XCTFail(@"The completion handler must not be called since a seek must do nothing if the media was not prepared");
    }];
    XCTAssertEqual(self.mediaPlayerController.playbackState, SRGMediaPlayerPlaybackStateIdle);
    TestAssertIndefiniteTime(self.mediaPlayerController.seekStartTime);
    TestAssertIndefiniteTime(self.mediaPlayerController.seekTargetTime);
}

- (void)testSeekInterruption
{
    XCTestExpectation *seekFinishedExpectation = [self expectationWithDescription:@"Seek finished"];
    
    // Wait until the player is in the playing state to seek
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        if ([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] != SRGMediaPlayerPlaybackStatePlaying) {
            return NO;
        }
        
        TestAssertIndefiniteTime(self.mediaPlayerController.seekStartTime);
        TestAssertIndefiniteTime(self.mediaPlayerController.seekTargetTime);
        
        [self.mediaPlayerController seekToTime:CMTimeMakeWithSeconds(30., NSEC_PER_SEC) withToleranceBefore:kCMTimePositiveInfinity toleranceAfter:kCMTimePositiveInfinity completionHandler:^(BOOL finished) {
            // This seek must have been interrupted by the second one
            XCTAssertFalse(finished);
            XCTAssertEqual(self.mediaPlayerController.playbackState, SRGMediaPlayerPlaybackStateSeeking);
            
            TestAssertEqualTimeInSeconds(self.mediaPlayerController.seekStartTime, 2);
            TestAssertEqualTimeInSeconds(self.mediaPlayerController.seekTargetTime, 50);
        }];
        [self.mediaPlayerController seekToTime:CMTimeMakeWithSeconds(50., NSEC_PER_SEC) withToleranceBefore:kCMTimePositiveInfinity toleranceAfter:kCMTimePositiveInfinity completionHandler:^(BOOL finished) {
            XCTAssertTrue(finished);
            XCTAssertEqual(self.mediaPlayerController.playbackState, SRGMediaPlayerPlaybackStatePlaying);
            TestAssertIndefiniteTime(self.mediaPlayerController.seekStartTime);
            TestAssertIndefiniteTime(self.mediaPlayerController.seekTargetTime);
            
            [seekFinishedExpectation fulfill];
        }];
        
        TestAssertEqualTimeInSeconds(self.mediaPlayerController.seekStartTime, 2);
        TestAssertEqualTimeInSeconds(self.mediaPlayerController.seekTargetTime, 50);
        
        return YES;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL() atTime:CMTimeMakeWithSeconds(2., NSEC_PER_SEC) withSegments:nil userInfo:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testSharpSeekInterruption
{
    XCTestExpectation *seekFinishedExpectation = [self expectationWithDescription:@"Seek finished"];
    
    // Wait until the player is in the playing state to seek
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        if ([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] != SRGMediaPlayerPlaybackStatePlaying) {
            return NO;
        }
        
        TestAssertIndefiniteTime(self.mediaPlayerController.seekStartTime);
        TestAssertIndefiniteTime(self.mediaPlayerController.seekTargetTime);
        
        [self.mediaPlayerController seekToTime:CMTimeMakeWithSeconds(30., NSEC_PER_SEC) withToleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
            // This seek must have been interrupted by the second one
            XCTAssertFalse(finished);
            XCTAssertEqual(self.mediaPlayerController.playbackState, SRGMediaPlayerPlaybackStateSeeking);
            
            TestAssertEqualTimeInSeconds(self.mediaPlayerController.seekStartTime, 2);
            TestAssertEqualTimeInSeconds(self.mediaPlayerController.seekTargetTime, 50);
        }];
        [self.mediaPlayerController seekToTime:CMTimeMakeWithSeconds(50., NSEC_PER_SEC) withToleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
            XCTAssertTrue(finished);
            XCTAssertEqual(self.mediaPlayerController.playbackState, SRGMediaPlayerPlaybackStatePlaying);
            TestAssertIndefiniteTime(self.mediaPlayerController.seekStartTime);
            TestAssertIndefiniteTime(self.mediaPlayerController.seekTargetTime);
            
            [seekFinishedExpectation fulfill];
        }];
        
        TestAssertEqualTimeInSeconds(self.mediaPlayerController.seekStartTime, 2);
        TestAssertEqualTimeInSeconds(self.mediaPlayerController.seekTargetTime, 50);
        
        return YES;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL() atTime:CMTimeMakeWithSeconds(2., NSEC_PER_SEC) withSegments:nil userInfo:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testSeekInterruptionSeries
{
    XCTestExpectation *seekFinishedExpectation = [self expectationWithDescription:@"Seek finished"];
    
    // Wait until the player is in the playing state to seek
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        if ([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] != SRGMediaPlayerPlaybackStatePlaying) {
            return NO;
        }
        
        static const NSInteger kSeekCount = 100;
        
        __block NSInteger finishedSeekCount = 0;
        for (NSInteger i = 0; i < kSeekCount; ++i) {
            [self.mediaPlayerController seekToTime:CMTimeMakeWithSeconds(10. + i * 5., NSEC_PER_SEC) withToleranceBefore:kCMTimePositiveInfinity toleranceAfter:kCMTimePositiveInfinity completionHandler:^(BOOL finished) {
                finishedSeekCount++;
                
                if (i != kSeekCount - 1) {
                    XCTAssertFalse(finished);
                    
                    // The start time must remain constant while seeks are piling up. The end time changes and is therefore
                    // difficult to test reliably when several seeks are interrupted.
                    TestAssertEqualTimeInSeconds(self.mediaPlayerController.seekStartTime, 0);
                }
                else {
                    XCTAssertTrue(finished);
                    XCTAssertEqual(finishedSeekCount, kSeekCount);
                    TestAssertIndefiniteTime(self.mediaPlayerController.seekStartTime);
                    TestAssertIndefiniteTime(self.mediaPlayerController.seekTargetTime);
                    [seekFinishedExpectation fulfill];
                }
            }];
        }
        
        TestAssertEqualTimeInSeconds(self.mediaPlayerController.seekStartTime, 0);
        TestAssertEqualTimeInSeconds(self.mediaPlayerController.seekTargetTime, 10. + (kSeekCount - 1) * 5.);
        return YES;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL()];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testSeekOutsideValidRange
{
    if (@available(iOS 11, *)) {
        NSLog(@"[INFO] The %@ test has been disabled on iOS 11", NSStringFromSelector(_cmd));
    }
    else {
        [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
            return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
        }];
        
        [self.mediaPlayerController playURL:OnDemandTestURL()];
        
        [self waitForExpectationsWithTimeout:30. handler:nil];
        
        [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
            return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStateEnded;
        }];
        
        [self.mediaPlayerController seekPreciselyToTime:CMTimeMakeWithSeconds(9999999999., NSEC_PER_SEC) withCompletionHandler:nil];
        
        [self waitForExpectationsWithTimeout:30. handler:nil];
    }
}

- (void)testPlaySeekAndPlayWhileSeeking
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL()];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStateSeeking;
    }];
    
    [self.mediaPlayerController seekPreciselyToTime:CMTimeMakeWithSeconds(10., NSEC_PER_SEC) withCompletionHandler:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePlaying);
        return YES;
    }];
    
    [self.mediaPlayerController play];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testPlaySeekAndPauseWhileSeeking
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL()];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStateSeeking;
    }];
    
    [self.mediaPlayerController seekPreciselyToTime:CMTimeMakeWithSeconds(10., NSEC_PER_SEC) withCompletionHandler:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self.mediaPlayerController pause];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePaused);
        return YES;
    }];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testPauseSeekAndPlayWhileSeeking
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePaused;
    }];
    
    [self.mediaPlayerController prepareToPlayURL:OnDemandTestURL() withCompletionHandler:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStateSeeking;
    }];
    
    [self.mediaPlayerController seekPreciselyToTime:CMTimeMakeWithSeconds(10., NSEC_PER_SEC) withCompletionHandler:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePlaying);
        return YES;
    }];
    
    [self.mediaPlayerController play];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testPauseSeekAndPauseWhileSeeking
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePaused;
    }];
    
    [self.mediaPlayerController prepareToPlayURL:OnDemandTestURL() withCompletionHandler:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStateSeeking;
    }];
    
    [self.mediaPlayerController seekPreciselyToTime:CMTimeMakeWithSeconds(10., NSEC_PER_SEC) withCompletionHandler:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePaused);
        return YES;
    }];
    
    [self.mediaPlayerController pause];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testPlaySeekAndTogglePlayPauseWhileSeeking
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL()];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStateSeeking;
    }];
    
    [self.mediaPlayerController seekPreciselyToTime:CMTimeMakeWithSeconds(10., NSEC_PER_SEC) withCompletionHandler:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePaused);
        return YES;
    }];
    
    [self.mediaPlayerController togglePlayPause];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testPauseSeekAndTogglePlayPauseWhileSeeking
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePaused;
    }];
    
    [self.mediaPlayerController prepareToPlayURL:OnDemandTestURL() withCompletionHandler:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStateSeeking;
    }];
    
    [self.mediaPlayerController seekPreciselyToTime:CMTimeMakeWithSeconds(10., NSEC_PER_SEC) withCompletionHandler:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePlaying);
        return YES;
    }];
    
    [self.mediaPlayerController togglePlayPause];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testReset
{
    // Wait until playing
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    // Pass empty collections as parameters
    [self.mediaPlayerController playURL:OnDemandTestURL() atTime:CMTimeMakeWithSeconds(2., NSEC_PER_SEC) withSegments:@[] userInfo:@{}];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // Ensure the player is correctly deallocated
    __weak AVPlayer *weakPlayer = self.mediaPlayerController.player;
    [self expectationForPredicate:[NSPredicate predicateWithBlock:^BOOL(id _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
        return weakPlayer == nil;
    }] evaluatedWithObject:self /* unused, but a non-nil argument is required */ handler:nil];
    
    // Reset the player and check its status
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStateIdle);
        XCTAssertFalse([notification.userInfo[SRGMediaPlayerSelectedKey] boolValue]);
        
        XCTAssertNil(self.mediaPlayerController.contentURL);
        XCTAssertNil(self.mediaPlayerController.segments);
        XCTAssertNil(self.mediaPlayerController.userInfo);
        
        // Receive previous playback information since it has changed
        XCTAssertNotNil(notification.userInfo[SRGMediaPlayerPreviousContentURLKey]);
        XCTAssertNotNil(notification.userInfo[SRGMediaPlayerPreviousTimeRangeKey]);
        XCTAssertNotNil(notification.userInfo[SRGMediaPlayerPreviousMediaTypeKey]);
        XCTAssertNotNil(notification.userInfo[SRGMediaPlayerPreviousStreamTypeKey]);
        XCTAssertNotNil(notification.userInfo[SRGMediaPlayerPreviousUserInfoKey]);
        
        TestAssertEqualTimeInSeconds([notification.userInfo[SRGMediaPlayerLastPlaybackTimeKey] CMTimeValue], 2);
        
        return YES;
    }];
    
    XCTAssertNotNil(self.mediaPlayerController.contentURL);
    XCTAssertNotNil(self.mediaPlayerController.segments);
    XCTAssertNotNil(self.mediaPlayerController.userInfo);
    
    [self.mediaPlayerController reset];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testResetWhileSeeking
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL()];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStateSeeking;
    }];
    
    [self.mediaPlayerController seekPreciselyToTime:CMTimeMakeWithSeconds(10., NSEC_PER_SEC) withCompletionHandler:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStateIdle);
        return YES;
    }];
    
    [self.mediaPlayerController reset];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testStop
{
    // Wait until playing
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    // Pass empty collections as parameters
    [self.mediaPlayerController playURL:OnDemandTestURL() atTime:kCMTimeZero withSegments:@[] userInfo:@{}];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // Stop the player and check its status
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStateIdle);
        XCTAssertFalse([notification.userInfo[SRGMediaPlayerSelectedKey] boolValue]);
        
        XCTAssertNotNil(self.mediaPlayerController.contentURL);
        XCTAssertNotNil(self.mediaPlayerController.segments);
        XCTAssertNotNil(self.mediaPlayerController.userInfo);
        
        // No previous playback information since it has not changed
        XCTAssertNil(notification.userInfo[SRGMediaPlayerPreviousContentURLKey]);
        XCTAssertNil(notification.userInfo[SRGMediaPlayerPreviousUserInfoKey]);
        
        // Previous playback information since it has changed
        XCTAssertNotNil(notification.userInfo[SRGMediaPlayerPreviousMediaTypeKey]);
        XCTAssertNotNil(notification.userInfo[SRGMediaPlayerPreviousTimeRangeKey]);
        XCTAssertNotNil(notification.userInfo[SRGMediaPlayerPreviousStreamTypeKey]);
        
        TestAssertEqualTimeInSeconds([notification.userInfo[SRGMediaPlayerLastPlaybackTimeKey] CMTimeValue], 0);
        return YES;
    }];
    
    XCTAssertNotNil(self.mediaPlayerController.contentURL);
    XCTAssertNotNil(self.mediaPlayerController.segments);
    XCTAssertNotNil(self.mediaPlayerController.userInfo);
    
    [self.mediaPlayerController stop];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testStopWhileWhilePreparing
{
    // Wait until preparing
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        if ([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] != SRGMediaPlayerPlaybackStatePreparing) {
            return NO;
        }
        
        // Stop early when the notification is received
        [self.mediaPlayerController stop];
        return YES;
    }];
    
    // Pass empty collections as parameters
    [self.mediaPlayerController playURL:OnDemandTestURL() atTime:kCMTimeZero withSegments:@[] userInfo:@{}];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    XCTAssertNil(self.mediaPlayerController.player);
    XCTAssertNotNil(self.mediaPlayerController.contentURL);
    XCTAssertNotNil(self.mediaPlayerController.segments);
    XCTAssertNotNil(self.mediaPlayerController.userInfo);
}

- (void)testStopWhileSeeking
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL()];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStateSeeking;
    }];
    
    [self.mediaPlayerController seekPreciselyToTime:CMTimeMakeWithSeconds(10., NSEC_PER_SEC) withCompletionHandler:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStateIdle);
        return YES;
    }];
    
    [self.mediaPlayerController stop];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testPlayAfterStop
{
    // Wait until playing
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL() atTime:kCMTimeZero withSegments:nil userInfo:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // Stop the player and check its status
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStateIdle);
        return YES;
    }];
    
    [self.mediaPlayerController stop];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // Can be played again after a stop
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController play];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testPlayAfterReset
{
    // Wait until playing
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL() atTime:kCMTimeZero withSegments:nil userInfo:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // Reset the player and check its status
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStateIdle);
        return YES;
    }];
    
    [self.mediaPlayerController reset];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // The player cannot be started by simply calling -play
    [self expectationForElapsedTimeInterval:4. withHandler:nil];
    
    id eventObserver = [[NSNotificationCenter defaultCenter] addObserverForName:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        XCTFail(@"The player cannot be restarted with a play after a reset. No event expected");
    }];
    
    [self.mediaPlayerController play];
    
    [self waitForExpectationsWithTimeout:30. handler:^(NSError * _Nullable error) {
        [[NSNotificationCenter defaultCenter] removeObserver:eventObserver];
    }];
}

- (void)testOnDemandTogglePlayPause
{
    // Wait until playing
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL() atTime:kCMTimeZero withSegments:nil userInfo:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // Toggle (pause)
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePaused;
    }];
    
    [self.mediaPlayerController togglePlayPause];
    
    // Toggle (play)
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController togglePlayPause];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testDVRTogglePlayPause
{
    // Wait until playing
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:DVRTestURL() atTime:kCMTimeZero withSegments:nil userInfo:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // Toggle (pause)
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePaused;
    }];
    
    [self.mediaPlayerController togglePlayPause];
    
    // Toggle (play)
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController togglePlayPause];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testTogglePlayPauseAfterStop
{
    // Wait until playing
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL() atTime:kCMTimeZero withSegments:nil userInfo:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // Stop the player and check its status
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStateIdle);
        return YES;
    }];
    
    [self.mediaPlayerController stop];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // Can be played again after a stop
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController togglePlayPause];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testTogglePlayPauseAfterReset
{
    // Wait until playing
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL() atTime:kCMTimeZero withSegments:nil userInfo:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // Reset the player and check its status
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStateIdle);
        return YES;
    }];
    
    [self.mediaPlayerController reset];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // The player cannot be started by simply calling -play
    [self expectationForElapsedTimeInterval:4. withHandler:nil];
    
    id eventObserver = [[NSNotificationCenter defaultCenter] addObserverForName:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        XCTFail(@"The player cannot be restarted with a togglePlayPause after a reset. No event expected");
    }];
    
    [self.mediaPlayerController togglePlayPause];
    
    [self waitForExpectationsWithTimeout:30. handler:^(NSError * _Nullable error) {
        [[NSNotificationCenter defaultCenter] removeObserver:eventObserver];
    }];
}

- (void)testConsecutiveMediaPlaybackInSamePlayer
{
    // Wait until playing
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    NSDictionary *userInfo = @{ @"test_key" : @"test_value" };
    [self.mediaPlayerController playURL:OnDemandTestURL() atTime:kCMTimeZero withSegments:nil userInfo:userInfo];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    SRGMediaPlayerMediaType mediaType = self.mediaPlayerController.mediaType;
    SRGMediaPlayerStreamType streamType = self.mediaPlayerController.streamType;
    CMTimeRange timeRange = self.mediaPlayerController.timeRange;
    NSInteger start = (NSInteger)CMTimeGetSeconds(timeRange.start);
    NSInteger duration = (NSInteger)CMTimeGetSeconds(timeRange.duration);
    
    // Wait until playing again. Expect a playback state change to idle, then to play
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        if ([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] != SRGMediaPlayerPlaybackStateIdle) {
            return NO;
        }
        
        // Expect previous playback information since it has changed
        XCTAssertEqualObjects(notification.userInfo[SRGMediaPlayerPreviousContentURLKey], OnDemandTestURL());
        TestAssertEqualTimeInSeconds([notification.userInfo[SRGMediaPlayerPreviousTimeRangeKey] CMTimeRangeValue].start, start);
        TestAssertEqualTimeInSeconds([notification.userInfo[SRGMediaPlayerPreviousTimeRangeKey] CMTimeRangeValue].duration, duration);
        XCTAssertEqualObjects(notification.userInfo[SRGMediaPlayerPreviousMediaTypeKey], @(mediaType));
        XCTAssertEqualObjects(notification.userInfo[SRGMediaPlayerPreviousStreamTypeKey], @(streamType));
        XCTAssertEqualObjects(notification.userInfo[SRGMediaPlayerPreviousUserInfoKey], userInfo);
        
        return YES;
    }];
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL() atTime:kCMTimeZero withSegments:nil userInfo:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testPlayerLifecycle
{
    // Wait until playing
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    XCTestExpectation *creationExpectation = [self expectationWithDescription:@"Player created"];
    
    @weakify(self)
    self.mediaPlayerController.playerCreationBlock = ^(AVPlayer *player) {
        @strongify(self)
        XCTAssertEqual(self.mediaPlayerController.player, player);
        [creationExpectation fulfill];
    };
    
    XCTestExpectation *configurationReloadExpectation = [self expectationWithDescription:@"Configuration reloaded"];
    
    self.mediaPlayerController.playerConfigurationBlock = ^(AVPlayer *player) {
        @strongify(self)
        XCTAssertEqual(self.mediaPlayerController.player, player);
        [configurationReloadExpectation fulfill];
    };
    
    [self.mediaPlayerController playURL:OnDemandTestURL() atTime:kCMTimeZero withSegments:nil userInfo:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // Reset the player
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStateIdle;
    }];
    
    XCTestExpectation *destructionExpectation = [self expectationWithDescription:@"Player destroyed"];
    
    self.mediaPlayerController.playerDestructionBlock = ^(AVPlayer *player) {
        @strongify(self)
        XCTAssertEqual(self.mediaPlayerController.player, player);
        [destructionExpectation fulfill];
    };
    
    [self.mediaPlayerController reset];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testConfigurationReload
{
    // Wait until playing
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        return [notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue] == SRGMediaPlayerPlaybackStatePlaying;
    }];
    
    XCTestExpectation *creationExpectation = [self expectationWithDescription:@"Player created"];
    self.mediaPlayerController.playerCreationBlock = ^(AVPlayer *player) {
        [creationExpectation fulfill];
    };
    
    XCTestExpectation *configurationInitialReloadExpectation = [self expectationWithDescription:@"Configuration initially reloaded"];
    self.mediaPlayerController.playerConfigurationBlock = ^(AVPlayer *player) {
        [configurationInitialReloadExpectation fulfill];
    };
    
    [self.mediaPlayerController playURL:OnDemandTestURL() atTime:kCMTimeZero withSegments:nil userInfo:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
    
    // Reload the configuration
    XCTestExpectation *configurationReloadExpectation = [self expectationWithDescription:@"Configuration reloaded"];
    self.mediaPlayerController.playerConfigurationBlock = ^(AVPlayer *player) {
        [configurationReloadExpectation fulfill];
    };
    
    [self.mediaPlayerController reloadPlayerConfiguration];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testConfigurationReloadBeforePlayerIsAvailable
{
    @weakify(self)
    self.mediaPlayerController.playerConfigurationBlock = ^(AVPlayer *player) {
        @strongify(self)
        XCTFail(@"Player configuration must not be called if no player is available");
    };
    
    [self.mediaPlayerController reloadPlayerConfiguration];
}

- (void)testStateChangeNotificationContent
{
    [self mpt_expectationForNotification:SRGMediaPlayerPlaybackStateDidChangeNotification object:self.mediaPlayerController handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStatePreparing);
        XCTAssertEqual([notification.userInfo[SRGMediaPlayerPreviousPlaybackStateKey] integerValue], SRGMediaPlayerPlaybackStateIdle);
        XCTAssertFalse([notification.userInfo[SRGMediaPlayerSelectedKey] boolValue]);
        return YES;
    }];
    
    [self.mediaPlayerController playURL:OnDemandTestURL() atTime:kCMTimeZero withSegments:nil userInfo:nil];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testPlaybackStateKeyValueObserving
{
    [self keyValueObservingExpectationForObject:self.mediaPlayerController keyPath:@"playbackState" expectedValue:@(SRGMediaPlayerPlaybackStatePreparing)];
    
    [self.mediaPlayerController playURL:OnDemandTestURL()];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testStalled
{
    // Idea (might take some time to implement, later): We could expose the resourceLoader property of the AVURLAsset we
    // can additionally create when instantiating the AVPlayer. Using AVAssetResourceLoader, it is possible to load
    // data in a custom way (in our case, to simulate a slow network). Custom URL protocols cannot be used with AVPlayer
}

- (void)testPeriodicTimeObserver
{
    XCTestExpectation *observerExpectation = [self expectationWithDescription:@"Periodic time observer fired"];
    
    @weakify(self)
    __block id periodicTimeObserver = [self.mediaPlayerController addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(1., NSEC_PER_SEC) queue:NULL usingBlock:^(CMTime time) {
        @strongify(self)
        [observerExpectation fulfill];
        
        // Do not fulfill the expectation more than once
        [self.mediaPlayerController removePeriodicTimeObserver:periodicTimeObserver];
    }];
    
    // Periodic time observers fire only when the player has been created
    [self.mediaPlayerController playURL:OnDemandTestURL()];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testPeriodicTimeObserverAddedWhilePlaying
{
    XCTestExpectation *observerExpectation = [self expectationWithDescription:@"Periodic time observer fired"];
    
    [self.mediaPlayerController playURL:OnDemandTestURL()];
    
    @weakify(self)
    __block id periodicTimeObserver = [self.mediaPlayerController addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(1., NSEC_PER_SEC) queue:NULL usingBlock:^(CMTime time) {
        @strongify(self)
        [observerExpectation fulfill];
        
        // Do not fulfill the expectation more than once
        [self.mediaPlayerController removePeriodicTimeObserver:periodicTimeObserver];
    }];
    
    [self waitForExpectationsWithTimeout:30. handler:nil];
}

- (void)testPeriodicTimeObserverWithoutPlayback
{
    [self expectationForElapsedTimeInterval:3. withHandler:nil];
    
    @weakify(self)
    __block id periodicTimeObserver = [self.mediaPlayerController addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(1., NSEC_PER_SEC) queue:NULL usingBlock:^(CMTime time) {
        @strongify(self)
        XCTFail(@"Periodic time observers are not fired when the player is idle");
    }];
    
    [self waitForExpectationsWithTimeout:30. handler:^(NSError * _Nullable error) {
        [self.mediaPlayerController removePeriodicTimeObserver:periodicTimeObserver];
    }];
}

- (void)testPeriodicTimeObserverAfterReset
{
    [self expectationForElapsedTimeInterval:3. withHandler:nil];
    
    [self.mediaPlayerController playURL:OnDemandTestURL()];
    [self.mediaPlayerController reset];
    
    @weakify(self)
    __block id periodicTimeObserver = [self.mediaPlayerController addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(1., NSEC_PER_SEC) queue:NULL usingBlock:^(CMTime time) {
        @strongify(self)
        XCTFail(@"Periodic time observers are not fired when the player is idle");
    }];
    
    [self waitForExpectationsWithTimeout:30. handler:^(NSError * _Nullable error) {
        [self.mediaPlayerController removePeriodicTimeObserver:periodicTimeObserver];
    }];
}

@end
