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

class PlayerViewController: UIViewController, CAAnimationDelegate {
    // MARK: Properties
    var seekTimer: Timer? = nil
    var initialPos: CGFloat = 0
    var stack: [AVMutableComposition] = []
    var undoPos: Int = -1 {
        didSet {
            let undoButtonImageName = undoPos <= 0 ? "undo_ban" : "undo"
            
            let undoButtonImage = UIImage(named: undoButtonImageName)
            
            undoButton.setImage(undoButtonImage, for: UIControlState())
            
            let redoButtonImageName = undoPos == stack.count - 1 ? "redo_ban" : "redo"
            
            let redoButtonImage = UIImage(named: redoButtonImageName)
            
            redoButton.setImage(redoButtonImage, for: UIControlState())
        }
    }
    
    func push() {
        var newComposition = self.composition!.mutableCopy() as! AVMutableComposition
        
        while undoPos < stack.count - 1 {
            stack.removeLast()
        }
        
        stack.append(newComposition)
        undoPos = stack.count - 1
    }
    
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
    
    @IBOutlet weak var startTimeLabel: UILabel!
    @IBOutlet weak var playPauseButton: UIButton!
    @IBOutlet weak var playerView: PlayerView!
    @IBOutlet weak var timeline: TimelineView!
    @IBOutlet weak var compositionDebugView: APLCompositionDebugView!
    
    @IBOutlet weak var splitButton: UIButton!
    @IBOutlet weak var copyButton: UIButton!
    @IBOutlet weak var removeButton: UIButton!
    @IBOutlet weak var undoButton: UIButton!
    @IBOutlet weak var redoButton: UIButton!
    
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
        let asset = AVURLAsset(url: movieURL, options: nil)
        asynchronouslyLoadURLAsset(asset)
        
        // Make sure we don't have a strong reference cycle by only capturing self as weak.
        let interval = CMTimeMake(1, 1)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: DispatchQueue.main) { [unowned self] time in
            let timeElapsed = Float(CMTimeGetSeconds(time))
            
            self.startTimeLabel.text = self.createTimeString(time: timeElapsed)
        }
        
        timeline_original_x = self.timeline.layer.position.x

        // add composition
        
        composition = AVMutableComposition()
        // Add two video tracks and two audio tracks.
        let compositionVideoTrack = composition!.addMutableTrack(withMediaType: AVMediaTypeVideo, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        let compositionAudioTrack = composition!.addMutableTrack(withMediaType: AVMediaTypeAudio, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        push()
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
        let movieSeconds = CMTimeGetSeconds((composition?.duration)!);
        let incrementSeconds = movieSeconds / Double(numberOfImages);
        let movieDuration = composition?.duration;
    
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
        self.compositionDebugView.player = self.player
        self.compositionDebugView.synchronize(to: self.composition, videoComposition: nil, audioMix: nil)
        self.compositionDebugView.setNeedsDisplay()
        
//        timeline.removeAllPositionalSubviews()
//
//        let numberOfImagesNeeded = timeline.countOfImagesRequired(duration: CMTimeGetSeconds(self.composition!.duration))
//
//        if kCMTimeZero != composition!.duration && (composition!.tracks(withMediaType: AVMediaTypeVideo).count) > 0 {
//            self.timeline.frame.size.width = CGFloat(numberOfImagesNeeded) * self.timeline.frame.size.height
//            let times = imageTimesForNumberOfImages(numberOfImages: numberOfImagesNeeded)
//
//            let imageGenerator = AVAssetImageGenerator.init(asset: composition!)
//
//            // Set a videoComposition on the ImageGenerator if the underlying movie has more than 1 video track.
//            imageGenerator.generateCGImagesAsynchronously(forTimes: times as [NSValue]) { (requestedTime, image, actualTime, result, error) in
//                if (image != nil) {
//                    let croppedImage = image!.cropping(to: CGRect(x: (image!.width - image!.height)/2, y: 0, width: image!.height, height: image!.height))
//                    let nextImage = UIImage.init(cgImage: croppedImage!)
//                    DispatchQueue.main.async {
//                        self.timeline.addImageView(nextImage)
//                    }
//                } else {
//                }
//            }
//        }
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
                
                try! self.composition!.insertTimeRange(CMTimeRangeMake(kCMTimeZero, newAsset.duration), of: newAsset, at: kCMTimeZero)
                
                self.push()
                
                self.playerItem = AVPlayerItem(asset: self.composition!)
                self.playerItem!.videoComposition = self.videoComposition
                self.playerItem!.audioMix = self.audioMix
                self.player.replaceCurrentItem(with: self.playerItem)
                
                // update timeline
                self.updateMovieTimeline()
            }
        }
    }
    
    // MARK: - IBActions
    
    @IBAction func undo(_ sender: Any) {
        if undoPos <= 0 {
            return
        }
        
        undoPos -= 1
        self.composition = stack[undoPos].mutableCopy() as! AVMutableComposition
        
        updateMovieTimeline()
    }
    
    @IBAction func redo(_ sender: Any) {
        if undoPos == stack.count - 1 {
            return
        }
        
        undoPos += 1
        self.composition = stack[undoPos].mutableCopy() as! AVMutableComposition
        
        updateMovieTimeline()
    }
    
    @IBAction func splitClip(_ sender: Any) {
        var timeRangeInAsset: CMTimeRange? = nil
        
        let compositionVideoTrack = self.composition!.tracks(withMediaType: AVMediaTypeVideo).first
        
        for s in compositionVideoTrack!.segments {
            timeRangeInAsset = s.timeMapping.target; // assumes non-scaled edit
            
            if timeRangeInAsset!.containsTime(player.currentTime()) {
                try! self.composition!.insertTimeRange(timeRangeInAsset!, of: composition!, at: timeRangeInAsset!.end)
                
                try! self.composition!.removeTimeRange(CMTimeRange(start:player.currentTime(), duration:timeRangeInAsset!.duration - CMTime(value: 1, timescale: 600)))
                
                break
            }
        }
        
        updateMovieTimeline()
        push()

//        let filePath  = Bundle.main.path(forResource: "json", ofType:"txt")
//        let nsMutData = NSData(contentsOfFile:filePath!)
//        var sJson: Any
//        try! sJson = JSONSerialization.jsonObject(with: nsMutData! as Data, options: .mutableContainers)
    }
    @IBAction func copyClip(_ sender: Any) {
        var timeRangeInAsset: CMTimeRange? = nil
        
        let compositionVideoTrack = self.composition!.tracks(withMediaType: AVMediaTypeVideo).first
        
        for s in compositionVideoTrack!.segments {
            timeRangeInAsset = s.timeMapping.target; // assumes non-scaled edit
            
            if timeRangeInAsset!.containsTime(player.currentTime()) {
                try! self.composition!.insertTimeRange(timeRangeInAsset!, of: composition!, at: timeRangeInAsset!.end)
                
                break
            }
        }
        
        updateMovieTimeline()
        push()

    }
    @IBAction func removeClip(_ sender: Any) {
        var timeRangeInAsset: CMTimeRange? = nil

        let compositionVideoTrack = self.composition!.tracks(withMediaType: AVMediaTypeVideo).first
        
        for s in compositionVideoTrack!.segments {
            timeRangeInAsset = s.timeMapping.target; // assumes non-scaled edit
            
            if timeRangeInAsset!.containsTime(player.currentTime()) {
                try! self.composition!.removeTimeRange(timeRangeInAsset!)
                
                break
            }
        }
        
        updateMovieTimeline()
        push()

    }
    
    @IBAction func playPauseButtonWasPressed(_ sender: UIButton) {
        if player.rate != 1.0 {
            // Not playing forward, so play.
            if currentTime == duration {
                // At end, so got back to begining.
                currentTime = 0.0
            }
            
            player.play()
            
            self.timeline.layer.removeAllAnimations()
            self.timeline.layer.position.x = timeline_original_x - self.timeline.frame.width * CGFloat(CMTimeGetSeconds(player.currentTime())) / CGFloat(CMTimeGetSeconds(self.composition!.duration))
            
            let constVelocityAnim = CAKeyframeAnimation(keyPath: "position.x")
            constVelocityAnim.calculationMode = kCAAnimationCubicPaced
            constVelocityAnim.values = [self.timeline.layer.position.x, self.timeline.layer.position.x - self.timeline.frame.width]
            constVelocityAnim.duration = CMTimeGetSeconds((composition!.duration))
            self.timeline.layer.add(constVelocityAnim, forKey: "position.x")
        }
        else {
            // Playing, so pause.
            player.pause()
            
            self.timeline.layer.removeAllAnimations()
            self.timeline.layer.position.x = timeline_original_x - self.timeline.frame.width * CGFloat(CMTimeGetSeconds(player.currentTime())) / CGFloat(CMTimeGetSeconds(self.composition!.duration))
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
            self.timeline.layer.removeAllAnimations()
            // Save the view's original position.
            
            self.initialPos = piece.layer.position.x
            
        }
        // Update the position for the .began, .changed, and .ended states
        if gestureRecognizer.state != .cancelled && gestureRecognizer.state != .ended {
            // Add the X and Y translation to the view's original position.
            piece.layer.position.x = self.initialPos + translation.x
            self.currentTime = Double(self.timeline_original_x - self.timeline.layer.position.x) / Double(self.timeline.layer.frame.width) * CMTimeGetSeconds(self.composition!.duration)
        }else if gestureRecognizer.state == .ended {
            let v = gestureRecognizer.velocity(in: piece).x
            
            let decVelocityAnim = CAKeyframeAnimation(keyPath: "position.x")
            decVelocityAnim.delegate = self
            decVelocityAnim.calculationMode = kCAAnimationCubic
            let init_x = self.timeline.layer.position.x
            decVelocityAnim.values = [init_x,
                                      init_x + CGFloat(0.25*v),
                                      init_x + CGFloat(0.45*v),
                                      init_x + CGFloat(0.5*v),
                                      init_x + CGFloat(0.45*v),
                                      init_x + CGFloat(0.25*v),
                                      init_x]
            decVelocityAnim.keyTimes = [0,0.2,0.5,1,1.5,1.8,2]
            
            decVelocityAnim.duration = 2.5
            self.timeline.layer.add(decVelocityAnim, forKey: "position.x")
            
            if #available(iOS 10.0, *) {
                seekTimer?.invalidate()
                seekTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { (timer) in
                    self.currentTime = Double(self.timeline_original_x - self.timeline.layer.position.x) / Double(self.timeline.layer.frame.width) * CMTimeGetSeconds(self.composition!.duration)
                })
            } else {
                // Fallback on earlier versions
            }
        }
        else {
            // On cancellation, return the piece to its original location.
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
    
    // MARK: Delegate
    
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        self.seekTimer?.invalidate()
    }

}
