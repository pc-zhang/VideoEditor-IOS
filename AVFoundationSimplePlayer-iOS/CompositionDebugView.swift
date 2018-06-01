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

class CompositionDebugView : UIView {
    
    var drawingLayer: CALayer? = nil
    var duration: CMTime? = nil
    var compositionRectWidth: CGFloat = 0.0
    
    var compositionTracks: NSArray = []
    var audioMixTracks: NSArray = []
    var videoCompositionStages: NSArray = []
    var scaledDurationToWidth: CGFloat = 0.0
    
    var player: AVPlayer! = nil
    
    
    func synchronize(_ composition: AVComposition!, videoComposition: AVVideoComposition!, audioMix: AVAudioMix!) {
        
    }
}
