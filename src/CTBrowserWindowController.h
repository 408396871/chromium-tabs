#import <Cocoa/Cocoa.h>
#import "CTBrowser.h"
#import "CTTabStripModelDelegate.h"
#import "CTTabWindowController.h"

@class CTTabStripController;
class CTTabStripModelObserverBridge;

@interface CTBrowserWindowController : CTTabWindowController {
  CTBrowser* browser_;
  CTTabStripController *tabStripController_;
  CTTabStripModelObserverBridge *tabStripObserver_;
 @private
  BOOL initializing_; // true if the instance is initializing
}

@property(readonly, nonatomic) CTTabStripController *tabStripController;
@property(readonly, nonatomic) CTBrowser *browser;

- (id)initWithWindowNibPath:(NSString *)windowNibPath
                    browser:(CTBrowser*)browser;

// Make the (currently-selected) tab contents the first responder, if possible.
- (void)focusTabContents;

// Returns fullscreen state.
- (BOOL)isFullscreen;

// Lays out the tab content area in the given frame. If the height changes,
// sends a message to the renderer to resize.
- (void)layoutTabContentArea:(NSRect)frame;

@end
