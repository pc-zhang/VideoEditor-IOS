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
    struct opsAndComps {
        var comp: AVMutableComposition
        var op: OpType
    }
    var stack: [opsAndComps] = []
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
    
    enum OpType {
        case add(CGRect)
        case remove(CGRect)
        case split(CGRect, CGRect)
        case copy(CGRect)
    }
    
    func push(op: OpType) {
        var newComposition = self.composition!.mutableCopy() as! AVMutableComposition
        
        while undoPos < stack.count - 1 {
            stack.removeLast()
        }
        
        stack.append(opsAndComps(comp: newComposition, op: op))
        undoPos = stack.count - 1
        
        redoOp(op: op)
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
    
    func equalFrame(_ aRect: CGRect, _ bRect: CGRect, digital: CGFloat) -> Bool {
        if abs(aRect.origin.x - bRect.origin.x) < digital && abs(aRect.width - bRect.width) < digital && abs(aRect.origin.y - bRect.origin.y) < digital && abs(aRect.height - bRect.height) < digital {
            return true
        } else {
            return false
        }
    }
    
    func validateTimeline() {
        
        if kCMTimeZero != composition!.duration {
            timelineView.frame.size = CGSize(width: CGFloat(CMTimeGetSeconds(composition!.duration)) * scaledDurationToWidth, height: timelineView.frame.height)
            scrollview.contentSize = timelineView.frame.size
            
            let compositionVideoTrack = self.composition!.tracks(withMediaType: AVMediaTypeVideo).first
            
            assert(compositionVideoTrack?.segments.count == timelineView.subviews.count)
            
            for segment in (compositionVideoTrack?.segments)! {
                let segmentRect = CGRect(x:CGFloat(CMTimeGetSeconds(segment.timeMapping.target.start)) * scaledDurationToWidth, y:0, width:CGFloat(CMTimeGetSeconds(segment.timeMapping.target.duration)) * scaledDurationToWidth, height:timelineView.frame.height).insetBy(dx: 1, dy: 0)
                
                var foundit = false
                for subview in timelineView.subviews {
                    if equalFrame(subview.frame, segmentRect, digital: 1) {
                        foundit = true
                        subview.frame = segmentRect
                        break
                    }
                }
                
                if foundit == false {
                    assert(false)
                }
                
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
        
        lastCenterTime = currentTime

        validateTimeline()
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
                
                let compositionVideoTrack = self.composition!.tracks(withMediaType: AVMediaTypeVideo).first
                
                if compositionVideoTrack!.segments.isEmpty {
                    try! self.composition!.insertTimeRange(CMTimeRangeMake(kCMTimeZero, newAsset.duration), of: newAsset, at: kCMTimeZero)
                    
                    let segmentRect = CGRect(x: 0, y: 0, width: self.scaledDurationToWidth * CGFloat(CMTimeGetSeconds(newAsset.duration)), height: self.timelineView.frame.height)
                    
                    self.push(op:.add(segmentRect))

                } else {
                    for s in compositionVideoTrack!.segments {
                        var timeRangeInAsset = s.timeMapping.target // assumes non-scaled edit
                        
                        if timeRangeInAsset.containsTime(self.player.currentTime()) {
                            try! self.composition!.insertTimeRange(CMTimeRangeMake(kCMTimeZero, newAsset.duration), of: newAsset, at: timeRangeInAsset.end)
                            
                            let segmentRect = CGRect(x: self.scaledDurationToWidth * CGFloat(CMTimeGetSeconds(timeRangeInAsset.start)), y: 0, width: self.scaledDurationToWidth * CGFloat(CMTimeGetSeconds(timeRangeInAsset.duration)), height: self.timelineView.frame.height)
                            
                            
                            let newSegmentRect = CGRect(x: segmentRect.maxX, y: 0, width: self.scaledDurationToWidth * CGFloat(CMTimeGetSeconds(newAsset.duration)), height: self.timelineView.frame.height)
                            
                            self.push(op:.add(newSegmentRect))
                            
                            break
                        }
                    }
                    
                }
                
                // update timeline
                self.updatePlayerAndTimeline()
            }
        }
    }
    
    func redoOp(op: OpType) {
        imageGenerator?.cancelAllCGImageGeneration()
        imageGenerator = AVAssetImageGenerator.init(asset: composition!)
        imageGenerator?.maximumSize = CGSize(width: self.timelineView.bounds.height * 2, height: self.timelineView.bounds.height)
        
        switch op {
        case let .copy(segmentRect):
            for subview in timelineView.subviews {
                if subview.frame.minX > segmentRect.maxX {
                    subview.frame.origin.x += segmentRect.width
                }
            }
            let newSegmentView = UIView(frame: segmentRect.insetBy(dx: 1, dy: 0))
            newSegmentView.backgroundColor = #colorLiteral(red: 0.9098039269, green: 0.4784313738, blue: 0.6431372762, alpha: 1)
            newSegmentView.clipsToBounds = true
            newSegmentView.frame.origin.x += segmentRect.width
            timelineView.addSubview(newSegmentView)


            if true {
                var times = [NSValue]()

                // Generate an image at time zero.
                let startTime = CMTime(seconds: Double(segmentRect.minX / scaledDurationToWidth), preferredTimescale: 60)
                let endTime = CMTime(seconds: Double(segmentRect.maxX / scaledDurationToWidth), preferredTimescale: 60)
                let incrementTime = CMTime(seconds: Double(segmentRect.height /  scaledDurationToWidth), preferredTimescale: 60)

                var iterTime = startTime

                while iterTime <= endTime {
//                    if timeRange.containsTime(iterTime) {
                    times.append(iterTime as NSValue)
//                    }
                    iterTime = CMTimeAdd(iterTime, incrementTime);
                }

                // Set a videoComposition on the ImageGenerator if the underlying movie has more than 1 video track.
                imageGenerator?.generateCGImagesAsynchronously(forTimes: times as [NSValue]) { (requestedTime, image, actualTime, result, error) in
                    if (image != nil) {
                        DispatchQueue.main.async {
                            let nextX = CGFloat(CMTimeGetSeconds(requestedTime - startTime)) * self.scaledDurationToWidth
                            let nextView = UIImageView.init(frame: CGRect(x: nextX, y: 0.0, width: newSegmentView.bounds.height, height: newSegmentView.bounds.height))
                            nextView.contentMode = .scaleAspectFill
                            nextView.clipsToBounds = true
                            nextView.image = UIImage.init(cgImage: image!)

                            newSegmentView.addSubview(nextView)
                            newSegmentView.setNeedsDisplay()
                        }
                    }
                }
            }
            
        case let .split(segmentRect, newSegmentRect):
            for subview in timelineView.subviews {
                if equalFrame(subview.frame, segmentRect.insetBy(dx: 1, dy: 0), digital: 0.00001) {
                    subview.frame.size.width = segmentRect.width - newSegmentRect.width - 2
                }
            }
            
            
            let newSegmentView = UIView(frame: newSegmentRect.insetBy(dx: 1, dy: 0))
            newSegmentView.backgroundColor = #colorLiteral(red: 0.9098039269, green: 0.4784313738, blue: 0.6431372762, alpha: 1)
            newSegmentView.clipsToBounds = true
            
            timelineView.addSubview(newSegmentView)
            
            if true {
                var times = [NSValue]()
                
                // Generate an image at time zero.
                let startTime = CMTime(seconds: Double(newSegmentRect.minX / scaledDurationToWidth), preferredTimescale: 60)
                let endTime = CMTime(seconds: Double(newSegmentRect.maxX / scaledDurationToWidth), preferredTimescale: 60)
                let incrementTime = CMTime(seconds: Double(newSegmentRect.height /  scaledDurationToWidth), preferredTimescale: 60)
                
                var iterTime = startTime
                
                while iterTime <= endTime {
                    //                    if timeRange.containsTime(iterTime) {
                    times.append(iterTime as NSValue)
                    //                    }
                    iterTime = CMTimeAdd(iterTime, incrementTime);
                }
                
                // Set a videoComposition on the ImageGenerator if the underlying movie has more than 1 video track.
                imageGenerator?.generateCGImagesAsynchronously(forTimes: times as [NSValue]) { (requestedTime, image, actualTime, result, error) in
                    if (image != nil) {
                        DispatchQueue.main.async {
                            let nextX = CGFloat(CMTimeGetSeconds(requestedTime - startTime)) * self.scaledDurationToWidth
                            let nextView = UIImageView.init(frame: CGRect(x: nextX, y: 0.0, width: newSegmentView.bounds.height, height: newSegmentView.bounds.height))
                            nextView.contentMode = .scaleAspectFill
                            nextView.clipsToBounds = true
                            nextView.image = UIImage.init(cgImage: image!)
                            
                            newSegmentView.addSubview(nextView)
                            newSegmentView.setNeedsDisplay()
                        }
                    }
                }
            }
        case let .add(segmentRect):
            for subview in self.timelineView.subviews {
                if subview.frame.minX >= segmentRect.minX {
                    subview.frame.origin.x += segmentRect.width
                }
            }
            
            let newSegmentView = UIView(frame: segmentRect.insetBy(dx: 1, dy: 0))
            
            newSegmentView.backgroundColor = #colorLiteral(red: 0.9098039269, green: 0.4784313738, blue: 0.6431372762, alpha: 1)
            newSegmentView.clipsToBounds = true
            
            self.timelineView.addSubview(newSegmentView)
            
            if true {
                var times = [NSValue]()
                
                // Generate an image at time zero.
                let startTime = CMTime(seconds: Double(segmentRect.minX / scaledDurationToWidth), preferredTimescale: 60)
                let endTime = CMTime(seconds: Double(segmentRect.maxX / scaledDurationToWidth), preferredTimescale: 60)
                let incrementTime = CMTime(seconds: Double(segmentRect.height /  scaledDurationToWidth), preferredTimescale: 60)
                
                var iterTime = startTime
                
                while iterTime <= endTime {
                    //                    if timeRange.containsTime(iterTime) {
                    times.append(iterTime as NSValue)
                    //                    }
                    iterTime = CMTimeAdd(iterTime, incrementTime);
                }
                
                // Set a videoComposition on the ImageGenerator if the underlying movie has more than 1 video track.
                imageGenerator?.generateCGImagesAsynchronously(forTimes: times as [NSValue]) { (requestedTime, image, actualTime, result, error) in
                    if (image != nil) {
                        DispatchQueue.main.async {
                            let nextX = CGFloat(CMTimeGetSeconds(requestedTime - startTime)) * self.scaledDurationToWidth
                            let nextView = UIImageView.init(frame: CGRect(x: nextX, y: 0.0, width: newSegmentView.bounds.height, height: newSegmentView.bounds.height))
                            nextView.contentMode = .scaleAspectFill
                            nextView.clipsToBounds = true
                            nextView.image = UIImage.init(cgImage: image!)
                            
                            newSegmentView.addSubview(nextView)
                            newSegmentView.setNeedsDisplay()
                        }
                    }
                }
            }
            
            break
            
        case let .remove(segmentRect):
            for subview in timelineView.subviews {
                if equalFrame(subview.frame, segmentRect.insetBy(dx: 1, dy: 0), digital: 0.00001) {
                    subview.removeFromSuperview()
                } else if subview.frame.minX > segmentRect.maxX {
                    subview.frame.origin.x -= segmentRect.width
                }
            }
        default:
            _ = 1
        }
    }
    
    func undoOp(op: OpType) {
        imageGenerator?.cancelAllCGImageGeneration()
        imageGenerator = AVAssetImageGenerator.init(asset: composition!)
        imageGenerator?.maximumSize = CGSize(width: self.timelineView.bounds.height * 2, height: self.timelineView.bounds.height)
        
        switch op {
        case let .copy(segmentRect):
            for subview in timelineView.subviews {
                if equalFrame(subview.frame, segmentRect.insetBy(dx: 1, dy: 0), digital: 0.00001) {
                    subview.removeFromSuperview()
                } else if subview.frame.minX > segmentRect.maxX {
                    subview.frame.origin.x -= segmentRect.width
                }
            }
        case let .split(segmentRect, newSegmentRect):
            var leftSegmentRect = segmentRect
            leftSegmentRect.size.width = segmentRect.width - newSegmentRect.width
            for subview in timelineView.subviews {
                if equalFrame(subview.frame, newSegmentRect.insetBy(dx: 1, dy: 0), digital: 0.00001) || equalFrame(subview.frame, leftSegmentRect.insetBy(dx: 1, dy: 0), digital: 0.00001){
                    subview.removeFromSuperview()
                }
            }
            
            
            let newSegmentView = UIView(frame: segmentRect.insetBy(dx: 1, dy: 0))
            newSegmentView.backgroundColor = #colorLiteral(red: 0.9098039269, green: 0.4784313738, blue: 0.6431372762, alpha: 1)
            newSegmentView.clipsToBounds = true
            
            timelineView.addSubview(newSegmentView)
            
            if true {
                var times = [NSValue]()
                
                // Generate an image at time zero.
                let startTime = CMTime(seconds: Double(segmentRect.minX / scaledDurationToWidth), preferredTimescale: 60)
                let endTime = CMTime(seconds: Double(segmentRect.maxX / scaledDurationToWidth), preferredTimescale: 60)
                let incrementTime = CMTime(seconds: Double(segmentRect.height /  scaledDurationToWidth), preferredTimescale: 60)
                
                var iterTime = startTime
                
                while iterTime <= endTime {
                    //                    if timeRange.containsTime(iterTime) {
                    times.append(iterTime as NSValue)
                    //                    }
                    iterTime = CMTimeAdd(iterTime, incrementTime);
                }
                
                // Set a videoComposition on the ImageGenerator if the underlying movie has more than 1 video track.
                imageGenerator?.generateCGImagesAsynchronously(forTimes: times as [NSValue]) { (requestedTime, image, actualTime, result, error) in
                    if (image != nil) {
                        DispatchQueue.main.async {
                            let nextX = CGFloat(CMTimeGetSeconds(requestedTime - startTime)) * self.scaledDurationToWidth
                            let nextView = UIImageView.init(frame: CGRect(x: nextX, y: 0.0, width: newSegmentView.bounds.height, height: newSegmentView.bounds.height))
                            nextView.contentMode = .scaleAspectFill
                            nextView.clipsToBounds = true
                            nextView.image = UIImage.init(cgImage: image!)
                            
                            newSegmentView.addSubview(nextView)
                            newSegmentView.setNeedsDisplay()
                        }
                    }
                }
            }
        case let .add(segmentRect):
            for subview in timelineView.subviews {
                if equalFrame(subview.frame, segmentRect.insetBy(dx: 1, dy: 0), digital: 0.00001) {
                    subview.removeFromSuperview()
                } else if subview.frame.minX > segmentRect.maxX {
                    subview.frame.origin.x -= segmentRect.width
                }
            }
            
            break
            
        case let .remove(segmentRect):
            for subview in self.timelineView.subviews {
                if subview.frame.minX >= segmentRect.minX {
                    subview.frame.origin.x += segmentRect.width
                }
            }
            
            let newSegmentView = UIView(frame: segmentRect.insetBy(dx: 1, dy: 0))
            
            newSegmentView.backgroundColor = #colorLiteral(red: 0.9098039269, green: 0.4784313738, blue: 0.6431372762, alpha: 1)
            newSegmentView.clipsToBounds = true
            
            self.timelineView.addSubview(newSegmentView)
            
            if true {
                var times = [NSValue]()
                
                // Generate an image at time zero.
                let startTime = CMTime(seconds: Double(segmentRect.minX / scaledDurationToWidth), preferredTimescale: 60)
                let endTime = CMTime(seconds: Double(segmentRect.maxX / scaledDurationToWidth), preferredTimescale: 60)
                let incrementTime = CMTime(seconds: Double(segmentRect.height /  scaledDurationToWidth), preferredTimescale: 60)
                
                var iterTime = startTime
                
                while iterTime <= endTime {
                    //                    if timeRange.containsTime(iterTime) {
                    times.append(iterTime as NSValue)
                    //                    }
                    iterTime = CMTimeAdd(iterTime, incrementTime);
                }
                
                // Set a videoComposition on the ImageGenerator if the underlying movie has more than 1 video track.
                imageGenerator?.generateCGImagesAsynchronously(forTimes: times as [NSValue]) { (requestedTime, image, actualTime, result, error) in
                    if (image != nil) {
                        DispatchQueue.main.async {
                            let nextX = CGFloat(CMTimeGetSeconds(requestedTime - startTime)) * self.scaledDurationToWidth
                            let nextView = UIImageView.init(frame: CGRect(x: nextX, y: 0.0, width: newSegmentView.bounds.height, height: newSegmentView.bounds.height))
                            nextView.contentMode = .scaleAspectFill
                            nextView.clipsToBounds = true
                            nextView.image = UIImage.init(cgImage: image!)
                            
                            newSegmentView.addSubview(nextView)
                            newSegmentView.setNeedsDisplay()
                        }
                    }
                }
            }
        default:
            _ = 1
        }
    }
    
    @IBAction func undo(_ sender: Any) {
        if undoPos <= 0 {
            return
        }
        
        undoPos -= 1
        self.composition = stack[undoPos].comp.mutableCopy() as! AVMutableComposition
        
        undoOp(op: stack[undoPos].op)
        
        updatePlayerAndTimeline()
    }
    
    @IBAction func redo(_ sender: Any) {
        if undoPos == stack.count - 1 {
            return
        }
        
        undoPos += 1
        self.composition = stack[undoPos].comp.mutableCopy() as! AVMutableComposition
        
        redoOp(op: stack[undoPos].op)
        
        updatePlayerAndTimeline()
    }
    
    @IBAction func splitClip(_ sender: Any) {
        var timeRangeInAsset: CMTimeRange? = nil
        
        let compositionVideoTrack = self.composition!.tracks(withMediaType: AVMediaTypeVideo).first
        
        for s in compositionVideoTrack!.segments {
            timeRangeInAsset = s.timeMapping.target // assumes non-scaled edit
            
            if timeRangeInAsset!.containsTime(player.currentTime()) {
                try! self.composition!.insertTimeRange(timeRangeInAsset!, of: composition!, at: timeRangeInAsset!.end)
                
                try! self.composition!.removeTimeRange(CMTimeRange(start:player.currentTime(), duration:timeRangeInAsset!.duration - CMTime(value: 1, timescale: 600)))
                
                let segmentRect = CGRect(x: scaledDurationToWidth * CGFloat(CMTimeGetSeconds(timeRangeInAsset!.start)), y: 0, width: scaledDurationToWidth * CGFloat(CMTimeGetSeconds(timeRangeInAsset!.duration)), height: timelineView.frame.height)
                
                let newSegmentRect = CGRect(x: scaledDurationToWidth * CGFloat(CMTimeGetSeconds(player.currentTime())), y: 0, width: scaledDurationToWidth * CGFloat(CMTimeGetSeconds(timeRangeInAsset!.end - player.currentTime())), height: timelineView.frame.height)
                
                push(op:.split(segmentRect, newSegmentRect))
                
                break
            }
        }
        
        updatePlayerAndTimeline()
    }
    
    @IBAction func copyClip(_ sender: Any) {
        var timeRangeInAsset: CMTimeRange? = nil
        
        let compositionVideoTrack = self.composition!.tracks(withMediaType: AVMediaTypeVideo).first
        
        for s in compositionVideoTrack!.segments {
            timeRangeInAsset = s.timeMapping.target; // assumes non-scaled edit
            
            if timeRangeInAsset!.containsTime(player.currentTime()) {
                try! self.composition!.insertTimeRange(timeRangeInAsset!, of: composition!, at: timeRangeInAsset!.end)
                
                let segmentRect = CGRect(x: scaledDurationToWidth * CGFloat(CMTimeGetSeconds(timeRangeInAsset!.start)), y: 0, width: scaledDurationToWidth * CGFloat(CMTimeGetSeconds(timeRangeInAsset!.duration)), height: timelineView.frame.height)
                
                push(op:.copy(segmentRect))
                
                break
            }
        }
        
        updatePlayerAndTimeline()
    }
    
    @IBAction func removeClip(_ sender: Any) {
        var timeRangeInAsset: CMTimeRange? = nil

        let compositionVideoTrack = self.composition!.tracks(withMediaType: AVMediaTypeVideo).first
        
        for s in compositionVideoTrack!.segments {
            timeRangeInAsset = s.timeMapping.target; // assumes non-scaled edit
            
            if timeRangeInAsset!.containsTime(player.currentTime()) {
                try! self.composition!.removeTimeRange(timeRangeInAsset!)
                
                let segmentRect = CGRect(x: scaledDurationToWidth * CGFloat(CMTimeGetSeconds(timeRangeInAsset!.start)), y: 0, width: scaledDurationToWidth * CGFloat(CMTimeGetSeconds(timeRangeInAsset!.duration)), height: timelineView.frame.height)
                
                push(op:.remove(segmentRect))
                
                break
            }
        }
        
        updatePlayerAndTimeline()
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
            if currentTime-lastCenterTime > 15 {
            }else if currentTime-lastCenterTime < -15 {
            }
        }
    }
}
