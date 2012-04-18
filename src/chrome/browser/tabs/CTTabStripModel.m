//
//  CTTabStripModel.m
//  chromium-tabs
//
// Copyright (c) 2010 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE-chromium file.
//

#import "CTTabStripModel.h"
#import "CTTabStripModelOrderController.h"
#import "CTPageTransition.h"

#import "CTTabContents.h"

@interface CTTabStripModel (PrivateMethods)
// Returns true if the specified CTTabContents is a New Tab at the end of the
// TabStrip. We check for this because opener relationships are _not_
// forgotten for the New Tab page opened as a result of a New Tab gesture
// (e.g. Ctrl+T, etc) since the user may open a tab transiently to look up
// something related to their current activity.
- (bool)IsNewTabAtEndOfTabStrip:(CTTabContents *)contents;

// Closes the CTTabContents at the specified indices. This causes the
// CTTabContents to be destroyed, but it may not happen immediately.  If the
// page in question has an unload event the CTTabContents will not be destroyed
// until after the event has completed, which will then call back into this
// method.
//
// Returns true if the CTTabContents were closed immediately, false if we are
// waiting for the result of an onunload handler.
- (bool)internalCloseTabs:(NSArray *)indices
			   closeTypes:(uint32)close_types;

// Invoked from InternalCloseTabs and when an extension is removed for an app
// tab. Notifies observers of TabClosingAt and deletes |contents|. If
// |create_historical_tabs| is true, CreateHistoricalTab is invoked on the
// delegate.
//
// The boolean parameter create_historical_tab controls whether to
// record these tabs and their history for reopening recently closed
// tabs.
- (void)internalCloseTab:(CTTabContents *)contents
				 atIndex:(int)index
	 createHistoricalTab:(bool)create_historical_tabs;

// The actual implementation of SelectTabContentsAt. Takes the previously
// selected contents in |old_contents|, which may actually not be in
// |contents_| anymore because it may have been removed by a call to say
// DetachTabContentsAt...
- (void)ChangeSelectedContentsFrom:(CTTabContents *)old_contents
						   toIndex:(int)to_index
					   userGesture:(bool)user_gesture;

// Returns the number of New Tab tabs in the TabStripModel.
//- (int)newTabCount;

// Selects either the next tab (|foward| is true), or the previous tab
// (|forward| is false).
- (void)SelectRelativeTab:(bool)forward;

// Returns the first non-phantom tab starting at |index|, skipping the tab at
// |ignore_index|.
- (int)indexOfNextNonPhantomTabFromIndex:(int)index
							 ignoreIndex:(int)ignore_index;

// Returns true if the tab at the specified index should be made phantom when
// the tab is closing.
- (bool)ShouldMakePhantomOnClose:(int)index;

// Makes the tab a phantom tab.
//- (void)MakePhantom:(int)index;

// Does the work of MoveTabContentsAt. This has no checks to make sure the
// position is valid, those are done in MoveTabContentsAt.
- (void)moveTabContentsAtImpl:(int)index
				   toPosition:(int)to_position
			  selectAfterMove:(bool)select_after_move;

// Returns true if the tab represented by the specified data has an opener
// that matches the specified one. If |use_group| is true, then this will
// fall back to check the group relationship as well.
//struct TabContentsData;
//static bool OpenerMatches(const TabContentsData* data,
//                          const NavigationController* opener,
//                          bool use_group);

// Does the work for ReplaceTabContentsAt returning the old CTTabContents.
// The caller owns the returned CTTabContents.
- (CTTabContents *)replaceTabContentsAtImpl:(int)index
							   withContents:(CTTabContents *)new_contents
								replaceType:(CTTabReplaceType)type;
@end

@interface TabContentsData : NSObject {
@public
    CTTabContents* contents;
	BOOL isPinned;
	BOOL isBlocked;
}
@end

@implementation TabContentsData

@end

@implementation CTTabStripModel {
	// Our delegate.
    NSObject<CTTabStripModelDelegate> *delegate_;
	
	// The CTTabContents data currently hosted within this TabStripModel.
	NSMutableArray *contents_data_;
	
	// The index of the CTTabContents in |contents_| that is currently selected.
	int selected_index_;
	
	// A profile associated with this TabStripModel, used when creating new Tabs.
	//Profile* profile_;
	
	// True if all tabs are currently being closed via CloseAllTabs.
	bool closing_all_;
	
	// An object that determines where new Tabs should be inserted and where
	// selection should move when a Tab is closed.
	CTTabStripModelOrderController *order_controller_;
	
	// Our observers.
	//	TabStripModelObservers observers_;
	
	// A scoped container for notification registries.
	//NotificationRegistrar registrar_;	
}

@synthesize delegate = delegate_;
@synthesize selected_index = selected_index_;
@synthesize closing_all = closing_all_;
@synthesize order_controller = order_controller_;

NSString* const CTTabInsertedNotification = @"CTTabInsertedNotification";
NSString* const CTTabClosingNotification = @"CTTabClosingNotification";
NSString* const CTTabDetachedNotification = @"CTTabDetachedNotification";
NSString* const CTTabDeselectedNotification = @"CTTabDeselectedNotification";
NSString* const CTTabSelectedNotification = @"CTTabSelectedNotification";
NSString* const CTTabMovedNotification = @"CTTabMovedNotification";
NSString* const CTTabChangedNotification = @"CTTabChangedNotification";
NSString* const CTTabReplacedNotification = @"CTTabReplacedNotification";
NSString* const CTTabPinnedStateChangedNotification = @"CTTabPinnedStateChangedNotification";
NSString* const CTTabBlockedStateChangedNotification = @"CTTabBlockedStateChangedNotification";
NSString* const CTTabMiniStateChangedNotification = @"CTTabMiniStateChangedNotification";
NSString* const CTTabStripEmptyNotification = @"CTTabStripEmptyNotification";
NSString* const CTTabStripModelDeletedNotification = @"CTTabStripModelDeletedNotification";

NSString* const CTTabContentsUserInfoKey = @"CTTabContentsUserInfoKey";
NSString* const CTTabNewContentsUserInfoKey = @"CTTabNewContentsUserInfoKey";
NSString* const CTTabIndexUserInfoKey = @"CTTabIndexUserInfoKey";
NSString* const CTTabToIndexUserInfoKey = @"CTTabToIndexUserInfoKey";
NSString* const CTTabForegroundUserInfoKey = @"CTTabForegroundUserInfoKey";
NSString* const CTTabUserGestureUserInfoKey = @"CTTaUserGestureUserInfoKey";
NSString* const CTTabOptionsUserInfoKey = @"CTTaOptionsInfoKey";

const int kNoTab = NSNotFound;

- (id)initWithDelegate:(NSObject <CTTabStripModelDelegate>*)delegate {
	self = [super init];
	if (self) {	
		contents_data_ = [[NSMutableArray alloc] init];
		selected_index_ = kNoTab;
		closing_all_ = false;
		//order_controller_ = NULL;
		
		delegate_ = delegate; // weak
		// TODO replace with nsnotificationcenter?
		/*registrar_.Add(this,
		 NotificationType::TAB_CONTENTS_DESTROYED,
		 NotificationService::AllSources());
		 registrar_.Add(this,
		 NotificationType::EXTENSION_UNLOADED);*/
		order_controller_ = [[CTTabStripModelOrderController alloc] initWithTabStripModel:self];
		
	}

	return self;
}

- (void)dealloc {
//	CALL_EACH_OBSERVER(observers_, @selector(tabStripModelDeleted), [observer tabStripModelDeleted]);
    [[NSNotificationCenter defaultCenter] postNotificationName:CTTabStripModelDeletedNotification 
														object:self];
	
	delegate_ = NULL; // weak
	
//	[order_controller_ release];
//	[contents_data_ release];
//    [super dealloc];
}

//- (void)AddObserver:(NSObject <CTTabStripModelObserver>*)observer {
//	observers_.AddObserver(observer);
//}
//
//- (void)RemoveObserver:(NSObject <CTTabStripModelObserver>*)observer {
//	observers_.RemoveObserver(observer);	
//}


#pragma mark -
#pragma mark getters/setters
- (NSUInteger)count {
	return [contents_data_ count];
}

- (bool)hasNonPhantomTabs {
	/*for (int i = 0; i < count(); i++) {
	 if (!IsPhantomTab(i))
	 return true;
	 }
	 return false;*/
	return !![self count];
}

// Sets the insertion policy. Default is INSERT_AFTER.
- (void)SetInsertionPolicy:(InsertionPolicy)policy {
	[order_controller_ setInsertionPolicy:policy];
}

- (InsertionPolicy)insertion_policy {
	return order_controller_.insertionPolicy;
}
//
//- (bool)HasObserver:(NSObject <CTTabStripModelObserver>*)observer {
//	return observers_.HasObserver(observer);
//}

#pragma mark -
#pragma mark Basic API
- (BOOL)containsIndex:(NSInteger)index {
    return index >= 0 && index < [self count];
}

- (void)appendTabContents:(CTTabContents *)contents
			 inForeground:(bool)foreground {
	int index = [order_controller_ determineInsertionIndexForAppending];
	[self insertTabContents:contents 
					atIndex:index 
			   withAddTypes:foreground ? (ADD_INHERIT_GROUP | ADD_SELECTED) :
	 ADD_NONE];
}

- (void)insertTabContents:(CTTabContents *)contents
				  atIndex:(int)index 
			 withAddTypes:(int)add_types {
	bool foreground = add_types & ADD_SELECTED;
	// Force app tabs to be pinned.
	bool pin = contents.isApp || add_types & ADD_PINNED;
	index = [self constrainInsertionIndex:index 
								  miniTab:pin];
	
	// In tab dragging situations, if the last tab in the window was detached
	// then the user aborted the drag, we will have the |closing_all_| member
	// set (see DetachTabContentsAt) which will mess with our mojo here. We need
	// to clear this bit.
	closing_all_ = false;
	
	// Have to get the selected contents before we monkey with |contents_|
	// otherwise we run into problems when we try to change the selected contents
	// since the old contents and the new contents will be the same...
	CTTabContents* selected_contents = [self selectedTabContents];
	TabContentsData* data = [[TabContentsData alloc] init];
	data->contents = contents;
	data->isPinned = pin;
//	contents.isPinned = pin;
	//data->pinned = pin;
	
	//contents_data_.insert(contents_data_.begin() + index, data);
	[contents_data_ insertObject:data atIndex:index];
	
	if (index <= selected_index_) {
		// If a tab is inserted before the current selected index,
		// then |selected_index| needs to be incremented.
		++selected_index_;
	}
	
    NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                              contents, CTTabContentsUserInfoKey,
                              [NSNumber numberWithInt:index], CTTabIndexUserInfoKey,
                              [NSNumber numberWithBool:foreground], CTTabForegroundUserInfoKey, 
                              nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:CTTabInsertedNotification 
														object:self 
													  userInfo:userInfo];
	
	if (foreground)
		[self ChangeSelectedContentsFrom:selected_contents
								 toIndex:index
							 userGesture:false];
}


- (void)replaceTabContentsAtIndex:(int)index 
					withContents:(CTTabContents *)new_contents 
					 replaceType:(CTTabReplaceType)type {
	[self replaceTabContentsAtImpl:index
					  withContents:new_contents
					   replaceType:type];
}

- (CTTabContents *)detachTabContentsAtIndex:(int)index {
	if ([contents_data_ count] == 0)
		return NULL;
	
	assert([self containsIndex:index]);
	
	CTTabContents* removed_contents = [self tabContentsAtIndex:index];
	int next_selected_index =
	[order_controller_ determineNewSelectedIndexAfterClose:index 
												  isRemove:true];
//	delete contents_data_.at(index);
//	contents_data_.erase(contents_data_.begin() + index);
	[contents_data_ removeObjectAtIndex:index];
	next_selected_index = [self indexOfNextNonPhantomTabFromIndex:next_selected_index ignoreIndex:-1];
	if ([self hasNonPhantomTabs])
		closing_all_ = true;
//	TabStripModelObservers::Iterator iter(observers_);
//	while (NSObject <CTTabStripModelObserver> *obs = iter.GetNext()) {
//		if ([obs respondsToSelector:@selector(tabDetachedWithContents:atIndex:)]) {
//			[obs tabDetachedWithContents:removed_contents
//								 atIndex:index];
//			if (![self hasNonPhantomTabs] && [obs respondsToSelector:@selector(tabStripEmpty)])
//			[obs tabStripEmpty];
//		}
//	}
	
    NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                              removed_contents, CTTabContentsUserInfoKey,
                              [NSNumber numberWithInt:index], CTTabIndexUserInfoKey,
                              nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:CTTabDetachedNotification 
														object:self 
													  userInfo:userInfo];
    if (![self count]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:CTTabStripEmptyNotification 
															object:self 
														  userInfo:nil];
    }
	if ([self hasNonPhantomTabs]) {
		if (index == selected_index_) {
			[self ChangeSelectedContentsFrom:removed_contents
									 toIndex:next_selected_index
								 userGesture:false];
		} else if (index < selected_index_) {
			// The selected tab didn't change, but its position shifted; update our
			// index to continue to point at it.
			--selected_index_;
		}
	}
	return removed_contents;
}

- (void)selectTabContentsAtIndex:(int)index 
					 userGesture:(BOOL)userGesture {
	if ([self containsIndex:index]) {
		[self ChangeSelectedContentsFrom:[self selectedTabContents]
								 toIndex:index
							 userGesture:userGesture];
	} else {
		DLOG("[ChromiumTabs] internal inconsistency: !ContainsIndex(index) in %s",
			 __PRETTY_FUNCTION__);
	}
}

- (void)moveTabContentsAtIndex:(int)index 
					   toIndex:(int)to_position 
			   selectAfterMove:(bool)select_after_move {
	assert([self containsIndex:index]);
	if (index == to_position)
		return;
	
	int first_non_mini_tab = [self IndexOfFirstNonMiniTab];
	if ((index < first_non_mini_tab && to_position >= first_non_mini_tab) ||
		(to_position < first_non_mini_tab && index >= first_non_mini_tab)) {
		// This would result in mini tabs mixed with non-mini tabs. We don't allow
		// that.
		return;
	}
	
	[self moveTabContentsAtImpl:index
					 toPosition:to_position
				selectAfterMove:select_after_move];
}

- (CTTabContents *)selectedTabContents {
	return [self tabContentsAtIndex:selected_index_];
}

- (CTTabContents *)tabContentsAtIndex:(int)index {
    if ([self containsIndex:index]) {
		TabContentsData* data = [contents_data_ objectAtIndex:index];
		return data->contents;
    }
    return nil;
}

- (int)indexOfTabContents:(const CTTabContents *)contents {
	int index = 0;
    for (TabContentsData* data in contents_data_) {
        if (data->contents == contents) {
            return index;
        }
        index++;
    }
	
	return kNoTab;
}

- (void)updateTabContentsStateAtIndex:(int)index 
						   changeType:(CTTabChangeType)changeType {
	assert([self containsIndex:index]);
//	CALL_EACH_OBSERVER(observers_, @selector(tabChangedWithContents:atIndex:changeType:),
//					  [observer tabChangedWithContents:[self contentsAtIndex:index] atIndex:index changeType:change_type]);
	
    NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
							  [self tabContentsAtIndex:index], CTTabContentsUserInfoKey,
                              [NSNumber numberWithInt:index], CTTabIndexUserInfoKey,
                              [NSNumber numberWithInt:changeType], CTTabOptionsUserInfoKey, 
                              nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:CTTabChangedNotification 
														object:self 
													  userInfo:userInfo];
}

- (void)closeAllTabs {
	closing_all_ = true;
	NSMutableArray *closing_tabs = [NSMutableArray array];
	for (int i = [self count] - 1; i >= 0; --i)
		[closing_tabs addObject:[NSNumber numberWithInt:i]];
	[self internalCloseTabs:closing_tabs closeTypes:CLOSE_CREATE_HISTORICAL_TAB];
}

- (bool)closeTabContentsAtIndex:(int)index 
				 closeTypes:(uint32)close_types {
	return [self internalCloseTabs:[NSArray arrayWithObject:[NSNumber numberWithInt:index]]
						closeTypes:close_types];
}

- (bool)tabsAreLoading {
//	TabContentsDataVector::const_iterator iter = contents_data_.begin();
//	for (; iter != contents_data_.end(); ++iter) {
//		if ((*iter)->contents.isLoading)
//			return true;
//	}
//	return false;
	for (TabContentsData *data in contents_data_) {
		if (data->contents.isLoading)
			return true;
	}
	return false;
}

- (void)TabNavigating:(CTTabContents *)contents
	   withTransition:(CTPageTransition)transition {
	
}

- (void)setTabAtIndex:(int)index 
			  blocked:(bool)blocked {
	assert([self containsIndex:index]);
	TabContentsData *data = [contents_data_ objectAtIndex:index];
	CTTabContents *contents = data->contents;
	if (data->isBlocked == blocked) {
		return;
	}
	data->isBlocked = blocked;
//	CALL_EACH_OBSERVER(observers_, @selector(tabBlockedStateChangedWithContents:atIndex:), [observer tabBlockedStateChangedWithContents:contents atIndex:index]);
	
    NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
							  contents, CTTabContentsUserInfoKey,
                              [NSNumber numberWithInt:index], CTTabIndexUserInfoKey,
                              [NSNumber numberWithInt:blocked], CTTabOptionsUserInfoKey, 
                              nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:CTTabBlockedStateChangedNotification
														object:self 
													  userInfo:userInfo];
}

- (void)setTabAtIndex:(int)index 
			   pinned:(bool)pinned {
	TabContentsData *data = [contents_data_ objectAtIndex:index];
	CTTabContents *contents = data->contents;
	if (data->isPinned == pinned)
		return;
	
	if ([self IsAppTab:index]) {
		if (!pinned) {
			// App tabs should always be pinned.
			NOTREACHED();
			return;
		}
		// Changing the pinned state of an app tab doesn't effect it's mini-tab
		// status.
		data->isPinned = pinned;
	} else {
		// The tab is not an app tab, it's position may have to change as the
		// mini-tab state is changing.
		int non_mini_tab_index = [self IndexOfFirstNonMiniTab];
		data->isPinned = pinned;
		if (pinned && index != non_mini_tab_index) {
			[self moveTabContentsAtImpl:index toPosition:non_mini_tab_index selectAfterMove:false];
			return;  // Don't send TabPinnedStateChanged notification.
		} else if (!pinned && index + 1 != non_mini_tab_index) {
			[self moveTabContentsAtImpl:index toPosition:non_mini_tab_index - 1 selectAfterMove:false];
			return;  // Don't send TabPinnedStateChanged notification.
		}
	
	    NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  contents, CTTabContentsUserInfoKey,
								  [NSNumber numberWithInt:index], CTTabIndexUserInfoKey,
								  nil];
		[[NSNotificationCenter defaultCenter] postNotificationName:CTTabMiniStateChangedNotification
															object:self 
														  userInfo:userInfo];
	
		
//		CALL_EACH_OBSERVER(observers_, @selector(tabMiniStateChangedWithContents:atIndex:), [observer tabMiniStateChangedWithContents:contents atIndex:index]);
	}
	
	// else: the tab was at the boundary and it's position doesn't need to
	// change.
	
	NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
							  contents, CTTabContentsUserInfoKey,
							  [NSNumber numberWithInt:index], CTTabIndexUserInfoKey,
							  [NSNumber numberWithInt:pinned], CTTabOptionsUserInfoKey, 
							  nil];
	[[NSNotificationCenter defaultCenter] postNotificationName:CTTabPinnedStateChangedNotification
														object:self
													  userInfo:userInfo];
//	CALL_EACH_OBSERVER(observers_, @selector(tabPinnedStateChangedWithContents:atIndex:), [observer tabPinnedStateChangedWithContents:contents atIndex:index]);
}

- (bool)IsTabPinned:(int)index {
	return ((TabContentsData *)[contents_data_ objectAtIndex:index])->isPinned;
}

- (bool)IsMiniTab:(int)index {
	return [self IsTabPinned:index] || [self IsAppTab:index];
}

- (bool)IsAppTab:(int)index {
	CTTabContents* contents = [self tabContentsAtIndex:index];
	return contents && contents.isApp;
}

- (bool)IsPhantomTab:(int)index {
	/*return IsTabPinned(index) &&
	 GetTabContentsAt(index)->controller().needs_reload();*/
	return false;
}

- (bool)IsTabBlocked:(int)index {
	return ((TabContentsData *)[contents_data_ objectAtIndex:index])->isBlocked;
}

- (int)IndexOfFirstNonMiniTab {
	for (int i = 0; i < [contents_data_ count]; ++i) {
		if (![self IsMiniTab:i])
			return i;
	}
	// No non-mini-tabs.
	return [self count];
}

- (int)constrainInsertionIndex:(int)index 
					   miniTab:(bool)mini_tab {
//	return mini_tab ? std::min(std::max(0, index), [self IndexOfFirstNonMiniTab]) :
//	std::min([self count], std::max(index, [self IndexOfFirstNonMiniTab]));
    return mini_tab ? MIN(MAX(0, index), [self IndexOfFirstNonMiniTab]) : MIN(self.count, MAX(index, [self IndexOfFirstNonMiniTab]));
}

// Returns the index of the first tab that is not a phantom tab. This returns
// kNoTab if all of the tabs are phantom tabs.
- (int)IndexOfFirstNonPhantomTab {
	/*for (int i = 0; i < count(); ++i) {
	 if (!IsPhantomTab(i))
	 return i;
	 }*/
	return [self count] ? 0 : kNoTab;
}

// Returns the number of non phantom tabs in the TabStripModel.
- (int)nonPhantomTabCount {
	/*int tabs = 0;
	 for (int i = 0; i < count(); ++i) {
	 if (!IsPhantomTab(i))
	 ++tabs;
	 }
	 return tabs;*/
	return [self count];
}

#pragma mark -
#pragma mark Command level API
- (int)addTabContents:(CTTabContents *)contents 
			  atIndex:(int)index
	   withTransition:(CTPageTransition)transition
			 addTypes:(int)add_types {
	// If the newly-opened tab is part of the same task as the parent tab, we want
	// to inherit the parent's "group" attribute, so that if this tab is then
	// closed we'll jump back to the parent tab.
	bool inherit_group = (add_types & ADD_INHERIT_GROUP) == ADD_INHERIT_GROUP;
	
	if (transition == CTPageTransitionLink &&
		(add_types & ADD_FORCE_INDEX) == 0) {
		// We assume tabs opened via link clicks are part of the same task as their
		// parent.  Note that when |force_index| is true (e.g. when the user
		// drag-and-drops a link to the tab strip), callers aren't really handling
		// link clicks, they just want to score the navigation like a link click in
		// the history backend, so we don't inherit the group in this case.
		index = [order_controller_ determineInsertionIndexWithContents:contents
															transition:transition
														  inForeground:add_types & ADD_SELECTED];
		inherit_group = true;
	} else {
		// For all other types, respect what was passed to us, normalizing -1s and
		// values that are too large.
		if (index < 0 || index > [self count])
			index = [order_controller_ determineInsertionIndexForAppending];
	}
	
	if (transition == CTPageTransitionTyped && index == [self count]) {
		// Also, any tab opened at the end of the TabStrip with a "TYPED"
		// transition inherit group as well. This covers the cases where the user
		// creates a New Tab (e.g. Ctrl+T, or clicks the New Tab button), or types
		// in the address bar and presses Alt+Enter. This allows for opening a new
		// Tab to quickly look up something. When this Tab is closed, the old one
		// is re-selected, not the next-adjacent.
		inherit_group = true;
	}
	[self insertTabContents:contents 
					atIndex:index 
			   withAddTypes:add_types | (inherit_group ? ADD_INHERIT_GROUP : 0)];
	// Reset the index, just in case insert ended up moving it on us.
	index = [self indexOfTabContents:contents];
		
	return index;
}

- (void)CloseSelectedTab {
	[self closeTabContentsAtIndex:selected_index_
				   closeTypes:CLOSE_CREATE_HISTORICAL_TAB];
}

- (void)SelectNextTab {
	[self SelectRelativeTab:true];
}

- (void)SelectPreviousTab {
	[self SelectRelativeTab:false];
}

- (void)SelectLastTab {
	[self selectTabContentsAtIndex:[self count]-1 
					   userGesture:true];
}

- (void)MoveTabNext {
	int new_index = MIN(selected_index_ + 1, [self count] - 1);
	[self moveTabContentsAtIndex:selected_index_ 
						 toIndex:new_index
				 selectAfterMove:true];
}

- (void)MoveTabPrevious {
	int new_index = MAX(selected_index_ - 1, 0);
	[self moveTabContentsAtIndex:selected_index_
						 toIndex:new_index
				 selectAfterMove:true];
}

#pragma mark -
#pragma mark View API
- (bool)isContextMenuCommandEnabled:(int)context_index
						  commandID:(ContextMenuCommand)command_id {
	assert(command_id > CommandFirst && command_id < CommandLast);
	CTTabContents* contents;
	switch (command_id) {
		case CommandNewTab:
		case CommandCloseTab:
			return [delegate_ canCloseTab];
			//return delegate_->CanCloseTab();
		case CommandReload:
			contents = [self tabContentsAtIndex:context_index];
			if (contents) {
				id delegate = contents.delegate;
				if ([delegate respondsToSelector:@selector(canReloadContents:)]) {
					return [delegate canReloadContents:contents];
				} else {
					return false;
				}
				//return contents->delegate()->CanReloadContents(contents);
			} else {
				return false;
			}
		case CommandCloseOtherTabs: {
			int mini_tab_count = [self IndexOfFirstNonMiniTab];
			int non_mini_tab_count = [self count] - mini_tab_count;
			// Close other doesn't effect mini-tabs.
			return non_mini_tab_count > 1 ||
			(non_mini_tab_count == 1 && context_index != mini_tab_count);
		}
		case CommandCloseTabsToRight:
			// Close doesn't effect mini-tabs.
			return [self count] != [self IndexOfFirstNonMiniTab] &&
			context_index < ([self count] - 1);
		case CommandDuplicate:
			return [delegate_ canDuplicateContentsAt:context_index];
			//return delegate_->CanDuplicateContentsAt(context_index);
		case CommandRestoreTab:
			return [delegate_ canRestoreTab];
			//return delegate_->CanRestoreTab();
		case CommandTogglePinned:
			return ![self IsAppTab:context_index];
			//case CommandBookmarkAllTabs:
			//  return delegate_->CanBookmarkAllTabs();
			//case CommandUseVerticalTabs:
			//  return true;
		default:
			NOTREACHED();
	}
	return false;
}

- (bool)isContextMenuCommandChecked:(int)context_index
						  commandID:(ContextMenuCommand)command_id {
	switch (command_id) {
			//case CommandUseVerticalTabs:
			//  return delegate()->UseVerticalTabs();
		default:
			NOTREACHED();
			break;
	}
	return false;
}

- (void)executeContextMenuCommand:(int)context_index
						commandID:(ContextMenuCommand)command_id {
	assert(command_id > CommandFirst && command_id < CommandLast);
	switch (command_id) {
		case CommandNewTab:
			[delegate_ addBlankTabAtIndex:context_index+1 inForeground:true];
			//delegate()->AddBlankTabAt(context_index + 1, true);
			break;
		case CommandReload:
			[[self tabContentsAtIndex:context_index].delegate reload];
			break;
		case CommandDuplicate:
			[delegate_ duplicateContentsAt:context_index];
			//delegate_->DuplicateContentsAt(context_index);
			break;
		case CommandCloseTab:
			[self closeTabContentsAtIndex:context_index
						   closeTypes:CLOSE_CREATE_HISTORICAL_TAB |
							   CLOSE_USER_GESTURE];
			break;
		case CommandCloseOtherTabs: {
			[self internalCloseTabs:[self GetIndicesClosedByCommand:command_id forTabAtIndex:context_index]
						 closeTypes:CLOSE_CREATE_HISTORICAL_TAB];
			break;
		}
		case CommandCloseTabsToRight: {
			[self internalCloseTabs:[self GetIndicesClosedByCommand:command_id forTabAtIndex:context_index]
						 closeTypes:CLOSE_CREATE_HISTORICAL_TAB];
			break;
		}
		case CommandRestoreTab: {
			[delegate_ restoreTab];
			//delegate_->RestoreTab();
			break;
		}
		case CommandTogglePinned: {
			if ([self IsPhantomTab:context_index]) {
				// The tab is a phantom tab, close it.
				[self closeTabContentsAtIndex:context_index 
							   closeTypes:CLOSE_USER_GESTURE | CLOSE_CREATE_HISTORICAL_TAB];
			} else {
				[self selectTabContentsAtIndex:context_index
								   userGesture:true];
				[self setTabAtIndex:context_index 
							 pinned:![self IsTabPinned:context_index]];
			}
			break;
		}
			
			/*case CommandBookmarkAllTabs: {
			 delegate_->BookmarkAllTabs();
			 break;
			 }*/
			
			/*case CommandUseVerticalTabs: {
			 delegate()->ToggleUseVerticalTabs();
			 break;
			 }*/
			
		default:
			NOTREACHED();
	}
}

- (NSArray *)GetIndicesClosedByCommand:(ContextMenuCommand)command_id
						 forTabAtIndex:(int)index {
	assert([self containsIndex:index]);
	
	// NOTE: some callers assume indices are sorted in reverse order.
	NSMutableArray *indices = [NSMutableArray array];
	
	if (command_id != CommandCloseTabsToRight && command_id != CommandCloseOtherTabs)
		return indices;
	
	int start = (command_id == CommandCloseTabsToRight) ? index + 1 : 0;
	for (int i = [self count] - 1; i >= start; --i) {
		if (i != index && ![self IsMiniTab:i])
			[indices addObject:[NSNumber numberWithInt:i]];
	}
	return indices;
}

- (void)TabContentsWasDestroyed:(CTTabContents *)contents {
	int index = [self indexOfTabContents:contents];
	if (index != kNoTab) {
		// Note that we only detach the contents here, not close it - it's
		// already been closed. We just want to undo our bookkeeping.
		//if (ShouldMakePhantomOnClose(index)) {
		//  // We don't actually allow pinned tabs to close. Instead they become
		//  // phantom.
		//  MakePhantom(index);
		//} else {
		[self detachTabContentsAtIndex:index];
		//}
	}
}
	
#pragma mark -
#pragma mark Private methods
- (bool)IsNewTabAtEndOfTabStrip:(CTTabContents *)contents {
	return !contents || contents == [self tabContentsAtIndex:([self count] - 1)];
	/*return LowerCaseEqualsASCII(contents->GetURL().spec(),
	 chrome::kChromeUINewTabURL) &&
	 contents == GetContentsAt(count() - 1) &&
	 contents->controller().entry_count() == 1;*/
}

- (bool)internalCloseTabs:(NSArray *)indices
			   closeTypes:(uint32)close_types {
	bool retval = true;
		
	// We now return to our regularly scheduled shutdown procedure.
	for (size_t i = 0; i < indices.count; ++i) {
		int index = [[indices objectAtIndex:i] intValue];
		CTTabContents* detached_contents = [self tabContentsAtIndex:index];
		[detached_contents closingOfTabDidStart:self]; // TODO notification
		
		if (![delegate_ canCloseContentsAt:index]) {
			retval = false;
			continue;
		}
		
		// Update the explicitly closed state. If the unload handlers cancel the
		// close the state is reset in CTBrowser. We don't update the explicitly
		// closed state if already marked as explicitly closed as unload handlers
		// call back to this if the close is allowed.
		if (!detached_contents.closedByUserGesture) {
			detached_contents.closedByUserGesture = close_types & CLOSE_USER_GESTURE;
		}
		
		//if (delegate_->RunUnloadListenerBeforeClosing(detached_contents)) {
		if ([delegate_ runUnloadListenerBeforeClosing:detached_contents]) {
			retval = false;
			continue;
		}
		
		[self internalCloseTab:detached_contents
					   atIndex:index
		   createHistoricalTab:((close_types & CLOSE_CREATE_HISTORICAL_TAB) != 0)];
	}
	
	return retval;	
}

- (void)internalCloseTab:(CTTabContents *)contents
				 atIndex:(int)index
	 createHistoricalTab:(bool)create_historical_tabs {
//	CALL_EACH_OBSERVER(observers_, @selector(tabClosingWithContents:atIndex:), [observer tabClosingWithContents:contents atIndex:index]);
	
    NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                              contents, CTTabContentsUserInfoKey,
                              [NSNumber numberWithInt:index], CTTabIndexUserInfoKey,
                              nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:CTTabClosingNotification 
														object:self 
													  userInfo:userInfo];
	
	// Ask the delegate to save an entry for this tab in the historical tab
	// database if applicable.
	if (create_historical_tabs) {
		[delegate_ createHistoricalTab:contents];
	}
	
	// Deleting the CTTabContents will call back to us via NotificationObserver
	// and detach it.
//	[contents destroy:self];
	[self detachTabContentsAtIndex:index];
}


- (void)ChangeSelectedContentsFrom:(CTTabContents *)oldContents
						   toIndex:(int)toIndex
					   userGesture:(bool)userGesture {
	assert([self containsIndex:toIndex]);
	CTTabContents* newContents = [self tabContentsAtIndex:toIndex];
	if (oldContents == newContents)
		return;
	
//	CTTabContents* last_selected_contents = old_contents;
//	if (last_selected_contents) {
//		CALL_EACH_OBSERVER(observers_, @selector(tabDeselectedWithContents:atIndex:),
//						  [observer tabDeselectedWithContents:last_selected_contents 
//													  atIndex:selected_index_]);
//	}
	
	selected_index_ = toIndex;
	NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                              newContents, CTTabNewContentsUserInfoKey,
                              [NSNumber numberWithInt:self.selected_index], CTTabIndexUserInfoKey,
                              [NSNumber numberWithBool:userGesture], CTTabUserGestureUserInfoKey,
                              oldContents, CTTabContentsUserInfoKey,
                              nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:CTTabSelectedNotification 
														object:self 
													  userInfo:userInfo];
//	CALL_EACH_OBSERVER(observers_, @selector(tabSelectedWithContents:previousContents:atIndex:userGesture:),
//					  [observer tabSelectedWithContents:new_contents 
//									   previousContents:last_selected_contents 
//												atIndex:selected_index_ 
//											userGesture:user_gesture]);
}

// Selects either the next tab (|foward| is true), or the previous tab
// (|forward| is false).
- (void)SelectRelativeTab:(bool)forward {
	// This may happen during automated testing or if a user somehow buffers
	// many key accelerators.
	if ([contents_data_ count] == 0)
		return;
	
	// Skip pinned-app-phantom tabs when iterating.
	int index = selected_index_;
	int delta = forward ? 1 : -1;
	do {
		index = (index + [self count] + delta) % [self count];
	} while (index != selected_index_ && [self IsPhantomTab:index]);
	[self selectTabContentsAtIndex:index 
					   userGesture:true];
}

// Returns the first non-phantom tab starting at |index|, skipping the tab at
// |ignore_index|.
- (int)indexOfNextNonPhantomTabFromIndex:(int)index
							 ignoreIndex:(int)ignore_index {
	if (index == kNoTab)
		return kNoTab;
	
	if ([contents_data_ count] == 0)
		return index;
	
	index = MIN([self count] - 1, MAX(0, index));
	int start = index;
	do {
		if (index != ignore_index && ![self IsPhantomTab:index])
			return index;
		index = (index + 1) % [self count];
	} while (index != start);
	
	// All phantom tabs.
	return start;
}

const bool kPhantomTabsEnabled = false;

// Returns true if the tab at the specified index should be made phantom when
// the tab is closing.
- (bool)ShouldMakePhantomOnClose:(int)index {
	if (kPhantomTabsEnabled && [self IsTabPinned:index] && ![self IsPhantomTab:index] &&
		!closing_all_) {
		if (![self IsAppTab:index])
			return true;  // Always make non-app tabs go phantom.
		
		//ExtensionsService* extension_service = profile()->GetExtensionsService();
		//if (!extension_service)
		return false;
		
		//Extension* extension_app = GetTabContentsAt(index)->extension_app();
		//assert(extension_app);
		
		// Only allow the tab to be made phantom if the extension still exists.
		//return extension_service->GetExtensionById(extension_app->id(),
		//                                           false) != NULL;
	}
	return false;
}

- (void)moveTabContentsAtImpl:(int)index
				   toPosition:(int)to_position
			  selectAfterMove:(bool)select_after_move {
	TabContentsData* movedData = [contents_data_ objectAtIndex:index];
//	[movedContents retain];
	[contents_data_ removeObjectAtIndex:index];
	[contents_data_ insertObject:movedData atIndex:to_position];
//	[movedContents release];
	
	// if !select_after_move, keep the same tab selected as was selected before.
	if (select_after_move || index == selected_index_) {
		selected_index_ = to_position;
	} else if (index < selected_index_ && to_position >= selected_index_) {
		selected_index_--;
	} else if (index > selected_index_ && to_position <= selected_index_) {
		selected_index_++;
	}
	
//	CALL_EACH_OBSERVER(observers_, @selector(tabMovedWithContents:fromIndex:toIndex:),
//					  [observer tabMovedWithContents:movedContents fromIndex:index toIndex:to_position]);
	
    NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                              movedData->contents, CTTabNewContentsUserInfoKey,
                              [NSNumber numberWithInt:index], CTTabIndexUserInfoKey,
                              [NSNumber numberWithInt:to_position], CTTabToIndexUserInfoKey,
                              nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:CTTabMovedNotification 
														object:self 
													  userInfo:userInfo];
}

- (CTTabContents *)replaceTabContentsAtImpl:(int)index
							   withContents:(CTTabContents *)new_contents
								replaceType:(CTTabReplaceType)type {
	assert([self containsIndex:index]);
	CTTabContents* old_contents = [self tabContentsAtIndex:index];
	TabContentsData* data = [contents_data_ objectAtIndex:index];
	data->contents = new_contents;
//	[contents_data_ replaceObjectAtIndex:index withObject:new_contents];
//	contents_data_[index]->contents = new_contents;
//	CALL_EACH_OBSERVER(observers_, @selector(tabReplacedWithContents:oldContents:atIndex:replaceType:),
//					  [observer tabReplacedWithContents:new_contents 
//											oldContents:old_contents atIndex:index replaceType:type]);
	
    NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                              old_contents, CTTabContentsUserInfoKey,
                              new_contents, CTTabNewContentsUserInfoKey,
                              [NSNumber numberWithInt:index], CTTabIndexUserInfoKey,
                              [NSNumber numberWithInt:type], CTTabOptionsUserInfoKey, 
                              nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:CTTabReplacedNotification 
														object:self 
													  userInfo:userInfo];
	return old_contents;
}
@end
