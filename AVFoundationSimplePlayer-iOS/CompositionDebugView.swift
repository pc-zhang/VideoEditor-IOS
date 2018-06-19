//
//  CompositionDebugView.swift
//  AVFoundationSimplePlayer-iOS
//
//  Created by zpc on 2018/6/1.
//  Copyright © 2018年 Apple Inc. All rights reserved.
//

import UIKit
import CoreMedia.CMTime
import AVFoundation

let kLeftInsetToMatchTimeSlider:CGFloat = 50
let kRightInsetToMatchTimeSlider:CGFloat = 60
let kLeftMarginInset:CGFloat = 4

let kBannerHeight:CGFloat = 20
let kIdealRowHeight:CGFloat = 36
let kGapAfterRows:CGFloat = 4


class CompositionDebugView : UIView {
    
    var drawingLayer: CALayer? = nil
    var duration: CMTime? = nil
    var compositionRectWidth: CGFloat = 0.0
    var scaledDurationToWidth: Double = 0.0
    var composition: AVComposition? = nil
    var audioMix: AVAudioMix? = nil
    var videoComposition: AVVideoComposition? = nil
    
    var player: AVPlayer! = nil
        
    override init(frame: CGRect) {
        super.init(frame: frame)
        drawingLayer = self.layer
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
//        fatalError("init(coder:) has not been implemented")
    }
    
    override func willMove(toSuperview newSuperview: UIView?) {
        drawingLayer?.frame = self.bounds
        drawingLayer?.delegate = self
        drawingLayer?.setNeedsDisplay()
    }
    
    
//    func drawVerticallyCenteredInRect(_ rect: CGRect, withAttributes attributes:NSDictionary) -> Void
//    {
//        CGSize size = [self sizeWithAttributes:attributes]
//        rect.origin.y += (rect.size.height - size.height) / 2.0
//        [self drawInRect:rect withAttributes:attributes]
//    }
    
    func horizontalPositionForTime(time:CMTime)->Double
    {
        var seconds: Double = 0
        if CMTIME_IS_NUMERIC(time) && time > kCMTimeZero {
            seconds = CMTimeGetSeconds(time)
        }
        
        return seconds * scaledDurationToWidth + Double(kLeftInsetToMatchTimeSlider) + Double(kLeftMarginInset)
    }
    
    override func draw(_ rect: CGRect) {
        if composition == nil {
            return
        }
        let context = UIGraphicsGetCurrentContext()
        
        var rect = rect.insetBy(dx: CGFloat(kLeftMarginInset), dy: 4.0)
        
        let numBanners: CGFloat = 1
        let numRows = CGFloat((composition?.tracks.count)!)
//            + (videoComposition != nil)
        //    + (int)[_audioMix count]
        
        let totalBannerHeight = numBanners * CGFloat(kBannerHeight + kGapAfterRows)
        var rowHeight = kIdealRowHeight
        if ( numRows > 0 ) {
            let maxRowHeight = (rect.size.height - totalBannerHeight) / CGFloat(numRows)
            rowHeight = min( rowHeight, maxRowHeight )
        }
        
        var runningTop = rect.origin.y
        var bannerRect = rect
        bannerRect.size.height = CGFloat(kBannerHeight)
        bannerRect.origin.y = runningTop
        
        var rowRect = rect
        rowRect.size.height = CGFloat(rowHeight)
        
        rowRect.origin.x += CGFloat(kLeftInsetToMatchTimeSlider)
        rowRect.size.width -= CGFloat(kLeftInsetToMatchTimeSlider + kRightInsetToMatchTimeSlider)
        compositionRectWidth = rowRect.size.width
        
        scaledDurationToWidth = Double(compositionRectWidth) / CMTimeGetSeconds(composition!.duration)
        
        if ((composition) != nil) {
            bannerRect.origin.y = runningTop
            context!.setFillColor(red: 0, green: 0, blue: 0, alpha: 1) // black
            
            runningTop += bannerRect.size.height
            
            for track in (composition?.tracks)! {
                rowRect.origin.y = runningTop
                var segmentRect = rowRect
                for segment in track.segments {
                    segmentRect.size.width = CGFloat(CMTimeGetSeconds(segment.timeMapping.source.duration) * scaledDurationToWidth)
                    
                    if (segment.isEmpty) {
                        context!.setFillColor(red: 0, green: 0, blue: 0, alpha: 1) // white
//                        [@"Empty" drawVerticallyCenteredInRect:segmentRect withAttributes:textAttributes];
                    }
                    else {
                        if (track.mediaType == AVMediaTypeVideo) {
                            context!.setFillColor(red: 0, green: 0.36, blue: 0.36, alpha: 1) // blue-green
                            context!.setStrokeColor(red: 0, green: 0.5, blue: 0.5, alpha: 1)
                        }
                        else {
                            context!.setFillColor(red: 0, green: 0.24, blue: 0.36, alpha: 1) // blue-green
                            context!.setStrokeColor(red: 0, green: 0.33, blue: 0.6, alpha: 1)
                        }
                        context!.setLineWidth(2.0);
                        context!.addRect(segmentRect.insetBy(dx: 3, dy: 3))
                        context!.drawPath(using: .fillStroke)
                        
                        context!.setFillColor(red: 0, green: 0, blue: 0, alpha: 1) // blue-green
                        //                    [segment->description drawVerticallyCenteredInRect:segmentRect withAttributes:textAttributes];
                    }
                    
                    segmentRect.origin.x += segmentRect.size.width;
                }
                
                runningTop += rowRect.size.height
            }
            runningTop += CGFloat(kGapAfterRows)
        }
        
        
        if (composition != nil) {
            self.layer.sublayers = nil
            var currentTimeRect = self.layer.bounds

            // The red band of the timeMaker will be 8 pixels wide
            currentTimeRect.origin.x = 0
            currentTimeRect.size.width = 8

            var timeMarkerRedBandLayer = CAShapeLayer()
            timeMarkerRedBandLayer.frame = currentTimeRect
            timeMarkerRedBandLayer.position = CGPoint(x:rowRect.origin.x, y:self.bounds.size.height / 2)
            let linePath = CGPath(rect: currentTimeRect, transform: nil)
            timeMarkerRedBandLayer.fillColor = #colorLiteral(red: 1, green: 0, blue: 0, alpha: 0.5)
            timeMarkerRedBandLayer.path = linePath

            currentTimeRect.origin.x = 0
            currentTimeRect.size.width = 1

            // Position the white line layer of the timeMarker at the center of the red band layer
            var timeMarkerWhiteLineLayer = CAShapeLayer()
            timeMarkerWhiteLineLayer.frame = currentTimeRect
            timeMarkerWhiteLineLayer.position = CGPoint(x:4, y:self.bounds.size.height / 2)
            let whiteLinePath = CGPath(rect: currentTimeRect, transform: nil)
            timeMarkerWhiteLineLayer.fillColor = #colorLiteral(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            timeMarkerWhiteLineLayer.path = whiteLinePath

            // Add the white line layer to red band layer, by doing so we can only animate the red band layer which in turn animates its sublayers
            timeMarkerRedBandLayer.addSublayer(timeMarkerWhiteLineLayer)

            // This scrubbing animation controls the x position of the timeMarker
            // On the left side it is bound to where the first segment rectangle of the composition starts
            // On the right side it is bound to where the last segment rectangle of the composition ends
            // Playback at rate 1.0 would take the timeMarker "duration" time to reach from one end to the other, that is marked as the duration of the animation
            let scrubbingAnimation = CABasicAnimation(keyPath: "position.x")
            scrubbingAnimation.fromValue = horizontalPositionForTime(time: kCMTimeZero)
            scrubbingAnimation.toValue = horizontalPositionForTime(time: (composition?.duration)!)
            scrubbingAnimation.isRemovedOnCompletion = false
            scrubbingAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
            scrubbingAnimation.duration = CMTimeGetSeconds((composition?.duration)!)
            scrubbingAnimation.fillMode = kCAFillModeBoth
            timeMarkerRedBandLayer.add(scrubbingAnimation, forKey: nil)

            // We add the red band layer along with the scrubbing animation to a AVSynchronizedLayer to have precise timing information
            let syncLayer = AVSynchronizedLayer(playerItem: self.player.currentItem!)
            syncLayer.addSublayer(timeMarkerRedBandLayer)
            self.layer.addSublayer(syncLayer)
        }
    }
    
    
}
