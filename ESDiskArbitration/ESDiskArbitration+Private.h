//
//  ESDiskArbitration+Private.h
//  ESDiskArbitration
//
//  Created by Etienne on 18/02/2016.
//  Copyright © 2016 Etienne Samson. All rights reserved.
//

#import <DiskArbitration/DiskArbitration.h>
#import <ESDiskArbitration/ESDiskArbitration.h>

// Used as a token by the block-based observer on ESDiskManager
@interface ESObserverObject : NSObject
@end

@interface ESDiskManager ()

- (ESDisk *)knownDiskForDADisk:(DADiskRef)diskRef;

@property (readonly, /* retain */) DASessionRef session;

@end

@interface ESAbstractDisk ()

+ (instancetype)diskWithDADisk:(DADiskRef)diskRef manager:(ESDiskManager *)manager;

- (instancetype)initWithDADisk:(DADiskRef)disk description:(NSDictionary *)diskDescription manager:(ESDiskManager *)manager NS_DESIGNATED_INITIALIZER;

- (NSMutableDictionary *)DAKeysMapping;

@property (readonly, retain) ESDiskManager *manager;
@property (readonly, /* retain */) DADiskRef diskRef;

@end

@interface ESDisk ()
@property (retain) NSMutableArray<ESVolume *> *mutableVolumes;
@end

@interface ESVolume ()
@property (readwrite, weak) ESDisk *disk;
@end

@interface NSError (ESDissenter)
+ (instancetype)es_errorWithDADissenter:(DADissenterRef)dissenter;
@end