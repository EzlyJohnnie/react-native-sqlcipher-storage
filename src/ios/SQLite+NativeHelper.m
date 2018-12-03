//
//  SQLite+NativeHelper.m
//  SQLite
//
//  Created by Johnnie Cheng on 3/12/18.
//  Copyright © 2018 Andrzej Porebski. All rights reserved.
//

#import "SQLite+NativeHelper.h"
#import "SQLiteResult.h"
#import "sqlite3.h"
#include <regex.h>


@implementation SQLite (NativeHelper)

static void sqlite_regexp(sqlite3_context* context, int argc, sqlite3_value** values) {
  if ( argc < 2 ) {
    sqlite3_result_error(context, "SQL function regexp() called with missing arguments.", -1);
    return;
  }
  
  char* reg = (char*)sqlite3_value_text(values[0]);
  char* text = (char*)sqlite3_value_text(values[1]);
  
  if ( argc != 2 || reg == 0 || text == 0) {
    sqlite3_result_error(context, "SQL function regexp() called with invalid arguments.", -1);
    return;
  }
  
  int ret;
  regex_t regex;
  
  ret = regcomp(&regex, reg, REG_EXTENDED | REG_NOSUB);
  if ( ret != 0 ) {
    sqlite3_result_error(context, "error compiling regular expression", -1);
    return;
  }
  
  ret = regexec(&regex, text , 0, NULL, 0);
  regfree(&regex);
  
  sqlite3_result_int(context, (ret != REG_NOMATCH));
}


+ (SQLiteResult *)performOpenDBWithFilename:(NSString *)filename
                               location:(NSString *)location
                                 dbname:(NSString *)dbname
                     createFromResource:(NSString *)createFromResource
                                  dbkey:(NSString *)dbkey
{
  return [SQLite performOpenDBWithFilename:filename
                                        location:location
                                          dbname:dbname
                              createFromResource:createFromResource
                                           dbkey:dbkey
                                         openedDBs:nil];
}

+ (SQLiteResult *)performOpenDBWithFilename:(NSString *)filename
                                   location:(NSString *)location
                                     dbname:(NSString *)dbname
                         createFromResource:(NSString *)createFromResource
                                      dbkey:(NSString *)dbkey
                                    openedDBs:(NSMutableDictionary *)openedDBs
{
  SQLiteResult *pluginResult = nil;
  
  if (location == NULL) location = @"docs";
  NSLog(@"using db location: %@", location);
  
  if (dbname == NULL) {
    NSLog(@"No db name specified for open");
    pluginResult = [SQLiteResult resultWithStatus:SQLiteStatus_OK messageAsString:@"You must specify database name"];
  }
  else {
    NSValue *dbPointer = nil;
    if(openedDBs){
      dbPointer = [openedDBs objectForKey:filename];
    }
    
    if (dbPointer != NULL) {
      NSLog(@"Reusing existing database connection for db name %@", filename);
      pluginResult = [SQLiteResult resultWithStatus:SQLiteStatus_OK messageAsString:@"Database opened"];
    } else {
      sqlite3 *db;
      
      NSLog(@"open full db path: %@", dbname);
      
      /* Option to create from resource (pre-populated) if db does not exist: */
      if (![[NSFileManager defaultManager] fileExistsAtPath:dbname]) {
        if (createFromResource != NULL)
        [self createFromResource:filename withDbname:dbname];
      }
      
      sqlite3 *unencryptedDB = [self openDatabase:dbname key:nil];
      if(unencryptedDB){
        //db is unencrypted and open success
        db = unencryptedDB;
        if(db && dbkey.length && ![[dbkey lowercaseString] isEqualToString:@"null"]){
          //encrypt db if key provided
          db = [self encryptDatabase:db key:dbkey dbname:dbname];
        }
      }
      else {
        //db is encrypted, try to open with provided key
        db = [self openDatabase:dbname key:dbkey];
      }
      
      if(db){
        //open db success
        dbPointer = [NSValue valueWithPointer:db];
        [openedDBs setObject: dbPointer forKey: filename];
        pluginResult = [SQLiteResult resultWithStatus:SQLiteStatus_OK messageAsString:@"Database opened"];
        pluginResult.dbPointer = dbPointer;
      }
      else{
        //open db failed
        pluginResult = [SQLiteResult resultWithStatus:SQLiteStatus_ERROR messageAsString:@"Unable to open DB"];
      }
      
    }
  }
  
  return pluginResult;
}

+ (void)createFromResource:(NSString *)dbfile withDbname:(NSString *)dbname {
  NSString *bundleRoot = [[NSBundle mainBundle] resourcePath];
  NSString *www = [bundleRoot stringByAppendingPathComponent:@"www"];
  NSString *prepopulatedDb = [www stringByAppendingPathComponent: dbfile];
  // NSLog(@"Look for prepopulated DB at: %@", prepopulatedDb);
  
  if ([[NSFileManager defaultManager] fileExistsAtPath:prepopulatedDb]) {
    NSLog(@"Found prepopulated DB: %@", prepopulatedDb);
    NSError *error;
    BOOL success = [[NSFileManager defaultManager] copyItemAtPath:prepopulatedDb toPath:dbname error:&error];
    
    if(success)
    NSLog(@"Copied prepopulated DB content to: %@", dbname);
    else
    NSLog(@"Unable to copy DB file: %@", [error localizedDescription]);
  }
}

+ (sqlite3 *)openDatabase:(NSString *)dbname key:(NSString *)key{
  sqlite3 *db;
  if(!key) key = @"";
  const char *name = [dbname UTF8String];
  const char *dbkey = [key UTF8String];
  bool openSuccess = sqlite3_open(name, &db) == SQLITE_OK
  && sqlite3_create_function(db, "regexp", 2, SQLITE_ANY, NULL, &sqlite_regexp, NULL, NULL) == SQLITE_OK;
  
  if(key.length){
    openSuccess = openSuccess && sqlite3_key(db, dbkey, strlen(dbkey)) == SQLITE_OK;
  }
  openSuccess = openSuccess && sqlite3_exec(db, (const char*)"SELECT count(*) FROM sqlite_master;", NULL, NULL, NULL) == SQLITE_OK;
  
  if(!openSuccess){
    NSLog(@"Open database failed");
  }
  
  return openSuccess ? db : nil;
}

+ (sqlite3 *)encryptDatabase:(sqlite3 *)db key:(NSString *)key dbname:(NSString *)dbname{
  NSString *tempDBname = [dbname stringByReplacingOccurrencesOfString:dbname.lastPathComponent withString:@"temp"];
  
  NSString *encryptCmd = [NSString stringWithFormat:@"ATTACH DATABASE '%@' AS encrypted KEY '%@';", tempDBname, key];
  bool encryptSuccess = sqlite3_exec(db, (const char*)[encryptCmd cStringUsingEncoding:NSASCIIStringEncoding], NULL, NULL, NULL) == SQLITE_OK
  && sqlite3_exec(db, (const char*)"SELECT sqlcipher_export('encrypted');", NULL, NULL, NULL) == SQLITE_OK
  && sqlite3_exec(db, (const char*)"DETACH DATABASE encrypted;", NULL, NULL, NULL) == SQLITE_OK;
  
  if(!encryptSuccess){
    [self deleteDB:dbname];
    NSLog(@"Encrypt DB failed");
    return nil;
  }
  
  //close old db
  sqlite3_close(db);
  
  //delete old db
  [self deleteDB:dbname];
  
  //rename encertped db to old name
  [[NSFileManager defaultManager] moveItemAtPath:tempDBname toPath:dbname error:nil];
  
  //open new encertped db
  return [self openDatabase:dbname key:key];
}

+ (void)deleteDB:(NSString *)dbname{
  NSFileManager *fManager = [NSFileManager defaultManager];
  if([fManager fileExistsAtPath:dbname]){
    [fManager removeItemAtPath:dbname error:nil];
  }
}

@end
