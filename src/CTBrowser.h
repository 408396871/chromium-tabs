#pragma once
#import <Cocoa/Cocoa.h>
#import "CTTabStripModel.h"
#import "CTTabStripModelDelegate.h"
#import "CTBrowserCommand.h"

enum CTWindowOpenDisposition {
  CTWindowOpenDispositionCurrentTab,
  CTWindowOpenDispositionNewForegroundTab,
  CTWindowOpenDispositionNewBackgroundTab,
};

class CTTabStripModel;
@class CTBrowserWindowController;

// There is one CTBrowser instance per percieved window.
// A CTBrowser instance has one TabStripModel.

@interface CTBrowser : NSObject <CTTabStripModelDelegate> {
  CTTabStripModel *tabStripModel_;
  CTBrowserWindowController *windowController_;
}

// The tab strip model
@property(readonly, nonatomic) CTTabStripModel* tabStripModel;

// The window controller
@property(readonly, nonatomic) CTBrowserWindowController* windowController;

// The window. Convenience for [windowController window]
@property(readonly, nonatomic) NSWindow* window;

// Create a new browser with a window. (autoreleased)
+(CTBrowser*)browser;
+(CTBrowser*)browserWithWindowFrame:(const NSRect)frame;

// Creates and opens a new window. (retained)
+(CTBrowser*)openEmptyWindow;

// Creates a new window controller. The default implementation will create a
// controller loaded with a nib called "BrowserWindow". If the nib can't be
// found in the main bundle, a fallback nib will be loaded from the framework.
// This is usually enough since all UI which normally is customized is comprised
// within each tab (CTTabContents view).
-(CTBrowserWindowController *)createWindowController;

// Creates a new CTTabContents instance.
// |baseContents| represents the CTTabContents which is currently in the
// foreground. It might be nil.
// Subclasses could override this to provide a custom CTTabContents type.
-(CTTabContents*)createTabContentsBasedOn:(CTTabContents*)baseContents;

// Commands
-(void)newWindow;
-(void)closeWindow;
-(CTTabContents*)addTabContents:(CTTabContents*)contents
                      atIndex:(int)index
                 inForeground:(BOOL)foreground;
-(CTTabContents*)addBlankTabAtIndex:(int)index inForeground:(BOOL)foreground;
-(CTTabContents*)addBlankTabInForeground:(BOOL)foreground;
-(CTTabContents*)addBlankTab; // InForeground:YES
-(void)closeTab;
-(void)selectNextTab;
-(void)selectPreviousTab;
-(void)moveTabNext;
-(void)moveTabPrevious;
-(void)selectTabAtIndex:(int)index;
-(void)selectLastTab;
-(void)duplicateTab;

-(void)executeCommand:(int)cmd
      withDisposition:(CTWindowOpenDisposition)disposition;
-(void)executeCommand:(int)cmd; // withDisposition:CURRENT_TAB

// callbacks
-(void)loadingStateDidChange:(CTTabContents*)contents;
-(void)windowDidBeginToClose;

// Convenience helpers (proxy for TabStripModel)
-(int)tabCount;
-(int)selectedTabIndex;
-(CTTabContents*)selectedTabContents;
-(CTTabContents*)tabContentsAtIndex:(int)index;
-(void)selectTabContentsAtIndex:(int)index userGesture:(BOOL)userGesture;
-(void)closeAllTabs;

@end
