
import UIKit

protocol TimelineUpdateDelgate : NSObjectProtocol {
    
    
    func movieTimeline(_ timeline: TimelineView!, didUpdateCursorTo toPoint: CGPoint)
    
    func didSelectTimelineRange(from fromPoint: CGPoint, to toPoint: CGPoint)
    
    func didSelectTimelinePoint(_ point: CGPoint)
}

class TimelineView : UIView {
    
    var delegate: TimelineUpdateDelgate!
    var imagesAdded: Int! = 0
    
    func removeAllPositionalSubviews() {
        for subView in self.subviews.enumerated() {
            subView.element.removeFromSuperview()
        }
        
        self.imagesAdded = 0
    }
    
    func countOfImagesRequiredToFillView() -> UInt {
        return UInt(floor(self.frame.size.width / self.imageViewWidth()));
    }
    
    func addImageView(_ image: UIImage!) {
        let nextX = CGFloat(self.imagesAdded) * self.imageViewWidth();
        let nextView = UIImageView.init(frame: CGRect(x: nextX, y: 0.0, width: self.imageViewWidth(), height: self.frame.size.height))
        
        nextView.image = image;
        self.addSubview(nextView)
        self.setNeedsDisplay(self.frame)
        
        self.imagesAdded = self.imagesAdded + 1
    }
    
    func updateTimeLabel(_ newLabel: String!) {
        
    }
    
    func imageViewWidth() -> CGFloat {
        return (self.frame.size.height * 16) / 9;
    }
}
