//
//  ESDiskManager.h
//  ESDiskArbitration
//
//  Created by Etienne on 26/08/13.
//
//

#import <Foundation/Foundation.h>

@class ESAbstractDisk;

@interface ESDiskManager : NSObject

+ (id)sharedManager;

@property (readonly, copy) NSArray *disks;
@property (readonly, copy) NSArray *volumes;

@end

typedef NS_OPTIONS(NSUInteger, ESDiskManagerEvent) {
    ESDiskManagerEventDiskPeek        = (1 << 0),  // A disk was probed
    ESDiskManagerEventDiskAppeared    = (1 << 1),  // A disk was connected
    ESDiskManagerEventDiskDisappeared = (1 << 2),  // A disk was disconnected
    ESDiskManagerEventDiskMounted     = (1 << 3),  // A disk was mounted
    ESDiskManagerEventDiskUnmounted   = (1 << 4),  // A disk was unmounted
    ESDiskManagerEventAny             = 0x1F,

    ESDiskManagerEventRequestMount    = (1 << 5),
    ESDiskManagerEventRequestUnmount  = (1 << 6),
    ESDiskManagerEventRequestEject    = (1 << 7),
    ESDiskManagerEventRequestAny      = 0xE0,
};

extern NSString *ESStringFromDiskManagerEvent(ESDiskManagerEvent event);

typedef void (^ESDiskMonitorBlock)(ESDiskManagerEvent event, ESAbstractDisk *disk);

@protocol ESDiskObserver <NSObject>
- (void)manager:(ESDiskManager *)manager didObserveDisk:(ESAbstractDisk *)disk;
- (void)manager:(ESDiskManager *)manager didObserveDiskAppearing:(ESAbstractDisk *)disk;
- (void)manager:(ESDiskManager *)manager didObserveDiskDisappearing:(ESAbstractDisk *)disk;
- (void)manager:(ESDiskManager *)manager didObserveDiskMounting:(ESAbstractDisk *)disk;
- (void)manager:(ESDiskManager *)manager didObserveDiskUnmounting:(ESAbstractDisk *)disk;
@end

@interface ESDiskManager (ESDiskObserver)

- (void)addObserver:(id <ESDiskObserver>)observer forEvents:(ESDiskManagerEvent)events;
- (void)removeObserver:(id)observer;

- (id <NSObject>)observeEvents:(ESDiskManagerEvent)events handler:(ESDiskMonitorBlock)block;

@end

typedef BOOL (^ESDiskApprovalBlock)(ESDiskManagerEvent event, ESAbstractDisk *disk, NSString **approvalMessage);

@protocol ESDiskApproval <NSObject>
- (BOOL)shouldManager:(ESDiskManager *)manager allowMountingOfDisk:(ESAbstractDisk *)disk message:(NSString **)message;
- (BOOL)shouldManager:(ESDiskManager *)manager allowUnmountingOfDisk:(ESAbstractDisk *)disk message:(NSString **)message;
- (BOOL)shouldManager:(ESDiskManager *)manager allowEjectionOfDisk:(ESAbstractDisk *)disk message:(NSString **)message;
@end

@interface ESDiskManager (ESDiskApproval)
- (void)addApprover:(id <ESDiskApproval>)approver forEvents:(ESDiskManagerEvent)events;
- (void)removeApprover:(id <ESDiskApproval>)approver;

- (id <NSObject>)approveEvents:(ESDiskManagerEvent)events handler:(ESDiskApprovalBlock)block;
@end