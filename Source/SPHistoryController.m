//
//  SPHistoryController.m
//  sequel-pro
//
//  Created by Rowan Beentje on July 23, 2009.
//  Copyright (c) 2008 Rowan Beentje. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//
//  More info at <https://github.com/sequelpro/sequelpro>

#import "SPDatabaseDocument.h"
#import "SPTableContent.h"
#import "SPTablesList.h"
#import "SPHistoryController.h"
#import "SPDatabaseViewController.h"
#import "SPThreadAdditions.h"

@implementation SPHistoryController

@synthesize history;
@synthesize historyPosition;
@synthesize modifyingState;

#pragma mark Setup and teardown

/**
 * Initialise by creating a blank history array.
 */
- (id) init
{
	if ((self = [super init])) {
		history = [[NSMutableArray alloc] init];
		tableContentStates = [[NSMutableDictionary alloc] init];
		historyPosition = NSNotFound;
		modifyingState = NO;
	}
	return self;	
}

- (void) awakeFromNib
{
	tableContentInstance = [theDocument valueForKey:@"tableContentInstance"];
	tablesListInstance = [theDocument valueForKey:@"tablesListInstance"];
	toolbarItemVisible = NO;
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(toolbarWillAddItem:) name:NSToolbarWillAddItemNotification object:[theDocument valueForKey:@"mainToolbar"]];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(toolbarDidRemoveItem:) name:NSToolbarDidRemoveItemNotification object:[theDocument valueForKey:@"mainToolbar"]];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(startDocumentTask:) name:SPDocumentTaskStartNotification object:theDocument];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(endDocumentTask:) name:SPDocumentTaskEndNotification object:theDocument];
}

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[tableContentStates release];
	[history release];
	[super dealloc];
}

#pragma mark -
#pragma mark Interface interaction

/**
 * Updates the toolbar item to reflect the current history state and position
 */
- (void) updateToolbarItem
{

	// If the toolbar item isn't visible, don't perform any actions - as manipulating
	// items not on the toolbar can cause crashes.
	if (!toolbarItemVisible) return;

	BOOL backEnabled = NO;
	BOOL forwardEnabled = NO;
	NSInteger i;
	NSMenu *navMenu;

	// Set the active state of the segments if appropriate
	if ([history count] && historyPosition > 0) backEnabled = YES;
	if ([history count] && historyPosition + 1 < [history count]) forwardEnabled = YES;

	if(!historyControl) return;

	[historyControl setEnabled:backEnabled forSegment:0];
	[historyControl setEnabled:forwardEnabled forSegment:1];

	// Generate back and forward menus as appropriate to reflect the new state
	if (backEnabled) {
		navMenu = [[NSMenu alloc] init];
		for (i = historyPosition - 1; i >= 0; i--) {
			[navMenu addItem:[self menuEntryForHistoryEntryAtIndex:i]];
		}
		[historyControl setMenu:navMenu forSegment:0];
		[navMenu release];
	} else {
		[historyControl setMenu:nil forSegment:0];
	}
	if (forwardEnabled) {
		navMenu = [[NSMenu alloc] init];
		for (i = historyPosition + 1; i < (NSInteger)[history count]; i++) {
			[navMenu addItem:[self menuEntryForHistoryEntryAtIndex:i]];
		}
		[historyControl setMenu:navMenu forSegment:1];
		[navMenu release];
	} else {
		[historyControl setMenu:nil forSegment:1];
	}
}

/**
 * Go backward in the history.
 */
- (void)goBackInHistory
{
	if (historyPosition == NSNotFound || !historyPosition) return;
	
	[self loadEntryAtPosition:historyPosition - 1];
}

/**
 * Go forward in the history.
 */
- (void)goForwardInHistory
{
	if (historyPosition == NSNotFound || historyPosition + 1 >= [history count]) return;
	
	[self loadEntryAtPosition:historyPosition + 1];
}

/**
 * Trigger a navigation action in response to a click
 */
- (IBAction) historyControlClicked:(NSSegmentedControl *)theControl
{

	// Ensure history navigation is permitted - trigger end editing and any required saves
	if (![theDocument couldCommitCurrentViewActions]) return;

	switch ([theControl selectedSegment]) 
	{
		// Back button clicked:
		case 0:
			[self goBackInHistory];
			break;

		// Forward button clicked:
		case 1:
			[self goForwardInHistory];
			break;
	}
}

/**
 * Retrieve the view that is currently selected from the database
 */
- (NSUInteger) currentlySelectedView
{
	NSUInteger theView = NSNotFound;

	NSString *viewName = [[[theDocument valueForKey:@"tableTabView"] selectedTabViewItem] identifier];
	
	if ([viewName isEqualToString:@"source"]) {
		theView = SPTableViewStructure;
	} else if ([viewName isEqualToString:@"content"]) {
		theView = SPTableViewContent;
	} else if ([viewName isEqualToString:@"customQuery"]) {
		theView = SPTableViewCustomQuery;
	} else if ([viewName isEqualToString:@"status"]) {
		theView = SPTableViewStatus;
	} else if ([viewName isEqualToString:@"relations"]) {
		theView = SPTableViewRelations;
	}
	else if ([viewName isEqualToString:@"triggers"]) {
		theView = SPTableViewTriggers;
	}

	return theView;
}

/**
 * Set up the toolbar items as appropriate.
 * State tracking is necessary as manipulating items not on the toolbar
 * can cause crashes.
 */
- (void) setupInterface
{
	NSArray *toolbarItems = [[theDocument valueForKey:@"mainToolbar"] items];
	for (NSToolbarItem *toolbarItem in toolbarItems) {
		if ([[toolbarItem itemIdentifier] isEqualToString:SPMainToolbarHistoryNavigation]) {
			toolbarItemVisible = YES;
			break;
		}
	}
}

/**
 * Disable the controls during a task.
 */
- (void) startDocumentTask:(NSNotification *)aNotification
{
	if (toolbarItemVisible) [historyControl setEnabled:NO];
}

/**
 * Enable the controls once a task has completed.
 */
- (void) endDocumentTask:(NSNotification *)aNotification
{
	if (toolbarItemVisible) [historyControl setEnabled:YES];
}

/**
 * Update the state when the item is added from the toolbar.
 * State tracking is necessary as manipulating items not on the toolbar
 * can cause crashes.
 */
- (void) toolbarWillAddItem:(NSNotification *)aNotification {
	if ([[[[aNotification userInfo] objectForKey:@"item"] itemIdentifier] isEqualToString:SPMainToolbarHistoryNavigation]) {
		toolbarItemVisible = YES;
		[self performSelectorOnMainThread:@selector(updateToolbarItem) withObject:nil waitUntilDone:YES];
	}
}

/**
 * Update the state when the item is removed from the toolbar
 * State tracking is necessary as manipulating items not on the toolbar
 * can cause crashes.
 */
- (void) toolbarDidRemoveItem:(NSNotification *)aNotification {
	if ([[[[aNotification userInfo] objectForKey:@"item"] itemIdentifier] isEqualToString:SPMainToolbarHistoryNavigation]) {
		toolbarItemVisible = NO;
	}
}

#pragma mark -
#pragma mark Adding or updating history entries

/**
 * Call to store or update a history item for the document state. Checks against
 * the latest stored details; if they match, a new history item is not created.
 * This should therefore be called without worry of duplicates.
 * Table histories are created per table/filter setting, and while view changes
 * update the current history entry, they don't replace it.
 */
- (void) updateHistoryEntries
{

	// Don't modify anything if we're in the process of restoring an old history state
	if (modifyingState) return;

	// Work out the current document details
	NSString *theDatabase = [theDocument database];
	NSString *theTable = [theDocument table];
	NSUInteger theView = [self currentlySelectedView];
	NSString *contentSortCol = [tableContentInstance sortColumnName];
	BOOL contentSortColIsAsc = [tableContentInstance sortColumnIsAscending];
	NSUInteger contentPageNumber = [tableContentInstance pageNumber];
	NSDictionary *contentSelectedRows = [tableContentInstance selectionDetailsAllowingIndexSelection:YES];
	NSRect contentViewport = [tableContentInstance viewport];
	NSDictionary *contentFilter = [tableContentInstance filterSettings];
	NSData *filterTableData = [tableContentInstance filterTableData];
	if (!theDatabase) return;

	// If a table is selected, save state information
	if (theDatabase && theTable) {

		// Save the table content state
		NSMutableDictionary *contentState = [NSMutableDictionary dictionaryWithObjectsAndKeys:
												[NSNumber numberWithUnsignedInteger:contentPageNumber], @"page",
												[NSValue valueWithRect:contentViewport], @"viewport",
												[NSNumber numberWithBool:contentSortColIsAsc], @"sortIsAsc",
												nil];
		if (contentSortCol) [contentState setObject:contentSortCol forKey:@"sortCol"];
		if (contentSelectedRows) [contentState setObject:contentSelectedRows forKey:@"selection"];
		if (contentFilter) [contentState setObject:contentFilter forKey:@"filter"];
		if (filterTableData) [contentState setObject:filterTableData forKey:@"filterTable"];

		// Update the table content states with this information - used when switching tables to restore last used view.
		[tableContentStates setObject:contentState forKey:[NSString stringWithFormat:@"%@.%@", [theDatabase backtickQuotedString], [theTable backtickQuotedString]]];
	}

	// If there's any items after the current history position, remove them
	if (historyPosition != NSNotFound && historyPosition < [history count] - 1) {
		[history removeObjectsInRange:NSMakeRange(historyPosition + 1, [history count] - historyPosition - 1)];

	} else if (historyPosition != NSNotFound && historyPosition == [history count] - 1) {
		NSMutableDictionary *currentHistoryEntry = [history objectAtIndex:historyPosition];

		// If the table is the same, and the filter settings haven't changed, delete the
		// last entry so it can be replaced.  This updates navigation within a table, rather than
		// creating a new entry every time detail is changed.
		if ([[currentHistoryEntry objectForKey:@"database"] isEqualToString:theDatabase]
			&& [[currentHistoryEntry objectForKey:@"table"] isEqualToString:theTable]
			&& ([[currentHistoryEntry objectForKey:@"view"] unsignedIntegerValue] != theView
				|| ((![currentHistoryEntry objectForKey:@"contentFilter"] && !contentFilter)
					|| (![currentHistoryEntry objectForKey:@"contentFilter"]
						&& ![(NSString *)[contentFilter objectForKey:@"filterValue"] length]
						&& ![[contentFilter objectForKey:@"filterComparison"] isEqualToString:@"IS NULL"]
						&& ![[contentFilter objectForKey:@"filterComparison"] isEqualToString:@"IS NOT NULL"])
					|| [[currentHistoryEntry objectForKey:@"contentFilter"] isEqualToDictionary:contentFilter])))
		{
			[history removeLastObject];

		// If the only db/table/view are the same, but the filter settings have changed, also store the
		// position details on the *previous* history item
		} else if ([[currentHistoryEntry objectForKey:@"database"] isEqualToString:theDatabase]
			&& [[currentHistoryEntry objectForKey:@"table"] isEqualToString:theTable]
			&& ([[currentHistoryEntry objectForKey:@"view"] unsignedIntegerValue] == theView
				|| ((![currentHistoryEntry objectForKey:@"contentFilter"] && contentFilter)
					|| ![[currentHistoryEntry objectForKey:@"contentFilter"] isEqualToDictionary:contentFilter])))
		{
			[currentHistoryEntry setObject:[NSValue valueWithRect:contentViewport] forKey:@"contentViewport"];
			if (contentSelectedRows) [currentHistoryEntry setObject:contentSelectedRows forKey:@"contentSelection"];

		// Special case: if the last history item is currently active, and has no table,
		// but the new selection does - delete the last entry, in order to replace it.
		// This improves history flow.
		} else if ([[currentHistoryEntry objectForKey:@"database"] isEqualToString:theDatabase]
			&& ![currentHistoryEntry objectForKey:@"table"])
		{
			[history removeLastObject];
		}
	}

	// Construct and add the new history entry
	NSMutableDictionary *newEntry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
										theDatabase, @"database",
										theTable, @"table",
										[NSNumber numberWithUnsignedInteger:theView], @"view",
										[NSNumber numberWithBool:contentSortColIsAsc], @"contentSortColIsAsc",
										[NSNumber numberWithInteger:contentPageNumber], @"contentPageNumber",
										[NSValue valueWithRect:contentViewport], @"contentViewport",
										nil];
	if (contentSortCol) [newEntry setObject:contentSortCol forKey:@"contentSortCol"];
	if (contentSelectedRows) [newEntry setObject:contentSelectedRows forKey:@"contentSelection"];
	if (contentFilter) [newEntry setObject:contentFilter forKey:@"contentFilter"];

	[history addObject:newEntry];

	// If there are now more than fifty history entries, remove one from the start
	if ([history count] > 50) [history removeObjectAtIndex:0];

	historyPosition = [history count] - 1;
	[[self onMainThread] updateToolbarItem];
}

#pragma mark -
#pragma mark Loading history entries

/**
 * Load a history entry and attempt to return the interface to that state.
 * Performs the load in a task which is threaded as necessary.
 */
- (void) loadEntryAtPosition:(NSUInteger)position
{

	// Sanity check the input
	if (position == NSNotFound || position >= [history count]) {
		NSBeep();
		return;
	}

	// Ensure a save of the current state - scroll position, selection - if we're at the last entry
	if (historyPosition == [history count] - 1) [self updateHistoryEntries];

	// Start the task and perform the load
	[theDocument startTaskWithDescription:NSLocalizedString(@"Loading history entry...", @"Loading history entry task desc")];
	if ([NSThread isMainThread]) {
		[NSThread detachNewThreadWithName:@"SPHistoryController load of history entry" target:self selector:@selector(loadEntryTaskWithPosition:) object:[NSNumber numberWithUnsignedInteger:position]];
	} else {
		[self loadEntryTaskWithPosition:[NSNumber numberWithUnsignedInteger:position]];
	}
}
- (void) loadEntryTaskWithPosition:(NSNumber *)positionNumber
{
	NSAutoreleasePool *loadPool = [[NSAutoreleasePool alloc] init];
	NSUInteger position = [positionNumber unsignedIntegerValue];

	modifyingState = YES;

	// Update the position and extract the history entry
	historyPosition = position;
	NSDictionary *historyEntry = [history objectAtIndex:historyPosition];

	// Set table content details for restore
	[tableContentInstance setSortColumnNameToRestore:[historyEntry objectForKey:@"contentSortCol"] isAscending:[[historyEntry objectForKey:@"contentSortColIsAsc"] boolValue]];
	[tableContentInstance setPageToRestore:[[historyEntry objectForKey:@"contentPageNumber"] integerValue]];
	[tableContentInstance setSelectionToRestore:[historyEntry objectForKey:@"contentSelection"]];
	[tableContentInstance setViewportToRestore:[[historyEntry objectForKey:@"contentViewport"] rectValue]];
	[tableContentInstance setFiltersToRestore:[historyEntry objectForKey:@"contentFilter"]];

	// If the database, table, and view are the same and content - just trigger a table reload (filters)
	if ([[theDocument database] isEqualToString:[historyEntry objectForKey:@"database"]]
		&& [historyEntry objectForKey:@"table"] && [[theDocument table] isEqualToString:[historyEntry objectForKey:@"table"]]
		&& [[historyEntry objectForKey:@"view"] unsignedIntegerValue] == [self currentlySelectedView]
		&& [[historyEntry objectForKey:@"view"] unsignedIntegerValue] == SPTableViewContent)
	{
		[tableContentInstance loadTable:[historyEntry objectForKey:@"table"]];
		modifyingState = NO;
		[[self onMainThread] updateToolbarItem];
		[theDocument endTask];
		[loadPool drain];
		return;
	}

	// If the same table was selected, mark the content as requiring a reload
	if ([historyEntry objectForKey:@"table"] && [[theDocument table] isEqualToString:[historyEntry objectForKey:@"table"]]) {
		[theDocument setContentRequiresReload:YES];
	}

	// Update the database and table name if necessary
	[theDocument selectDatabase:[historyEntry objectForKey:@"database"] item:[historyEntry objectForKey:@"table"]];

	// If the database or table couldn't be selected, error.
	if ((![[theDocument database] isEqualToString:[historyEntry objectForKey:@"database"]]
			&& ([theDocument database] || [historyEntry objectForKey:@"database"]))
		|| 
		(![[theDocument table] isEqualToString:[historyEntry objectForKey:@"table"]]
			&& ([theDocument table] || [historyEntry objectForKey:@"table"])))
	{
		return [self abortEntryLoadWithPool:loadPool];
	}

	// Check and set the view
	if ([self currentlySelectedView] != [[historyEntry objectForKey:@"view"] unsignedIntegerValue]) {
		switch ([[historyEntry objectForKey:@"view"] integerValue]) {
			case SPTableViewStructure:
				[theDocument viewStructure:self];
				break;
			case SPTableViewContent:
				[theDocument viewContent:self];
				break;
			case SPTableViewCustomQuery:
				[theDocument viewQuery:self];
				break;
			case SPTableViewStatus:
				[theDocument viewStatus:self];
				break;
			case SPTableViewRelations:
				[theDocument viewRelations:self];
				break;
			case SPTableViewTriggers:
				[theDocument viewTriggers:self];
				break;
		}
		if ([self currentlySelectedView] != [[historyEntry objectForKey:@"view"] unsignedIntegerValue]) {
			return [self abortEntryLoadWithPool:loadPool];
		}
	}

	modifyingState = NO;
	[[self onMainThread] updateToolbarItem];

	// End the task
	[theDocument endTask];
	[loadPool drain];
}

/**
 * Convenience method for aborting history load - could at some point
 * clean up the history list, show an alert, etc
 */
- (void) abortEntryLoadWithPool:(NSAutoreleasePool *)pool
{
	NSBeep();
	modifyingState = NO;
	[theDocument endTask];
	if (pool) [pool drain];
}

/**
 * Load a history entry from an associated menu item
 */
- (void) loadEntryFromMenuItem:(id)theMenuItem
{
	[self loadEntryAtPosition:[theMenuItem tag]];
}

#pragma mark -
#pragma mark Restoring view states

/**
 * Check saved view states for the currently selected database and
 * table (if any), and restore them if present.
 */
- (void) restoreViewStates
{
	NSString *theDatabase = [theDocument database];
	NSString *theTable = [theDocument table];
	NSDictionary *contentState;

	// Return if the history state is currently being modified
	if (modifyingState) return;

	// Return if no database or table are selected
	if (!theDatabase || !theTable) return;

	// Retrieve the saved content state, returning if none was found
	contentState = [tableContentStates objectForKey:[NSString stringWithFormat:@"%@.%@", [theDatabase backtickQuotedString], [theTable backtickQuotedString]]];
	if (!contentState) return;

	// Restore the content view state
	[tableContentInstance setSortColumnNameToRestore:[contentState objectForKey:@"sortCol"] isAscending:[[contentState objectForKey:@"sortIsAsc"] boolValue]];
	[tableContentInstance setPageToRestore:[[contentState objectForKey:@"page"] unsignedIntegerValue]];
	[tableContentInstance setSelectionToRestore:[contentState objectForKey:@"selection"]];
	[tableContentInstance setViewportToRestore:[[contentState objectForKey:@"viewport"] rectValue]];
	[tableContentInstance setFiltersToRestore:[contentState objectForKey:@"filter"]];
}

#pragma mark -
#pragma mark History entry details and description

/**
 * Returns a menuitem for a history entry at a supplied index
 */
- (NSMenuItem *) menuEntryForHistoryEntryAtIndex:(NSInteger)theIndex
{
	NSMenuItem *theMenuItem = [[NSMenuItem alloc] init];
	NSDictionary *theHistoryEntry = [history objectAtIndex:theIndex];

	[theMenuItem setTag:theIndex];
	[theMenuItem setTitle:[self nameForHistoryEntryDetails:theHistoryEntry]];
	[theMenuItem setTarget:self];
	[theMenuItem setAction:@selector(loadEntryFromMenuItem:)];
	
	return [theMenuItem autorelease];
}

/**
 * Returns a descriptive name for a history item dictionary
 */
- (NSString *) nameForHistoryEntryDetails:(NSDictionary *)theEntry
{
	if (![theEntry objectForKey:@"database"]) return NSLocalizedString(@"(no selection)", @"History item title with nothing selected");

	NSMutableString *theName = [NSMutableString stringWithString:[theEntry objectForKey:@"database"]];
	if (![theEntry objectForKey:@"table"] || ![(NSString *)[theEntry objectForKey:@"table"] length]) return theName;

	[theName appendFormat:@"/%@", [theEntry objectForKey:@"table"]];

	if ([theEntry objectForKey:@"contentFilter"]) {
		NSDictionary *filterSettings = [theEntry objectForKey:@"contentFilter"];
		if ([filterSettings objectForKey:@"filterField"]) {
			if([filterSettings objectForKey:@"menuLabel"]) {
				theName = [NSMutableString stringWithFormat:NSLocalizedString(@"%@ (Filtered by %@)", @"History item filtered by values label"),
							theName, [filterSettings objectForKey:@"menuLabel"]];
			}
		}
	}

	if ([theEntry objectForKey:@"contentPageNumber"]) {
		NSUInteger pageNumber = [[theEntry objectForKey:@"contentPageNumber"] unsignedIntegerValue];
		if (pageNumber > 1) {
			theName = [NSMutableString stringWithFormat:NSLocalizedString(@"%@ (Page %lu)", @"History item with page number label"),
						theName, (unsigned long)pageNumber];
		}
	}

	return theName;
}

@end
