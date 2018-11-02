---
layout: post
uuid: 2fa0e759-986a-4b5f-a04e-4fa55530e7da
title: Separate cache Backends with Drupal6 and Drupal7.
categories: [english, Drupal]
tags: [Drupal, Performance, Cache, PHP]
pic: old12.jpg
excerpt: Detailled explanation on how to split Drupal's cache tables on several devices, as each cache does not need the same speed and/or capacity. 

---

Drupal use a lot of caches at different levels but all of them are by default stored in the database.

In this article we'll study how to push all these caches in better places.

This is a new feature of default Drupal7, but simple solutions are available if you want the same thing on a Drupal6 installation.

###The default situation###

Take your Drupal Database and check what are the cache tables used, here I'll use a quite basic default Drupal installation on Drupal6:

{% highlight sql %}
mysql> show tables like 'cache%';
+---------------------------+
| Tables_in_expat6 (cache%) |
+---------------------------+
| cache                     |
| cache_block               |
| cache_content             |
| cache_filter              |
| cache_form                |
| cache_menu                |
| cache_page                |
| cache_update              |
| cache_views               |
| cache_views_data          |
| cache_admin_menu          |
+---------------------------+
{% endhighlight %}

Let's try to get more informations on theses tables with a query on the INFORMATION_SCHEMA of MySQL, here a database named mydrupal

{% highlight sql %}
mysql> SELECT 
    ->  concat(table_schema,'.',table_name) dbtable,
    ->  concat(round(table_rows/1000,2),'K') rows,
    ->  concat(round(data_length/(1024*1024),2),'M') DATA,
    ->  concat(round(index_length/(1024*1024),2),'M') indexes,
    ->  concat(round((data_length+index_length)/(1024*1024),2),'M') total_size,
    ->  round(index_length/data_length,2) idxfrac 
    ->  FROM information_schema.TABLES 
    ->  WHERE table_name LIKE 'cache%'
    ->  AND table_schema="mydrupal"
    ->  ORDER BY data_length+index_length DESC;
+---------------------------+-------+-------+---------+------------+---------+
| dbtable                   | rows  | DATA  | indexes | total_size | idxfrac |
+---------------------------+-------+-------+---------+------------+---------+
| mydrupal.cache_menu       | 1.02K | 7.19M | 0.06M   | 7.26M      |    0.01 | 
| mydrupal.cache_form       | 0.01K | 4.99M | 0.01M   | 5.00M      |    0.00 | 
| mydrupal.cache_update     | 0.00K | 0.86M | 0.01M   | 0.86M      |    0.01 | 
| mydrupal.cache_filter     | 0.22K | 0.49M | 0.03M   | 0.52M      |    0.06 | 
| mydrupal.cache            | 0.01K | 0.46M | 0.01M   | 0.46M      |    0.01 | 
| mydrupal.cache_content    | 0.17K | 0.35M | 0.01M   | 0.36M      |    0.03 | 
| mydrupal.cache_views      | 0.01K | 0.23M | 0.01M   | 0.23M      |    0.03 | 
| mydrupal.cache_admin_menu | 0.00K | 0.00M | 0.01M   | 0.01M      |   96.00 | 
| mydrupal.cache_page       | 0.00K | 0.00M | 0.00M   | 0.00M      |    NULL | 
| mydrupal.cache_views_data | 0.00K | 0.00M | 0.00M   | 0.00M      |    NULL | 
| mydrupal.cache_block      | 0.00K | 0.00M | 0.00M   | 0.00M      |    NULL | 
+---------------------------+-------+-------+---------+------------+---------+
11 rows in set (0.00 sec)
{% endhighlight %}

So, well, here my example is a quite little website. Cache tables are small and not heavily used.
You would get bigger numbers on a big website.
But anyway, the real problem in term of performance here is not on the size of 
caches or the size of the indexes, but on the number of read and write queries
running on theses tables.


When the website will grow you will need to activate more internal caching,
maybe you will use good modules, which make their own cache tables and use them
& the existing ones to avoid recomputing all answers.
You may even use so much the cache that some queries on the website will be answered
by only requesting the cache table (aggressive cache mode with cache_page).

Soon enough you will ask yourself "Could I use some smarter solutions like Memcache for the cache storage?".

And of course some existing modules could help you doing that.
The memcache module, for example.
And the "cache router" module applied some of the ideas we'll study later on this article.

You may wonder why it is smart to use something which is not the database to perform the caching storage?

 * You could maybe avoid completely the database requests in aggressive mode
 * Dedicated storage engine (cache engines) perform faster than a relational database both in write and read operations
 * Reducing the number of requests made on MySQL is very important with Drupal, where a single page can be between 50 and 250 requests. With core modules only, adding Panels, some views and some other modules and you could grow up to 600 requests.
 * data not managed in MySQl will never impact MySQL memory buffers management (smallest database will have more chances to avoid pagination)
 * In some circumstances cache tables can get a lot of write operations and the query_cache for queries on theses tables will be wiped out frequently, which is bad for the query cache ratio and usage. But this is not always true, depends a lot on your Drupal cache usages

I said before cache engines can be faster in both write and read operations.
So now you may ask "why don't we use Cache engines for everything?". And the answer is that a relational database provides more services, it can for example provides a better persitency,
or manage better simultaneous writes, or allow handling relationship between objects.
**Use the right tool for the right thing**.
But this is still a good question. Drupal 8 studies & discussions are actually requesting whether a document based backend for most Drupal storage wouldn't be  more appropriate than a relational database.
For now we'll just have a look at the cache tables problems.

###Cache backends with Drupal7###

Now comes Drupal7. The cache management has been rewritten, using cache router and memcached ideas and try to put the things one step further in the core.
Cache bins are used, for example the bin **'foo'** will use the cache table **cache_foo**.
And **for each bin you can specify which storage backend will be used**.

Available cache backends are:</p>
 * Database: the default one, like before
 * File (module filecache): a file-based storage which could be useful with fast disk storage (and a shared disk storage if you have several apache servers)
 * Apc (module apc): APC is not only an opcode (PHP code precompiler) it also  provides a local cache of shared memory. If you have several Apache servers you will have one APC cache per server, but it's not a big one, be careful (and part of the available memory space is occupied by the opcode). In case of full cache (overflow) the cache is completely wiped out, so do not use that for long persistency.
 * Memcache (module memcache): To use the well known memcached daemon. where you could use a basic mono-server setting or a complex multi-servers with replications usage

But other backends could be written.
And you can already find two Redis backends implementations (**Predis** & **PhpRedis**) with the  [redis module](http://drupal.org/project/redis) (alpha).
Module maintained by **pounard**, a Makina Corpus worker.
There is also a [MongoDB module](http://drupal.org/project/mongodb) providing a mongodb cache backend (beta2), that I did not test yet, powered by Damien Tournoud.

###Having a drupal6? Or do you want some configuration details?###

The only thing we need know is a documentation on how to configure these.
This is always (almost) provided in the module documentation but we will use the [cache backport module](http://drupal.org/project/cache_backport) documentation as an example.
This module, again maintained by  **pounard**, is a backport of Drupal7 cache engine (separating  backends) for Drupal6.
So it's a replacement for Cache Router where you can reuse the cache parts of Drupal7 cache backends in a Drupal6 website.
And One of the good points of this module is that it provides a centralized documentation on several cache backends which is spread on the different modules for Drupal7.

The first question is "where should I put each separate cache bin (or each cache table for short) ?"

The **cache** and **cache_bootstrap** bins contains short and often used data.
They will love the APC cache backend.

For all the others bins you could apply a different policy.
You may want to keep some bins in the database, but you should test the memcached/mongodb backend for most bins.
You could also try the filecache backend, with a modern linux kernel often used files will get mapped into memory buffers and you may get good results.

There is no magic rules, the best tool will depend on your cache usage and on used modules.
MySQL is already working a lot, moving all caches outside of the  database will help MySQL.
But you will need to allow some memory (server?) for these new backends, maybe some of the memory given previously to MySQl or Apache.
Keep in mind that you should never make a server swap.

Let's look at a complete configuration, for Drupal6 the cache backport module would require these lines:

{% highlight php %}
  // Load the cache backport replacement for cache.inc:
  $conf['cache_inc'] = 'sites/all/modules/cache_backport/cache.inc';
{% endhighlight %}

And now for Drupal7 or Drupal6 we would have (of course it depends of the bins available on your installation, check the table created in MySQL to see what bin are requested by the modules):

{% highlight php %}
  // Define cache engines:
  // Database : 'DrupalDatabaseCache'
  $conf['cache_backends'][] = 'sites/all/modules/cache_backport/database.inc';
  // FileCache : 'DrupalFileCache'
  $conf['cache_backends'][] = 'sites/all/modules/filecache/filecache.inc';
  // APC : 'DrupalAPCCache'
  $conf['cache_backends'][] = 'sites/all/modules/apc/drupal_apc_cache.inc';
  // Memcache from drupal 7 : 'MemCacheDrupal'
  $conf['cache_backends'][] = 'sites/all/modules/memcache/memcache.inc';
  
  // Define cache bins, here's the magic, deporting several cache on the
  // appropriate place depending on usage frequency, size, and others:
  // Please consider seriously doing brainstorming and benchmarking on your own
  // since this is only an example, and sites performance may vary depending
  // on modules and usage.
  // Cache name |  Usage/frequency/size
  // default    |  any/any/any          select memcache, apc, file or db
  $conf['cache_default_class']          = 'DrupalDatabaseCache';
  // WARNING: this one is 'cache_class_cache' and not 'cache_class_cache_cache'
  // general    |  all/every/medium     select memcache > file > apc > db
  $conf['cache_class_cache']            = 'MemCacheDrupal';
  // bootstrap  |  all/every/medium     select apc > db
  $conf['cache_class_cache_bootstrap']  = 'DrupalAPCCache';
  // block      |  any/often/small      select memcache > db > file
  $conf['cache_class_cache_block']      = 'MemCacheDrupal';
  // field      |  page/some/large      select file > memcache > db
  $conf['cache_class_cache_content']    = 'DrupalFileCache';
  // filter     |  page/some/large      select file > memcache > db
  $conf['cache_class_cache_filter']     = 'DrupalFileCache';
  // form       |  edit/rare/medium     select file > memcache > db
  $conf['cache_class_cache_form']       = 'DrupalFileCache';
  // menu       |  any/often/large      select memcache > db > file
  $conf['cache_class_cache_menu']       = 'MemCacheDrupal';
  // page       |  page/often/large     select memcache > file > db
  $conf['cache_class_cache_page']       = 'MemCacheDrupal';
  // pathdst    |  any/some/medium      select memcache > db > file
  $conf['cache_class_cache_pathdst']    = 'MemCacheDrupal';
  // pathsrc    |  any/some/medium      select memcache > db > file
  $conf['cache_class_cache_pathsrc']    = 'MemCacheDrupal';
  // multiprice |  any/often/medium     select memcache > db > file
  $conf['cache_class_cache_uc_price']   = 'MemCacheDrupal';
  // update     |  system/rare/large,   select file > db
  $conf['cache_class_cache_update']     = 'DrupalFileCache';
  // users      |  any/some/large       select memcache > file > db
  $conf['cache_class_cache_users']      = 'MemCacheDrupal';
  // views      |  any/some/large       select memcache > file > db
  $conf['cache_class_cache_views']      = 'MemCacheDrupal';
  // views data |  any/often/small      select apc > db
  $conf['cache_class_cache_views_data'] = 'DrupalAPCCache';
  
  // Define File Cache settings:
  // See README.TXT in FileCache directory for configuration details.
  $conf['filecache_fast_pagecache'] = TRUE; // set TRUE to enable fast page serving
  // you will need to define your $conf['file_directory_temp'] = '/something/tmp';
  // before using this line. Put the directory in a place where drupal can write
  // (tmp, or files subdirectory) but that is not available via direct web
  // access, default Drupal conf protects .ht* directories, so default name is
  // .ht.filecache in the files directory if you provide no value for this setting
  $conf['filecache_directory'] = $conf['file_directory_temp'] . DIRECTORY_SEPARATOR . 'filecache';
  
  // Define APC settings.
  $conf['apc_show_debug'] = FALSE; // set TRUE to enable debug mode
  // TODO In order to use multiple Drupal instance on the same physical box,
  // each site settings.php file should provide a bin name prefix for APC and
  // most other bin. Currently APC is managing it internally with request's
  // $_SERVER['PHP_HOST']. 
  
  // Define Memcache settings.
  /* in case you use php-memcached and not php-memcache (for this one use php.ini settings)
  $conf['memcache_options'] = array(
    Memcached::OPT_BINARY_PROTOCOL => FALSE, // set TRUE to enable binary protocol when using memcached >= 1.4
    Memcached::OPT_COMPRESSION => FALSE, // set FALSE to disable compression for improved performance
    Memcached::OPT_DISTRIBUTION => Memcached::DISTRIBUTION_CONSISTENT, // set consistent distribution
    Memcached::OPT_HASH => Memcached::HASH_CRC, // set CRC32 hash method
    Memcached::OPT_CONNECT_TIMEOUT => 1000, // connection timeout in milliseconds
    Memcached::OPT_SERVER_FAILURE_LIMIT => 5, // failure limit for server connection attempts
  );*/
  // This is not necessary if you have only 1 memcached server on default port
  // (11211) but could be used to map & replicate bins between several servers
  // (see memcached module documentation).
  $conf['memcache_servers'] = array(
    '127.0.0.1:11211' => 'default',
  );
  // comment cache bins not used with memcached
  $conf['memcache_bins'] = array(
    'cache'            => 'default',
    //'cache_bootstrap'  => 'default',
    'cache_block'      => 'default',
    //'cache_content'    => 'default',
    //'cache_filter'     => 'default',
    //'cache_form'       => 'default',
    'cache_menu'       => 'default',
    'cache_page'       => 'default',
    'cache_pathdst'    => 'default',
    'cache_pathsrc'    => 'default',
    'cache_uc_price'   => 'default',
    //'cache_update'     => 'default',
    'cache_users'      => 'default',
    'cache_views'      => 'default',
    //'cache_views_data' => 'default',    
  );
  
  // Define Drupal cache settings:
  // Inactivate database connection if the cache backend doesn't need it (for
  // cache_page bin only). If the page is not cached the db connection will be
  // made later.
  $conf['page_cache_without_database'] = TRUE;
  // Avoid executing very early hooks in case of page cached (like hook_boot).
  $conf['page_cache_invoke_hooks']     = TRUE;
  // Cached page lifetime.
  $conf['page_cache_maximum_age']      = 3600;
  // Default lifetime for all cache entries (except form and page), if no
  // lifetime is specified by the module.
  $conf['cache_lifetime']              = 0;
{% endhighlight %}

###And the sessions?###

We've just been removing write and read requests from MySQL.
But if you're tracking the request & locks usage in MySQL you will see that the main problem  is not really the cache backends, it's the session managmenent.
Session Management in MySQL implies a very huge number of write operations in the session table.
This single table is used in a very special way, no other table in the database is used with such read/write/delete ratio.
So by definition it's quite hard to perform some fine tunning on the MySQL server if this table is not removed.
To be honest statistics tracking can also make a lot of write requests,  but this is yet another problem

The Cache Backend management is not responsible of the session storage (at least  by default).
Memcache module is providing a tool for that, Cache Router module  was announcing it as well.
But The use of a new Module called [Session Proxy](http://drupal.org/sandbox/pounard/1263216) should be the definitive solution,
allowing usage of a cache backend or usage of PHP native sessions (which can be set to memcache, mongodb, redis, etc.).
Today it's still a sandboxed  module, no official release. available only with Drupal7.

More on this module when released (like how to manage session locks, how to configure the cache backend for sessions, etc).

We could also talk about the lock API in Drupal (lock.inc), with a default implementation using MySQL.
Some modules provides lock alternatives which are faster (like the Redis module)...
