//
//  CWBTCNetwork.m
//  iphone_app
//
//  Created by LIN CHIH-HUNG on 2014/10/18.
//  Copyright (c) 2014年 LIN CHIH-HUNG. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CwBtcNetwork.h"
//Used to receive balance change notification from block.io
#import "SRWebSocket.h"
#import "CwManager.h"
#import "CwCard.h"
#import "CwAccount.h"
#import "CwAddress.h"
#import "CwTx.h"
#import "CwTxin.h"
#import "CwTxout.h"
#import "CwUnspentTxIndex.h"
#import "OCAppCommon.h"


static const NSString *serverSite        = @"https://btc.blockr.io/api/v1";
static const NSString *currencyURLStr    = @"exchangerate/current";
static const NSString *decodeURLStr      = @"tx/decode";
static const NSString *pushURLStr        = @"tx/push";
static const NSString *balanceURLStr     = @"address/balance"; //query multiple address with ?confirmations=0
static const NSString *allTxsURLStr      = @"address/txs";     //query address txs, get the txs detail by tx/info
static const NSString *unspentTxsURLStr  = @"address/unspent"; //query unspent, with ?unconfirmed=1
static const NSString *unconfirmTxsURLStr = @"address/unconfirmed"; //query address unconfirmed txs, get the txs detail by tx/info
static const NSString *txInfoURLStr      = @"tx/info";         //query tx infos

@interface CwBtcNetWork ()  <SRWebSocketDelegate>
@end

BOOL didGetTransactionByAccountFlag[5];

@implementation CwBtcNetWork
{
    SRWebSocket *_webSocket;
    CwManager *cwManager;
    CwCard *cwCard;
}

#pragma mark - Singleton methods
+(id) sharedManager {
    static CwBtcNetWork *sharedCwManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{sharedCwManager = [[self alloc] init];});
    return sharedCwManager;
}


- (id) init
{
    self = [super init];
    
    //connect to websocket
    _webSocket.delegate = nil;
    [_webSocket close];
    
    _webSocket = [[SRWebSocket alloc] initWithURLRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"wss://n.block.io/"]]];
    _webSocket.delegate = self;
    
    [_webSocket open];
    
    //prepare cwCard
    cwManager = [CwManager sharedManager];
    
    return self;
}

#pragma mark - SRWebSocketDelegate

- (void)webSocketDidOpen:(SRWebSocket *)webSocket;
{
    //NSLog(@"Websocket Connected");
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error;
{
    NSLog(@":( Websocket Failed With Error %@", error);
    
    _webSocket = nil;
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message;
{
    NSError *_err = nil;
    
    NSLog(@"Websocket Received \"%@\"", message);

    cwCard = cwManager.connectedCwCard;
    
    //Got Balance Update Message
    //Update Address Balance
    //call delegate if others needs it
    //Add a notification to the system
    
    NSDictionary *JSON =[NSJSONSerialization JSONObjectWithData:[message dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&_err];
    NSLog(@"didReceiveMessage: %@", JSON);
    if(_err || ![@"address" isEqualToString:JSON[@"type"]] || !(JSON[@"data"]))
    {
        return;
    }
    else
    {
        /*
         {
            "type": "address",
            "data": {
                "network": "BTC",
                "address": "3cBraN1Q...",
                "balance_change": "0.01000000", // net balance change, can be negative
                "amount_sent": "0.00000000",
                "amount_received": "0.01000000",
                "txid": "7af5cf9f2...", // the transaction's identifier (hash)
                "confirmations": X, // X = {0,1,3} for Bitcoin
                "is_green": false // was the transaction sent by a green address?
            }
         }
         */
        
        NSString *addr = JSON[@"data"][@"address"];

        int64_t balanceChangeNum = (int64_t)([JSON[@"data"][@"balance_change"] doubleValue] * 1e8 + ([JSON[@"data"][@"balance_change"] doubleValue]<0.0? -.5:.5));
        CwBtc *balanceChange = [CwBtc BTCWithSatoshi: [NSNumber numberWithLongLong:balanceChangeNum]];

        int64_t amountReceivedNum = (int64_t)([JSON[@"data"][@"amount_received"] doubleValue] * 1e8 + ([JSON[@"data"][@"amount_received"] doubleValue]<0.0? -.5:.5));
        CwBtc *amountReceived = [CwBtc BTCWithSatoshi: [NSNumber numberWithLongLong:amountReceivedNum]];
        //CwBtc *amountSend = [CwBtc BTCWithBTC:[NSNumber numberWithFloat:[JSON[@"data"][@"amount_sent"] floatValue]]];

        NSNumber *confirmations = JSON[@"data"][@"confirmations"];

        //find addr in accounts
        BOOL foundAddr = NO;
        NSInteger foundAccId = -1;
        NSInteger foundExtInt = 0;
        NSInteger foundAccIndex = -1;
        
        for (int a=0; a<cwCard.cwAccounts.count; a++)
        {
            CwAccount *acc = [cwCard.cwAccounts objectForKey:[NSString stringWithFormat: @"%d", a]];
            
            for (int i=0; i<acc.extKeys.count; i++) {
                CwAddress *add =acc.extKeys[i];
                if ([add.address isEqualToString:addr]) {
                    foundAccId = acc.accId;
                    foundAddr = YES;
                    foundExtInt = 0; //External Key
                    foundAccIndex = i;
                    
                    //update address balance
                    add.balance = add.balance + [balanceChange.satoshi integerValue];
                    acc.extKeys[i]=add;
                    break;
                }
            }
            if (!foundAddr) {
                for (int i=0; i<acc.intKeys.count; i++) {
                    CwAddress *add =acc.intKeys[i];
                    if ([add.address isEqualToString:addr]) {
                        foundAccId = acc.accId;
                        foundAddr = YES;
                        foundExtInt = 1; //Internal Key
                        foundAccIndex = i;
                    
                        //update address balance
                        add.balance = add.balance + [balanceChange.satoshi integerValue];
                        acc.intKeys[i]=add;
                        break;
                    }
                }
            }
            
            if (foundAddr) {
                //update account balance
                acc.balance = acc.balance + [balanceChange.satoshi integerValue];
                [cwCard.cwAccounts setObject:acc forKey:[NSString stringWithFormat: @"%ld", acc.accId]];
                [cwCard setAccount:acc.accId Balance:acc.balance];

                //refresh account transaction
                //Need a better way!
                //[self getTransactionByAccount: acc.accId];
                
                if (foundExtInt == 0) {
                    [self getTransactionByAddress:acc.extKeys[foundAccIndex] wtihAddressType:CwAddressKeyChainExternal fromAccount:acc];
                } else {
                    [self getTransactionByAddress:acc.intKeys[foundAccIndex] wtihAddressType:CwAddressKeyChainInternal fromAccount:acc];
                }
                
                break;
            }
        }
        
        //set notification if receive bitcoin in external address)
        if (foundAddr && balanceChange.satoshi.intValue>0 && foundExtInt==0)
        {
            UILocalNotification *notify = [[UILocalNotification alloc] init];
            notify.userInfo = @{@"title": @"Bitcoin Received"};
            
            if ([amountReceived.satoshi intValue]!=0) {
                notify.alertBody = [NSString stringWithFormat:@"Account %ld\nAddress: %@\nReceived Amount: %@ %@\nConfirmations: %d", foundAccId+1, addr, [amountReceived getBTCDisplayFromUnit], [[OCAppCommon getInstance] BitcoinUnit], confirmations.intValue];
            }
            notify.soundName = UILocalNotificationDefaultSoundName;
            [[UIApplication sharedApplication] presentLocalNotificationNow: notify];
        }
    }
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean;
{
    NSLog(@"WebSocket closed");
    _webSocket = nil;
}

- (void)webSocket:(SRWebSocket *)webSocket didReceivePong:(NSData *)pongPayload;
{
    NSLog(@"Websocket received pong");
}

#pragma mark - Internal Functions

- (NSData*) hexstringToData:(NSString*)hexStr
{
    NSMutableData *data = [[NSMutableData alloc]initWithCapacity:32];
    Byte byte;
    
    for (int i=0; 2*i<[hexStr length]; i++)
    {
        NSRange range = {2*i ,2};
        byte = strtol([[hexStr substringWithRange:range] UTF8String], NULL, 16);
        [data appendBytes:&byte length:1];
        
    }
    return data;
}

- (NSString*) dataToHexstring:(NSData*)data
{
    NSString *hexStr = [NSString stringWithFormat:@"%@",data];
    NSRange range = {1,[hexStr length]-2};
    hexStr = [[hexStr substringWithRange:range] stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    return hexStr;
}

- (NSData*) HTTPRequestUsingGETMethodFrom:(NSString*)urlStr err:(NSError**)_err response:(NSURLResponse**)_response
{
    NSURL *url = [[NSURL alloc]initWithString:urlStr];
    NSMutableURLRequest *httpRequest = [[NSMutableURLRequest alloc]init];
    
    [httpRequest setURL:url];
    [httpRequest setHTTPMethod:@"GET"];
    [httpRequest setHTTPBody:nil];
    
    NSData *data = [NSURLConnection sendSynchronousRequest:httpRequest returningResponse:_response error:_err];
    
    return data;
}

#pragma marks - Functions

- (NSDictionary *) getCurrRate;//key: CurrId, value: rate
{
    GetCurrErr err = GETCURR_BASE;
    
    NSError *_err = nil;
    
    NSString *stringURL = [NSString stringWithFormat:@"%@/%@/",serverSite,currencyURLStr];
    NSURL *url = [NSURL URLWithString:stringURL];
    NSData *data = [NSData dataWithContentsOfURL:url];
    
    if(data)
    {
        NSDictionary *JSON =[NSJSONSerialization JSONObjectWithData:data options:0 error:&_err];
        if(_err || ![@"success" isEqualToString:JSON[@"status"]] || !(JSON[@"data"][0][@"rates"]))
        {
            err = CETCURR_JSON;
        }
        else
        {
            err = GETCURR_BASE;
            NSMutableDictionary *rates = [JSON[@"data"][0][@"rates"] mutableCopy];
            
            //get BTC to USD rate
            NSNumber *btcRate = [rates objectForKey:@"BTC"];
            
            [rates removeObjectForKey:@"BTC"];
            
            [rates enumerateKeysAndObjectsUsingBlock: ^(id currId, id currRate, BOOL *stop) {
                currRate = [NSNumber numberWithFloat: (((NSNumber *)currRate).floatValue/((NSNumber *)btcRate).floatValue)];
                [rates setObject:currRate forKey:currId];
            }];
            
            /*
            for (NSString* currId in rates) {
                NSNumber *currRate = [rates objectForKey:currId];
                
                //calculate the rate against BTC
                currRate =[NSNumber numberWithFloat: (currRate.floatValue/btcRate.floatValue)];

                [rates setObject:currRate forKey:currId];
            }*/
            
            return rates;
        }
    }
    else
    {
        err = GETCURR_NETWORK;
    }
    
    return nil;
}

- (GetTransactionByAccountErr) getTransactionByAccount:(NSInteger)accId
{
    GetTransactionByAccountErr err = GETTRXBYACCT_BASE;
    
    didGetTransactionByAccountFlag[accId] = NO;
    
    NSLog(@"Get Transaction By Account %ld", (long)accId);
    
    cwCard = cwManager.connectedCwCard;

    CwAccount *account = [cwCard.cwAccounts objectForKey:[NSString stringWithFormat: @"%ld", (long)accId]];
    
    account.transactions = [[NSMutableDictionary alloc]init];
    account.unspentTxs = [[NSMutableArray alloc]init];
    
    //get external key transactions
    for (int i=0; i< account.extKeys.count; i++) {
        CwAddress *add =account.extKeys[i];
        
        [self getTransactionByAddress:add wtihAddressType:CwAddressKeyChainExternal fromAccount:account];
        
//        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//            if (add.historyTrx==nil) {
//                //NSLog(@"Get HistoryTxsByAddr: %@", add.address);
//                NSMutableArray *addrTxs;
//                
//                if([self getHistoryTxsByAddr:add.address txs:&addrTxs] != GETALLTXSBYADDR_BASE)
//                {
//                    //err = GETTRXBYACCT_ALLTX;
//                    //break;
//                }
//                else
//                {
//                    //add txs to address
//                    add.historyTrx = addrTxs;
//                    account.extKeys[i] = add;
//                    
//                    //add txs to account
//                    for (CwTx *htx in addrTxs)
//                    {
//                        CwTx *record = [account.transactions objectForKey:htx.tid];
//                        if(record)
//                        {
//                            //update amount
//                            NSLog(@"Update Trx %@ amount %@ with %@", record.tid, record.historyAmount.satoshi,  htx.historyAmount.satoshi);
//                            
//                            record.historyAmount = [record.historyAmount add:htx.historyAmount];
//                            /*
//                             CwTx *txOrg = [account.transactions objectForKey:record.tid];
//                             
//                             txOrg.historyAmount = [txOrg.historyAmount add:record.historyAmount];
//                             */
//                            //update confirmations
//                            [record setConfirmations:[htx confirmations]];
//                            
//                            [account.transactions setObject:record forKey:record.tid];
//                        }
//                        else
//                        {
//                            //add new txs
//                            NSLog(@"Add New Trx %@ with amount %@", htx.tid, htx.historyAmount.satoshi);
//                            [account.transactions setObject:htx forKey:htx.tid];
//                        }
//                    }
//                }
//                //save account back to cwCard
//                [cwCard.cwAccounts setObject:account forKey:[NSString stringWithFormat: @"%ld", (long)accId]];
//            }
//            //check if all addresses of account synced
//            [self isGetTransactionByAccount: accId];
//            
//        });
//        
//        
//        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//            
//            if (add.unspendTrx==nil) {
//                
//                //NSLog(@"Get UnspentTxsByAddr: %@", add.address);
//                NSMutableArray *addrUnspentTxs;
//                if([self getUnspentTxsByAddr:add.address unspentTxs:&addrUnspentTxs]!= GETUNSPENTTXSBYADDR_BASE)
//                {
//                    //err = GETTRXBYACCT_UNSPENTTX;
//                    //break;
//                }
//                else
//                {
//                    //add txs to address
//                    add.unspendTrx = addrUnspentTxs;
//                    account.extKeys[i] = add;
//                    
//                    //add txs to account
//                    for (CwTx *utx in addrUnspentTxs)
//                    {
//                        CwUnspentTxIndex *unspentTxIndex = [[CwUnspentTxIndex alloc]init];
//                        unspentTxIndex.tid = [NSData dataWithData:[utx tid]];
//                        unspentTxIndex.n = [utx unspentN];
//                        unspentTxIndex.amount = [utx unspentAmount];
//                        unspentTxIndex.scriptPub =[utx unspentScriptPub];
//                        unspentTxIndex.kId = [add keyId];
//                        unspentTxIndex.kcId = [add keyChainId];
//                        
//                        [account.unspentTxs addObject:unspentTxIndex];
//                    }
//                }
//                //save account back to cwCard
//                [cwCard.cwAccounts setObject:account forKey:[NSString stringWithFormat: @"%ld", (long)accId]];
//            }
//            //check if all addresses of account synced
//            [self isGetTransactionByAccount: accId];
//            
//        });
    }
    
    //get internal key addresses
    for (int i=0; i< account.intKeys.count; i++) {
        CwAddress *add =account.intKeys[i];
        
        [self getTransactionByAddress:add wtihAddressType:CwAddressKeyChainInternal fromAccount:account];
        
//        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//            
//            if (add.historyTrx==nil) {
//                //NSLog(@"Get HistoryTxsByAddr: %@", add.address);
//                NSMutableArray *addrTxs;
//                
//                if([self getHistoryTxsByAddr:add.address txs:&addrTxs] != GETALLTXSBYADDR_BASE)
//                {
//                    //err = GETTRXBYACCT_ALLTX;
//                    //break;
//                }
//                else
//                {
//                    //add txs to address
//                    add.historyTrx = addrTxs;
//                    account.intKeys[i] = add;
//                    
//                    //add txs to account
//                    for (CwTx *htx in addrTxs)
//                    {
//                        CwTx *record = [account.transactions objectForKey:htx.tid];
//                        if(record)
//                        {
//                            //update amount
//                            NSLog(@"Update Trx %@ amount %@ with %@", record.tid, record.historyAmount.satoshi,  htx.historyAmount.satoshi);
//                            
//                            record.historyAmount = [record.historyAmount add:htx.historyAmount];
//                            /*
//                             CwTx *txOrg = [account.transactions objectForKey:record.tid];
//                             
//                             txOrg.historyAmount = [txOrg.historyAmount add:record.historyAmount];
//                             */
//                            //update confirmations
//                            [record setConfirmations:[htx confirmations]];
//                            
//                            [account.transactions setObject:record forKey:record.tid];
//                        }
//                        else
//                        {
//                            //add new txs
//                            NSLog(@"Add New Trx %@ with amount %@", htx.tid, htx.historyAmount.satoshi);
//                            [account.transactions setObject:htx forKey:htx.tid];
//                        }
//                    }
//                }
//                
//                //save account back to cwCard
//                [cwCard.cwAccounts setObject:account forKey:[NSString stringWithFormat: @"%ld", (long)accId]];
//            }
//            
//            //check if all addresses of account synced
//            [self isGetTransactionByAccount: accId];
//            
//        });
//
//        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//            //NSLog(@"Get UnspentTxsByAddr: %@", add.address);
//            
//            
//            if (add.unspendTrx==nil) {
//                
//                NSMutableArray *addrUnspentTxs;
//                if([self getUnspentTxsByAddr:add.address unspentTxs:&addrUnspentTxs]!= GETUNSPENTTXSBYADDR_BASE)
//                {
//                    //err = GETTRXBYACCT_UNSPENTTX;
//                    //break;
//                }
//                else
//                {
//                    //add txs to address
//                    add.unspendTrx = addrUnspentTxs;
//                    account.intKeys[i] = add;
//                    
//                    //add txs to account
//                    for (CwTx *utx in addrUnspentTxs)
//                    {
//                        CwUnspentTxIndex *unspentTxIndex = [[CwUnspentTxIndex alloc]init];
//                        unspentTxIndex.tid = [NSData dataWithData:[utx tid]];
//                        unspentTxIndex.n = [utx unspentN];
//                        unspentTxIndex.amount = [utx unspentAmount];
//                        unspentTxIndex.scriptPub =[utx unspentScriptPub];
//                        unspentTxIndex.kId = [add keyId];
//                        unspentTxIndex.kcId = [add keyChainId];
//                        
//                        [account.unspentTxs addObject:unspentTxIndex];
//                    }
//                }
//                
//                //save account back to cwCard
//                [cwCard.cwAccounts setObject:account forKey:[NSString stringWithFormat: @"%ld", (long)accId]];
//            }
//            
//            //check if all addresses of account synced
//            [self isGetTransactionByAccount: accId];
//            
//        });
    }

    return err;
}

-(void) getTransactionByAddress:(CwAddress *)addr wtihAddressType:(int)addrType fromAccount:(CwAccount *)account
{
    if (addrType != CwAddressKeyChainExternal && addrType != CwAddressKeyChainInternal) {
        return;
    }
    
    int addrIndex;
    if (addrType == CwAddressKeyChainExternal) {
        addrIndex = (int)[account.extKeys indexOfObject:addr];
    } else {
        addrIndex = (int)[account.intKeys indexOfObject:addr];
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *addrTxs;
        if([self getHistoryTxsByAddr:addr.address txs:&addrTxs] != GETALLTXSBYADDR_BASE)
        {
            //err = GETTRXBYACCT_ALLTX;
            //break;
        }
        else
        {
            for (CwTx *htx in addrTxs)
            {
                CwTx *record = [account.transactions objectForKey:htx.tid];
                if(record)
                {
                    //update amount
                    NSLog(@"Update Trx %@ amount %@ with %@, conifrm: %ld", record.tid, record.historyAmount.satoshi,  htx.historyAmount.satoshi, [htx confirmations]);
                    
                    if (addr.historyTrx == nil) {
                        NSLog(@"1111, record BTC: %ld, satoshi: %lld", record.historyAmount.BTC.longValue, record.historyAmount.satoshi.longLongValue);
                        NSLog(@"1111, htx BTC: %ld, satoshi: %lld", htx.historyAmount.BTC.longValue, htx.historyAmount.satoshi.longLongValue);
                        record.historyAmount = [record.historyAmount add:htx.historyAmount];
                    } else {
                        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF.tid == %@", htx.tid];
                        NSArray *searchResult = [addr.historyTrx filteredArrayUsingPredicate:predicate];
                        if (searchResult.count == 0) {
                            NSLog(@"2222, record BTC: %ld, satoshi: %lld", record.historyAmount.BTC.longValue, record.historyAmount.satoshi.longLongValue);
                            NSLog(@"2222, htx BTC: %ld, satoshi: %lld", htx.historyAmount.BTC.longValue, htx.historyAmount.satoshi.longLongValue);
                            record.historyAmount = [record.historyAmount add:htx.historyAmount];
                        }
                    }
                    
                    //update confirmations
                    [record setConfirmations:[htx confirmations]];
                    
                    [account.transactions setObject:record forKey:record.tid];
                }
                else
                {
                    //add new txs
                    NSLog(@"Add New Trx %@ with amount %@", htx.tid, htx.historyAmount.satoshi);
                    [account.transactions setObject:htx forKey:htx.tid];
                }
            }
            
            addr.historyTrx = addrTxs;
            if (addrType == CwAddressKeyChainExternal) {
                account.extKeys[addrIndex] = addr;
            } else {
                account.intKeys[addrIndex] = addr;
            }
        }
        
        [cwCard.cwAccounts setObject:account forKey:[NSString stringWithFormat: @"%ld", (long)account.accId]];
        
//        if (addr.historyTrx==nil) {
//            //NSLog(@"Get HistoryTxsByAddr: %@", add.address);
//            NSMutableArray *addrTxs;
//            
//            if([self getHistoryTxsByAddr:addr.address txs:&addrTxs] != GETALLTXSBYADDR_BASE)
//            {
//                //err = GETTRXBYACCT_ALLTX;
//                //break;
//            }
//            else
//            {
//                //add txs to address
//                addr.historyTrx = addrTxs;
//                if (addrType == CwAddressKeyChainExternal) {
//                    account.extKeys[addrIndex] = addr;
//                } else {
//                    account.intKeys[addrIndex] = addr;
//                }
//                
//                //add txs to account
//                for (CwTx *htx in addrTxs)
//                {
//                    CwTx *record = [account.transactions objectForKey:htx.tid];
//                    if(record)
//                    {
//                        //update amount
//                        NSLog(@"Update Trx %@ amount %@ with %@, conifrm: %ld", record.tid, record.historyAmount.satoshi,  htx.historyAmount.satoshi, [htx confirmations]);
//                        
////                        record.historyAmount = htx.historyAmount;
//                        record.historyAmount = [record.historyAmount add:htx.historyAmount];
//                        /*
//                         CwTx *txOrg = [account.transactions objectForKey:record.tid];
//                         
//                         txOrg.historyAmount = [txOrg.historyAmount add:record.historyAmount];
//                         */
//                        //update confirmations
//                        [record setConfirmations:[htx confirmations]];
//                        
//                        [account.transactions setObject:record forKey:record.tid];
//                    }
//                    else
//                    {
//                        //add new txs
//                        NSLog(@"Add New Trx %@ with amount %@", htx.tid, htx.historyAmount.satoshi);
//                        [account.transactions setObject:htx forKey:htx.tid];
//                    }
//                }
//            }
//            //save account back to cwCard
//            [cwCard.cwAccounts setObject:account forKey:[NSString stringWithFormat: @"%ld", (long)account.accId]];
//        }
        //check if all addresses of account synced
        [self isGetTransactionByAccount: account.accId];
        
    });
    
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
//        if (addr.unspendTrx==nil) {
        
            //NSLog(@"Get UnspentTxsByAddr: %@", add.address);
            NSMutableArray *addrUnspentTxs;
            if([self getUnspentTxsByAddr:addr.address unspentTxs:&addrUnspentTxs]!= GETUNSPENTTXSBYADDR_BASE)
            {
                //err = GETTRXBYACCT_UNSPENTTX;
                //break;
            }
            else
            {
                //add txs to account
                for (CwTx *utx in addrUnspentTxs)
                {
                    CwUnspentTxIndex *unspentTxIndex = [[CwUnspentTxIndex alloc]init];
                    unspentTxIndex.tid = [NSData dataWithData:[utx tid]];
                    unspentTxIndex.n = [utx unspentN];
                    unspentTxIndex.amount = [utx unspentAmount];
                    unspentTxIndex.scriptPub =[utx unspentScriptPub];
                    unspentTxIndex.kId = [addr keyId];
                    unspentTxIndex.kcId = [addr keyChainId];
                    
                    if (addr.unspendTrx == nil) {
                        NSLog(@"Add unspentTxs to account %ld", account.accId);
                        [account.unspentTxs addObject:unspentTxIndex];
                    } else {
                        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF.tid == %@", unspentTxIndex.tid];
                        NSArray *searchResult = [addr.unspendTrx filteredArrayUsingPredicate:predicate];
                        if (searchResult == 0) {
                            NSLog(@"not matched. Add unspentTxs to account %ld", account.accId);
                            [account.unspentTxs addObject:unspentTxIndex];
                        }
                    }
                }
                
                //add txs to address
                addr.unspendTrx = addrUnspentTxs;
                if (addrType == CwAddressKeyChainExternal) {
                    account.extKeys[addrIndex] = addr;
                } else {
                    account.intKeys[addrIndex] = addr;
                }
            }
            //save account back to cwCard
            [cwCard.cwAccounts setObject:account forKey:[NSString stringWithFormat: @"%ld", (long)account.accId]];
//        }
        //check if all addresses of account synced
        [self isGetTransactionByAccount: account.accId];
        
    });
    
}

- (void) isGetTransactionByAccount: (NSInteger) accId
{
    CwAccount *account = [cwCard.cwAccounts objectForKey:[NSString stringWithFormat: @"%ld", (long)accId]];
    BOOL isGetTrx = YES;
    
    //get external key transactions
    for (int i=0; i< account.extKeys.count; i++) {
        CwAddress *add =account.extKeys[i];
        if (add.historyTrx==nil || add.unspendTrx==nil) {
            isGetTrx=NO;
            break;
        }
    }

    if (isGetTrx) {
        //get int key transactions
        for (int i=0; i< account.intKeys.count; i++) {
            CwAddress *add =account.intKeys[i];
            if (add.historyTrx==nil || add.unspendTrx==nil) {
                isGetTrx=NO;
                break;
            }
        }
    }
    
    if (isGetTrx && !didGetTransactionByAccountFlag[accId]) {
        //Call Delegate
        if ([self.delegate respondsToSelector:@selector(didGetTransactionByAccount:)]) {
            [self.delegate didGetTransactionByAccount:accId];
        }
        didGetTransactionByAccountFlag[accId] = YES;
    }
    
    return;
}

- (RegisterNotifyByAddrErr) registerNotifyByAccount: (NSInteger)accId
{
    RegisterNotifyByAddrErr err = REGNOTIFYBYADDR_BASE;
    
    cwCard = cwManager.connectedCwCard;
    
    CwAccount *account = [cwCard.cwAccounts objectForKey:[NSString stringWithFormat: @"%ld", (long)accId]];
    
    //add addresses to query string
    for (int i=0; i< account.extKeys.count; i++) {
        CwAddress *add =account.extKeys[i];
        if (add.registerNotification) continue;
        
        //register a notification of the address when balance change
        NSString *msg = [NSString stringWithFormat:@"{\"network\": \"BTC\",\"type\": \"address\",\"address\": \"%@\"}", add.address];
        NSLog(@"WebNotify: %@", msg);
        [_webSocket send:msg];
        
        add.registerNotification = YES;
    }
    for (int i=0; i< account.intKeys.count; i++) {
        CwAddress *add =account.intKeys[i];
        if (add.registerNotification) continue;
        
        //register a notification of the address when balance change
        NSString *msg = [NSString stringWithFormat:@"{\"network\": \"BTC\",\"type\": \"address\",\"address\": \"%@\"}", add.address];
        NSLog(@"WebNotify: %@", msg);
        [_webSocket send:msg];
        
        add.registerNotification = YES;
    }
    
    return err;
}

- (GetBalanceByAddrErr) getBalanceByAccount:(NSInteger) accId
{
    GetBalanceByAddrErr err = GETBALANCEBYADDR_BASE;
    NSMutableArray *addrs = [[NSMutableArray alloc] init];
    
    cwCard = cwManager.connectedCwCard;
    
    NSError *_err = nil;
    
    NSLog(@"GetBalanceByAccount: %ld", (long)accId);
    
    CwAccount *account = [cwCard.cwAccounts objectForKey:[NSString stringWithFormat: @"%ld", (long)accId]];
    
    //add addresses to query string
    for (int i=0; i< account.extKeys.count; i++) {
        CwAddress *add =account.extKeys[i];
        [addrs addObject:add];
    }
    for (int i=0; i< account.intKeys.count; i++) {
        CwAddress *add =account.intKeys[i];
        [addrs addObject:add];
    }
    
    account.balance = 0;

    while (addrs.count>0) {
        NSInteger num=0;
        if (addrs.count>20)
            num=20;
        else
            num=addrs.count;
        
        NSString *stringURL = [NSString stringWithFormat:@"%@/%@/",serverSite,balanceURLStr];

        //create stringURL
        for (int i=0; i<num; i++) {
            CwAddress *add = [addrs objectAtIndex:num-i-1];
            [addrs removeObjectAtIndex:num-i-1];
            stringURL = [stringURL stringByAppendingString: add.address];
            stringURL = [stringURL stringByAppendingString:@","];
        }
        //remove the last , and add "?confirmations=0"
        stringURL = [stringURL substringToIndex:stringURL.length-1];
        stringURL = [stringURL stringByAppendingString:@"?confirmations=0"];
    
        NSURL *url = [NSURL URLWithString:stringURL];
        NSData *data = [NSData dataWithContentsOfURL:url];

        if(data)
        {
            NSDictionary *JSON =[NSJSONSerialization JSONObjectWithData:data options:0 error:&_err];
            if(_err || ![@"success" isEqualToString:JSON[@"status"]] || !(JSON[@"data"]))
            {
                err = GETBALANCEBYADDR_JSON;
            }
            else
            {
                id jsonObject = [JSON valueForKey:@"data"];

                if ([jsonObject isKindOfClass:[NSArray class]]) {
                    NSArray *jsonArray = (NSArray *)jsonObject;
                    //NSLog(@"its an array!");
                    //NSLog(@"jsonArray - %@",jsonArray);
                
                    for (NSDictionary *addBalance in jsonArray) {
                        //update the balance of each address
                        NSNumber *bal = [addBalance valueForKey:@"balance"];
                        int64_t balance = (int64_t)([bal doubleValue] * 1e8 + ([bal doubleValue] < 0.0 ? -.5 : .5));
                    
                        //might be external address
                        for (int i=0; i< account.extKeys.count; i++) {
                            CwAddress *add =account.extKeys[i];
                            if ([add.address isEqualToString:[addBalance valueForKey: @"address"]]) {
                                add.balance = balance;
                                account.extKeys[i]=add;
                                //shouldn't have other address matches
                                NSLog(@"     QueryAccountBalance: %@ balance: %lld", add.address, add.balance);
                            
                                break;
                            }
                        }
                    
                        for (int i=0; i< account.intKeys.count; i++) {
                            CwAddress *add =account.intKeys[i];
                            if ([add.address isEqualToString:[addBalance valueForKey: @"address"]]) {
                                add.balance = balance;
                                account.intKeys[i]=add;
                                //shouldn't have other address matches
                                NSLog(@"     QueryAccountBalance: %@ balance: %lld", add.address, add.balance);
                            
                                break;
                            }
                        }
                    
                        //update account balance
                        account.balance += balance;
                    }
                
                } else {
                    NSDictionary *jsonDictionary = (NSDictionary *)jsonObject;
                    //NSLog(@"its probably a dictionary");
                    //NSLog(@"jsonDictionary - %@",jsonDictionary);

                
                    //update the balance of each address
                    NSNumber *bal = [jsonDictionary valueForKey:@"balance"];
                    int64_t balance = (int64_t)([bal doubleValue] * 1e8 + ([bal doubleValue] < 0.0 ? -.5 : .5));

                
                    //might be external address
                    for (int i=0; i< account.extKeys.count; i++) {
                        CwAddress *add =account.extKeys[i];
                        if ([add.address isEqualToString:[jsonDictionary valueForKey: @"address"]]) {
                            add.balance = balance;
                            account.extKeys[i]=add;
                            //shouldn't have other address matches
                            NSLog(@"     QueryAccountBalance: %@ balance: %lld", add.address, add.balance);
                        
                            break;
                        }
                    }
                
                    for (int i=0; i< account.intKeys.count; i++) {
                        CwAddress *add =account.intKeys[i];
                        if ([add.address isEqualToString:[jsonDictionary valueForKey: @"address"]]) {
                            add.balance = balance;
                            account.intKeys[i]=add;
                            //shouldn't have other address matches
                            NSLog(@"     QueryAccountBalance: %@ balance: %lld", add.address, add.balance);
                        
                            break;
                        }
                    }
                
                    //update account balance
                    account.balance += balance;
                }
            }
        }
        else
        {
            err = GETBALANCEBYADDR_NETWORK;
            return err;
        }
    }
    
    [cwCard.cwAccounts setObject:account forKey:[NSString stringWithFormat: @"%ld", accId]];
    err = GETBALANCEBYADDR_BASE;
    
    return err;
}

- (GetBalanceByAddrErr) getBalanceByAddr:(NSString*)addr balance:(int64_t *)balance
{
    GetBalanceByAddrErr err = GETBALANCEBYADDR_BASE;
    
    NSError *_err = nil;
    
    NSString *stringURL = [NSString stringWithFormat:@"%@/%@/%@?confirmations=0",serverSite,balanceURLStr,addr];
    NSURL *url = [NSURL URLWithString:stringURL];
    NSData *data = [NSData dataWithContentsOfURL:url];
    
    NSLog(@"Get Balance by Address %@", addr);
    
    if(data)
    {
        NSDictionary *JSON =[NSJSONSerialization JSONObjectWithData:data options:0 error:&_err];
        if(_err || ![@"success" isEqualToString:JSON[@"status"]] || !(JSON[@"data"] && JSON[@"data"][@"balance"]))
        {
            err = GETBALANCEBYADDR_JSON;
        }
        else
        {
            NSNumber *bal = JSON[@"data"][@"balance"];
            *balance = (int64_t)([bal doubleValue] * 1e8 + ([bal doubleValue] < 0.0 ? -.5 : .5));
            NSLog(@"    Balance: %lld", *balance);
            err = GETBALANCEBYADDR_BASE;
        }
        
        //register a notification of the address when balance change
        NSString *msg = [NSString stringWithFormat:@"{\"network\": \"BTC\",\"type\": \"address\",\"address\": \"%@\"}", addr];
        [_webSocket send:msg];
        
    }
    else
    {
        err = GETBALANCEBYADDR_NETWORK;
    }

    return err;
}

- (GetAllTxsByAddrErr) getHistoryTxsByAddr:(NSString*)addr txs:(NSMutableArray**)txs
{
    NSError *_err = nil;
    GetAllTxsByAddrErr err = GETALLTXSBYADDR_BASE;
    NSURLResponse *_response = nil;
    NSData *data = [self HTTPRequestUsingGETMethodFrom:[NSString stringWithFormat:@"%@/%@/%@",serverSite,allTxsURLStr,addr] err:&_err response:&_response];
    NSMutableArray* _txs = [[NSMutableArray alloc] init];

    NSLog(@"Get HistoryTxs by Address %@", addr);
    
    if(_err)
    {
        err = GETALLTXSBYADDR_NETWORK;
    }
    else
    {
        NSDictionary *JSON =[NSJSONSerialization JSONObjectWithData:data options:0 error:&_err];
        if(!(!_err && [@"success" isEqualToString:JSON[@"status"]] && JSON[@"data"] && JSON[@"data"][@"txs"]))
        {
            err = GETALLTXSBYADDR_JSON;
        }
        else
        {
            NSArray* rawTxs = JSON[@"data"][@"txs"];
            
            for (NSDictionary *rawTx in rawTxs)
            {

                int64_t amountNum = (int64_t)([rawTx[@"amount"] doubleValue] * 1e8 + ([rawTx[@"amount"] doubleValue]<0.0? -.5:.5));
                CwBtc* amount = [CwBtc BTCWithSatoshi: [NSNumber numberWithLongLong:amountNum]];
                
                NSData* tid = [self hexstringToData:rawTx[@"tx"]];
                NSDateFormatter *dateformat = [[NSDateFormatter alloc]init];
                [dateformat setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"];
                
                CwTx *tx = [[CwTx alloc] init];
                tx.txType = TypeHistoryTx;
                tx.tid = tid;
                tx.historyTime_utc = [dateformat dateFromString:rawTx[@"time_utc"]];
                tx.historyAmount = amount;
                tx.confirmations = [rawTx[@"confirmations"] unsignedIntegerValue];
                tx.inputs = [[NSMutableArray alloc] init];
                tx.outputs = [[NSMutableArray alloc] init];
                
                //get trxdetails
                data = [self HTTPRequestUsingGETMethodFrom:[NSString stringWithFormat:@"%@/%@/%@",serverSite,txInfoURLStr,[self dataToHexstring:tid]] err:&_err response:&_response];
                
                if (_err)
                {
                    err = GETALLTXSBYADDR_NETWORK;
                    break;
                }
                else
                {
                    NSDictionary *txDetail=[NSJSONSerialization JSONObjectWithData:data options:0 error:&_err];
                    if(!(!_err && [@"success" isEqualToString:JSON[@"status"]] && JSON[@"data"]))
                    {
                        err = GETALLTXSBYADDR_JSON;
                        break;
                    }
                    else
                    {
                        NSArray *txIns = txDetail[@"data"][@"vins"];
                        NSArray *txOuts = txDetail[@"data"][@"vouts"];
                        
                        for (NSDictionary *txIn in txIns)
                        {
                            NSString *address = txIn[@"address"];
                            int64_t amountNum = (int64_t)([txIn[@"amount"] doubleValue] * 1e8 + ([txIn[@"amount"] doubleValue]<0.0? -.5:.5));
                            CwBtc* amount = [CwBtc BTCWithSatoshi: [NSNumber numberWithLongLong:amountNum]];
                            NSInteger n = [txIn[@"n"] integerValue];
                            NSData* tid = [self hexstringToData:txIn[@"vout_tx"]];
                            
                            CwTxin *txin = [[CwTxin alloc] init];
                            txin.tid = tid;
                            txin.addr = address;
                            txin.n = n;
                            txin.amount = amount;
                            
                            [tx.inputs addObject:txin];
                        }
                        
                        for (NSDictionary *txOut in txOuts)
                        {
                            NSString *address = txOut[@"address"];
                            int64_t amountNum = (int64_t)([txOut[@"amount"] doubleValue] * 1e8 + ([txOut[@"amount"] doubleValue]<0.0? -.5:.5));
                            CwBtc* amount = [CwBtc BTCWithSatoshi: [NSNumber numberWithLongLong:amountNum]];
                            
                            NSInteger n = [txOut[@"n"] integerValue];
                            BOOL isSpent = [txOut[@"is_spent"] boolValue];
                            
                            CwTxout *txout = [[CwTxout alloc] init];
                            txout.addr = address;
                            txout.amount = amount;
                            txout.n = n;
                            txout.isSpent = isSpent;
                            
                            [tx.outputs addObject:txout];
                        }
                    }
                }
                
                [_txs addObject:tx];
                NSLog(@"    tid:%@ amount:%@", tid, amount.satoshi);
            }
        }
    }
    
    if (err != GETALLTXSBYADDR_BASE)
        return err;
    
    //get unconfirmed
    data = [self HTTPRequestUsingGETMethodFrom:[NSString stringWithFormat:@"%@/%@/%@",serverSite,unconfirmTxsURLStr,addr] err:&_err response:&_response];
    
    NSLog(@"Get UnconfirmTxs by Address %@", addr);
    
    if(_err)
    {
        err = GETALLTXSBYADDR_NETWORK;
    }
    else
    {
        NSDictionary *JSON =[NSJSONSerialization JSONObjectWithData:data options:0 error:&_err];
        if(!(!_err && [@"success" isEqualToString:JSON[@"status"]] && JSON[@"data"] && JSON[@"data"][@"unconfirmed"]))
        {
            err = GETALLTXSBYADDR_JSON;
        }
        else
        {
            NSArray* rawTxs = JSON[@"data"][@"unconfirmed"];
            
            for (NSDictionary *rawTx in rawTxs)
            {
                int64_t amountNum = (int64_t)([rawTx[@"amount"] doubleValue] * 1e8 + ([rawTx[@"amount"] doubleValue]<0.0? -.5:.5));
                CwBtc* amount = [CwBtc BTCWithSatoshi: [NSNumber numberWithLongLong:amountNum]];
                
                NSData* tid = [self hexstringToData:rawTx[@"tx"]];
                NSDateFormatter *dateformat = [[NSDateFormatter alloc]init];
                [dateformat setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"];
                
                CwTx *tx = [[CwTx alloc] init];
                tx.txType = TypeHistoryTx;
                tx.tid = tid;
                tx.historyTime_utc = [dateformat dateFromString:rawTx[@"time_utc"]];
                tx.historyAmount = amount;
                tx.confirmations = 0;
                tx.inputs = [[NSMutableArray alloc] init];
                tx.outputs = [[NSMutableArray alloc] init];
                
                //get trxdetails
                data = [self HTTPRequestUsingGETMethodFrom:[NSString stringWithFormat:@"%@/%@/%@",serverSite,txInfoURLStr,[self dataToHexstring:tid]] err:&_err response:&_response];
                
                if (_err)
                {
                    err = GETALLTXSBYADDR_NETWORK;
                    break;
                }
                else
                {
                    NSDictionary *txDetail=[NSJSONSerialization JSONObjectWithData:data options:0 error:&_err];
                    if(!(!_err && [@"success" isEqualToString:JSON[@"status"]] && JSON[@"data"]))
                    {
                        err = GETALLTXSBYADDR_JSON;
                        break;
                    }
                    else
                    {
                        NSArray *txIns = txDetail[@"data"][@"vins"];
                        NSArray *txOuts = txDetail[@"data"][@"vouts"];
                        
                        for (NSDictionary *txIn in txIns)
                        {
                            NSString *address = txIn[@"address"];

                            int64_t amountNum = (int64_t)([txIn[@"amount"] doubleValue] * 1e8 + ([txIn[@"amount"] doubleValue]<0.0? -.5:.5));
                            CwBtc* amount = [CwBtc BTCWithSatoshi: [NSNumber numberWithLongLong:amountNum]];
                            
                            NSInteger n = [txIn[@"n"] integerValue];
                            NSData* tid = [self hexstringToData:txIn[@"vout_tx"]];
                            
                            CwTxin *txin = [[CwTxin alloc] init];
                            txin.tid = tid;
                            txin.addr = address;
                            txin.n = n;
                            txin.amount = amount;
                            
                            [tx.inputs addObject:txin];
                        }
                        
                        for (NSDictionary *txOut in txOuts)
                        {
                            NSString *address = txOut[@"address"];
                            
                            int64_t amountNum = (int64_t)([txOut[@"amount"] doubleValue] * 1e8 + ([txOut[@"amount"] doubleValue]<0.0? -.5:.5));
                            CwBtc* amount = [CwBtc BTCWithSatoshi: [NSNumber numberWithLongLong:amountNum]];
                            
                            NSInteger n = [txOut[@"n"] integerValue];
                            BOOL isSpent = [txOut[@"is_spent"] boolValue];
                            
                            CwTxout *txout = [[CwTxout alloc] init];
                            txout.addr = address;
                            txout.amount = amount;
                            txout.n = n;
                            txout.isSpent = isSpent;
                            
                            [tx.outputs addObject:txout];
                        }
                    }
                }

                [_txs addObject:tx];
                NSLog(@"    tid:%@ amount:%@", tid, amount.satoshi);
            }
        }
    }
    
    if (err==GETALLTXSBYADDR_BASE) {
        *txs = _txs;

    }
    return err;
    
}

- (GetUnspentTxsByAddrErr) getUnspentTxsByAddr:(NSString*)addr unspentTxs:(NSMutableArray**)unspentTxs
{
    GetUnspentTxsByAddrErr err = GETUNSPENTTXSBYADDR_BASE;
    NSError *_err;
    NSURLResponse *_response = nil;
    NSData *data = [self HTTPRequestUsingGETMethodFrom:[NSString stringWithFormat:@"%@/%@/%@?unconfirmed=1",serverSite,unspentTxsURLStr,addr] err:&_err response:&_response];
    
    
    NSLog(@"Get UnspentTxs by Address %@", addr);
    
    if(_err)
    {
        err = GETUNSPENTTXSBYADDR_NETWORK;
    }
    else
    {
        NSDictionary *JSON =[NSJSONSerialization JSONObjectWithData:data options:0 error:&_err];
        if(!(!_err && [@"success" isEqualToString:JSON[@"status"]] && JSON[@"data"] && JSON[@"data"][@"unspent"]))
        {
            
            err = GETUNSPENTTXSBYADDR_JSON;
        }
        else
        {
            NSArray* rawUnspentTxs = JSON[@"data"][@"unspent"];
            NSMutableArray *_unspentTxs = [[NSMutableArray alloc] initWithCapacity:[rawUnspentTxs count]];
            
            for (NSDictionary *rawUnspentTx in rawUnspentTxs)
            {

                int64_t amountNum = (int64_t)([rawUnspentTx[@"amount"] doubleValue] * 1e8 + ([rawUnspentTx[@"amount"] doubleValue]<0.0? -.5:.5));
                CwBtc* amount = [CwBtc BTCWithSatoshi: [NSNumber numberWithLongLong:amountNum]];
                
                NSData* tid = [self hexstringToData:rawUnspentTx[@"tx"]];
                NSData* scriptPub = [self hexstringToData:rawUnspentTx[@"script"]];
                NSUInteger n = [rawUnspentTx[@"n"] unsignedIntegerValue];
                
                
                CwTx *unspentTx = [[CwTx alloc] init ];
                unspentTx.txType = TypeUnspentTx;
                unspentTx.unspentAddr = addr;
                unspentTx.unspentAmount = amount;
                unspentTx.tid = tid;
                unspentTx.unspentScriptPub = scriptPub;
                unspentTx.unspentN = n;
                
                [_unspentTxs addObject:unspentTx];
                NSLog(@"    tid:%@ n:%lu amount:%@", tid, (unsigned long)n, amount.satoshi);
            }
            *unspentTxs = _unspentTxs;
        }
    }
    
    return err;
}

- (PublishErr) publish:(CwTx*)tx result:(NSData **)result
{
    NSURL *connection = [[NSURL alloc]initWithString:@"https://btc.blockr.io/api/v1/tx/push"];
    NSString *postString = [NSString stringWithFormat:@"{\"hex\":\"%@\"}",[self dataToHexstring:[tx rawTx]]];
    NSMutableURLRequest *httpRequest = [[NSMutableURLRequest alloc]init];
    
    NSLog(@"tx raw: %@", postString);
    
    [httpRequest setURL:connection];
    [httpRequest setHTTPMethod:@"POST"];
    [httpRequest setHTTPBody:[postString dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSData *decodeTxJSON = [NSURLConnection sendSynchronousRequest:httpRequest returningResponse:nil error:nil];
    
    *result = [[NSData alloc] initWithData: decodeTxJSON];
    
    return PUBLISH_BASE;
}

- (GetCurrErr) getCurrency:(NSNumber**)currency
{
    // TODO ...
    return GETCURR_BASE;
}

- (DecodeErr) decode:(CwTx*)tx result:(NSData **)result
{
    NSURL *connection = [[NSURL alloc]initWithString:@"https://btc.blockr.io/api/v1/tx/decode"];
    NSString *postString = [NSString stringWithFormat:@"{\"hex\":\"%@\"}",[self dataToHexstring:[tx rawTx]]];
    NSMutableURLRequest *httpRequest = [[NSMutableURLRequest alloc]init];
    
    NSLog(@"tx raw: %@", postString);
    
    [httpRequest setURL:connection];
    [httpRequest setHTTPMethod:@"POST"];
    [httpRequest setHTTPBody:[postString dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSData *decodeTxJSON = [NSURLConnection sendSynchronousRequest:httpRequest returningResponse:nil error:nil];
    
    *result = [[NSData alloc] initWithData: decodeTxJSON];
    
    return DECODE_BASE;
}

@end