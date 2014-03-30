//
//  BNGMainViewController.m
//  Bang
//
//  Created by Jesse on 14-3-25.
//  Copyright (c) 2014年 Taobao. All rights reserved.
//

#import "BNGMainViewController.h"
#import "BNGBarItemWindowController.h"
#import "BNGTableCell.h"

#import <ServiceManagement/ServiceManagement.h>


static NSString * const kUserDefaultsLoginAtStartKey    = @"StartAtLoginKey";
static NSString * const kParseShareTableName            = @"ShareTable";
static NSString * const kParseShareTableUserKey         = @"User";
static NSString * const kParseShareTableFileKey         = @"File";
static NSString * const kParseShareTableTypeKey         = @"Type";
static NSString * const kParseShareTableTitleKey        = @"Title";


@interface BNGMainViewController () <NSTableViewDataSource, NSTableViewDelegate>

@property (weak) IBOutlet NSTableView   *tableView;
@property (weak) IBOutlet NSTextField   *statusLabel;
@property (weak) IBOutlet NSButton      *addButton;
@property (strong) IBOutlet NSMenu      *preferenceMenu;
@property (strong) IBOutlet NSMenu      *addMenu;

@property (assign, nonatomic) BOOL isUploading;
@property (strong, nonatomic) NSMutableArray *items;
@property (strong, nonatomic) PFFile *uploadingFile;

@end


@implementation BNGMainViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Initialization code here.
        
        self.items = [NSMutableArray array];
        
        // Fetch Data
        [self fetchUserItems];
        
    }
    return self;
}


- (void)awakeFromNib {
    [super awakeFromNib];
}


#pragma mark - Actions

- (IBAction)preferenceAction:(NSButton *)sender {

    // set start at login value
    int startAtLogin = [[[NSUserDefaults standardUserDefaults] objectForKey:kUserDefaultsLoginAtStartKey] intValue];
    [(NSButton *)[self.preferenceMenu.itemArray objectAtIndex:0] setState:startAtLogin];
    
    // pop up menu
    NSPoint location = [sender convertPoint:NSMakePoint(10, NSMaxY(sender.frame)) toView:nil];
    NSEvent *event =  [NSEvent mouseEventWithType:NSLeftMouseDown
                                         location:location
                                    modifierFlags:NSLeftMouseDownMask
                                        timestamp:[[NSDate date] timeIntervalSince1970]
                                     windowNumber:[[sender window] windowNumber]
                                          context:[[sender window] graphicsContext]
                                      eventNumber:0
                                       clickCount:1
                                         pressure:1];
    
    [NSMenu popUpContextMenu:self.preferenceMenu
                   withEvent:event
                     forView:sender];
}


- (IBAction)addAction:(NSButton *)sender {
    if (self.isUploading) {
        
        [self cancelUpload];
        
    } else {
        // pop up menu
        NSPoint location = [sender convertPoint:NSMakePoint(10, NSMaxY(sender.frame)) toView:nil];
        NSEvent *event =  [NSEvent mouseEventWithType:NSLeftMouseDown
                                             location:location
                                        modifierFlags:NSLeftMouseDownMask
                                            timestamp:[[NSDate date] timeIntervalSince1970]
                                         windowNumber:[[sender window] windowNumber]
                                              context:[[sender window] graphicsContext]
                                          eventNumber:0
                                           clickCount:1
                                             pressure:1];
        
        [NSMenu popUpContextMenu:self.addMenu
                       withEvent:event
                         forView:sender];
    }
}



- (IBAction)itemImageAction:(id)sender {
    NSInteger row = [self.tableView rowForView:sender];
    PFObject *item = [self.items objectAtIndex:row];
    PFFile *file = item[kParseShareTableFileKey];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:file.url]];
}

- (IBAction)linkAction:(id)sender {
    NSInteger row = [self.tableView rowForView:sender];
    PFObject *item = [self.items objectAtIndex:row];
    PFFile *file = item[kParseShareTableFileKey];

    // copy url to pasteboard
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    [pboard declareTypes:[NSArray arrayWithObject:NSPasteboardTypeString] owner:self];
    if ([pboard setString:file.url forType:NSPasteboardTypeString]) {
        [self updateStatus:@"Copied to pasteboard!" shouldHide:YES];
    }
}


- (IBAction)deleteAction:(id)sender {
    NSInteger row = [self.tableView rowForView:sender];
    PFObject *item = [self.items objectAtIndex:row];
    [item deleteInBackground];
    
    // update the table view
    [self.tableView beginUpdates];
    [self.items removeObject:item];
    [self.tableView removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:row]
                          withAnimation:NSTableViewAnimationEffectFade];
    [self.tableView endUpdates];
}


#pragma mark - Menu Actions

- (IBAction)startAtLoginAction:(id)sender {
    NSButton *button = sender;
    if (button.state == NSOffState) { // ON
        if (SMLoginItemSetEnabled ((__bridge CFStringRef)@"com.damarc.Helper", YES)) {
            button.state = NSOnState;
        }
    } else {
        if (SMLoginItemSetEnabled ((__bridge CFStringRef)@"com.damarc.Helper", NO)) {
            button.state = NSOffState;
        }
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:@(button.state) forKey:kUserDefaultsLoginAtStartKey];
}


- (IBAction)signOutAction:(id)sender {

    // clear data
    [self.items removeAllObjects];
    [self.tableView reloadData];

    // log out
    [PFUser logOut];
    
    // change to login view
    [[BNGBarItemWindowController sharedController] changeToLoginViewController];
}


- (IBAction)quitAction:(id)sender {
    [[NSApplication sharedApplication] terminate:nil];
}


- (IBAction)captureScheenshotAction:(id)sender {
    // hide window
    [[BNGBarItemWindowController sharedController] hideWindow];
    
    // capture
    [self capture];
}


- (IBAction)shareFileAction:(id)sender {
    // hide window
    [[BNGBarItemWindowController sharedController] hideWindow];
    
    // open FileChooser
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setCanChooseFiles:YES];
    [openPanel setCanChooseDirectories:NO];
    if ( [openPanel runModal] == NSOKButton )
    {
        NSURL *fileUrl = [[openPanel URLs] objectAtIndex:0];
        NSFileManager *fileManger = [NSFileManager defaultManager];
        BOOL isDir;
        if ([fileManger fileExistsAtPath:fileUrl.relativePath isDirectory:&isDir] && !isDir) {
            
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:fileUrl.relativePath error: NULL];
            int64_t result = [attrs fileSize];
            if (result < 10485760) {
                NSString *fileType = @"file";
                if ([[NSImage imageFileTypes] containsObject:[fileUrl pathExtension]]) {
                    fileType = @"image";
                }
                
                PFFile *file = [PFFile fileWithName:[fileUrl lastPathComponent] contentsAtPath:fileUrl.relativePath];
                [self uploadFile:file type:fileType];
            } else {
                [self updateStatus:@"Sorry, File is too Large (>10M)" shouldHide:YES];
                [[BNGBarItemWindowController sharedController] showWindow];
            }
            
        } else {
            [self updateStatus:@"Sorry, Directory is Not Allowed" shouldHide:YES];
            [[BNGBarItemWindowController sharedController] showWindow];
        }
    }}


#pragma mark - utility

- (void)capture {
    @try {
        
        NSTask* task = [[NSTask alloc] init];
        [task setArguments: [NSArray arrayWithObject: @"-ic"]];
        [task setLaunchPath: @"/usr/sbin/screencapture"];
        [task launch];
        [task waitUntilExit];
        
        NSData* data = [[NSPasteboard generalPasteboard] dataForType: NSPasteboardTypePNG];
        if (data != nil) {
            NSString *fileName = [NSString stringWithFormat:@"SC%@", @((NSInteger)[[NSDate date] timeIntervalSince1970])];
            PFFile *file = [PFFile fileWithName:fileName data:data];
            [self uploadFile:file type:@"image"];
        }
    }
    @catch (NSException *exception) {
        
    }
}


- (void)uploadFile:(PFFile *)file type:(NSString *)fileType{
    
    // Upload file first
    self.isUploading = YES;
    [self updateStatus:@"Uploading.." shouldHide:NO];

    [file saveInBackgroundWithBlock:^(BOOL succeeded, NSError *error) {
        if (succeeded) {
            
            // then save object
            [self updateStatus:@"Saving.." shouldHide:NO];

            PFObject *screenCapture = [PFObject objectWithClassName:kParseShareTableName];
            screenCapture[kParseShareTableTitleKey] = file.name;
            screenCapture[kParseShareTableFileKey] = file;
            screenCapture[kParseShareTableTypeKey] = fileType;
            screenCapture[kParseShareTableUserKey] = [PFUser currentUser];
            
            PFACL *acl = [PFACL ACLWithUser:[PFUser currentUser]];
            [acl setPublicReadAccess:YES];
            [screenCapture setACL:acl];
            
            [screenCapture saveInBackgroundWithBlock:^(BOOL succeeded, NSError *error) {

                if (succeeded) {
                    [self updateStatus:@"Done!" shouldHide:YES];
                } else {
                    [self updateStatus:[NSString stringWithFormat:@"Error:%@", error.userInfo] shouldHide:NO];
                }
                
                self.isUploading = NO;
                
                // change the status bar item color
                [[BNGBarItemWindowController sharedController] setStatusItemHighligted:YES];

                // update the table view
                [self.tableView beginUpdates];
                [self.items insertObject:screenCapture atIndex:0];
                [self.tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:0]
                                      withAnimation:NSTableViewAnimationSlideDown];
                [self.tableView endUpdates];
            }];
            
        } else {
            
            [self updateStatus:[NSString stringWithFormat:@"Error:%@", error.userInfo] shouldHide:NO];
            self.isUploading = NO;

        }
    } progressBlock:^(int percentDone) {
        [self updateStatus:[NSString stringWithFormat:@"Uploading (%d%%)", percentDone] shouldHide:NO];
    }];
    
    self.uploadingFile = file;
}


- (void)cancelUpload {
    [self.uploadingFile cancel];
    self.uploadingFile = nil;
    self.isUploading = NO;
    
    [self updateStatus:@"Cancaled" shouldHide:YES];
}


- (void)fetchUserItems {
    PFQuery *query = [PFQuery queryWithClassName:kParseShareTableName];
    [query whereKey:kParseShareTableUserKey equalTo:[PFUser currentUser]];
    [query orderByDescending:@"createdAt"];
    [query findObjectsInBackgroundWithBlock:^(NSArray *objects, NSError *error) {
        if (!error) {
            
            [self.items addObjectsFromArray:objects];
            [self.tableView reloadData];
            
            NSLog(@"Fetch items : %ld", objects.count);
        } else {
            // Log details of the failure
            NSLog(@"Error: %@ %@", error, [error userInfo]);
        }
    }];
}


- (void)setIsUploading:(BOOL)isUploading {
    _isUploading = isUploading;
    
    if (isUploading) {
        [self.addButton.animator setFrameCenterRotation:45.0f];
    } else {
        [self.addButton.animator setFrameCenterRotation:0.0f];
    }
}


- (void)updateStatus:(NSString *)string shouldHide:(BOOL)shouldHide {
    self.statusLabel.stringValue = string;
    
    // set @"" after 1 second
    if (shouldHide) {
        [[self.statusLabel class] cancelPreviousPerformRequestsWithTarget:self];
        [self.statusLabel performSelector:@selector(setStringValue:)
                               withObject:@""
                               afterDelay:2.0f];
    }
}


//TODO: not good now
- (NSString *)formattedDataStringFromNSDate:(NSDate *)date {
    static NSString * month[] = {@"Jan", @"Feb", @"Mar", @"Apr", @"May", @"Jun", @"Jul", @"Aug", @"Sep", @"Oct", @"Nov", @"Dec"};
    
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [calendar components:NSMinuteCalendarUnit|NSHourCalendarUnit|NSDayCalendarUnit|NSMonthCalendarUnit
                                               fromDate:date];

    return [NSString stringWithFormat:@"%ld:%ld   %@ %ldst", components.hour, components.minute, month[components.month - 1], components.day];
}


#pragma mark - TableView

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    
    BNGTableCell *cell = [tableView makeViewWithIdentifier:@"BNGTableCell" owner:self];
   
    PFObject *item = [self.items objectAtIndex:row];
    cell.nameLabel.stringValue = item[kParseShareTableTitleKey];
    cell.nameLabel.toolTip = item[kParseShareTableTitleKey];
    cell.timeLabel.stringValue = [self formattedDataStringFromNSDate:item.createdAt];

    return cell;
}


- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.items.count;
}


- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    return 60.0f;
}


- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    return NO;
}

@end
