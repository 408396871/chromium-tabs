#import "AppDelegate.h"
#import <ChromiumTabs/ChromiumTabs.h>

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  NSLog(@"applicationDidFinishLaunching");
  // Create a browser and show the window
  [CTBrowser openEmptyWindow];
}

- (void)commandDispatch:(id)sender {
  assert(sender);
  switch ([sender tag]) {
    // Window management commands
    case CTBrowserCommandNewWindow:
    case CTBrowserCommandNewTab:     [CTBrowser openEmptyWindow]; break;
    case CTBrowserCommandExit:       [NSApp terminate:self]; break;
  }
}


@end
