//
//  PHPhotoLibrary+SaveImage.h
//  EdiMax
//
//  Created by Bryant Tsai on 27/02/2018.
//

#import <Photos/Photos.h>

@interface PHPhotoLibrary (SaveImage)

//- (void) saveURL:(NSURL *)url albumName:(NSString *)albumName completion:(void (^)(PHAsset *, NSError *))completion;
//- (void) savePhoto:(UIImage*)image albumName:(NSString*)albumName completion:(void (^)(PHAsset*, NSError*))completion;
- (void) saveVideo:(NSURL*)url albumName:(NSString*)albumName completion:(void (^)(PHAsset*, NSError*))completion;
@end
