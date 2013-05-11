---
layout: post
title: 6 nice things not know enough about PostgreSQL
categories: [PostgreSQL, English]
tags: [PostgreSQL]
pic: redflower2.png
excerpt: Let's explore FillFactor, Returning inserts, TOAST, table inheritance, table partitionning and Notify/listen features. 

---

With the new PostgreSQL server versions in place (8.2 and 8.3) and in a more general way with the 8.x series
some nice fonctionnalities have benn added.  

Let's have a short look at som interesting ones:  
`FILLFACTOR=50`, Id on `INSERT`, `TOAST` fields, `TABLE INHERITANCE`, `TABLE PARTITIONNING`, `NOTIFY` and `LISTEN`.

### WITH FILLFACTOR=50 in CREATE TABLE instructions (since 8.2):###

FILLFACTOR is 100% by default and is a good default setting for tables
where the basic usage is `INSERT`s (and select).  
But when you know that you'll make a lot of `UPDATE`s on your rows you should decrease this factor.

This way **some space on the table will be reserved near your inserted rows**.
This space will then be used as a work zone when you'll make an `UPDATE` on the row.  
And the magic effect is that this work zone won't be at the end of the table but near your row,
in the same page in memory.

see [postgreSQL documentation page](http://www.postgresql.org/docs/8.3/interactive/sql-createtable.html#SQL-CREATETABLE-STORAGE-PARAMETERS) for details.

###2) RETURNING on INSERT INTO to get your INSERTED Id (since 8.2):###

The classical way to get your **'last insert Id'** in PostgreSQl as always been using `currval(SEQUENCE)`

This is right and secure as `PRIMARY KEYS` are usually defined as `SEQUENCE`s with `DEFAULT nextval(SEQUENCE)`.  
And `currvall` renders the last value set by `nextval` in the current session (others concurrent sessions cannot interfere with it).

But that's not something easy to understand for newbies and very bad examples with `max(id)` can always be found googling around.

Now you can add a **RETURNING MyId** code on your `INSERT` query and the result of your insert won't be the row `OID` anymore
but your `Id` (or anything else if you want).

Consult [postgreSQL documentation page](http://www.postgresql.org/docs/8.3/interactive/sql-insert.html) for details.

###3) TOAST FIELDS:###

`TOAST` means **'The Oversized-Attribute Storage Technique'.**

You can set up to **1Gb** in **one field** of your **row**.  
This column won't be saved in the same physical file as the others. Another file will be created to store
such big fields. 

[PostgreSQL documentation page](http://www.postgresql.org/docs/8.3/interactive/storage-toast.html) is still the best reference.

If you wonder about the size of your tables and the physical files on your filesystem you should not.
Your tables are always split in files of **2Gb**. And Toast values are stored on their own files.

###4) TABLE INHERITANCE:###

You can define a **table B as child of table A**.

Request on table `A` will then render rows from `A` and `B` tables.  
With `ONLY` keyword you can limit requests on `A` with `A` rows.  
`A` could have several tables (B, C, D, etc). Indexes are done tables by table, and are by this way shorter.

This is quite powerfull but you'll have some problems with **contraints**. `UNIQUE` constraints for example
are done for each table. You cannot ensure `A+B+C+D` rows will not share the same value for this **'UNIQUE'** constraint.

Setting Referential integrity from one of this table to a `Z` table is easy (but should be done for each table).  
But setting the reverse relation from `Z` to `A+B+C+D` isn't possible.

You should really look [postgreSQL documentation page](http://www.postgresql.org/docs/8.3/interactive/ddl-inherit.html), as always.

###5) TABLE PARTITIONNING:###

One of the most powerfull thing you can do with `INHERITANCE` is table `PARTITIONNING`.

Using `TABLESPACE`s you can define several different physical storage locations for your databases.

`TABLESPACES` can easily be used for a database, a table, or even for an index (or the WAL sync log).  
This is fine. You can use several storage devices with different characteristics, each one fitting
your differents needs (capacity, speed, sync/async, etc).  
But this combined with `INHERITANCE` becomes even more powerfull:  
Define table `A` as an empty table.  
Define table `B` and `C` as child tables of `A`, and use different tablespaces for `B` and `C`.  
You then have a **virtual A table** with his content spread on diferent storage devices
(or not, you could use the TABLESPACE on the same storage but you'll lose most of the power of the 'thing').

Your benefits? **smaller indexes**, on different devices, which can run in **parallel**,
some problems with constraints as with previous part,
but this is not a problem for all tables, and for a huge table this `TABLESPACE` splitting could be
a cool thing to study.

Have a look at [postgreSQL documentation page](http://www.postgresql.org/docs/8.3/interactive/ddl-partitioning.html).

One last point, you'll have to defined how the rows are splitted with the different tables
(ranges, or domains, or anything else),
you'll maybe have to check `RULES` as well, even with simple `INHERITANCE`, because `INSERT`
for example should be done on the child table, and `INSERT` on the main `TABLE` should be redirected elsewhere.

###6) NOTIFY/LISTEN:###

PostgreSQL has a builtin fonctionnality for **Observer/observable Design Pattern**.

You can `NOTIFY` something, as an `SQL` command and at the end of your transaction
(or directly if you're not in a transaction) others SQL sessions which have registered this notification with `LISTEN`
will get your notification ([the doc](http://www.postgresql.org/docs/8.1/interactive/libpq-notify.html)).  
Usefull with server processes (while true processes), a cli process in PHP for example with builtin [pg lib](http://www.php.net/manual/en/function.pg-get-notify.php)
but not with PDO actually.

Here is as well a [Java example](http://jdbc.postgresql.org/documentation/83/listennotify.html) and examples in [python, the demo2a/b](http://pypgsql.cvs.sourceforge.net/viewvc/pypgsql/pypgsql/examples/) files.

