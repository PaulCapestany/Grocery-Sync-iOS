//
//  RootViewController.m
//  Couchbase Mobile
//
//  Created by Jan Lehnardt on 27/11/2010.
//  Copyright 2011 Couchbase, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License"); you may not
// use this file except in compliance with the License. You may obtain a copy of
// the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
// License for the specific language governing permissions and limitations under
// the License.
//

#import "RootViewController.h"
#import "ConfigViewController.h"
#import "DemoAppDelegate.h"

#import <CouchCocoa/CouchCocoa.h>
#import <CouchCocoa/RESTBody.h>
#import <Couchbase/CouchbaseMobile.h>


@interface RootViewController ()
@property(nonatomic, retain)CouchDatabase *database;
@property(nonatomic, retain)NSURL* remoteSyncURL;
- (void)updateSyncURL;
- (void)showSyncButton;
- (void)showSyncStatus;
- (IBAction)configureSync:(id)sender;
- (void)forgetSync;
@end


@implementation RootViewController


@synthesize dataSource;
@synthesize database;
@synthesize tableView;
@synthesize remoteSyncURL;


#pragma mark - View lifecycle


- (void)viewDidLoad {
    [super viewDidLoad];

    [CouchUITableSource class];     // Prevents class from being dead-stripped by linker

    UIBarButtonItem* deleteButton = [[UIBarButtonItem alloc] initWithTitle: @"Clean"
                                                            style:UIBarButtonItemStylePlain
                                                           target: self 
                                                           action: @selector(deleteCheckedItems:)];
    self.navigationItem.leftBarButtonItem = [deleteButton autorelease];
    
    [self showSyncButton];
    
    [self.tableView setBackgroundView:nil];
    [self.tableView setBackgroundColor:[UIColor clearColor]];
    if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        [addItemBackground setFrame:CGRectMake(45, 8, 680, 44)];
        [addItemTextField setFrame:CGRectMake(56, 8, 665, 43)];
    }
}


- (void)dealloc {
    [self forgetSync];
    [database release];
    [super dealloc];
}


- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear: animated];
    // Check for changes after returning from the sync config view:
    [self updateSyncURL];
}


- (void)useDatabase:(CouchDatabase*)theDatabase {
    self.database = theDatabase;
    
    // Create a CouchDB 'view' containing list items sorted by date:
    CouchDesignDocument* design = [theDatabase designDocumentWithName: @"grocery"];
    [design defineViewNamed: @"byDate"
                        map: @"function(doc) {if (doc.created_at) emit(doc.created_at, doc);}"];
    CouchLiveQuery* query = [[design queryViewNamed: @"byDate"] asLiveQuery];
    query.descending = YES;  // Sort by descending date, i.e. newest items first
    
    self.dataSource.query = query;
    self.dataSource.labelProperty = @"text";    // Document property to display in the cell label
    [self updateSyncURL];
}


- (void)showErrorAlert: (NSString*)message forOperation: (RESTOperation*)op {
    NSLog(@"%@: op=%@, error=%@", message, op, op.error);
    [(DemoAppDelegate*)[[UIApplication sharedApplication] delegate] 
        showAlert: message error: op.error fatal: NO];
}


#pragma mark - Couch table source delegate


// Customize the appearance of table view cells.
- (void)couchTableSource:(CouchUITableSource*)source
             willUseCell:(UITableViewCell*)cell
                  forRow:(CouchQueryRow*)row
{
    // Set the cell background and font:
    static UIColor* kBGColor;
    if (!kBGColor)
        kBGColor = [[UIColor colorWithPatternImage: [UIImage imageNamed:@"item_background"]] 
                        retain];
    cell.backgroundColor = kBGColor;
    cell.selectionStyle = UITableViewCellSelectionStyleGray;

    cell.textLabel.font = [UIFont fontWithName: @"Helvetica" size:18.0];
    cell.textLabel.backgroundColor = [UIColor clearColor];
    
    // Configure the cell contents:
    NSDictionary* properties = row.document.properties;
    BOOL checked = [[properties valueForKey:@"check"] boolValue];
    
    UILabel *labelWithText = cell.textLabel;
    labelWithText.text = [properties valueForKey:@"text"];
    labelWithText.textColor = checked ? [UIColor grayColor] : [UIColor blackColor];

    [cell.imageView setImage:[UIImage imageNamed:
            (checked ? @"list_area___checkbox___checked" : @"list_area___checkbox___unchecked")]];
}


#pragma mark - Table view delegate


- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 50;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    CouchQueryRow *row = [self.dataSource rowAtIndex:indexPath.row];
    CouchDocument *doc = [row document];

    // Toggle the document's 'checked' property:
    NSMutableDictionary *docContent = [[doc.properties mutableCopy] autorelease];
    BOOL wasChecked = [[docContent valueForKey:@"check"] boolValue];
    [docContent setObject:[NSNumber numberWithBool:!wasChecked] forKey:@"check"];

    // Save changes, asynchronously:
    RESTOperation* op = [doc putProperties:docContent];
    [op onCompletion: ^{
        if (op.error)
            [self showErrorAlert: @"Failed to update item" forOperation: op];
        // Re-run the query:
		[self.dataSource.query start];
    }];
    [op start];
}


#pragma mark - Editing:


- (NSArray*)checkedDocuments {
    // If there were a whole lot of documents, this would be more efficient with a custom query.
    NSMutableArray* checked = [NSMutableArray array];
    for (CouchQueryRow* row in self.dataSource.rows) {
        CouchDocument* doc = row.document;
        if ([[doc.properties valueForKey:@"check"] boolValue])
            [checked addObject: doc];
    }
    return checked;
}


- (IBAction)deleteCheckedItems:(id)sender {
    NSUInteger numChecked = self.checkedDocuments.count;
    if (numChecked == 0)
        return;
    NSString* message = [NSString stringWithFormat: @"Are you sure you want to remove the %u"
                                                     " checked-off item%@?",
                                                     numChecked, (numChecked==1 ? @"" : @"s")];
    UIAlertView* alert = [[UIAlertView alloc] initWithTitle: @"Remove Completed Items?"
                                                    message: message
                                                   delegate: self
                                          cancelButtonTitle: @"Cancel"
                                          otherButtonTitles: @"Remove", nil];
    [alert show];
    [alert release];
}


- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 0)
        return;
    [dataSource deleteDocuments: self.checkedDocuments];
}


- (void)couchTableSource:(CouchUITableSource*)source
         operationFailed:(RESTOperation*)op
{
    NSString* message = op.isDELETE ? @"Couldn't delete item" : @"Operation failed";
    [self showErrorAlert: message forOperation: op];
}


#pragma mark - UITextField delegate


- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
    [addItemBackground setImage:[UIImage imageNamed:@"textfield___inactive.png"]];

	return YES;
}


- (void)textFieldDidBeginEditing:(UITextField *)textField {
    [addItemBackground setImage:[UIImage imageNamed:@"textfield___active.png"]];
}


-(void)textFieldDidEndEditing:(UITextField *)textField {
    // Get the name of the item from the text field:
	NSString *text = addItemTextField.text;
    if (text.length == 0) {
        return;
    }
    [addItemTextField setText:nil];

    // Get the current date+time as a string in standard JSON format:
    NSString* dateString = [RESTBody JSONObjectWithDate: [NSDate date]];

    // Construct a unique document ID that will sort chronologically:
    CFUUIDRef uuid = CFUUIDCreate(nil);
    NSString *guid = (NSString*)CFUUIDCreateString(nil, uuid);
    CFRelease(uuid);
	NSString *docId = [NSString stringWithFormat:@"%@-%@", dateString, guid];
    [guid release];

    // Create the new document's properties:
	NSDictionary *inDocument = [NSDictionary dictionaryWithObjectsAndKeys:text, @"text",
                                [NSNumber numberWithBool:NO], @"check",
                                dateString, @"created_at",
                                nil];

    // Save the document, asynchronously:
    CouchDocument* doc = [database documentWithID: docId];
    RESTOperation* op = [doc putProperties:inDocument];
    [op onCompletion: ^{
        if (op.error)
            [self showErrorAlert: @"Couldn't save the new item" forOperation: op];
        // Re-run the query:
		[self.dataSource.query start];
	}];
    [op start];
}


#pragma mark - SYNC:


- (IBAction)configureSync:(id)sender {
    UINavigationController* navController = (UINavigationController*)self.parentViewController;
    ConfigViewController* controller = [[ConfigViewController alloc] init];
    [navController pushViewController: controller animated: YES];
    [controller release];
}


- (void)updateSyncURL {
    if (!self.database)
        return;
    NSURL* newRemoteURL = nil;
    NSString *syncpoint = [[NSUserDefaults standardUserDefaults] objectForKey:@"syncpoint"];
    if (syncpoint.length > 0)
        newRemoteURL = [NSURL URLWithString:syncpoint];
    
    [self forgetSync];

    NSArray* repls = [self.database replicateWithURL: newRemoteURL exclusively: YES];
    _pull = [[repls objectAtIndex: 0] retain];
    _push = [[repls objectAtIndex: 1] retain];
    [_pull addObserver: self forKeyPath: @"completed" options: 0 context: NULL];
    [_push addObserver: self forKeyPath: @"completed" options: 0 context: NULL];
}


- (void) forgetSync {
    [_pull removeObserver: self forKeyPath: @"completed"];
    [_pull release];
    _pull = nil;
    [_push removeObserver: self forKeyPath: @"completed"];
    [_push release];
    _push = nil;
}


- (void)showSyncButton {
    if (!showingSyncButton) {
        showingSyncButton = YES;
        UIBarButtonItem* syncButton =
                [[UIBarButtonItem alloc] initWithTitle: @"Configure"
                                                 style:UIBarButtonItemStylePlain
                                                target: self 
                                                action: @selector(configureSync:)];
        self.navigationItem.rightBarButtonItem = [syncButton autorelease];
    }
}


- (void)showSyncStatus {
    if (showingSyncButton) {
        showingSyncButton = NO;
        if (!progress) {
            progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
            CGRect frame = progress.frame;
            frame.size.width = self.view.frame.size.width / 4.0;
            progress.frame = frame;
        }
        UIBarButtonItem* progressItem = [[UIBarButtonItem alloc] initWithCustomView:progress];
        progressItem.enabled = NO;
        self.navigationItem.rightBarButtonItem = [progressItem autorelease];
    }
}


- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object 
                         change:(NSDictionary *)change context:(void *)context
{
    if (object == _pull || object == _push) {
        unsigned completed = _pull.completed + _push.completed;
        unsigned total = _pull.total + _push.total;
        NSLog(@"SYNC progress: %u / %u", completed, total);
        if (total > 0 && completed < total) {
            [self showSyncStatus];
            [progress setProgress:(completed / (float)total)];
            database.server.activityPollInterval = 0.5;   // poll often while progress is showing
        } else {
            [self showSyncButton];
            database.server.activityPollInterval = 2.0;   // poll less often at other times
        }
    }
}


@end
