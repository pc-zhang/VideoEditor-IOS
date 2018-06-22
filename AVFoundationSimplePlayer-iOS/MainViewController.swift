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
private var MainViewControllerKVOContext = 0

class MainViewController: UIViewController, UIScrollViewDelegate {
    // MARK: Properties

    @IBOutlet weak var scrollview: UIScrollView! {
        didSet{
            scrollview.delegate = self
        }
    }
    
    var seekTimer: Timer? = nil
    var lastCenterTime: Double = 0
    var scaledDurationToWidth: CGFloat = 0
    var imageGenerator: AVAssetImageGenerator? = nil
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
    
    var currentTime: Double {
        get {
            return CMTimeGetSeconds(player.currentTime())
        }
        set {
            let newTime = CMTimeMakeWithSeconds(newValue, 60)
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
    @IBOutlet weak var timelineView: TimelineView!
    
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
        addObserver(self, forKeyPath: #keyPath(MainViewController.player.currentItem.duration), options: [.new, .initial], context: &MainViewControllerKVOContext)
        addObserver(self, forKeyPath: #keyPath(MainViewController.player.rate), options: [.new, .initial], context: &MainViewControllerKVOContext)
        addObserver(self, forKeyPath: #keyPath(MainViewController.player.currentItem.status), options: [.new, .initial], context: &MainViewControllerKVOContext)
        
        playerView.playerLayer.player = player
        
        // Make sure we don't have a strong reference cycle by only capturing self as weak.
        let interval = CMTimeMake(1, 1)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: DispatchQueue.main) { [unowned self] time in
            let timeElapsed = Float(CMTimeGetSeconds(time))
            
            self.startTimeLabel.text = self.createTimeString(time: timeElapsed)
        }
        
        // add composition
        
        composition = AVMutableComposition()
        // Add two video tracks and two audio tracks.
        _ = composition!.addMutableTrack(withMediaType: AVMediaTypeVideo, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        _ = composition!.addMutableTrack(withMediaType: AVMediaTypeAudio, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        timelineView.backgroundColor = #colorLiteral(red: 1, green: 0, blue: 0, alpha: 0)
        scrollview.contentSize = timelineView.frame.size
        scrollview.contentOffset = CGPoint(x:-scrollview.frame.width / 2, y:0)
        scrollview.contentInset = UIEdgeInsets(top: 0, left: scrollview.frame.width/2, bottom: 0, right: scrollview.frame.width/2)
        
        scaledDurationToWidth = scrollview.frame.width / 30
        
        addClip()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        if let timeObserverToken = timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
        
        player.pause()
        
        removeObserver(self, forKeyPath: #keyPath(MainViewController.player.currentItem.duration), context: &MainViewControllerKVOContext)
        removeObserver(self, forKeyPath: #keyPath(MainViewController.player.rate), context: &MainViewControllerKVOContext)
        removeObserver(self, forKeyPath: #keyPath(MainViewController.player.currentItem.status), context: &MainViewControllerKVOContext)
    }
    
    // MARK: todo
    
    func updateTimeline() {
        lastCenterTime = currentTime
        
        for subview in timelineView.subviews {
            subview.removeFromSuperview()
        }
        
        if kCMTimeZero != composition!.duration {
            timelineView.frame.size = CGSize(width: CGFloat(CMTimeGetSeconds(composition!.duration)) * scaledDurationToWidth, height: timelineView.frame.height)
            scrollview.contentSize = timelineView.frame.size
            
            let compositionVideoTrack = self.composition!.tracks(withMediaType: AVMediaTypeVideo).first
            
            imageGenerator?.cancelAllCGImageGeneration()
            imageGenerator = AVAssetImageGenerator.init(asset: composition!)
            imageGenerator?.maximumSize = CGSize(width: self.timelineView.bounds.height * 2, height: self.timelineView.bounds.height * 2)
            
            var segmentRect = CGRect(origin: CGPoint(x:0,y:0), size: timelineView.frame.size)
            for segment in (compositionVideoTrack?.segments)! {
                segmentRect.size.width = CGFloat(CMTimeGetSeconds(segment.timeMapping.source.duration)) * scaledDurationToWidth
                
                let segmentView = UIView(frame: segmentRect)
                segmentView.frame = segmentView.frame.insetBy(dx: 1, dy: 0)
                segmentView.backgroundColor = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 0)
                timelineView.addSubview(segmentView)
                segmentView.clipsToBounds = true
                
                if true {
                    var times = [NSValue]()
                    
                    // Generate an image at time zero.
                    let startTime = CMTime(seconds: Double(segmentRect.minX / scaledDurationToWidth), preferredTimescale: 60)
                    let endTime = CMTime(seconds: Double(segmentRect.maxX / scaledDurationToWidth), preferredTimescale: 60)
                    let incrementTime = CMTime(seconds: Double(segmentRect.height /  scaledDurationToWidth), preferredTimescale: 60)
                    
                    var iterTime = startTime
                    
                    while iterTime <= endTime {
                        if CMTimeRange(start: CMTime(seconds: currentTime-60, preferredTimescale: 1), end: CMTime(seconds: currentTime+60, preferredTimescale: 1)).containsTime(iterTime) {
                            times.append(iterTime as NSValue)
                        }
                        iterTime = CMTimeAdd(iterTime, incrementTime);
                    }
                    
                    // Set a videoComposition on the ImageGenerator if the underlying movie has more than 1 video track.
                    imageGenerator?.generateCGImagesAsynchronously(forTimes: times as [NSValue]) { (requestedTime, image, actualTime, result, error) in
                        if (image != nil) {
                            DispatchQueue.main.async {
                                let nextX = CGFloat(CMTimeGetSeconds(requestedTime - startTime)) * self.scaledDurationToWidth
                                let nextView = UIImageView.init(frame: CGRect(x: nextX, y: 0.0, width: segmentView.bounds.height, height: segmentView.bounds.height))
                                nextView.contentMode = .scaleAspectFill
                                nextView.clipsToBounds = true
                                nextView.image = UIImage.init(cgImage: image!)
                                
                                segmentView.addSubview(nextView)
                                segmentView.setNeedsDisplay()
                            }
                        }
                    }
                }
                
                
                segmentRect.origin.x += segmentRect.size.width;
            }
        }
    }
    
    func updatePlayerAndTimeline() {
        if composition == nil {
            return
        }
        
        playerItem = AVPlayerItem(asset: composition!)
        playerItem!.videoComposition = videoComposition
        playerItem!.audioMix = audioMix
        player.replaceCurrentItem(with: playerItem)
        
        currentTime = Double((scrollview.contentOffset.x + scrollview.frame.width/2) / scaledDurationToWidth)
        
        updateTimeline()
    }
    
    // MARK: - IBActions
    
    func addClip() {
        let movieURL = Bundle.main.url(forResource: "wallstreet", withExtension: "mov")!
        let newAsset = AVURLAsset(url: movieURL, options: nil)
        /*
         Using AVAsset now runs the risk of blocking the current thread (the
         main UI thread) whilst I/O happens to populate the properties. It's
         prudent to defer our work until the properties we need have been loaded.
         */
        newAsset.loadValuesAsynchronously(forKeys: MainViewController.assetKeysRequiredToPlay) {
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
                for key in MainViewController.assetKeysRequiredToPlay {
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
                
                // update timeline
                self.updatePlayerAndTimeline()
            }
        }
    }
    
    
    @IBAction func undo(_ sender: Any) {
        if undoPos <= 0 {
            return
        }
        
        undoPos -= 1
        self.composition = stack[undoPos].mutableCopy() as! AVMutableComposition
        
        updatePlayerAndTimeline()
    }
    
    @IBAction func redo(_ sender: Any) {
        if undoPos == stack.count - 1 {
            return
        }
        
        undoPos += 1
        self.composition = stack[undoPos].mutableCopy() as! AVMutableComposition
        
        updatePlayerAndTimeline()
    }
    
    @IBAction func splitClip(_ sender: Any) {
        var timeRangeInAsset: CMTimeRange? = nil
        
        let compositionVideoTrack = self.composition!.tracks(withMediaType: AVMediaTypeVideo).first
        
        for s in compositionVideoTrack!.segments {
            timeRangeInAsset = s.timeMapping.source; // assumes non-scaled edit
            
            if timeRangeInAsset!.containsTime(player.currentTime()) {
                try! self.composition!.insertTimeRange(timeRangeInAsset!, of: composition!, at: timeRangeInAsset!.end)
                
                try! self.composition!.removeTimeRange(CMTimeRange(start:player.currentTime(), duration:timeRangeInAsset!.duration - CMTime(value: 1, timescale: 600)))
                
                break
            }
        }
        
        updatePlayerAndTimeline()
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
            timeRangeInAsset = s.timeMapping.source; // assumes non-scaled edit
            
            if timeRangeInAsset!.containsTime(player.currentTime()) {
                try! self.composition!.insertTimeRange(timeRangeInAsset!, of: composition!, at: timeRangeInAsset!.end)
                
                break
            }
        }
        
        updatePlayerAndTimeline()
        push()

    }
    @IBAction func removeClip(_ sender: Any) {
        var timeRangeInAsset: CMTimeRange? = nil

        let compositionVideoTrack = self.composition!.tracks(withMediaType: AVMediaTypeVideo).first
        
        for s in compositionVideoTrack!.segments {
            timeRangeInAsset = s.timeMapping.source; // assumes non-scaled edit
            
            if timeRangeInAsset!.containsTime(player.currentTime()) {
                try! self.composition!.removeTimeRange(timeRangeInAsset!)
                
                break
            }
        }
        
        updatePlayerAndTimeline()
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
            
            if #available(iOS 10.0, *) {
                seekTimer?.invalidate()
                seekTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { (timer) in
                    self.scrollview.contentOffset.x = CGFloat(self.currentTime/CMTimeGetSeconds(self.composition!.duration)*Double(self.timelineView.frame.width)) - self.scrollview.frame.size.width/2
                })
            } else {
                // Fallback on earlier versions
            }
        }
        else {
            // Playing, so pause.
            player.pause()
            seekTimer?.invalidate()
        }
    }
    
    
    // MARK: - KVO Observation
    
    // Update our UI when player or `player.currentItem` changes.
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        // Make sure the this KVO callback was intended for this view controller.
        guard context == &MainViewControllerKVOContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        
        if keyPath == #keyPath(MainViewController.player.currentItem.duration) {
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
        else if keyPath == #keyPath(MainViewController.player.rate) {
            // Update `playPauseButton` image.
            
            let newRate = (change?[NSKeyValueChangeKey.newKey] as! NSNumber).doubleValue
            
            let buttonImageName = newRate == 1.0 ? "pausebutton" : "playbutton"
            
            let buttonImage = UIImage(named: buttonImageName)
            
            playPauseButton.setImage(buttonImage, for: UIControlState())
        }
        else if keyPath == #keyPath(MainViewController.player.currentItem.status) {
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
            "duration":     [#keyPath(MainViewController.player.currentItem.duration)],
            "rate":         [#keyPath(MainViewController.player.rate)]
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
    
    func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        
        // Figure out what our orientation is, and use that to form the rectangle
        var newSize: CGSize
        if(widthRatio > heightRatio) {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio,  height: size.height * widthRatio)
        }
        
        // This is the rect that we've calculated out and this is what is actually used below
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        
        // Actually do the resizing to the rect using the ImageContext stuff
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage!
    }
    
    
    func createTimeString(time: Float) -> String {
        let components = NSDateComponents()
        components.second = Int(max(0.0, time))
        
        return timeRemainingFormatter.string(from: components as DateComponents)!
    }
    
    // MARK: Delegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return timelineView
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if player.rate == 0 {
            currentTime = Double(scrollview.contentOffset.x + scrollview.frame.width/2) / Double(timelineView.frame.width) * CMTimeGetSeconds(composition!.duration)
            if abs(currentTime-lastCenterTime) > 15 {
                updateTimeline()
            }
        }
    }
}
