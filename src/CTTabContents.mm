#import "CTTabContents.h"
#import "CTTabStripModel.h"
#import "CTBrowser.h"

const NSString* CTTabContentsDidCloseNotification =
    @"CTTabContentsDidCloseNotification";

@implementation CTTabContents

// Custom @synthesize which invokes [browser_ updateTabStateForContent:self]
// when setting values.
#define _synthRetain(T, setname, getname) \
- (T)getname { return getname##_; } \
- (void)set##setname :(T)v { \
  objc_exch(&(getname##_), v); \
  if (browser_) [browser_ updateTabStateForContent:self]; \
}
#define _synthAssign(T, setname, getname) \
- (T)getname { return getname##_; } \
- (void)set##setname :(T)v { \
  getname##_ = v; \
  if (browser_) [browser_ updateTabStateForContent:self]; \
}

@synthesize isApp = isApp_;

// setting any of these implies [browser_ updateTabStateForContent:self]

_synthAssign(BOOL, IsLoading, isLoading);
_synthAssign(BOOL, IsWaitingForResponse, isWaitingForResponse);
_synthAssign(BOOL, IsCrashed, isCrashed);

@synthesize delegate = delegate_;
@synthesize closedByUserGesture = closedByUserGesture_;
@synthesize view = view_;

_synthRetain(NSString*, Title, title);
_synthRetain(NSImage*, Icon, icon);

@synthesize browser = browser_;

#undef _synth


-(id)initWithBaseTabContents:(CTTabContents*)baseContents {
  // subclasses should probably override this
  self.parentOpener = baseContents;
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


- (CTTabContents*)parentOpener {
  return parentOpener_;
}

- (void)setParentOpener:(CTTabContents*)parentOpener {
  NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
  if (parentOpener_) {
    [nc removeObserver:self
                  name:CTTabContentsDidCloseNotification
                object:parentOpener_];
  }
  parentOpener_ = parentOpener; // weak
  if (parentOpener_) {
    [nc addObserver:self
           selector:@selector(tabContentsDidClose:)
               name:CTTabContentsDidCloseNotification
             object:parentOpener_];
  }
}

- (void)tabContentsDidClose:(NSNotification*)notification {
  // detach (NULLify) our parentOpener_ when it closes
  CTTabContents* tabContents = [notification object];
  if (tabContents == parentOpener_) {
    parentOpener_ = nil;
  }
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
  NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:CTTabContentsDidCloseNotification object:self];
}

// Called when this tab was inserted into a browser
- (void)tabDidInsertIntoBrowser:(CTBrowser*)browser
                        atIndex:(NSInteger)index
                   inForeground:(bool)foreground {
  browser_ = browser;
}

// Called when this tab is about to close
- (void)tabWillCloseInBrowser:(CTBrowser*)browser atIndex:(NSInteger)index {
  browser_ = nil;
}

// Called when this tab was removed from a browser
- (void)tabDidDetachFromBrowser:(CTBrowser*)browser atIndex:(NSInteger)index {
  browser_ = nil;
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
  [view_ setFrame:newFrame];
}

@end
