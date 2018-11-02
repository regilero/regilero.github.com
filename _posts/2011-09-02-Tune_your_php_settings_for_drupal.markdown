---
layout: post
uuid: 45a3b558-115a-410c-9d72-96c5a2cb767a
title: Tune your php settings for Drupal
categories: [english, Drupal]
tags: [Drupal, Apache, PHP, Security, APC]
pic: old10.jpg
excerpt: How to make a clean Apache Virtualhost for each drupal project, with PHP settings altered for each project

---

In this article we'll study how to tune the `php.ini` settings for a Drupal host,
how to manage variations of theses settings **per Virtalhosts**,
and of course how to do it without the ugly `.htaccess` file.

##Get a Drupal VirtualHost##

Why am I saying `.htaccess` files are ugly and you should have a VirtualHost for your Drupal?  
Because `.htaccess` files are slowing down your Apache, and everything set by Drupal in
the .htaccess can be safely put in the VirtualHost.   
Check [this previous article]({% post_url 2011-09-01-better_rewrite_rules_for_drupal %}) for details
(first part is about removing the .htaccess).  

Now having a VirtualHost you can handle several parallel Drupal installations on the same host
and you will be able to securize this by adding restrictions on the available directories
for each separate VirtualHost.  
We will see that we will also be able to handle **different PHP configurations** for each VirtualHost.

##Several configurations? But I only have one php.ini!##

Yes.

Only one php.ini is loaded by PHP, but you can alter the PHP settings in apache configuration
by using `php_value`, `php_admin_value`, `php_flag` and `php_admin_flag` directives.  
You could also alter the PHP settings in PHP code with `ini_set()` instructions.
But the `php_admin_value` and php_admin__flag differs from the simpliest one by the fact any
setting set with the **"_admin_"** commands **cannot be overriden** by any `ini_set()` call in the code.

So this means you will be able to set the PHP settings to the value you need for each VirtualHost,
just think about the `open_basedir` restriction, each Drupal installation can have an `open_basedir`
that forbids any access to another parallel Drupal website on the same host.

##What are the PHP settings enforced by default Drupal .htaccess?##

First let's see what is the default php settings that Drupal is asking for in Drupal6:

{% highlight apache %}
<ifmodule mod_php5.c="">
   php_value magic_quotes_gpc                0
   php_value register_globals                0
   php_value session.auto_start              0
   php_value mbstring.http_input             pass
   php_value mbstring.http_output            pass
   php_value mbstring.encoding_translation   0
</ifmodule>
{% endhighlight %}

And in Drupal7:

{% highlight apache %}
<ifmodule mod_php5.c="">
   php_flag magic_quotes_gpc                 off
   php_flag magic_quotes_sybase              off
   php_flag register_globals                 off
   php_flag session.auto_start               off
   php_value mbstring.http_input             pass
   php_value mbstring.http_output            pass
   php_flag mbstring.encoding_translation    off
</ifmodule>
{% endhighlight %}

Not much differences.   
The `0` becames `off`, that mean the same, except if you use php `ini_get()` functions in your scripts
([see here how bad is ini_get()](http://www.makina-corpus.org/blog/how-retrieve-boolean-values-php-s-configuration)).

Drupal7 adds the `magic_quotes_sybase` de-activation, which is a good rule that you can backport to Drupal6,
as if this setting is on, then magic quoting will happen.  
Magic quotes are bad, http input stream is not the right place to escape strings for `SQL`,
you need to do it before any SQL input, but this is the only right place
(so quite dep in the code, and magic quoting does not protect you as much as database provided escape functions),
else you will even be magic-quoting the uploaded files...

`register_globals` is `off`, very dangerous setting when it's On.  
For mbstrings settings I'll trust Drupal when they say they want it this way.

But that's a quite short php tuning.

##Where to put the files?##

So we said we wanted several Drupal, running in parallel projects
(We're not talking about Drupal multi-site handling, which is another problem,
we're talking about Drupal projects). And we wanted to protect each one from the others.  
The things to secure are:

 * **temporary files** (by default everyone share the same path in `/tmp`, not very clean, the less secure application you run with this apache will give you the security level of this `/tmp`
 * **uploaded files** while they're uploaded
 * **filesystem** access, by default any PHP application as the power to read any file the web user can see
 
But in term of projects we would certainly also like to have configuration files,
administrative scripts, and documentations, maybe logs as well.

The project tree can be a quite long debate, so I'll give you one as an example,
then the settings in this article will use this tree, but you can alter it I wont cry.
So for a project named **mydrupal** accessed via **http://mydrupal.example.com** 
(use your `/etc/hosts` to map it to `127.0.0.1` in dev):

<pre>
 -/
  \-var/
    \-www/
      \-mydrupal/
         # project root
        \-etc/
          # here goes the configuration files, like for example you Apache Virtualhost
          # linked in /etc/apache2/sites-available/42-mydrupal.example.com (debian)
        \-www/
          # here goes Drupal sources, this is the Web Directory Root (DocumentRoot)
           \-sites
             \-default
               # here is Drupal settings.php
                \-files
             \-all
                \-files
        \-bin/
          # here goes your managment scripts
        \-doc/
          # project documentation
        \-var/
          \-log/
            # apache logs for this project.
            # Directory may be linked to /var/log/apache2/mydrupal.example.com
            # for log rotation, or use cronolog
          \-tmp/
            # this is the temporary directory for that project
</pre>

You may need to write some scripts to maintain ownership and rights on this tree. Hee are some hints:

 * the web user (www-data) needs read access on all files on the `/var/www/mydrupal/www` subtree
 * the web user needs the "x" right on each parent directory (`/var/www/mydrupal`, `/var/www/`, `/var`)
 * default rights for directories should be "2775" with ownserhip or group to the web user
 * default rights for files should be "0664" with ownserhip or group to the web user
 * on some directories the web user needs **write access**, the files subdirectories under `"/var/www/mydrupal/www/sites/[all|default|foo]"`
 * for a *tmp* directory you can use `"chmod 1777"`, the **1** is important, else use `"chmod 2775"` with `"www-data:www-data"` ownership.
 
Usually chmod command use 3 digits, when using 4 the first one as some meanings,
the "2" for directories means that new files and directories created there will inherit the user and group
of the directory, this is really important for the `"files/"` subdirectory where Drupal is sometimes
creating new subdirectories.

To use a different temporary directory than `/tmp` we'll have to alter the Drupal configuration and some of
the PHP settings. For Drupal settings you simply need to add this line in the settings.php file:

{% highlight php %}
# Drupal 6
$conf['file_directory_temp'] = '/var/www/mydrupal/var/tmp';
# Drupal 7
$conf['file_temporary_path'] = '/var/www/mydrupal/var/tmp';
{% endhighlight %}

##Let's add some PHP settings##

So we keep the existing settings (take the Drupal7 version). And now we add some more.

####Upload####

First we'll put some default settings for File upload management:

{% highlight apache %}
php_admin_flag  file_uploads            1
php_admin_value upload_tmp_dir          "/var/www/mydrupal/var/tmp"
#Maximum allowed size for uploaded files.
php_admin_value upload_max_filesize     "50M"
php_admin_value max_input_time          120
php_admin_value post_max_size           "50M"
{% endhighlight %}

We are using our new temporary directory,
limit the size of any POST request to 50M,
same for the uploaded files,
and allow 2 minutes for the client to push these 50M before disconnecting.

####Logs####

Now let's handle PHP logs, first if we are not in development mode,
we'll prevent Drupal from allowing messages to be outputed.
If you grep `display_errors` in Drupal source code you'll see that the administrator
can allow error output on the page, very dangerous in production, with an `"admin_value"`
here it won't be allowed.

{% highlight apache %}
php_admin_value display_errors          0
php_admin_value display_startup_errors  0
php_admin_value html_errors             0
php_admin_value log_errors              1
php_admin_value define_syslog_variables 0
#E_ALL & ~E_NOTICE -> 6135
#E_ALL -> 6143
#E_ALL^E_STRICT -> 8191
# really all -> -1
php_value error_reporting               6135
{% endhighlight %}

You cannot use `E_ALL` notation, we're not in PHP execution environment and the PHP defines
are not defined, so we need to use the numerical value of theses options

####Security####

Here are the most important settings, first I'll list them:

{% highlight apache %}
php_admin_value open_basedir    ".:/var/www/mydrupal/www:/var/www/mydrupal/var/tmp:/usr/share/php/:/usr/share/php5/"
php_value       include_path    ".:/usr/lib/php5/20090626+lfs:/var/www/mydrupal/www:/var/www/mydrupal/www/include:/usr/share/php/:/usr/share/php5/"
php_admin_value expose_php      0
# you may need to allow url_fopen, but by default we dissallow it
php_admin_value allow_url_fopen 0
# Do not show detailled headers with apache, apache modules, and php version
php_admin_value expose_php      0
# safe_mode is more buggy than no safe mode
php_admin_value safe_mode       0
{% endhighlight %}

Now, let's explain them from the end to the top.

**"safe_mode"** is not activated, using the PHP safe_mode is in fact not a "safe" thing and as proven more security problems
than not using it, it will soon be a deprecated option (well, it is deprecated in PHP 5.3).

**"expose_php"** is a not-known-enough PHP setting that set a default header in the HTTP answer if you
do not disable it. In my Apache Virtualhost I've been reading the security file,
and I've set the `"ServerToken Prod"` setting to avoid disclaiming Apache version in the HTTP headers,
cool, it's only saying "Apache" and not "Apache.2.2 (debian ...).  
Now if I do not set this expose_php php settings PHP will add this awfull header:

<pre>
    X-Powered-By: PHP/5.2.10-2ubuntu6.10
</pre>

Funny thing the official documentation say you can only alter it in php.ini, well it works in a VirtualHost

**"allow_url_fopen"**, you may need to allow this if you need to perform includes to some other websites.  
By default I prefer disallowing this setting, as it's the starting point of a lot of security attacks
(bad filtered includes for example).  
When developpers really needs it, they need to buy some beers if they want this setting altered.

**`"include_path"** this is not complelty related to security (but ùaitain it close to open_basedir, easier to maintain).
It's the path where PHP will search when you gives it a filename to include which is not **absolute**.  
You should keep this list quite short. So having your project path here, and not the others,
is quite important, do not forget the dot, it means the **"current directory"**.  
And if you use PHP extensions (like, maybe, apc) you may need to help includes in the places
where these common extensions are shared.

**"open_basedir"** this is **the most important setting**. And maybe the one giving you some errors after activation.
PHP will not be able to work in a directory which is not listed there.  
So you'll need your project web directory (the `www` inside the project) but also the temporary directory
(not `/tmp` for us) and the shared libraries directories.   
The important thing is to prevent inclusion of your OS's `/etc` and of other projects files (like with `/tmp`)

####Some other useful things####

{% highlight apache %}
# Maximum amount of time each script may spend parsing request data
php_value max_execution_time            "300"
# Maximum amount of memory a script may consume
php_value memory_limit                  "32M"
 
# Sessions: IMPORTANT reactivate garbage collector on Debian!!!
php_value session.gc_maxlifetime        3600
php_admin_value session.gc_probability  1
php_admin_value session.gc_divisor      100
{% endhighlight %}

So here after 300s (4minutes) a PHP script will be killed.  
Then we limit the memory usage of any Apache process running this website to 32M.  
Some bad Drupal developpers will cry and ask for 128M, but, hey, who can buy 13Go of RAM just to handle
100 parallel HTTP requests?.  
You may need to alter that for Drupal, which is an heavy RAM-eater. But you may also read my next article
about php-fpm (and ask Makina-Coprus for an audit, why the hell your Drupal needs 128M?)

Notice that we've used **"php_value"** and not **"php_admin_value"** for some of these settings,
it means that for a given Drupal method, for a given HTTP request, deep in the code, you may use **ini_set()**
functions to alter theses settings (like asking for 128M of RAM for one request or allowing for more time).

Last point as a comment which says all, on Debian the PHP garbage collector is inactivated
(to use a debian script cleaning the `/var/lib/php5` session directory).  
Problem, Drupal is not using PHP default session management, and needs the garbage collector
call to perform session cleanups. If you forgot that, you may get a session table in Drupal
growing until your `/var/lib/mysql` partition gets full (and this may let you in a quite bad
situation -- hopefully the drupal server will maybe start to be quite slow when requesting
the millions of rows session table and you will see it before)

###Apc and Memcache settings?###

Want some more? Here are some settings for classical APC or memchache usage (via php-memcache, not php-memcached).

For APC some settings musn't be altered on each VirtualHost,
they're shared, so they should be global to the Apache server.   
Alter theses settings in the real php.ini or /etc/php5/conf.d/apc.ini file:

{% highlight apache %}
# Shared Memory
# These settings MUS'NT be ALTERED ON A PER-VIRTUALHOST basis
# BUT THEY'RE IMPORTANT, by default you'll get only 30M for the whole
# opcode+user cache, very short, very dangerous (apc emptying cache when full)
# SO YOU MUST ALTER DEFAULT APC CONFIGURATION on SHARED MEMORY
apc.shm_segments=1
apc.shm_size=128
apc.mmap_file_mask=/apc.shm.XXXXXX
{% endhighlight %}

Here we ask for 128M of shared memory.  
The default is 30M because most OS will not allow you to ask for 128M or 256M.  
To allow 128M Put in `/etc/sysctl.conf` at least theses numbers (and load them in sysctl): 

<pre>
kernel.shmmax=134217728
kernel.shmall=2097152
</pre>

Now for the Virtualhost here are some settings:

{% highlight apache %}
php_admin_flag  apc.enabled                     1 
# file upload progress bar available
php_admin_value apc.rfc1867                     1
 
# ON a VirtualHost basis we can tune theses APC settings
# want to gain speed? ------------------
# Optimisation of include/require_once calls
php_admin_value apc.include_once_override       1
# transform paths in absolute ones (no effect if apc.stat is not 0), files from stream wrappers (extended includes)
# won't be cached if this is activated as they cannot be used with php's realpath()
php_admin_flag  apc.canonicalize                1
# In production set it to 0, then file changes won't be observed before apache is restarted,
# significant boost, else file time is stated at each access (needed at 1 in dev)
php_admin_flag apc.stat                         0
# avoid problems with rsync or svn not modifying mtime but only ctime
# so if you're in production set this to 1, like for the previous one
php_admin_flag apc.stat_ctime                   0
 
# deprecated option: apc.optimization not available anymore
#php_admin_flag apc.optimization               0
 
# indication on number of files (ZF=1300, nude Drupal 7=1000)
php_admin_value apc.num_files_hint              "2000"
 
# indication on the number of cache variables
php_admin_value apc.user_entries_hint           "0"
 
# cache lifetime managmenent ----------------
# time (s) we can stay on the cache even when the cache is full -- Cache full count --
# that means Garbage Collector is never inactivating theses datas before this time is over
# >0 -> old data could stay in the cache while new data want's to come, if no data is deprecated
# 7200 -> entries older than 2 hours will be thrown to make some place
# 0 -> emptying full cache when full
php_admin_value apc.ttl                         "3600"
php_admin_value apc.user_ttl                    "3600"
# this one is the same but you should note this this prevent Garbage collecting after each source change.
php_admin_value apc.gc_ttl                      "3600"
 
# What to cache ? ----------------------------
# could be used to prevent some caching on specific files
# but it's better to cache often used files, isn't it? at least in production
# php_admin_value apc.filters                     "-config.php-.ini"
#default to 1M, files bigger than that won't be cached
php_admin_value apc.max_file_size               "5M"
 
# various things -------------------------------
# only one process caching a same file (beter than apc.slam_defense)
php_admin_flag apc.write_lock                   On
# prevents caching half written files (by cp for example) by waiting x seconds for new files caching. set it to 0 if using only rsync or mv
php_admin_value apc.apc.file_update_protection  "2"
 
# newest versions of APC only
# optimisations from Facebook, adding a lazy loding capabilities, so you can parse a lot of files
# and only used things are cached
# need to be tested
# php_admin_value apc.lazy_functions               1
# php_admin_value apc.lazy_classes                 1
{% endhighlight %}

As stated in the comments, in production you should set the apc.stat & apc.stat_ctime flags to 1.
It will be a lot faster, but APC will not even try to see if the file has been updated on disk.

And for memcache here are some default settings that you could use:

{% highlight apache %}
# Memcache settings (php-memcache, not php-memcached)
# should we try other servers?
php_admin_value memcache.allow_failover        0
php_admin_value memcache.max_failover_attempts 3
# how many copies of the session on different servers (to avoid loosing session on server crash) ?
php_admin_value memcache.session_redundancy    1
# may be the same behavior but for all data
php_admin_value memcache.redundancy            1
# protocol, undocumented, don't kwown what is available instead of ascii
php_admin_value memcache.protocol              ascii
# Data will be transferred in chunks of this size(8192 by default, or 32768 since v3.0.0)
php_admin_value memcache.chunk_size            32768
# default port to connect memcached
php_admin_value memcache.default_port          11211
# consistent is better than default, avoid hash keys being remaped when a new server join
php_admin_value memcache.hash_strategy         consistent
# hash can be crc32 or fnv
php_admin_value memcache.hash_function         crc32
# undocumented
php_admin_value memcache.compress_threshold    2000
# undocumented ...
php_admin_value memcache.maxreclevel           0
php_admin_value memcache.maxfiles              0
php_admin_value memcache.archivememlim         0
php_admin_value memcache.maxfilesize           0
php_admin_value memcache.maxratio              0
 
# session management by memcache.
# needs memcache > 3.0.4 to get session locking, else you may have
# some race conditions with ajax or any parallel query execution in
# the same requests
# Here we use the not-yet-official session proxy drupal module to handle this
# you may check also with memcached module
php_admin_value session.save_handler            memcache
php_admin_value session.save_path               "tcp://127.0.0.1:11211"
{% endhighlight %}

###Closely Related articles###

 * [Better Rewrite Rules for Drupal]({% post_url 2011-09-01-better_rewrite_rules_for_drupal %})
 * [Drupal with Apache & chrooted php-fpm]({% post_url 2011-09-03-Install_drupal_in_php_fpm_fastcgi_and_apache_chroot %})



