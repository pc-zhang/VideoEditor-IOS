
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
    
    func addImageView(_ image: UIImage!) {
        let nextX = CGFloat(self.imagesAdded) * self.bounds.height
        let nextView = UIImageView.init(frame: CGRect(x: nextX, y: 0.0, width: self.bounds.height, height: self.bounds.height))
        
        nextView.image = image
        self.addSubview(nextView)
        self.setNeedsDisplay(self.frame)
        
        self.imagesAdded = self.imagesAdded + 1
    }
    
}
