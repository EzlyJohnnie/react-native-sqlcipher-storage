/*
 * SQLite.m
 *
 * Created by Andrzej Porebski on 10/29/15.
 * Copyright (c) 2015 Andrzej Porebski.
 *
 * This software is largely based on the SQLLite Storage Cordova Plugin created by Chris Brody & Davide Bertola.
 * The implementation was adopted and converted to use React Native bindings.
 *
 * See https://github.com/litehelpers/Cordova-sqlite-storage
 *
 * This library is available under the terms of the MIT License (2008).
 * See http://opensource.org/licenses/alphabetical for full text.
 */

#import <Foundation/Foundation.h>

#import "SQLite.h"
#import "SQLiteResult.h"
#import "SQLite+NativeHelper.h"

#import <React/RCTLog.h>
#import <React/RCTUtils.h>
#import <React/RCTBridge.h>
#import <React/RCTEventDispatcher.h>

/*
 * Copyright (C) 2012-2015 Chris Brody
 * Copyright (C) 2011 Davide Bertola
 *
 * This library is available under the terms of the MIT License (2008).
 * See http://opensource.org/licenses/alphabetical for full text.
 */

#import "sqlite3.h"

#include <regex.h>

@implementation SQLite

RCT_EXPORT_MODULE();

@synthesize openDBs;
@synthesize appDBPaths;

- (id) init
{
  NSLog(@"Initializing SQLitePlugin");
  self = [super init];
  if (self) {
    openDBs = [NSMutableDictionary dictionaryWithCapacity:0];
    appDBPaths = [NSMutableDictionary dictionaryWithCapacity:0];
#if !__has_feature(objc_arc)
    [openDBs retain];
    [appDBPaths retain];
#endif
    
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex: 0];
    NSLog(@"Detected docs path: %@", docs);
    [appDBPaths setObject: docs forKey:@"docs"];
    
    NSString *libs = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex: 0];
    NSLog(@"Detected Library path: %@", libs);
    [appDBPaths setObject: libs forKey:@"libs"];
    
    NSString *nosync = [libs stringByAppendingPathComponent:@"LocalDatabase"];
    NSError *err;
    if ([[NSFileManager defaultManager] fileExistsAtPath: nosync])
    {
      NSLog(@"no cloud sync at path: %@", nosync);
      [appDBPaths setObject: nosync forKey:@"nosync"];
    }
    else
    {
      if ([[NSFileManager defaultManager] createDirectoryAtPath: nosync withIntermediateDirectories:NO attributes: nil error:&err])
      {
        NSURL *nosyncURL = [ NSURL fileURLWithPath: nosync];
        if (![nosyncURL setResourceValue: [NSNumber numberWithBool: YES] forKey: NSURLIsExcludedFromBackupKey error: &err])
        {
          NSLog(@"IGNORED: error setting nobackup flag in LocalDatabase directory: %@", err);
        }
        NSLog(@"no cloud sync at path: %@", nosync);
        [appDBPaths setObject: nosync forKey:@"nosync"];
      }
      else
      {
        // fallback:
        NSLog(@"WARNING: error adding LocalDatabase directory: %@", err);
        [appDBPaths setObject: libs forKey:@"nosync"];
      }
    }
  }
  return self;
}

- (void)runInBackground:(void (^)())block
{
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), block);
}

-(id) getDBPath:(NSString *)dbFile at:(NSString *)atkey {
  if (dbFile == NULL) {
    return NULL;
  }
  
  NSString *dbdir = [appDBPaths objectForKey:atkey];
  //NSString *dbPath = [NSString stringWithFormat:@"%@/%@", dbdir, dbFile];
  NSString *dbPath = [dbdir stringByAppendingPathComponent: dbFile];
  return dbPath;
}

RCT_EXPORT_METHOD(open: (NSDictionary *) options success:(RCTResponseSenderBlock)success error:(RCTResponseSenderBlock)error)
{
  NSString *dbfilename = [options objectForKey:@"name"];
  NSString *dblocation = [options objectForKey:@"dblocation"];
  NSString *createFromResource = [options objectForKey:@"createFromResource"];
  NSString *dbkey = [options objectForKey:@"key"];
  NSString *dbname = [self getDBPath:dbfilename at:dblocation];
  
  SQLiteResult* pluginResult = [SQLite performOpenDBWithFilename:dbfilename
                                                        location:dblocation
                                                          dbname:dbname
                                              createFromResource:createFromResource
                                                           dbkey:dbkey
                                                       openedDBs:openDBs];
  
  [pluginResult.status intValue] == SQLiteStatus_OK ? success(@[pluginResult.message]) : error(@[pluginResult.message]);
}

RCT_EXPORT_METHOD(close: (NSDictionary *) options success:(RCTResponseSenderBlock)success error:(RCTResponseSenderBlock)error)
{
  SQLiteResult* pluginResult = nil;
  
  NSString *dbFileName = [options objectForKey:@"path"];
  
  if (dbFileName == NULL) {
    // Should not happen:
    NSLog(@"No db name specified for close");
    pluginResult = [SQLiteResult resultWithStatus:SQLiteStatus_ERROR messageAsString:@"You must specify database path"];
  } else {
    NSValue *val = [openDBs objectForKey:dbFileName];
    sqlite3 *db = [val pointerValue];
    NSString *dbPath = [self getDBPath:dbFileName at:@"docs"];
    
    if ([[NSFileManager defaultManager]fileExistsAtPath:dbPath]) {
      NSLog(@"database still exists");
    }
    if (db == NULL) {
      // Should not happen:
      NSLog(@"close: db name was not open: %@", dbFileName);
      pluginResult = [SQLiteResult resultWithStatus:SQLiteStatus_ERROR messageAsString:@"Specified db was not open"];
    }
    else {
      NSLog(@"close db name: %@", dbFileName);
      
      sqlite3_close (db);
      [openDBs removeObjectForKey:dbFileName];
      pluginResult = [SQLiteResult resultWithStatus:SQLiteStatus_OK messageAsString:@"DB closed"];
    }
    if ([[NSFileManager defaultManager]fileExistsAtPath:dbPath]) {
      NSLog(@"database file still exists after close");
    } else {
      NSLog(@"database file doesn't exists after close");
    }
    
  }
  
  [pluginResult.status intValue] == SQLiteStatus_OK ? success(@[pluginResult.message]) : error(@[pluginResult.message]);
}

RCT_EXPORT_METHOD(delete: (NSDictionary *) options success:(RCTResponseSenderBlock)success error:(RCTResponseSenderBlock)error)
{
  SQLiteResult* pluginResult = nil;
  NSString *dbFileName = [options objectForKey:@"path"];
  NSString *dblocation = [options objectForKey:@"dblocation"];
  if (dblocation == NULL) dblocation = @"docs";
  
  if (dbFileName==NULL) {
    // Should not happen:
    NSLog(@"No db name specified for delete");
    pluginResult = [SQLiteResult resultWithStatus:SQLiteStatus_ERROR messageAsString:@"You must specify database path"];
  } else {
    NSString *dbPath = [self getDBPath:dbFileName at:dblocation];
    
    if ([[NSFileManager defaultManager]fileExistsAtPath:dbPath]) {
      NSLog(@"delete full db path: %@", dbPath);
      [[NSFileManager defaultManager]removeItemAtPath:dbPath error:nil];
      [openDBs removeObjectForKey:dbFileName];
      pluginResult = [SQLiteResult resultWithStatus:SQLiteStatus_OK messageAsString:@"DB deleted"];
    } else {
      NSLog(@"delete: db was not found: %@", dbPath);
      pluginResult = [SQLiteResult resultWithStatus:SQLiteStatus_ERROR messageAsString:@"The database does not exist on that path"];
    }
  }
  
  [pluginResult.status intValue] == SQLiteStatus_OK ? success(@[pluginResult.message]) : error(@[pluginResult.message]);
}


RCT_EXPORT_METHOD(backgroundExecuteSqlBatch: (NSDictionary *) options success:(RCTResponseSenderBlock)success error:(RCTResponseSenderBlock)error)
{
  [self runInBackground:^{
    [self executeSqlBatch: options success:success error:error];
  }];
}

RCT_EXPORT_METHOD(executeSqlBatch: (NSDictionary *) options success:(RCTResponseSenderBlock)success error:(RCTResponseSenderBlock)error)
{
  NSMutableArray *results = [NSMutableArray arrayWithCapacity:0];
  NSMutableDictionary *dbargs = [options objectForKey:@"dbargs"];
  NSMutableArray *executes = [options objectForKey:@"executes"];
  
  SQLiteResult *pluginResult;
  
  @synchronized(self) {
    for (NSMutableDictionary *dict in executes) {
      SQLiteResult *result = [self executeSqlWithDict:dict andArgs:dbargs];
      if ([result.status intValue] == SQLiteStatus_ERROR) {
        /* add error with result.message: */
        NSMutableDictionary *r = [NSMutableDictionary dictionaryWithCapacity:4];
        [r setObject:[dict objectForKey:@"qid"] forKey:@"qid"];
        [r setObject:@"error" forKey:@"type"];
        [r setObject:result.message forKey:@"error"];
        [r setObject:result.message forKey:@"result"];
        [results addObject: r];
      } else {
        /* add result with result.message: */
        NSMutableDictionary *r = [NSMutableDictionary dictionaryWithCapacity:3];
        [r setObject:[dict objectForKey:@"qid"] forKey:@"qid"];
        [r setObject:@"success" forKey:@"type"];
        [r setObject:result.message forKey:@"result"];
        [results addObject: r];
      }
    }
    
    pluginResult = [SQLiteResult resultWithStatus:SQLiteStatus_OK messageAsArray:results];
  }
  
  success(@[pluginResult.message]);
}

RCT_EXPORT_METHOD(backgroundExecuteSql: (NSDictionary *) options success:(RCTResponseSenderBlock)success error:(RCTResponseSenderBlock)error)
{
  [self runInBackground:^{
    [self executeSql:options success:success error:error];
  }];
}

RCT_EXPORT_METHOD(executeSql: (NSDictionary *) options success:(RCTResponseSenderBlock)success error:(RCTResponseSenderBlock)error)
{
  NSMutableDictionary *dbargs = [options objectForKey:@"dbargs"];
  NSMutableDictionary *ex = [options objectForKey:@"ex"];
  
  SQLiteResult* pluginResult;
  @synchronized (self) {
    pluginResult = [self executeSqlWithDict: ex andArgs: dbargs];
  }
  
  success(@[pluginResult.message]);
}

-(SQLiteResult *) executeSqlWithDict: (NSMutableDictionary*)options andArgs: (NSMutableDictionary*)dbargs
{
  NSString *dbFileName = [dbargs objectForKey:@"dbname"];
  if (dbFileName == NULL) {
    return [SQLiteResult resultWithStatus:SQLiteStatus_ERROR messageAsString:@"You must specify database path"];
  }
  
  NSMutableArray *params = [options objectForKey:@"params"]; // optional
  
  NSValue *dbPointer = [openDBs objectForKey:dbFileName];
  if (dbPointer == NULL) {
    return [SQLiteResult resultWithStatus:SQLiteStatus_ERROR messageAsString:@"No such database, you must open it first"];
  }
  sqlite3 *db = [dbPointer pointerValue];
  
  NSString *sql = [options objectForKey:@"sql"];
  if (sql == NULL) {
    return [SQLiteResult resultWithStatus:SQLiteStatus_ERROR messageAsString:@"You must specify a sql query to execute"];
  }
  
  const char *sql_stmt = [sql UTF8String];
  NSDictionary *error = nil;
  sqlite3_stmt *statement;
  int result, i, column_type, count;
  int previousRowsAffected, nowRowsAffected, diffRowsAffected;
  long long previousInsertId, nowInsertId;
  BOOL keepGoing = YES;
  BOOL hasInsertId;
  NSMutableDictionary *resultSet = [NSMutableDictionary dictionaryWithCapacity:0];
  NSMutableArray *resultRows = [NSMutableArray arrayWithCapacity:0];
  NSMutableDictionary *entry;
  NSObject *columnValue;
  NSString *columnName;
  NSObject *insertId;
  NSObject *rowsAffected;
  
  hasInsertId = NO;
  previousRowsAffected = sqlite3_total_changes(db);
  previousInsertId = sqlite3_last_insert_rowid(db);
  
  if (sqlite3_prepare_v2(db, sql_stmt, -1, &statement, NULL) != SQLITE_OK) {
    error = [SQLite captureSQLiteErrorFromDb:db];
    keepGoing = NO;
  } else if (params != NULL) {
    for (int b = 0; b < params.count; b++) {
      [self bindStatement:statement withArg:[params objectAtIndex:b] atIndex:(b+1)];
    }
  }
  
  //    NSLog(@"inside executeSqlWithDict");
  while (keepGoing) {
    result = sqlite3_step (statement);
    switch (result) {
        
      case SQLITE_ROW:
        i = 0;
        entry = [NSMutableDictionary dictionaryWithCapacity:0];
        count = sqlite3_column_count(statement);
        
        while (i < count) {
          columnValue = nil;
          columnName = [NSString stringWithFormat:@"%s", sqlite3_column_name(statement, i)];
          
          column_type = sqlite3_column_type(statement, i);
          switch (column_type) {
            case SQLITE_INTEGER:
              columnValue = [NSNumber numberWithLongLong: sqlite3_column_int64(statement, i)];
              break;
            case SQLITE_FLOAT:
              columnValue = [NSNumber numberWithDouble: sqlite3_column_double(statement, i)];
              break;
            case SQLITE_BLOB:
              columnValue = [SQLite getBlobAsBase64String: sqlite3_column_blob(statement, i)
                                               withLength: sqlite3_column_bytes(statement, i)];
#ifdef INCLUDE_SQL_BLOB_BINDING // TBD subjet to change:
              columnValue = [@"sqlblob:;base64," stringByAppendingString:columnValue];
#endif
              break;
            case SQLITE_TEXT:
              columnValue = [[NSString alloc] initWithBytes:(char *)sqlite3_column_text(statement, i)
                                                     length:sqlite3_column_bytes(statement, i)
                                                   encoding:NSUTF8StringEncoding];
#if !__has_feature(objc_arc)
              [columnValue autorelease];
#endif
              break;
            case SQLITE_NULL:
              // just in case (should not happen):
            default:
              columnValue = [NSNull null];
              break;
          }
          
          if (columnValue) {
            [entry setObject:columnValue forKey:columnName];
          }
          
          i++;
        }
        [resultRows addObject:entry];
        break;
        
      case SQLITE_DONE:
        nowRowsAffected = sqlite3_total_changes(db);
        diffRowsAffected = nowRowsAffected - previousRowsAffected;
        rowsAffected = [NSNumber numberWithInt:diffRowsAffected];
        nowInsertId = sqlite3_last_insert_rowid(db);
        if (nowRowsAffected > 0 && nowInsertId != 0) {
          hasInsertId = YES;
          insertId = [NSNumber numberWithLongLong:sqlite3_last_insert_rowid(db)];
        }
        keepGoing = NO;
        break;
        
      default:
        error = [SQLite captureSQLiteErrorFromDb:db];
        keepGoing = NO;
    }
  }
  
  sqlite3_finalize (statement);
  
  if (error) {
    return [SQLiteResult resultWithStatus:SQLiteStatus_ERROR messageAsDictionary:error];
  }
  
  [resultSet setObject:resultRows forKey:@"rows"];
  [resultSet setObject:rowsAffected forKey:@"rowsAffected"];
  if (hasInsertId) {
    [resultSet setObject:insertId forKey:@"insertId"];
  }
  return [SQLiteResult resultWithStatus:SQLiteStatus_OK messageAsDictionary:resultSet];
}

-(void)bindStatement:(sqlite3_stmt *)statement withArg:(NSObject *)arg atIndex:(NSUInteger)argIndex
{
  if ([arg isEqual:[NSNull null]]) {
    sqlite3_bind_null(statement, (int) argIndex);
  } else if ([arg isKindOfClass:[NSNumber class]]) {
    NSNumber *numberArg = (NSNumber *)arg;
    const char *numberType = [numberArg objCType];
    if (strcmp(numberType, @encode(int)) == 0) {
      sqlite3_bind_int(statement, (int) argIndex, (int) [numberArg integerValue]);
    } else if (strcmp(numberType, @encode(long long int)) == 0) {
      sqlite3_bind_int64(statement, (int) argIndex, [numberArg longLongValue]);
    } else if (strcmp(numberType, @encode(double)) == 0) {
      sqlite3_bind_double(statement, (int) argIndex, [numberArg doubleValue]);
    } else {
      sqlite3_bind_text(statement, (int) argIndex, [[arg description] UTF8String], -1, SQLITE_TRANSIENT);
    }
  } else { // NSString
    NSString *stringArg;
    
    if ([arg isKindOfClass:[NSString class]]) {
      stringArg = (NSString *)arg;
    } else {
      stringArg = [arg description]; // convert to text
    }
    
#ifdef INCLUDE_SQL_BLOB_BINDING // TBD subjet to change:
    // If the string is a sqlblob URI then decode it and store the binary directly.
    //
    // A sqlblob URI is formatted similar to a data URI which makes it easy to convert:
    //   sqlblob:[<mime type>][;charset=<charset>][;base64],<encoded data>
    //
    // The reason the `sqlblob` prefix is used instead of `data` is because
    // applications may want to use data URI strings directly, so the
    // `sqlblob` prefix disambiguates the desired behavior.
    if ([stringArg hasPrefix:@"sqlblob:"]) {
      // convert to data URI, decode, store as blob
      stringArg = [stringArg stringByReplacingCharactersInRange:NSMakeRange(0,7) withString:@"data"];
      NSData *data = [NSData dataWithContentsOfURL: [NSURL URLWithString:stringArg]];
      sqlite3_bind_blob(statement, (int) argIndex, data.bytes, data.length, SQLITE_TRANSIENT);
    }
    else
#endif
    {
      NSData *data = [stringArg dataUsingEncoding:NSUTF8StringEncoding];
      sqlite3_bind_text(statement, (int) argIndex, data.bytes, (int) data.length, SQLITE_TRANSIENT);
    }
  }
}

-(void)dealloc
{
  int i;
  NSArray *keys = [openDBs allKeys];
  NSValue *pointer;
  NSString *key;
  sqlite3 *db;
  
  /* close db the user forgot */
  for (i=0; i<[keys count]; i++) {
    key = [keys objectAtIndex:i];
    pointer = [openDBs objectForKey:key];
    db = [pointer pointerValue];
    sqlite3_close (db);
  }
  
#if !__has_feature(objc_arc)
  [openDBs release];
  [appDBPaths release];
  [super dealloc];
#endif
}

+(NSDictionary *)captureSQLiteErrorFromDb:(struct sqlite3 *)db
{
  int code = sqlite3_errcode(db);
  int webSQLCode = [SQLite mapSQLiteErrorCode:code];
#if INCLUDE_SQLITE_ERROR_INFO
  int extendedCode = sqlite3_extended_errcode(db);
#endif
  const char *message = sqlite3_errmsg(db);
  
  NSMutableDictionary *error = [NSMutableDictionary dictionaryWithCapacity:4];
  
  [error setObject:[NSNumber numberWithInt:webSQLCode] forKey:@"code"];
  [error setObject:[NSString stringWithUTF8String:message] forKey:@"message"];
  
#if INCLUDE_SQLITE_ERROR_INFO
  [error setObject:[NSNumber numberWithInt:code] forKey:@"sqliteCode"];
  [error setObject:[NSNumber numberWithInt:extendedCode] forKey:@"sqliteExtendedCode"];
  [error setObject:[NSString stringWithUTF8String:message] forKey:@"sqliteMessage"];
#endif
  
  return error;
}

+(int)mapSQLiteErrorCode:(int)code
{
  // map the sqlite error code to
  // the websql error code
  switch(code) {
    case SQLITE_ERROR:
      return SYNTAX_ERR;
    case SQLITE_FULL:
      return QUOTA_ERR;
    case SQLITE_CONSTRAINT:
      return CONSTRAINT_ERR;
    default:
      return UNKNOWN_ERR;
  }
}

+(NSString*)getBlobAsBase64String:(const char*)blob_chars
                       withLength:(int)blob_length
{
  NSData* data = [NSData dataWithBytes:blob_chars length:blob_length];
  
  // Encode a string to Base64
  NSString* result = [data base64EncodedStringWithOptions:0];
  
#if !__has_feature(objc_arc)
  [result autorelease];
#endif
  
  return result;
}

@end /* vim: set expandtab : */


