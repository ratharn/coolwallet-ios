//
//  CwUtils.m
//  CoolWallet
//
//  Created by 鄭斐文 on 2015/11/11.
//  Copyright © 2015年 MAC-BRYAN. All rights reserved.
//

#import "CwUtils.h"

@implementation CwUtils

+ (NSData*) hexstringToData:(NSString*)hexStr
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

+ (NSString*) dataToHexstring:(NSData*)data
{
    NSString *hexStr = [NSString stringWithFormat:@"%@",data];
    NSRange range = {1,[hexStr length]-2};
    hexStr = [[hexStr substringWithRange:range] stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    return hexStr;
}

@end
