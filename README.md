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

There isn't much right now. Check out the `FCModel.h` header and the example project. I'll add more here when I get a chance.
