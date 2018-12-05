package org.pgsqlite;

import android.content.Context;
import android.text.TextUtils;
import android.util.Log;

import net.sqlcipher.database.SQLiteDatabase;
import net.sqlcipher.database.SQLiteException;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

public class SQLiteDatabaseUtils {

    public final static int WRITABLE_OPEN_FLAGS = SQLiteDatabase.OPEN_READWRITE | SQLiteDatabase.CREATE_IF_NECESSARY;
    public final static int READONLY_OPEN_FLAGS = SQLiteDatabase.OPEN_READONLY | SQLiteDatabase.CREATE_IF_NECESSARY;

    public static SQLiteDatabase openDatabaseWithEncryption(Context context, String dbname, String key, String assetFilePath, int openFlags){
        SQLiteDatabase db = null;
        try {
            //open unencrypted database
            db = openDatabase(context, dbname, null, assetFilePath, openFlags);
            if(db != null && !TextUtils.isEmpty(key)){
                //db is not encrypted, encrypt it with provided key
                encryptDatabase(context, db, dbname, key, assetFilePath, openFlags);
                db = openDatabase(context, dbname, key, assetFilePath, openFlags);
            }
        } catch (Exception e) {
            try {
                db = openDatabase(context, dbname, key, assetFilePath, openFlags);
            } catch (Exception ignored) { }

        }

        return db;
    }

    /**
     * Open a database.
     *
     * @param context
     * @param dbname - The name of the database file
     * @param key - encryption key
     * @param assetFilePath - path to the pre-populated database file
     * @param openFlags - the db open options
     * @return instance of SQLite database
     * @throws Exception
     */
    public static SQLiteDatabase openDatabase(Context context, String dbname, String key, String assetFilePath, int openFlags) throws Exception {
        try {
            File dbfile = getDbFile(context, dbname, openFlags, assetFilePath);

            Log.v("info", "Opening sqlite db: " + dbfile.getAbsolutePath());
            SQLiteDatabase mydb = SQLiteDatabase.openOrCreateDatabase(dbfile.getAbsolutePath(), key, null);

            return mydb;
        } catch (SQLiteException ex) {
            throw ex;
        }
    }

    public static File getDbFile(Context context, String dbname, int openFlags, String assetFilePath) throws Exception{
        InputStream in = null;
        File dbfile = null;
        if (assetFilePath != null && assetFilePath.length() > 0) {
            if (assetFilePath.compareTo("1") == 0) {
                assetFilePath = "www/" + dbname;
                in = context.getAssets().open(assetFilePath);
                Log.v("info", "Located pre-populated DB asset in app bundle www subdirectory: " + assetFilePath);
            } else if (assetFilePath.charAt(0) == '~') {
                assetFilePath = assetFilePath.startsWith("~/") ? assetFilePath.substring(2) : assetFilePath.substring(1);
                in = context.getAssets().open(assetFilePath);
                Log.v("info", "Located pre-populated DB asset in app bundle subdirectory: " + assetFilePath);
            } else {
                File filesDir = context.getFilesDir();
                assetFilePath = assetFilePath.startsWith("/") ? assetFilePath.substring(1) : assetFilePath;
                File assetFile = new File(filesDir, assetFilePath);
                in = new FileInputStream(assetFile);
                Log.v("info", "Located pre-populated DB asset in Files subdirectory: " + assetFile.getCanonicalPath());
                if (openFlags == SQLiteDatabase.OPEN_READONLY) {
                    dbfile = assetFile;
                    Log.v("info", "Detected read-only mode request for external asset.");
                }
            }
        }

        if (dbfile == null) {
            dbfile = context.getDatabasePath(dbname);

            if (!dbfile.exists() && in != null) {
                Log.v("info", "Copying pre-populated db asset to destination");
                createFromAssets(dbname, dbfile, in);
            }

            if (!dbfile.exists()) {
                dbfile.getParentFile().mkdirs();
            }
        }

        return dbfile;
    }

    /**
     * If a prepopulated DB file exists in the assets folder it is copied to the dbPath.
     * Only runs the first time the app runs.
     *
     * @param dbName The name of the database file - could be used as filename for imported asset
     * @param dbfile The File of the destination db
     * @param assetFileInputStream input file stream for pre-populated db asset
     */
    private static void createFromAssets(String dbName, File dbfile, InputStream assetFileInputStream) {
        OutputStream out = null;

        try {
            Log.v("info", "Copying pre-populated DB content");
            String dbPath = dbfile.getAbsolutePath();
            dbPath = dbPath.substring(0, dbPath.lastIndexOf("/") + 1);

            File dbPathFile = new File(dbPath);
            if (!dbPathFile.exists())
                dbPathFile.mkdirs();

            File newDbFile = new File(dbPath + dbName);
            out = new FileOutputStream(newDbFile);

            // XXX TODO: this is very primitive, other alternatives at:
            // http://www.journaldev.com/861/4-ways-to-copy-file-in-java
            byte[] buf = new byte[1024];
            int len;
            while ((len = assetFileInputStream.read(buf)) > 0)
                out.write(buf, 0, len);

            Log.v("info", "Copied pre-populated DB content to: " + newDbFile.getAbsolutePath());
        } catch (IOException e) {
            Log.v("createFromAssets", "No pre-populated DB found, error=" + e.getMessage());
        } finally {
            if (out != null) {
                try {
                    out.close();
                } catch (IOException ignored) {
                }
            }
        }
    }

    private static void encryptDatabase(Context context, SQLiteDatabase mydb, String dbname, String key, String assetFilePath, int openFlags) {
        try {
            File originalFile = getDbFile(context, dbname, openFlags, assetFilePath);
            File newFile = File.createTempFile("temp_db", "temp", originalFile.getParentFile());

            mydb.rawExecSQL("ATTACH DATABASE '" + newFile.getPath() + "' AS encrypted KEY '" + key + "';");
            mydb.rawExecSQL("SELECT sqlcipher_export('encrypted');");
            mydb.rawExecSQL("DETACH DATABASE encrypted;");

            //close old db
            mydb.close();

            //delete old db
            originalFile.delete();

            //rename encertped db to old name
            newFile.renameTo(originalFile);
        } catch (Exception e) {
            e.printStackTrace();
        }

    }
}
