FCModel
=======

An alternative to Core Data for people who like having direct SQL access.

By [Marco Arment](http://www.marco.org/). See the LICENSE file for license info (it's the MIT license).

__Requires [Gus Mueller's excellent FMDB](https://github.com/ccgus/fmdb),__ a nice Objective-C wrapper around the SQLite C API.

FCModel is a generic model layer on top of FMDB. It's intended for people who want _some_ of Core Data's convenience, but with more control over implementation, performance, database schemas, queries, indexes, and migrations, and the ability to use raw SQL queries and SQLite features directly.

FCModel accomplishes a lot of what [Brent Simmons wrote about](http://www.objc.io/issue-4/SQLite-instead-of-core-data.html). This is my version of that. (Are you reading [objc.io](http://www.objc.io) yet? You should be. It's excellent.)

## Alpha status

This is an __alpha.__ I'm building an app around it, and this is the first time it's seeing outside eyes, so the API can still change in backwards-incompatible ways, and the code will probably change rapidly over the next few months.

## Requirements

* Xcode 5
* iOS 6 or above (haven't tested on Mac) since it requires `NSMapTable`
* ARC
* [FMDB](https://github.com/ccgus/fmdb)
* Link your project with `sqlite3`

## Documentation

There isn't much right now. Check out the `FCModel.h` header and the example project. I'll add more here as I get the chance.

## Schema-to-object mapping

SQLite tables are associated with FCModel subclasses of the same name, and database columns map to `@property` declarations with the same name. So you could have a table like this:

```SQL
CREATE TABLE Person (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    name         TEXT NOT NULL DEFAULT '',
    createdTime  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS name ON Person (name);
```

A single-column primary key is required. It can be an integer or a string, and `AUTOINCREMENT` is optional. You're responsible for creating your own indexes.

This table's model would look like this:

```obj-c
#import "FCModel.h"

@interface Person : FCModel

@property (nonatomic, assign) int64_t id;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) NSDate *createdTime;

@end
```

You can name your column-property ivars whatever you like, and you can use primitives like `int` or objects like `NSNumber` — your choice. (No structs or blocks.) Since field-change tracking is implemented using KVO, just ensure that if you manipulate properties directly in the class (without using the property accessors), you call `didChangeValueForKey:` afterward to register the change with FCModel.

`NSDate` and `NSURL` objects are automatically converted to/from Unix timestamp integers and absoluteStrings, respectively, for database storage. (Be careful that any column you define as an NSDate fits within the Unix-timestamp range.)

You can add any other properties you'd like — they don't all need to have database columns.

## Schema creation and migrations

In your `application:didFinishLaunchingWithOptions:` method, __before any models are accessed,__ call FCModel's `openDatabaseAtPath:withSchemaBuilder:`. This looks a bit crazy, but bear with me — it's conceptually very simple.

Your schema-builder block is passed `int *schemaVersion`, which is an in-out argument:

* FCModel tells you the current schema on the way in (on an empty database, this starts at 0).
* You execute any schema-creation or migration statements to get to the next schema version.
* You update `*schemaVersion` to reflect the new version.

Here's an example from that Person class described above:

```obj-c
NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
NSString *dbPath = [documentsPath stringByAppendingPathComponent:@"testDB.sqlite3"];

[FCModel openDatabaseAtPath:dbPath withSchemaBuilder:^(FMDatabase *db, int *schemaVersion) {
    [db beginTransaction];

    // My custom failure handling. Yours may vary.
    void (^failedAt)(int statement) = ^(int statement){
        [db rollback];
        NSAssert3(0, @"Migration statement %d failed, code %d: %@", statement, db.lastErrorCode, db.lastErrorMessage);
    };

    if (*schemaVersion < 1) {
        if (! [db executeUpdate:
            @"CREATE TABLE Person ("
            @"    id           INTEGER PRIMARY KEY AUTOINCREMENT,"
            @"    name         TEXT NOT NULL DEFAULT '',"
            @"    createdTime  INTEGER NOT NULL"
            @");"
        ]) failedAt(1);

        if (! [db executeUpdate:@"CREATE INDEX IF NOT EXISTS name ON Person (name);"]) failedAt(2);

        *schemaVersion = 1;
    }

    // If you wanted to change the schema in a later app version, you'd add something like this here:
    /*
    if (*schemaVersion < 2) {
        if (! [db executeUpdate:@"ALTER TABLE Person ADD COLUMN title TEXT NOT NULL DEFAULT ''"]) failedAt(3);
        *schemaVersion = 2;
    }

    // And so on...
    if (*schemaVersion < 3) {
        if (! [db executeUpdate:@"CREATE TABLE..."]) failedAt(4);
        *schemaVersion = 3;
    }

    */

    [db commit];
}];
```

Once you've shipped a version to customers, never change its construction in your code. That way, on an initial launch of a new version, your schema-builder will see that the customer's existing database is at e.g. schema version 2, and you can execute only what's required to bring it up to version 3.

## Creating, fetching, and updating model instances

Creating new instances (INSERTs):

```obj-c
// If using AUTOINCREMENT:
Person *bob = [Person new]; // .id will be set after save
// If not:
Person *bob = [Person instanceWithPrimaryKey:@(123)];
bob.name = @"Bob";
bob.createdTime = [NSDate date];
[bob save];
```

SELECT and UPDATE queries should look familiar to FMDB fans: everything's parameterized with `?` placeholders and varargs query functions, and it's passed right through to FMDB. Just as with FMDB, you need to box primitives when passing them as query params, e.g. `@(1)` instead of `1`.

```obj-c
// Find that specific Bob by ID
Person *bob = [Person instanceWithPrimaryKey:@(123)];
bob.name = @"Robert";
[bob save];

// Or find the first person named Bob
Person *firstBob = [Person firstInstanceWhere:@"name = ? ORDER BY id LIMIT 1", @"Bob"];

// Find all Bobs
NSArray *allBobs = [Person instancesWhere:@"name = ?", @"Bob"];
```

You can use two shortcuts in queries:

* `$T`: The model's table name. (e.g. "Person")
* `$PK`: The model's primary-key column name. (e.g. "id")

Now here's where it gets crazy. Suppose you wanted to rename all Bobs to Robert, or delete all people named Sue, without loading them all and doing a million queries. (Hi, Core Data.)

```obj-c
// Suppose these are hanging out here, being retained somewhere (in the UI, maybe)
Person *bob = [Person instanceWithPrimaryKey:@(123)];
Person *sue = [Person firstInstanceWhere:@"name = 'Sue'"]; // you don't HAVE to parameterize everything
// ...

[Person executeUpdateQuery:@"UPDATE $T SET name = ? WHERE name = ?", @"Robert", @"Bob"];

NSLog(@"This Bob's name is now %@.", bob.name);
// prints: This Bob's name is now Robert.

[Person executeUpdateQuery:@"DELETE FROM $T WHERE name = 'Sue'"];

NSLog(@"Sue is %@.", sue.deleted ? @"deleted" : @"around");
// prints: Sue is deleted.
```

It works. (Or at least, it should. Please let me know if it doesn't.)

## Object-to-object relationships

FCModel is not designed to handle this automatically. You're meant to write this from each model's implementation as appropriate. This gives you complete control over schema, index usage, automatic fetching queries (or not), and caching.

If you want automatic relationship mappings, consider using Core Data. It's very good at that.

## Retention and Caching

Each FCModel instance is exclusive in memory by its table and primary-key value. If you load Person ID 1, then some other query loads Person ID 1, they'll be the same instance (unless the first one got deallocated in the meantime).

FCModels are safe to retain for a while, even by the UI. You can use KVO to observe changes, or you can write your own change-tracking logic in your model implementations. Just check instances' `deleted` property where relevant, and watch for change notifications.

FCModels are inherently cached by primary key:

```obj-c
NSArray *allBobs = [Person instancesWhere:@"name = ?", @"Bob"];
// executes query: SELECT * FROM Person WHERE name = 'Bob'

Person *bob = [Person instanceWithPrimaryKey:@(123)];
// cache hit, no query executed
```

...but only among what's retained in your app. If you want to cache an entire table, for instance, you'll want to do something like retain its `allInstances` array somewhere long-lived (such as the app delegate).

## Concurrency

FCModels can be accessed and modified from any thread (again, as far as I know), but all database operations are run synchronously on a serial queue, so you're not likely to see any performance gains by concurrent access.

If you observe any of FCModel's notifications (`FCModelInsertNotification`, etc.), be careful when updating the UI. Those are posted on the thread that caused the update, which may not be the main thread if you're accessing models from other threads or queues.

## Support

For now, it's just right here on GitHub.

## Contributions

...are welcome, with the following guideline:

More than anything else, I'd like to keep FCModel _small,_ simple, and easy to fit in your mental L2 cache.