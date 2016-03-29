//
//  UIViewController+TabTransactionDetailViewController.m
//  CoolWallet
//
//  Created by bryanLin on 2015/7/8.
//  Copyright (c) 2015年 MAC-BRYAN. All rights reserved.
//

#import "TabTransactionDetailViewController.h"
#import "CwAccount.h"
#import "CwBtcNetWork.h"
#import "CwTx.h"
#import "CwTxin.h"
#import "CwTxout.h"
#import "OCAppCommon.h"
#import "NSDate+Localize.h"
#import "NSString+HexToData.h"

@implementation TabTransactionDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];    
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [self.navigationItem setTitle:@"Transaction details"];
    
    [self SetTxDetailData];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void) SetTxDetailData
{    
    NSString *BTCAmount = [self.tx.historyAmount getBTCDisplayFromUnit];
    if([self.tx.historyAmount.BTC doubleValue] >=0) {
        _lblTxType.text = @"Receive from";
        _lblTxAmount.text = [NSString stringWithFormat: @"+%@", BTCAmount];
        if(self.tx.inputs.count > 0) {
            CwTxin* txin = (CwTxin *)[self.tx.inputs objectAtIndex:0];
            _lblTxAddr.text = txin.addr;
        }
    }else{
        _lblTxType.text = @"Send to";
        _lblTxAmount.text = [NSString stringWithFormat: @"%@", BTCAmount];
        if(self.tx.outputs.count > 0) {
            CwTxout* txout = (CwTxout *)[self.tx.outputs objectAtIndex:0];
            _lblTxAddr.text = txout.addr;
        }
    }
    
    if(self.cwManager.connectedCwCard.currRate != nil) {
        double fiat = [self.tx.historyAmount.BTC doubleValue] * ([self.cwManager.connectedCwCard.currRate doubleValue]/100 );
        _lblTxFiatMoney.text = [NSString stringWithFormat:@"%.2f",fiat];
    }
    
    _lblTxDate.text = [self.tx.historyTime_utc cwDateString];
    _lblTxConfirm.text = [NSString stringWithFormat:@"%@", self.tx.confirmations];
    
    NSString *tid = [NSString dataToHexstring: self.tx.tid];
    _lblTxId.text = tid;
    
}

- (IBAction)btnBlockchain:(id)sender {
    NSString *url = [NSString stringWithFormat:@"https://blockchain.info/tx/%@", _lblTxId.text];
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
}
@end
