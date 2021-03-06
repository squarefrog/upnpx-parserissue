//
//  FolderViewController.m
//  upnpxdemo
//
//  Created by Bruno Keymolen on 02/07/11.
//  Copyright 2011 Bruno Keymolen. All rights reserved.
//

#import "FolderViewController.h"

#import "MediaServerBasicObjectParser.h"
#import "MediaServer1ItemObject.h"
#import "MediaServer1ContainerObject.h"
#import "PlayBack.h"

@implementation FolderViewController

@synthesize titleLabel;

-(instancetype)initWithMediaDevice:(MediaServer1Device*)device andHeader:(NSString*)header andRootId:(NSString*)rootId{
    self = [super init];
    
    if (self) {
        /* TODO: Properties are not retained. Possible issue? */
        m_device = device;
        m_rootId=rootId;
        m_title=header;
        
        m_playList = [[NSMutableArray alloc] init];
    }

    return self;
}




#pragma mark - View lifecycle

- (void)viewDidLoad
{
    
    [super viewDidLoad];
    
    // Before we do anything, some devices do not support sorting and will fail if we try to sort on our request
    NSMutableString *outSortCaps = [[NSMutableString alloc] init];
    [[m_device contentDirectory] GetSortCapabilitiesWithOutSortCaps:outSortCaps];
    
    if ([outSortCaps rangeOfString:@"dc:title"].location != NSNotFound)
    {
        sortCriteria = @"+dc:title";
    }
    
    self.navigationController.toolbarHidden = NO;
    
    
    // Fetch the first set of results synchronously
    [self fetchResults:0];
    
    
    if (numberOfResults != m_playList.count) {
        
        // Setup a batch operation for the next set of results
        operationQueue = [[NSOperationQueue alloc] init];
//        [operationQueue setMaxConcurrentOperationCount:4];
        
        NSInteger operations = ceil((CGFloat)numberOfResults / (CGFloat)20);
        __weak typeof(self) weakSelf = self;
        
        for (NSInteger i = 1; i < operations; i++) {
            NSBlockOperation *op = [NSBlockOperation blockOperationWithBlock:^{
                NSInteger startingIndex = i * 20;
                [weakSelf fetchResults:startingIndex];
            }];
            [operationQueue addOperation:op];
        }
    }
    
    
    
    
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0 , 11.0f, self.navigationController.view.frame.size.width, 21.0f)];
    [self.titleLabel setFont:[UIFont fontWithName:@"Helvetica-Bold" size:18]];
    [self.titleLabel setBackgroundColor:[UIColor clearColor]];
    [self.titleLabel setTextColor:[UIColor colorWithRed:255.0 green:255.0 blue:255.0 alpha:1.0]];
    
    if([[PlayBack GetInstance] renderer] == nil){
        [self.titleLabel setText:@"No Renderer Selected"];        
    }else{
        [self.titleLabel setText:[[[PlayBack GetInstance] renderer] friendlyName] ];
    }
    
    [self.titleLabel setTextAlignment:NSTextAlignmentLeft];
    UIBarButtonItem *ttitle = [[UIBarButtonItem alloc] initWithCustomView:self.titleLabel];
    NSArray *items = @[ttitle]; 
    self.toolbarItems = items; 

    
    self.title = m_title;    
    
}

- (void)fetchResults:(NSInteger)startingIndex
{
    NSLog(@"Fetching %@ of %@", @(startingIndex), @(numberOfResults));
    
    //Allocate NMSutableString's to read the results
    NSMutableString *outResult = [[NSMutableString alloc] init];
    NSMutableString *outNumberReturned = [[NSMutableString alloc] init];
    NSMutableString *outTotalMatches = [[NSMutableString alloc] init];
    NSMutableString *outUpdateID = [[NSMutableString alloc] init];
    
    NSString *indexString = [NSString stringWithFormat:@"%@", @(startingIndex)];
    
    [[m_device contentDirectory] BrowseWithObjectID:m_rootId BrowseFlag:@"BrowseDirectChildren" Filter:@"*" StartingIndex:indexString RequestedCount:@"20" SortCriteria:sortCriteria OutResult:outResult OutNumberReturned:outNumberReturned OutTotalMatches:outTotalMatches OutUpdateID:outUpdateID];
//    SoapActionsAVTransport1* _avTransport = [m_device avTransport];
//    SoapActionsConnectionManager1* _connectionManager = [m_device connectionManager];
    
    //The collections are returned as DIDL Xml in the string 'outResult'
    //upnpx provide a helper class to parse the DIDL Xml in usable MediaServer1BasicObject object
    //(MediaServer1ContainerObject and MediaServer1ItemObject)
    //Parse the return DIDL and store all entries as objects in the 'mediaObjects' array
//    [m_playList removeAllObjects];
    NSData *didl = [outResult dataUsingEncoding:NSUTF8StringEncoding];
    
    NSMutableArray *objectArray = [NSMutableArray array];
    MediaServerBasicObjectParser *parser = [[MediaServerBasicObjectParser alloc] initWithMediaObjectArray:objectArray itemsOnly:NO];
    [parser parseFromData:didl];
    
    [m_playList addObjectsFromArray:objectArray];
    
    numberOfResults = [outTotalMatches integerValue];
    
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [m_playList count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    
    static NSString *CellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }
    
    // Configure the cell...
    MediaServer1BasicObject *item = m_playList[indexPath.row];
   [[cell textLabel] setText:[item title]];
//    NSLog(@"[item title]:%@", [item title]);
    
    cell.accessoryType = item.isContainer ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    
    return cell;    
    
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    MediaServer1BasicObject *item = m_playList[indexPath.row];
    if([item isContainer]){
        MediaServer1ContainerObject *container = m_playList[indexPath.row];
        FolderViewController *targetViewController = [[FolderViewController alloc] initWithMediaDevice:m_device andHeader:[container title] andRootId:[container objectID]];
        [[self navigationController] pushViewController:targetViewController animated:YES];
    }else{
        MediaServer1ItemObject *item = m_playList[indexPath.row];

        MediaServer1ItemRes *resource = nil;		
        NSEnumerator *e = [[item resources] objectEnumerator];
        while((resource = (MediaServer1ItemRes*)[e nextObject])){
            NSLog(@"%@ - %d, %@, %d, %lld, %d, %@", [item title], [resource bitrate], [resource duration], [resource nrAudioChannels], [resource size],  [resource durationInSeconds],  [resource protocolInfo] );
        }	    

        [[PlayBack GetInstance] Play:m_playList position:indexPath.row];
        
    }
}



@end
