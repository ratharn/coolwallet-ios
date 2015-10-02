//
//  CWBTCNetWork.h
//  BCDC
//
//  Created by LIN CHIH-HUNG on 2014/8/22.
//  Copyright (c) 2014年 LIN CHIH-HUNG. All rights reserved.
//
#pragma once

#import <Foundation/Foundation.h>
#import "CwBtcNetworkError.h"
#import "CwTx.h"
#import "CwBtc.h"
#import "CwBtcNetworkDelegate.h"

@interface CwBtcNetWork : NSObject

@property (nonatomic, assign) id<CwBtcNetworkDelegate> delegate;

//used for Singleton
+(id) sharedManager;

- (GetTransactionByAccountErr) getTransactionByAccount: (NSInteger)accId;
- (GetBalanceByAddrErr) getBalanceByAccount: (NSInteger)accId;
- (RegisterNotifyByAddrErr) registerNotifyByAccount: (NSInteger)accId;
- (GetBalanceByAddrErr) getBalanceByAddr: (NSString*)addr balance:(int64_t *)balance;
- (GetAllTxsByAddrErr) getHistoryTxsByAddr: (NSString*)addr txs:(NSMutableArray**)txs;
- (GetUnspentTxsByAddrErr) getUnspentTxsByAddr: (NSString*)addr unspentTxs:(NSMutableArray**)unspentTxs;

- (PublishErr) publish:(CwTx*)tx result:(NSString**)result;
- (DecodeErr) decode:(CwTx*)tx result:(NSString**)result;

- (NSDictionary *) getCurrRate; //key: CurrId, value: rate

@end
