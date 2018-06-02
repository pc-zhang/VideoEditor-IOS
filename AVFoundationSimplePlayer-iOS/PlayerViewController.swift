/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 View controller containing a player view and basic playback controls.
 */

import Foundation
import AVFoundation
import UIKit

/*
 KVO context used to differentiate KVO callbacks for this class versus other
 classes in its class hierarchy.
 */
private var playerViewControllerKVOContext = 0

class PlayerViewController: UIViewController {
    // MARK: Properties
    var initialPos = CGFloat()  // The initial center point of the view.
    var initialTime = Double()
    
    // Attempt load and test these asset keys before playing.
    static let assetKeysRequiredToPlay = [
        "playable",
        "hasProtectedContent"
    ]
    
    let player = AVPlayer()
    
    var timeline_original_x : CGFloat = 0.0
    
    var currentTime: Double {
        get {
            return CMTimeGetSeconds(player.currentTime())
        }
        set {
            let newTime = CMTimeMakeWithSeconds(newValue, 1)
            player.seek(to: newTime, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero)
        }
    }
    
    var duration: Double {
        guard let currentItem = player.currentItem else { return 0.0 }
        
        return CMTimeGetSeconds(currentItem.duration)
    }
    
    var rate: Float {
        get {
            return player.rate
        }
        
        set {
            player.rate = newValue
        }
    }
    
    var asset: AVURLAsset? {
        didSet {
            guard let newAsset = asset else { return }
            
            asynchronouslyLoadURLAsset(newAsset)
        }
    }
    
    var composition: AVMutableComposition? = nil
    var videoComposition: AVMutableVideoComposition? = nil
    var audioMix: AVMutableAudioMix? = nil
    
    private var playerLayer: AVPlayerLayer? {
        return playerView.playerLayer
    }
    
    /*
     A formatter for individual date components used to provide an appropriate
     value for the `startTimeLabel` and `durationLabel`.
     */
    let timeRemainingFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.zeroFormattingBehavior = .pad
        formatter.allowedUnits = [.minute, .second]
        
        return formatter
    }()
    
    /*
     A token obtained from calling `player`'s `addPeriodicTimeObserverForInterval(_:queue:usingBlock:)`
     method.
     */
    private var timeObserverToken: Any?
    
    private var playerItem: AVPlayerItem? = nil
    
    // MARK: - IBOutlets
    
//    @IBOutlet weak var timeSlider: UISlider!
    @IBOutlet weak var startTimeLabel: UILabel!
//    @IBOutlet weak var durationLabel: UILabel!
//    @IBOutlet weak var rewindButton: UIButton!
    @IBOutlet weak var playPauseButton: UIButton!
//    @IBOutlet weak var fastForwardButton: UIButton!
    @IBOutlet weak var playerView: PlayerView!
    @IBOutlet weak var timeline: TimelineView!
    @IBOutlet weak var compositionDebugView: APLCompositionDebugView!
    
    // MARK: - View Controller
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        /*
         Update the UI when these player properties change.
         
         Use the context parameter to distinguish KVO for our particular observers
         and not those destined for a subclass that also happens to be observing
         these properties.
         */
        addObserver(self, forKeyPath: #keyPath(PlayerViewController.player.currentItem.duration), options: [.new, .initial], context: &playerViewControllerKVOContext)
        addObserver(self, forKeyPath: #keyPath(PlayerViewController.player.rate), options: [.new, .initial], context: &playerViewControllerKVOContext)
        addObserver(self, forKeyPath: #keyPath(PlayerViewController.player.currentItem.status), options: [.new, .initial], context: &playerViewControllerKVOContext)
        
        playerView.playerLayer.player = player
        
        let movieURL = Bundle.main.url(forResource: "wallstreet", withExtension: "mov")!
        asset = AVURLAsset(url: movieURL, options: nil)
        
        // Make sure we don't have a strong reference cycle by only capturing self as weak.
        let interval = CMTimeMake(1, 1)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: DispatchQueue.main) { [unowned self] time in
            let timeElapsed = Float(CMTimeGetSeconds(time))
            
            self.startTimeLabel.text = self.createTimeString(time: timeElapsed)
        }
        
        // add composition
        
        composition = AVMutableComposition()
        // Add two video tracks and two audio tracks.
        let compositionVideoTrack: AVMutableCompositionTrack = composition!.addMutableTrack(withMediaType: AVMediaTypeVideo, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        let compositionAudioTrack: AVMutableCompositionTrack = composition!.addMutableTrack(withMediaType: AVMediaTypeAudio, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        
        // update timeline
        updateMovieTimeline()
        
        compositionDebugView.synchronize(to: composition, videoComposition: nil, audioMix: nil)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        if let timeObserverToken = timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
        
        player.pause()
        
        removeObserver(self, forKeyPath: #keyPath(PlayerViewController.player.currentItem.duration), context: &playerViewControllerKVOContext)
        removeObserver(self, forKeyPath: #keyPath(PlayerViewController.player.rate), context: &playerViewControllerKVOContext)
        removeObserver(self, forKeyPath: #keyPath(PlayerViewController.player.currentItem.status), context: &playerViewControllerKVOContext)
    }
    
    
    
    // MARK: todo
    
    func imageTimesForNumberOfImages(numberOfImages:UInt) -> [NSValue] {
        let movieSeconds = CMTimeGetSeconds((asset?.duration)!);
        let incrementSeconds = movieSeconds / Double(numberOfImages);
        let movieDuration = asset?.duration;
    
        let incrementTime = CMTimeMakeWithSeconds(incrementSeconds, 1000);
        var times = [NSValue]();
    
        // Generate an image at time zero.
        var startTime = kCMTimeZero;
        while startTime <= movieDuration! {
            var nextValue = startTime as NSValue;
            if startTime == movieDuration {
                // Ensure that one image is always the last image in the movie.
                nextValue = movieDuration as! NSValue;
            }
            times.append(nextValue)
            startTime = CMTimeAdd(startTime, incrementTime);
        }
    
        return times;
    }
    
    func updateMovieTimeline() {
        timeline.removeAllPositionalSubviews()
        
        let numberOfImagesNeeded = timeline.countOfImagesRequiredToFillView()
        
        if kCMTimeZero != asset!.duration && (asset?.tracks(withMediaType: AVMediaTypeVideo).count)! > 0 {
            let times = imageTimesForNumberOfImages(numberOfImages: numberOfImagesNeeded)
        
            let imageGenerator = AVAssetImageGenerator.init(asset: self.asset!)
            
            // Set a videoComposition on the ImageGenerator if the underlying movie has more than 1 video track.
            imageGenerator.generateCGImagesAsynchronously(forTimes: times as [NSValue]) { (requestedTime, image, actualTime, result, error) in
                if (image != nil) {
                    let nextImage = UIImage.init(cgImage: image!)
                    DispatchQueue.main.async {
                        self.timeline.addImageView(nextImage)
                    }
                } else {
                    //                    NSLog(@"There was an error creating an image at time: %f", CMTimeGetSeconds(requestedTime));
                }
            }
        }
        
        timeline_original_x = self.timeline.layer.position.x
        self.timeline.layer.position.x = timeline_original_x + self.timeline.frame.width / 2
        
    }
    
    
    // MARK: - Asset Loading
    
    func asynchronouslyLoadURLAsset(_ newAsset: AVURLAsset) {
        /*
         Using AVAsset now runs the risk of blocking the current thread (the
         main UI thread) whilst I/O happens to populate the properties. It's
         prudent to defer our work until the properties we need have been loaded.
         */
        newAsset.loadValuesAsynchronously(forKeys: PlayerViewController.assetKeysRequiredToPlay) {
            /*
             The asset invokes its completion handler on an arbitrary queue.
             To avoid multiple threads using our internal state at the same time
             we'll elect to use the main thread at all times, let's dispatch
             our handler to the main queue.
             */
            DispatchQueue.main.async {
                /*
                 `self.asset` has already changed! No point continuing because
                 another `newAsset` will come along in a moment.
                 */
                guard newAsset == self.asset else { return }
                
                /*
                 Test whether the values of each of the keys we need have been
                 successfully loaded.
                 */
                for key in PlayerViewController.assetKeysRequiredToPlay {
                    var error: NSError?
                    
                    if newAsset.statusOfValue(forKey: key, error: &error) == .failed {
                        let stringFormat = NSLocalizedString("error.asset_key_%@_failed.description", comment: "Can't use this AVAsset because one of it's keys failed to load")
                        
                        let message = String.localizedStringWithFormat(stringFormat, key)
                        
                        self.handleErrorWithMessage(message, error: error)
                        
                        return
                    }
                }
                
                // We can't play this asset.
                if !newAsset.isPlayable || newAsset.hasProtectedContent {
                    let message = NSLocalizedString("error.asset_not_playable.description", comment: "Can't use this AVAsset because it isn't playable or has protected content")
                    
                    self.handleErrorWithMessage(message)
                    
                    return
                }
                
                /*
                 We can play this asset. Create a new `AVPlayerItem` and make
                 it our player's current item.
                 */
                self.asset = newAsset
                
                let nextClipStartTime: CMTime = kCMTimeZero

                let timeRangeInAsset = CMTimeRangeMake(kCMTimeZero, newAsset.duration);
                
                guard let clipVideoTrack = newAsset.tracks(withMediaType: AVMediaTypeVideo).first else{
                    return
                }
                
                let compositionVideoTrack = self.composition!.mutableTrack(compatibleWith: clipVideoTrack)
                
                try! compositionVideoTrack?.insertTimeRange(timeRangeInAsset, of: clipVideoTrack, at: nextClipStartTime)
                
                guard let clipAudioTrack = newAsset.tracks(withMediaType: AVMediaTypeAudio).first else{
                    return
                }
                
                let compositionAudioTrack = self.composition!.mutableTrack(compatibleWith: clipAudioTrack)
                
                try! compositionAudioTrack?.insertTimeRange(timeRangeInAsset, of: clipAudioTrack, at: nextClipStartTime)
                
                self.playerItem = AVPlayerItem(asset: self.composition!)
                self.playerItem!.videoComposition = self.videoComposition
                self.playerItem!.audioMix = self.audioMix
                self.player.replaceCurrentItem(with: self.playerItem)
            }
        }
    }
    
    // MARK: - IBActions
    
    @IBAction func playPauseButtonWasPressed(_ sender: UIButton) {
        if player.rate != 1.0 {
            // Not playing forward, so play.
            if currentTime == duration {
                // At end, so got back to begining.
                currentTime = 0.0
            }
            
            player.play()
            
            self.timeline.layer.removeAllAnimations()
            self.timeline.layer.position.x = timeline_original_x + self.timeline.frame.width / 2 - self.timeline.frame.width / CGFloat(CMTimeGetSeconds((self.asset?.duration)!)) * CGFloat(CMTimeGetSeconds(player.currentTime()))
            
            UIView.animate(withDuration: CMTimeGetSeconds((self.asset?.duration)!)) {
                // Change the opacity implicitly.
                self.timeline.layer.position.x = self.timeline.layer.position.x - self.timeline.frame.width
            }
        }
        else {
            // Playing, so pause.
            player.pause()
            
            self.timeline.layer.removeAllAnimations()
            self.timeline.layer.position.x = timeline_original_x + self.timeline.frame.width / 2 - self.timeline.frame.width / CGFloat(CMTimeGetSeconds((self.asset?.duration)!)) * CGFloat(CMTimeGetSeconds(player.currentTime()))
        }
    }
    
    @IBAction func rewindButtonWasPressed(_ sender: UIButton) {
        // Rewind no faster than -2.0.
        rate = max(player.rate - 2.0, -2.0)
    }
    
    @IBAction func fastForwardButtonWasPressed(_ sender: UIButton) {
        // Fast forward no faster than 2.0.
        rate = min(player.rate + 2.0, 2.0)
    }
    
    @IBAction func timeSliderDidChange(_ sender: UISlider) {
        currentTime = Double(sender.value)
    }
    
    
    @IBAction func timelineTap(_ sender: UITapGestureRecognizer) {
        
    }
    
    @IBAction func timelineDrag(_ gestureRecognizer : UIPanGestureRecognizer) {
        guard gestureRecognizer.view != nil else {return}
        //        playPauseButtonWasPressed()
        let piece = gestureRecognizer.view!
        // Get the changes in the X and Y directions relative to
        // the superview's coordinate space.
        let translation = gestureRecognizer.translation(in: piece.superview)
        if gestureRecognizer.state == .began {
            
            // Save the view's original position.
            self.initialPos = piece.layer.position.x
            self.initialTime = self.currentTime
        }
        // Update the position for the .began, .changed, and .ended states
        if gestureRecognizer.state != .cancelled {
            // Add the X and Y translation to the view's original position.
            piece.layer.position.x = self.initialPos + translation.x
            
            self.currentTime = initialTime - Double(translation.x) / Double(piece.layer.frame.width) * CMTimeGetSeconds(self.asset!.duration)
            
            self.timeline.layer.removeAllAnimations()
            let v = gestureRecognizer.velocity(in: piece).x
            UIView.animate(withDuration: CMTimeGetSeconds((self.asset?.duration)!)) {
                if v < 0 {
                    // Change the opacity implicitly.
                    self.timeline.layer.position.x = self.timeline.layer.position.x - CGFloat(0.01 * v * v)
                } else {
                    self.timeline.layer.position.x = self.timeline.layer.position.x + CGFloat(0.01 * v * v)
                }
            }
        }
        else {
            // On cancellation, return the piece to its original location.
            piece.layer.position.x = initialPos
            self.currentTime = initialTime
        }
    }
    
    // MARK: - KVO Observation
    
    // Update our UI when player or `player.currentItem` changes.
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        // Make sure the this KVO callback was intended for this view controller.
        guard context == &playerViewControllerKVOContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        
        if keyPath == #keyPath(PlayerViewController.player.currentItem.duration) {
            // Update timeSlider and enable/disable controls when duration > 0.0
            
            /*
             Handle `NSNull` value for `NSKeyValueChangeNewKey`, i.e. when
             `player.currentItem` is nil.
             */
            let newDuration: CMTime
            if let newDurationAsValue = change?[NSKeyValueChangeKey.newKey] as? NSValue {
                newDuration = newDurationAsValue.timeValue
            }
            else {
                newDuration = kCMTimeZero
            }
            
            let hasValidDuration = newDuration.isNumeric && newDuration.value != 0
            let newDurationSeconds = hasValidDuration ? CMTimeGetSeconds(newDuration) : 0.0
            let currentTime = hasValidDuration ? Float(CMTimeGetSeconds(player.currentTime())) : 0.0
            
//            timeSlider.maximumValue = Float(newDurationSeconds)
//
//            timeSlider.value = currentTime
//
//            rewindButton.isEnabled = hasValidDuration
            
            playPauseButton.isEnabled = hasValidDuration
            
//            fastForwardButton.isEnabled = hasValidDuration
//
//            timeSlider.isEnabled = hasValidDuration
            
            startTimeLabel.isEnabled = hasValidDuration
            startTimeLabel.text = createTimeString(time: currentTime)
            
//            durationLabel.isEnabled = hasValidDuration
//            durationLabel.text = createTimeString(time: Float(newDurationSeconds))
        }
        else if keyPath == #keyPath(PlayerViewController.player.rate) {
            // Update `playPauseButton` image.
            
            let newRate = (change?[NSKeyValueChangeKey.newKey] as! NSNumber).doubleValue
            
            let buttonImageName = newRate == 1.0 ? "pausebutton" : "playbutton"
            
            let buttonImage = UIImage(named: buttonImageName)
            
            playPauseButton.setImage(buttonImage, for: UIControlState())
        }
        else if keyPath == #keyPath(PlayerViewController.player.currentItem.status) {
            // Display an error if status becomes `.Failed`.
            
            /*
             Handle `NSNull` value for `NSKeyValueChangeNewKey`, i.e. when
             `player.currentItem` is nil.
             */
            let newStatus: AVPlayerItemStatus
            
            if let newStatusAsNumber = change?[NSKeyValueChangeKey.newKey] as? NSNumber {
                newStatus = AVPlayerItemStatus(rawValue: newStatusAsNumber.intValue)!
            }
            else {
                newStatus = .unknown
            }
            
            if newStatus == .failed {
                handleErrorWithMessage(player.currentItem?.error?.localizedDescription, error:player.currentItem?.error)
            }
        }
    }
    
    // Trigger KVO for anyone observing our properties affected by player and player.currentItem
    override class func keyPathsForValuesAffectingValue(forKey key: String) -> Set<String> {
        let affectedKeyPathsMappingByKey: [String: Set<String>] = [
            "duration":     [#keyPath(PlayerViewController.player.currentItem.duration)],
            "rate":         [#keyPath(PlayerViewController.player.rate)]
        ]
        
        return affectedKeyPathsMappingByKey[key] ?? super.keyPathsForValuesAffectingValue(forKey: key)
    }
    
    // MARK: - Error Handling
    
    func handleErrorWithMessage(_ message: String?, error: Error? = nil) {
        NSLog("Error occured with message: \(message), error: \(error).")
        
        let alertTitle = NSLocalizedString("alert.error.title", comment: "Alert title for errors")
        let defaultAlertMessage = NSLocalizedString("error.default.description", comment: "Default error message when no NSError provided")
        
        let alert = UIAlertController(title: alertTitle, message: message == nil ? defaultAlertMessage : message, preferredStyle: UIAlertControllerStyle.alert)
        
        let alertActionTitle = NSLocalizedString("alert.error.actions.OK", comment: "OK on error alert")
        
        let alertAction = UIAlertAction(title: alertActionTitle, style: .default, handler: nil)
        
        alert.addAction(alertAction)
        
        present(alert, animated: true, completion: nil)
    }
    
    // MARK: Convenience
    
    func createTimeString(time: Float) -> String {
        let components = NSDateComponents()
        components.second = Int(max(0.0, time))
        
        return timeRemainingFormatter.string(from: components as DateComponents)!
    }

}
