//
//  ESDiskManager.m
//  ESDiskArbitration
//
//  Created by Etienne on 26/08/13.
//
//

#import "ESDiskManager.h"
#import "ESDisk.h"
#import "ESDiskArbitration+Private.h"

#define NSSTRINGIFY(x) @#x
#define ESSTRINGIFYEVENT(x) \
if (event & x) {\
    [eventStrings addObject:NSSTRINGIFY(x)];\
}

NSString *ESStringFromDiskManagerEvent(ESDiskManagerEvent event) {
    NSMutableArray *eventStrings = [NSMutableArray array];
    ESSTRINGIFYEVENT(ESDiskManagerEventDiskPeek);
    ESSTRINGIFYEVENT(ESDiskManagerEventDiskAppeared);
    ESSTRINGIFYEVENT(ESDiskManagerEventDiskDisappeared);
    ESSTRINGIFYEVENT(ESDiskManagerEventDiskMounted);
    ESSTRINGIFYEVENT(ESDiskManagerEventDiskUnmounted);
    ESSTRINGIFYEVENT(ESDiskManagerEventRequestMount);
    ESSTRINGIFYEVENT(ESDiskManagerEventRequestUnmount);
    ESSTRINGIFYEVENT(ESDiskManagerEventRequestEject);

    return [eventStrings componentsJoinedByString:@"|"];
}

#undef ESSTRINGIFYEVENT

struct ESNotificationContext {
    BOOL approved;
    __unsafe_unretained NSString *message;
};

@interface ESDiskManager () {
    dispatch_queue_t _queue;
}

@property (retain) NSMapTable *notificationHandlers;
@property (retain) NSMutableSet *underlyingDiskSet;
@property (retain) NSMutableSet *diskSet;
@property (retain) NSMutableSet *volumeSet;

- (void)notifyHandlersOfEvent:(ESDiskManagerEvent)event forDisk:(DADiskRef)diskRef context:(struct ESNotificationContext **)context;

@end

#pragma mark -
#pragma mark DiskArbitration notification callbacks

void ESDiskMonitorAppearedCallback(DADiskRef disk, void *context) {
    NSCParameterAssert(disk != nil);
    NSCParameterAssert(context != NULL);

    ESDiskManager *self = (__bridge ESDiskManager *)context;
    [self notifyHandlersOfEvent:ESDiskManagerEventDiskAppeared forDisk:disk context:NULL];
}

void ESDiskMonitorDisappearedCallback(DADiskRef disk, void *context) {
    NSCParameterAssert(disk != nil);
    NSCParameterAssert(context != NULL);

    ESDiskManager *self = (__bridge ESDiskManager *)context;
    [self notifyHandlersOfEvent:ESDiskManagerEventDiskDisappeared forDisk:disk context:NULL];
}

void ESDiskMonitorPeekCallback(DADiskRef disk, void *context) {
    NSCParameterAssert(disk != nil);
    NSCParameterAssert(context != NULL);

    ESDiskManager *self = (__bridge ESDiskManager *)context;
    [self notifyHandlersOfEvent:ESDiskManagerEventDiskPeek forDisk:disk context:NULL];
}

void ESDiskMountDetectionCallback(DADiskRef disk, CFArrayRef keys, void *context) {
    NSCParameterAssert(disk != nil);
    NSCParameterAssert(context != NULL);

    ESDiskManager *self = (__bridge ESDiskManager *)context;
    
    NSDictionary *diskDict = (NSDictionary *)CFBridgingRelease(DADiskCopyDescription(disk));

    for (NSString *key in (__bridge NSArray *)keys) {
        id value = diskDict[key];

        if ([key isEqualToString:(NSString *)kDADiskDescriptionVolumePathKey]) {
            [self notifyHandlersOfEvent:(value != nil ? ESDiskManagerEventDiskMounted : ESDiskManagerEventDiskUnmounted) forDisk:disk context:NULL];
        }
    }
}

#pragma mark -
#pragma mark DiskArbitration approval callbacks

CF_RETURNS_RETAINED DADissenterRef ESDiskMountApprovalCallback(DADiskRef disk, void *context) {
    NSCParameterAssert(disk != nil);
    NSCParameterAssert(context != NULL);

    ESDiskManager *self = (__bridge ESDiskManager *)context;

    DADissenterRef dissenter = NULL;
    struct ESNotificationContext *data = NULL;

    [self notifyHandlersOfEvent:ESDiskManagerEventRequestMount forDisk:disk context:&data];
    if (data && !data->approved) {
        dissenter = DADissenterCreate(kCFAllocatorDefault, kDAReturnNotPermitted, (__bridge CFStringRef)data->message);
    }
    return dissenter;
}

CF_RETURNS_RETAINED DADissenterRef ESDiskUnmountApprovalCallback(DADiskRef disk, void *context) {
    NSCParameterAssert(disk != nil);
    NSCParameterAssert(context != NULL);

    ESDiskManager *self = (__bridge ESDiskManager *)context;

    DADissenterRef dissenter = NULL;
    struct ESNotificationContext *data = NULL;

    [self notifyHandlersOfEvent:ESDiskManagerEventRequestUnmount forDisk:disk context:&data];
    if (data && !data->approved) {
        dissenter = DADissenterCreate(kCFAllocatorDefault, kDAReturnNotPermitted, (__bridge CFStringRef)data->message);
    }
    return dissenter;
}

CF_RETURNS_RETAINED DADissenterRef ESDiskEjectApprovalCallback(DADiskRef disk, void *context) {
    NSCParameterAssert(disk != nil);
    NSCParameterAssert(context != NULL);

    ESDiskManager *self = (__bridge ESDiskManager *)context;

    DADissenterRef dissenter = NULL;
    struct ESNotificationContext *data = NULL;

    [self notifyHandlersOfEvent:ESDiskManagerEventRequestEject forDisk:disk context:&data];
    if (data && !data->approved) {
        dissenter = DADissenterCreate(kCFAllocatorDefault, kDAReturnNotPermitted, (__bridge CFStringRef)data->message);
    }
    return dissenter;
}

@implementation ESDiskManager

+ (NSSet *)keyPathsForValuesAffectingDisks {
    return [NSSet setWithObject:@"diskSet"];
}

+ (NSSet *)keyPathsForValuesAffectingVolumes {
    return [NSSet setWithObject:@"volumeSet"];
}

+ (id)sharedManager {
    static ESDiskManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    char *label;
    int err = asprintf(&label, "ESDiskManagerQueue %p", (__bridge void *)self);
    if (err == -1) return nil;
    
    _queue = dispatch_queue_create(label, NULL);
    free(label);
    if (!_queue) {
        return nil;
    }

    _session = DASessionCreate(NULL);
    if (!_session) {
        return nil;
    }

    _notificationHandlers = [[NSMapTable alloc] init];

    _underlyingDiskSet = [NSMutableSet set];
    _diskSet = [NSMutableSet set];
    _volumeSet = [NSMutableSet set];

    DASessionSetDispatchQueue(_session, _queue);

    DARegisterDiskAppearedCallback(_session, NULL, ESDiskMonitorAppearedCallback, (__bridge void *)self);
    DARegisterDiskDisappearedCallback(_session, NULL, ESDiskMonitorDisappearedCallback, (__bridge void *)self);
    DARegisterDiskPeekCallback(_session, NULL, 0, ESDiskMonitorPeekCallback, (__bridge void *)self);

    DARegisterDiskDescriptionChangedCallback(_session, NULL, (__bridge CFArrayRef)@[(NSString *)kDADiskDescriptionVolumePathKey], ESDiskMountDetectionCallback, (__bridge void *)self);

    DARegisterDiskMountApprovalCallback(_session, NULL, ESDiskMountApprovalCallback, (__bridge void *)self);
    DARegisterDiskUnmountApprovalCallback(_session, NULL, ESDiskUnmountApprovalCallback, (__bridge void *)self);
    DARegisterDiskEjectApprovalCallback(_session, NULL, ESDiskEjectApprovalCallback, (__bridge void *)self);

    return self;
}

- (void)dealloc {
    DASessionSetDispatchQueue(_session, NULL);

    if (_session) {
        CFRelease(_session), _session = nil;
    }
}

- (Class)diskClassForDiskDescription:(NSDictionary *)info {
    if ([info[(__bridge NSString *)kDADiskDescriptionVolumeNetworkKey] isEqual:@(YES)]) {
        return [ESNetworkVolume class];
    } else if ([info[(__bridge NSString *)kDADiskDescriptionMediaWholeKey] isEqual:@(YES)]) {
        return [ESDisk class];
    } else {
        return [ESVolume class];
    }
    return nil;
}

- (ESAbstractDisk *)knownDiskForDADisk:(DADiskRef)diskRef {
    // Search our disk set for the correct disk
    for (ESDisk *disk in self.underlyingDiskSet) {
        if (CFHash(disk.diskRef) == CFHash(diskRef)) {
            return disk;
        }
    }

    NSDictionary *info = (__bridge_transfer NSDictionary *)DADiskCopyDescription(diskRef);

    Class klass = [self diskClassForDiskDescription:info];
    ESAbstractDisk *disk = [[klass alloc] initWithDADisk:diskRef description:info manager:self];
    NSAssert(disk != nil, @"disk was nil");

    [self.underlyingDiskSet addObject:disk];
    if (disk.isDisk) {
        [self.diskSet addObject:disk];
    } else if (disk.isVolume) {
        [self.volumeSet addObject:disk];
    } else {
        [NSException raise:NSInternalInconsistencyException format:@"Unhandled disk type: %@", disk];
    }

    return disk;
}

- (void)registerNotificationHandler:(id)handler info:(NSDictionary *)handlerDict {
    NSParameterAssert(handler != nil);
    NSParameterAssert(handlerDict != nil);

    [self.notificationHandlers setObject:handlerDict forKey:handler];
}

- (void)unregisterNotificationHandler:(id)handler {
    NSParameterAssert(handler != nil);
    [self.notificationHandlers removeObjectForKey:handler];
}

- (void)notifyHandlersOfEvent:(ESDiskManagerEvent)notifyEvent forDisk:(DADiskRef)diskRef context:(struct ESNotificationContext **)context {
    NSParameterAssert(diskRef != nil);

    ESAbstractDisk *disk = [self knownDiskForDADisk:diskRef];

    for (id handler in self.notificationHandlers) {
        NSDictionary *observerInfo = [self.notificationHandlers objectForKey:handler];

        ESDiskManagerEvent observedEvents = [observerInfo[@"events"] unsignedIntegerValue];

//        NSLog(@"%s: matching event %lX against %lX for %@", __FUNCTION__, notifyEvent, observedEvents, disk);

        if (!(observedEvents & notifyEvent)) continue;

//        NSLog(@"%s: event %lX matches %lX for %@", __FUNCTION__, notifyEvent, observedEvents, disk);

        ESDiskMonitorBlock observerBlock = (ESDiskMonitorBlock)observerInfo[@"observationBlock"];
        ESDiskApprovalBlock approvalBlock = (ESDiskApprovalBlock)observerInfo[@"approvalBlock"];
        if (observerBlock) {
            observerBlock(notifyEvent, disk);
        } else if (approvalBlock) {
            *context = calloc(1, sizeof(struct ESNotificationContext));
            NSString *message = nil;
            (*context)->approved = approvalBlock(notifyEvent, disk, &message);
            (*context)->message = message;
        }
    }


}

- (NSArray *)disks {
    return [self.diskSet allObjects];
}

- (NSArray *)volumes {
    return [self.volumeSet allObjects];
}

@end

@implementation ESDiskManager (ESDiskObserver)

- (void)addObserver:(id <ESDiskObserver>)observer forEvents:(ESDiskManagerEvent)events {
    [self registerNotificationHandler:observer info:@{@"events": @(events)}];
}

- (void)removeObserver:(id)observer {
    [self unregisterNotificationHandler:observer];
}

- (id <NSObject>)observeEvents:(ESDiskManagerEvent)events handler:(ESDiskMonitorBlock)block {
    NSParameterAssert(block != nil);

    ESObserverObject *observer = [[ESObserverObject alloc] init];
    [self registerNotificationHandler:observer info:@{@"events": @(events), @"observationBlock": [block copy]}];
    return observer;
}

@end

@implementation ESDiskManager (ESDiskApproval)

- (void)addApprover:(id <ESDiskApproval>)approver forEvents:(ESDiskManagerEvent)events {
    [self registerNotificationHandler:approver info:@{@"events": @(events)}];
}

- (void)removeApprover:(id<ESDiskApproval>)approver {
    [self unregisterNotificationHandler:approver];
}

- (id <NSObject>)approveEvents:(ESDiskManagerEvent)events handler:(ESDiskApprovalBlock)block {
    NSParameterAssert(block != nil);
    ESObserverObject *approver = [[ESObserverObject alloc] init];

    [self registerNotificationHandler:approver info:@{@"events": @(events), @"approvalBlock": [block copy]}];

    return approver;
}

@end