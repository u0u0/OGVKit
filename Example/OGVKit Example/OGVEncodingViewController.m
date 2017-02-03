//
//  OGVEncodingViewController.m
//  OGVKit Example
//
//  Created by Brion on 2/2/17.
//  Copyright © 2017 Brion Vibber. All rights reserved.
//

#import "OGVEncodingViewController.h"
#import <MobileCoreServices/MobileCoreServices.h>

@interface OGVEncodingViewController ()

@end

@implementation OGVEncodingViewController
{
    NSURL *inputURL;
    NSURL *outputURL;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.transcodeButton.enabled = NO;
    self.transcodeProgress.progress = 0.0f;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/


- (IBAction)chooserAction:(id)sender
{
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        NSLog(@"no photo library permission?");
        return;
    }
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[(__bridge id)kUTTypeMovie];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        picker.modalPresentationStyle = UIModalPresentationPopover;
    }
    [self presentViewController:picker animated:YES completion:nil];
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        UIPopoverPresentationController *pop = [picker popoverPresentationController];
        pop.sourceView = sender;
    }
}

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info
{
    [picker.parentViewController dismissViewControllerAnimated:YES completion:nil];

    inputURL = info[UIImagePickerControllerMediaURL];
    outputURL = nil;
    
    self.inputPlayer.sourceURL = inputURL;
    
    self.transcodeButton.enabled = YES;
    self.transcodeProgress.progress = 0.0f;
}

- (IBAction)transcodeAction:(id)sender
{
    self.chooserButton.enabled = NO;
    self.transcodeButton.enabled = NO;
    self.transcodeProgress.progress = 0.0f;
    
    OGVMediaType *mp4 = [[OGVMediaType alloc] initWithString:@"video/mp4"];
    OGVDecoder *decoder = [[OGVKit singleton] decoderForType:mp4];
    decoder.inputStream = [OGVInputStream inputStreamWithURL:inputURL];
    
    dispatch_queue_t transcodeThread = dispatch_queue_create("Example.transcode", NULL);
    dispatch_async(transcodeThread, ^() {
        while (!decoder.dataReady) {
            if (![decoder process]) {
                [NSException raise:@"ExampleException"
                            format:@"failed before data ready?"];
            }
        }
        while ((decoder.hasAudio && !decoder.audioReady) || (decoder.hasVideo && !decoder.frameReady)) {
            // hack to make sure found packets
            [decoder process];
        }
        
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"output.webm"];
        OGVFileOutputStream *outputStream = [[OGVFileOutputStream alloc] initWithPath:path];

        OGVMediaType *webm = [[OGVMediaType alloc] initWithString:@"video/webm"];
        OGVEncoder *encoder = [[OGVEncoder alloc] initWithMediaType:webm];
        [encoder openOutputStream:outputStream];
        [encoder addVideoTrackFormat:decoder.videoFormat
                             options:@{OGVVideoEncoderOptionsBitrateKey:@1000000,
                                       OGVVideoEncoderOptionsKeyframeIntervalKey: @150}];
        [encoder addAudioTrackFormat:decoder.audioFormat
                             options:@{OGVAudioEncoderOptionsBitrateKey:@128000}];
        
        float total = decoder.duration;
        float lastTime = 0.0f;
        while (decoder.frameReady || decoder.audioReady) {
            BOOL doVideo = NO, doAudio = NO;

            if (decoder.frameReady && decoder.audioReady) {
                if (decoder.audioTimestamp <= decoder.frameTimestamp) {
                    lastTime = decoder.audioTimestamp;
                    doAudio = YES;
                } else {
                    lastTime = decoder.frameTimestamp;
                    doVideo = YES;
                }
            } else if (decoder.frameReady) {
                lastTime = decoder.frameTimestamp;
                doVideo = YES;
            } else if (decoder.audioReady) {
                lastTime = decoder.audioTimestamp;
                doAudio = YES;
            }

            float percent = lastTime / total;
            dispatch_async(dispatch_get_main_queue(), ^() {
                self.transcodeProgress.progress = percent;
            });
            if (doVideo) {
                NSLog(@"frame");
                if ([decoder decodeFrame]) {
                    [encoder encodeFrame:decoder.frameBuffer];
                }
            } else if (doAudio) {
                NSLog(@"audio");
                if ([decoder decodeAudio]) {
                    [encoder encodeAudio:decoder.audioBuffer];
                }
            }
            while ((decoder.hasAudio && !decoder.audioReady) || (decoder.hasVideo && !decoder.frameReady)) {
                if (![decoder process]) {
                    break;
                }
            }
        }
        NSLog(@"done");
        
        [encoder close];
        
        dispatch_async(dispatch_get_main_queue(), ^() {
            NSLog(@"playing %@", path);
            self.transcodeProgress.progress = 1.0;
            self.chooserButton.enabled = YES;
            self.outputPlayer.sourceURL = [NSURL fileURLWithPath:path];
            [self.outputPlayer play];
        });
    });
}

@end