//
//  PHPhotoLibrary+SaveImage.m
//  EdiMax
//
//  Created by Bryant Tsai on 27/02/2018.
//

#import "PHPhotoLibrary+SaveImage.h"
//#import "AFNetworking/AFNetworking.h"
#define PHAssetDomain @"PHAssetDomain"
@implementation PHPhotoLibrary (SaveImage)


- (void) _saveVideo:(NSURL*)url album:(PHAssetCollection*)album completion:(void (^)(PHAsset*, NSError*))completion {
    __block PHObjectPlaceholder *placeholder = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetCreationRequest *createRequest = [PHAssetCreationRequest creationRequestForAssetFromVideoAtFileURL:url];
        PHAssetCollectionChangeRequest *albumChangeRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:album];
        placeholder = [createRequest placeholderForCreatedAsset];
        if (placeholder == nil) {
            return;
        }
        [albumChangeRequest addAssets:@[placeholder]];
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (error) {
        
        }
        if (placeholder == nil) {
            completion(nil, error);
            return;
        }
        
        if (success) {
            PHFetchResult *asset = [PHAsset fetchAssetsWithLocalIdentifiers:@[placeholder.localIdentifier] options:nil];
            completion(asset.firstObject, nil);
        } else {
            completion(nil, error);
        }
    }];
}

//- (void) _savePhoto:(UIImage*)image albumName:(NSString*)albumName completion:(void (^)(PHAsset*, NSError*))completion {
//    PHAssetCollection* album = [self findAlbum:albumName];
//    if (album != nil) {
//        [self _saveImage:image album:album completion:completion];
//    } else {
//        [self createAlbum:albumName completion:^(PHAssetCollection *collection) {
//            if (collection != nil) {
//                [self _saveImage:image album:album completion:completion];
//            } else {
//                if (completion) {
//                    completion(nil, [NSError errorWithDomain:PHAssetDomain code:0 userInfo:@{@"message": @"Failed to create album"}]);
//                }
//            }
//        }];
//    }
//}

- (void) _saveVideo:(NSURL*)url albumName:(NSString*)albumName completion:(void (^)(PHAsset*, NSError*))completion {
    PHAssetCollection* album = [self findAlbum:albumName];
    if (album != nil) {
        [self _saveVideo:url album:album completion:completion];
    } else {
        [self createAlbum:albumName completion:^(PHAssetCollection *collection) {
            if (collection != nil) {
                [self _saveVideo:url album:album completion:completion];
            } else {
                if (completion) {
                    completion(nil, [NSError errorWithDomain:PHAssetDomain code:0 userInfo:@{@"message": @"Failed to create album"}]);
                }
            }
        }];
    }
}

- (PHAssetCollection *) findAlbum:(NSString*)albumName  {
    PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
    fetchOptions.predicate = [NSPredicate predicateWithFormat:@"title = %@", albumName];
    PHFetchResult *fetchResult = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAny options:fetchOptions];
    return fetchResult.firstObject;
}

- (void) createAlbum:(NSString*)albumName completion:(void (^)(PHAssetCollection*))completion {
    __block PHObjectPlaceholder *placeholder = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetCollectionChangeRequest *createAlbumRequest = [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:albumName];
        placeholder = createAlbumRequest.placeholderForCreatedAssetCollection;
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (success) {
            if (placeholder == nil) {
                completion(nil);
                return;
            }
            
            PHFetchResult *fetchResult = [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[placeholder.localIdentifier] options:nil];
            completion(fetchResult.firstObject);
        } else {
            completion(nil);
        }
    }];
}

//- (void) savePhoto:(UIImage*)image albumName:(NSString*)albumName completion:(void (^)(PHAsset*, NSError*))completion {
//    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
//    if (status == PHAuthorizationStatusAuthorized) {
//        [self _savePhoto:image albumName:albumName completion:completion];
//    } else if (status == PHAuthorizationStatusDenied) {
//        if (completion) {
//            completion(nil, [NSError errorWithDomain:PHAssetDomain code:0 userInfo:@{@"message": @"Authorization denied"}]);
//        }
//    } else {
//        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
//            if (status == PHAuthorizationStatusAuthorized) {
//                [self _savePhoto:image albumName:albumName completion:completion];
//            }
//        }];
//    }
//}

- (void) saveVideo:(NSURL*)url albumName:(NSString*)albumName completion:(void (^)(PHAsset*, NSError*))completion {
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusAuthorized) {
        [self _saveVideo:url albumName:albumName completion:completion];
    } else if (status == PHAuthorizationStatusDenied) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:PHAssetDomain code:0 userInfo:@{@"message": @"Authorization denied"}]);
        }
    } else {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            if (status == PHAuthorizationStatusAuthorized) {
                [self _saveVideo:url albumName:albumName completion:completion];
            }
        }];
    }
}
@end
