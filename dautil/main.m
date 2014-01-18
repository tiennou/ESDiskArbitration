//
//  main.m
//  dautil
//
//  Created by Etienne on 17/02/2016.
//  Copyright © 2016 Etienne Samson. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <ESDiskArbitration/ESDiskArbitration.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        ESDiskManager *manager = [ESDiskManager sharedManager];
        [manager observeEvents:ESDiskManagerEventAny handler:^(ESDiskManagerEvent event, ESAbstractDisk *absDisk) {
            NSLog(@"got event: %ld, %@, disk: %@, \"%@\"", event, ESStringFromDiskManagerEvent(event), absDisk.BSDName, absDisk.name);
            NSLog(@"description: %@", absDisk.diskDescription);
            NSLog(@"manager disks: %@, volumes: %@", manager.disks, manager.volumes);
//            NSImage *diskIcon = absDisk.icon;

            if (absDisk.isDisk && (event & ESDiskManagerEventDiskAppeared)) {
                ESDisk *disk = (ESDisk *)absDisk;
                NSLog(@"Disk %@ is %@", disk.name, (disk.isRemovable ? @"removable" : @"unremovable"));
                if (disk.isRemovable) {
                    [(ESDisk *)disk eject:ESDiskEjectOptionsDefault completionHandler:^(NSError *error) {
                        if (error) {
                            NSLog(@"Failed to eject %@: %@", disk, error);
                            return;
                        }
                        NSLog(@"Ejection of %@ successful: %@", disk, manager.disks);
                    }];
                }
            } else if (absDisk.isVolume) {
                ESVolume *volume = (ESVolume *)absDisk;
                if (volume.disk.isRemovable) {
                    if (event & ESDiskManagerEventDiskMounted && volume.isMounted) {
                        [volume unmount:ESVolumeUnmountOptionsDefault completionHandler:^(NSError *error) {
                            if (error) {
                                NSLog(@"Failed to unmount volume: %@", error);
                                return;
                            }
                            NSLog(@"Successfully unmounted volume: %@", manager.volumes);
                        }];
                    } else if (!volume.isMounted) {
                        [volume mount:^(NSError *error) {
                            if (error) {
                                NSLog(@"Failed to mount volume: %@", error);
                                return;
                            }
                            NSLog(@"Successfully mounted volume: %@", manager.volumes);
                        }];
                    }
                }
            }
        }];

        [manager approveEvents:ESDiskManagerEventRequestAny handler:^BOOL(ESDiskManagerEvent event, ESAbstractDisk *disk, NSString *__autoreleasing *approvalMessage) {
            NSLog(@"got approval request %@ for %@:", ESStringFromDiskManagerEvent(event), disk);
            if (disk.isVolume && [[(ESVolume *)disk disk] isRemovable]) {
                *approvalMessage = @"I don't want no removable disks anywhere here";
                return NO;
            }
            *approvalMessage = @"I always say something";
            return YES;
        }];

        dispatch_main();
    }
    return 0;
}
