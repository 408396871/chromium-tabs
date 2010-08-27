#import "CTTabContents.h"
#import "CTTabStripModel.h"

@implementation CTTabContents

@synthesize isApp = isApp_;
@synthesize isLoading = isLoading_;
@synthesize isWaitingForResponse = isWaitingForResponse_;
@synthesize isCrashed = isCrashed_;
@synthesize delegate = delegate_;
@synthesize closedByUserGesture = closedByUserGesture_;
@synthesize view = view_;
@synthesize title = title_;
@synthesize icon = icon_;

-(id)initWithBaseTabContents:(CTTabContents*)baseContents {
  // subclasses should probably override this
  return [super init];
}

-(void)dealloc {
  [super dealloc];
}

-(void)destroy:(CTTabStripModel*)sender {
  // TODO: notify "disconnected"?
  sender->TabContentsWasDestroyed(self); // TODO: NSNotification
  [self release];
}

-(BOOL)hasIcon {
  return YES;
}

-(void)setIsVisible:(BOOL)visible {
  if (isVisible_ != visible && !isTeared_) {
    isVisible_ = visible;
    if (isVisible_) {
      [self tabDidBecomeVisible];
    } else {
      [self tabDidResignVisible];
    }
  }
}

-(BOOL)isVisible {
  return isVisible_;
}

-(void)setIsSelected:(BOOL)selected {
  if (isSelected_ != selected && !isTeared_) {
    isSelected_ = selected;
    if (isSelected_) {
      [self tabDidBecomeSelected];
    } else {
      [self tabDidResignSelected];
    }
  }
}

-(BOOL)isSelected {
  return isSelected_;
}

-(void)setIsTeared:(BOOL)teared {
  if (isTeared_ != teared) {
    isTeared_ = teared;
    if (isTeared_) {
      [self tabWillBecomeTeared];
    } else {
      [self tabWillResignTeared];
    }
  }
}

-(BOOL)isTeared {
  return isTeared_;
}

-(void)closingOfTabDidStart:(CTTabStripModel*)closeInitiatedByTabStripModel {
  // subclasses can implement this
  //NSLog(@"CTTabContents closingOfTabDidStart");
}

-(void)tabDidBecomeSelected {
  if (isVisible_)
    [[view_ window] makeFirstResponder:view_];
}

-(void)tabDidResignSelected {}
-(void)tabDidBecomeVisible {}
-(void)tabDidResignVisible {}

-(void)tabWillBecomeTeared {
  // Teared tabs should always be visible and selected since tearing is invoked
  // by the user selecting the tab on screen.
  assert(isVisible_);
  assert(isSelected_);
}

-(void)tabWillResignTeared {
  assert(isVisible_);
  assert(isSelected_);
}

// Unlike the above callbacks, this one is explicitly called by
// CTBrowserWindowController
-(void)tabDidResignTeared {
  [[view_ window] makeFirstResponder:view_];
}

-(void)viewFrameDidChange:(NSRect)newFrame {
  DLOG("viewFrameDidChange viewFrameDidChange viewFrameDidChange");
  [view_ setFrame:newFrame];
}

@end
