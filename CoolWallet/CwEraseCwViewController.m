//
//  CwEraseCwViewController.m
//  CwTest
//
//  Created by CP Hsiao on 2014/12/16.
//  Copyright (c) 2014年 CP Hsiao. All rights reserved.
//

#import "CwEraseCwViewController.h"
#import "CwInfoViewController.h"
#import "CwManager.h"
#import "CwListTableViewController.h"
#import "CwCommandDefine.h"
#import "CwCardApduError.h"
#import "CwResetInfo.h"

#import <ReactiveCocoa/ReactiveCocoa.h>

@interface CwEraseCwViewController () <CwManagerDelegate, CwCardDelegate, UITextFieldDelegate>
{
    CGFloat _currentMovedUpHeight;
}

@property CwManager *cwManager;

@property (weak, nonatomic) IBOutlet UILabel *resetHintLabel;
@property (weak, nonatomic) IBOutlet UIView *otpConfirmView;
@property (weak, nonatomic) IBOutlet UITextField *otpField;
@property (weak, nonatomic) IBOutlet UIButton *resetBtn;

@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *actBusyIndicator;
- (IBAction)btnEraseCw:(id)sender;
@end

CwCard *cwCard;

@implementation CwEraseCwViewController

- (void)viewDidLoad {
    [super viewDidLoad];
        
    // Do any additional setup after loading the view.
    //find CW via BLE
    self.cwManager = [CwManager sharedManager];
    
    cwCard = self.cwManager.connectedCwCard;
    
    self.actBusyIndicator.hidden = YES;
    
    self.resetHintLabel.hidden = NO;
    self.otpConfirmView.hidden = YES;
    
    @weakify(self)
    [[self.otpField.rac_textSignal filter:^BOOL(NSString *newText) {
        return self.otpField.text.length > 6;
    }] subscribeNext:^(NSString *newText) {
        @strongify(self)
        self.otpField.text = [newText substringToIndex:6];
    }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.cwManager.delegate = self;
    self.cwManager.connectedCwCard.delegate = self;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

//Close the cwCard connection and goback to ListTable
- (void)viewWillDisappear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
    
    long currentVCIndex = [self.navigationController.viewControllers indexOfObject:self.navigationController.topViewController];
    NSObject *listCV = [self.navigationController.viewControllers objectAtIndex:currentVCIndex];
    
    if ([listCV isKindOfClass:[CwInfoViewController class]]) {
        [((CwInfoViewController *)listCV) viewDidLoad];
    }
}

-(void) touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    if (!self.otpConfirmView.isHidden) {
        [self.otpField resignFirstResponder];
    }
}

- (void) startLoading
{
    self.actBusyIndicator.hidden = NO;
    [self.actBusyIndicator startAnimating];
}

- (void) stopLoading
{
    [self.actBusyIndicator stopAnimating];
    self.actBusyIndicator.hidden = YES;
}

-(void) keyboardWillShow:(NSNotification *)notification
{
    NSDictionary *info = [notification userInfo];
    CGSize kbSize = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    CGFloat deltaHeight = kbSize.height - (self.view.frame.size.height - self.otpConfirmView.frame.origin.y - self.otpConfirmView.frame.size.height);
    
    if (deltaHeight <= 0) {
        _currentMovedUpHeight = 0.0f;
        return;
    }
    
    _currentMovedUpHeight = deltaHeight;
    
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.3];
    [UIView setAnimationDelegate:self];
    
    [UIView setAnimationBeginsFromCurrentState:YES];
    
    self.view.frame = CGRectMake(self.view.frame.origin.x,
                                 self.view.frame.origin.y - _currentMovedUpHeight,
                                 self.view.frame.size.width,
                                 self.view.frame.size.height);
    
    [UIView commitAnimations];
}


-(void) keyboardWillHide:(NSNotification *)notification
{
    if (_currentMovedUpHeight <= 0) {
        return;
    }
    
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.3];
    [UIView setAnimationDelegate:self];
    
    [UIView setAnimationBeginsFromCurrentState:YES];
    
    self.view.frame = CGRectMake(self.view.frame.origin.x,
                                 self.view.frame.origin.y + _currentMovedUpHeight,
                                 self.view.frame.size.width,
                                 self.view.frame.size.height);
    
    [UIView commitAnimations];
    
    _currentMovedUpHeight = 0.0f;
}


#pragma marks - UITextFieldDelegate Delegates

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return NO;
}

#pragma marks - Actions

- (IBAction)btnEraseCw:(id)sender {
    [self startLoading];
    
    if (self.otpConfirmView.isHidden) {
        [cwCard getModeState];
    } else {
        [self.cwManager.connectedCwCard verifyResetOtp:self.otpField.text];
    }
}

#pragma marks - CwCard Delegates

-(void) didPrepareService
{
    NSLog(@"didPrepareService");
    //[cwCard getModeState];
}

-(void) didGetModeState
{
    NSLog(@"didGetModeState mode = %@", cwCard.mode);
    if (cwCard.mode.integerValue == CwCardModeNoHost) {
        [self didEraseCw];
    } else {
        [self.cwManager.connectedCwCard getCwCardId];
    }
}

-(void) didGetCwCardId
{
    [self.cwManager.connectedCwCard genResetOtp];
}

-(void) didGenOTPWithError:(NSInteger)errId
{
    if (errId == -1) {
        [self stopLoading];
        
        self.resetHintLabel.hidden = YES;
        self.otpConfirmView.hidden = NO;
        [self.otpField performSelector:@selector(becomeFirstResponder) withObject:nil afterDelay:0];
        
        if (![self.resetBtn.currentTitle isEqualToString:NSLocalizedString(@"Confirm",nil)]) {
            [self.resetBtn setTitle:NSLocalizedString(@"Confirm",nil) forState:UIControlStateNormal];
            RAC(self.resetBtn, enabled) = [self.otpField.rac_textSignal map:^NSNumber *(NSString *text) {
                return @(text.length == 6);
            }];
        }
    } else {
        if (errId == ERR_CMD_NOT_SUPPORT) {
            // old firmware, allow reset directly
            [self.cwManager.connectedCwCard pinChlng];
        } else {
            // TODO: show msg?
            [self stopLoading];
        }
    }
}

-(void) didVerifyOtp
{
    [self.cwManager.connectedCwCard pinChlng];
}

-(void) didVerifyOtpError:(NSInteger)errId
{
    if (errId == ERR_TRX_VERIFY_OTP) {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"OTP Error",nil) message:nil preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            self.otpField.text = @"";
            [self.cwManager.connectedCwCard genResetOtp];
        }];
        [alertController addAction:okAction];
        
        [self presentViewController:alertController animated:YES completion:nil];
    }
}

-(void) didPinChlng
{
    NSLog(@"didPinChlng");
    [cwCard eraseCw:NO Pin:cwCard.cardResetInfo.pinOld NewPin:cwCard.cardResetInfo.pinNew];
}

-(void) didEraseCw {
    cwCard.cardResetInfo.pinOld = @"12345678";
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"CoolWallet has reset",nil) message:nil preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self.cwManager disconnectCwCard];
    }];
    [alertController addAction:okAction];
    
    [self.navigationController presentViewController:alertController animated:YES completion:nil];
    
    NSLog(@"CoolWallet Erased");
}

-(void) didEraseCwError:(NSInteger)errId
{
    [self stopLoading];
    
    cwCard.cardResetInfo.pinOld = @"123456";
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Update",nil) message:NSLocalizedString(@"Please restart CoolWallet and reset again.",nil) preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self.cwManager disconnectCwCard];
    }];
    [alertController addAction:okAction];
    
    [self.navigationController presentViewController:alertController animated:YES completion:nil];
    
    NSLog(@"CoolWallet Erased Fail: %ld", errId);
}

#pragma mark - CwManager Delegate
-(void) didDisconnectCwCard: (NSString *)cardName
{
    NSLog(@"didDisconnectCwCard");
    
    //Add a notification to the system
     UILocalNotification *notify = [[UILocalNotification alloc] init];
     notify.alertBody = [NSString stringWithFormat:NSLocalizedString(@"%@ Disconnected",nil), cardName];
     notify.soundName = UILocalNotificationDefaultSoundName;
     notify.applicationIconBadgeNumber=1;
     [[UIApplication sharedApplication] presentLocalNotificationNow: notify];

     // Get the storyboard named secondStoryBoard from the main bundle:
     UIStoryboard *secondStoryBoard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
     // Load the view controller with the identifier string myTabBar
     // Change UIViewController to the appropriate class
     UIViewController *listCV = (UIViewController *)[secondStoryBoard instantiateViewControllerWithIdentifier:@"CwMain"];
     // Then push the new view controller in the usual way:
     [self.parentViewController presentViewController:listCV animated:YES completion:nil];
}

- (IBAction)BtnCancelAction:(id)sender {
    [self.cwManager disconnectCwCard];
    [self.navigationController popViewControllerAnimated:YES];
}

@end
