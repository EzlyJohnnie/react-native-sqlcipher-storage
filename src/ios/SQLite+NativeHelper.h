//
//  SQLite+NativeHelper.h
//  SQLite
//
//  Created by Johnnie Cheng on 3/12/18.
//  Copyright © 2018 Andrzej Porebski. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SQLite.h"
#import "SQLiteResult.h"

@interface SQLite (NativeHelper)



+ (SQLiteResult *)performOpenDBWithFilename:(NSString *)filename
                                   location:(NSString *)location
                                     dbname:(NSString *)dbname
                         createFromResource:(NSString *)createFromResource
                                      dbkey:(NSString *)dbkey;

+ (SQLiteResult *)performOpenDBWithFilename:(NSString *)filename
                                   location:(NSString *)location
                                     dbname:(NSString *)dbname
                         createFromResource:(NSString *)createFromResource
                                      dbkey:(NSString *)dbkey
                                    openedDBs:(NSMutableDictionary *)openedDBs;

@end

