//
//  SegmentView.swift
//  AVFoundationSimplePlayer-iOS
//
//  Created by zpc on 2018/6/27.
//  Copyright © 2018年 Apple Inc. All rights reserved.
//

import UIKit

class SegmentView: UICollectionViewCell {
    override var transform: CGAffineTransform {
        get { return super.transform }
        set {
            var t = newValue
            t.d = 1.0
            super.transform = t
        }
    }
}
