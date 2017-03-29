//
//  ScanVCViewController.m
//  ScanBarcode
//
//  Created by Lesley Liang on 2017/3/13.
//  Copyright © 2017年 Lesley Liang. All rights reserved.
//

#import "ScanViewController.h"
#import "SCShapeView.h"

@interface ScanViewController ()
{
    AVCaptureDeviceInput *input;
    AVCaptureDevice *mycaptureDevice;
    SCShapeView *_boundingBox;
    NSTimer *_boxHideTimer;
    BOOL checkEAN13CodeResult;
}

@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *videoPreviewLayer;
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;
@property (nonatomic) BOOL isReading;
@property (nonatomic,weak) UIView *focusCircle;

@end

@implementation ScanViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"返回" style:UIBarButtonItemStylePlain target:self action:@selector(back)];
    _captureSession = nil;
    _isReading = NO;
    
    [self startStopReading];
}

-(void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [self stopReading];
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

#pragma mark - Private
-(void)back {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)startStopReading {
    if (!_isReading) {
        [self startReading];
    } else {
        [self stopReading];
    }
    
    _isReading = !_isReading;
}

- (BOOL)startReading {
    _captureSession = [[AVCaptureSession alloc] init];
    mycaptureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error = nil;
    
    // Want the normal device
    input = [AVCaptureDeviceInput deviceInputWithDevice:mycaptureDevice error:&error];
    
    if(input) {
        // Add the input to the session
        [_captureSession addInput:input];
    } else {
        //NSLog(@"error: %@", error);
        return NO;
    }
    
    AVCaptureMetadataOutput *output = [[AVCaptureMetadataOutput alloc] init];
    // Have to add the output before setting metadata types
    [_captureSession addOutput:output];
    // What different things can we register to recognise?
    //NSLog(@"%@", [output availableMetadataObjectTypes]);
    // We're only interested in QR Codes
    [output setMetadataObjectTypes:@[AVMetadataObjectTypeQRCode]];
    // This VC is the delegate. Please call us on the main queue
    [output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];

    if ([mycaptureDevice isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus] && [mycaptureDevice lockForConfiguration:&error]){
        if ([mycaptureDevice isFocusPointOfInterestSupported])
            [mycaptureDevice setFocusPointOfInterest:CGPointMake(0.5f,0.5f)];
            [mycaptureDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
            [mycaptureDevice unlockForConfiguration];
    }else{
        NSLog(@"problem ");
    }
    
    // Display on screen
    _videoPreviewLayer = [AVCaptureVideoPreviewLayer layerWithSession:_captureSession];
    _videoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _videoPreviewLayer.bounds = self.view.bounds;
    _videoPreviewLayer.position = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
    [self.view.layer addSublayer:_videoPreviewLayer];
    
    // Add the view to draw the bounding box for the UIView
    _boundingBox = [[SCShapeView alloc] initWithFrame:self.view.bounds];
    _boundingBox.backgroundColor = [UIColor clearColor];
    _boundingBox.hidden = YES;
    [self.view addSubview:_boundingBox];
    
    // Start the AVSession running
    [_captureSession startRunning];
    
    return YES;
}

-(void)stopReading{
    [_captureSession stopRunning];
    _captureSession = nil;
    
    [_videoPreviewLayer removeFromSuperlayer];
}

#pragma mark - AVCaptureMetadataOutputObjectsDelegate
-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection
{
    checkEAN13CodeResult = NO;
    
    //for (AVMetadataObject *metadata in metadataObjects) {
    if (metadataObjects != nil && [metadataObjects count] > 0) {
        AVMetadataMachineReadableCodeObject *metadataObj = [metadataObjects objectAtIndex:0];
        if ([metadataObj.type isEqualToString:AVMetadataObjectTypeQRCode]) {
            // Transform the meta-data coordinates to screen coords
            AVMetadataMachineReadableCodeObject *transformed = (AVMetadataMachineReadableCodeObject *)[_videoPreviewLayer transformedMetadataObjectForMetadataObject:metadataObj];
            // Update the frame on the _boundingBox view, and show it
            _boundingBox.frame = transformed.bounds;
            _boundingBox.hidden = NO;
            // Now convert the corners array into CGPoints in the coordinate system
            //  of the bounding box itself
            NSArray *translatedCorners = [self translatePoints:transformed.corners
                                                      fromView:self.view
                                                        toView:_boundingBox];
            
            // Set the corners array
            _boundingBox.corners = translatedCorners;
            
            // Start the timer which will hide the overlay
            [self startOverlayHideTimer];
            
            checkEAN13CodeResult = [self checkEAN13Code:transformed.stringValue];
            
            if (checkEAN13CodeResult && _isReading == YES) {
                //[self showResult:ret];
                _isReading = NO;
                [self performSelector:@selector(showResult) withObject:nil afterDelay:0.5];
            }
        }
    }
}

- (void)showResult
{
    [self stopReading];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *msg = @"";
        
        if (checkEAN13CodeResult) {
            msg = @"PASS";
        }else{
            msg = @"FAIL";
        }
        
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:msg message:nil preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            //[self.navigationController dismissViewControllerAnimated:YES completion:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    _isReading = NO;
                    [self startStopReading];
                });
            //}];
        }]];
        [self presentViewController:ac animated:YES completion:nil];
        
        ac = nil;
    });
}

-(BOOL)checkEAN13Code:(NSString *)strCode
{
    /*EAN13及EAN8檢查碼計算
    EAN13
    例如要算出*471002110526*此筆資料的檢查碼，其計算過程如下:
    (1)	將偶位數值相加乘3 。
    7+0+2+1+5+6=21 , 21*3=63
    (2)	將奇位數值相加。
    4+1+0+1+0+2=8
    (3)	將步驟1.2中所求得的值相加，取其個位數之值。
    63+8=71
    (4)	以10減去步驟3中所求得的值，即為該EAN條碼之檢查碼。
    若步驟3求得的個位數為0， 檢查碼應為0。
    10-1=9........檢查碼
    EAN 8的檢查碼計算方式與EAN13相同。*/
    
    if (strCode.length == 13) {
        int step1 = ([[strCode substringWithRange:NSMakeRange(1, 1)] intValue] + [[strCode substringWithRange:NSMakeRange(3, 1)] intValue] + [[strCode substringWithRange:NSMakeRange(5, 1)] intValue] + [[strCode substringWithRange:NSMakeRange(7, 1)] intValue] + [[strCode substringWithRange:NSMakeRange(9, 1)] intValue] + [[strCode substringWithRange:NSMakeRange(11, 1)] intValue]) * 3;
        
        int step2 = [[strCode substringWithRange:NSMakeRange(0, 1)] intValue] + [[strCode substringWithRange:NSMakeRange(2, 1)] intValue] + [[strCode substringWithRange:NSMakeRange(4, 1)] intValue] +  [[strCode substringWithRange:NSMakeRange(6, 1)] intValue] +  [[strCode substringWithRange:NSMakeRange(8, 1)] intValue] + [[strCode substringWithRange:NSMakeRange(10, 1)] intValue];
        
        int step3 = (step1 + step2) % 10;
        
        int step4 = 10 - step3;
        
        if (step4 == [[strCode substringWithRange:NSMakeRange(12, 1)] intValue]) {
            return YES;
        }else{
            return NO;
        }
    }
    
    return NO;
}

#pragma mark - Utility Methods
- (void)startOverlayHideTimer
{
    // Cancel it if we're already running
    if(_boxHideTimer) {
        [_boxHideTimer invalidate];
    }
    
    // Restart it to hide the overlay when it fires
    _boxHideTimer = [NSTimer scheduledTimerWithTimeInterval:0.2
                                                     target:self
                                                   selector:@selector(removeBoundingBox:)
                                                   userInfo:nil
                                                    repeats:NO];
}

- (void)removeBoundingBox:(id)sender
{
    // Hide the box and remove the decoded text
    _boundingBox.hidden = YES;
}

- (NSArray *)translatePoints:(NSArray *)points fromView:(UIView *)fromView toView:(UIView *)toView
{
    NSMutableArray *translatedPoints = [NSMutableArray new];
    
    // The points are provided in a dictionary with keys X and Y
    for (NSDictionary *point in points) {
        // Let's turn them into CGPoints
        CGPoint pointValue = CGPointMake([point[@"X"] floatValue], [point[@"Y"] floatValue]);
        // Now translate from one view to the other
        CGPoint translatedPoint = [fromView convertPoint:pointValue toView:toView];
        // Box them up and add to the array
        [translatedPoints addObject:[NSValue valueWithCGPoint:translatedPoint]];
    }
    
    return [translatedPoints copy];
}

@end
