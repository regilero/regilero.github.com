---
layout: post
uuid: 039d0a71-89a0-41dd-a6ad-5c03f4b2911a
title: Install Drupal in php-fpm (fastcgi) with Apache and a chroot php-fpm
categories: [Drupal, English]
tags: [Drupal, Apache, PHP, PHP-fpm, Security]
pic: blackbee.png
excerpt: Step by step Apache+php-fpm installation of Drupal with some explanations on how to use php-fpm chroot while still not having mod_proxy_fcgi.

---

Using PHP-fpm is a way to push PHP execution outside of Apache,
one of the main reasons to use it is freeing memory usage of PHP in the apache processes
and allowing usage of a threaded Apache server.

In this article we'll explain what this sentence means :-) and will detail installation
and configuration of php-fpm for a Drupal project.  
We'll try to keep all the good php settings for project separation we used [before]({% post_url 2011-09-02-Tune_your_php_settings_for_drupal %}),
and we'll try to provide a solution to the chrooted php-fpm problems.

##Why do we need php-fpm to solve Apache memory problems with Drupal?##

Well, first you are maybe not needing it.  
But if you experience problems with the memory usage of Drupal
(usually big functionnal websites ask for more than 64M in PHP memory_limit)
and the number of parallel requests handled by apache, then you'll may find
a good solution with php-fpm.

###Apache processes, PHP Memory, Prefork and Worker MPM###

On a basic apache/PHP installation you're quite certainly using PHP as `mod_php`,
it means it's an **Apache module**. And when `memory_limit` is set to `64M`
it means **each** Apache child process can grow up to 64M.
With `mod_php` Apache is enforced in the **prefork** model,
so **each HTTP request use one Apache fork**, with `MaxClient` limit (usually **150** by default).
By default you handle 150 parallel HTTP request.  
But there's also the `KeepAlive` settings, by default **15s** (but please set that to **3s**),
so a forked Apache process stay online with the client browser for that amount of time,
and cannot handle a new request.   
If you use long keepalives, and even with shorts ones, chances are you'll soon need more than
150 in MaxClients to handle parallel incoming HTTP requests.
And here comes the **64M** of RAM per apache process.
If you want to push the MaxClients to 250 : `250 * 64M = 15,6 Go` of RAM!

The **prefork mpm** is the very **old** way to handle incoming requests for Apache.
One of the cool things coming with Apache 2 was the **worker mpm**.
In this mode Apache forks a *few* process (let's say 10 for example) and use threads inside
(from 25 to 75 by default), handling here `10*75 = 750` HTTP requests in parallel.  
It would be quite cool to use that on big websites,
for example all static files (js, css, images, ...) could be handled by parallel Apache threads,
maybe disabling KeepAlive completly, one request, one thread, simple and fast
(well, tests different combinations, it depends).  
But **mod_php cannot be used in the worker mpm**.  
PHP 5 is multithread-enabled, but this is not the case for all PHP libraries.
Check documentation warnings on `setlocale()`, here if you have several languages in your websites,
you may have mixed languages in the output if parallel threads in Apache are calling different `selocale()`, quite bad.
And you could encounter this with a lot of PHP extension, hard to find, hard to debug,
this is why mod_php is always used with the old prefork model.

##PHP as fastcgi##

So we're not using all capabilities of Apache because of PHP? That's sad.  
But if you extract PHP from Apache and run it in his own daemon then Apache is simply acting as a proxy of your PHP content generation.  
This is one of the main ideas in `%cgi%` things.
PHP is not only available as mod_php (apache module), it can be used in cli (command line interface), so it can be used as cgi.

Strictly speaking cgi is a slow thing, this is why **fastcgi** exists, and in the fastcgi familly there's quite a lot of possibilities
(fastcgi fcgid, etc). I'm too lazy to explain them all.

The important thing is that **php-fpm** is a way to **run php as a fastcgi**.  
When Apache 2.2.4 will be there (or if you are brave enough to use Apache unstable 2.2.3),
the right way to connect Apache and php-fpm will be the Apache module [mod_proxy_fcgi](http://httpd.apache.org/docs/2.4/fr/mod/mod_proxy_fcgi.html).
The name says all, Apache is simply proxying a fastcgi thing outside, which produces results for each given HTTP request.  
Waiting for that we'll instead use the apache module mod_fcgi.  
It works quite well, but the behaviour is not as simple and clear as the proxy behavior.
Some Apache environment variables are still transfered to this module,
and we'll see that using php-fpm in a chrooted environment for each project will be a little more complex
than what it would be with the future **mod_proxy_fastcgi**, anyway I'll explain a solution so we can now start the install.

##Installing php-fpm on Debian step by step##

This step by step was tested on a Debian squeeze (6.0).  
You'd better start it on a fresh install.
Installing php-fpm on a server where mod_php with Apache in mpm_prefork is still needed is not possible.

###Adding dotdeb & non-free repositories###

We'll need the dotdeb repository

Add this line in /etc/apt/sources.list

{% highlight bash %}
    deb http://packages.dotdeb.org stable all
{% endhighlight %}

then add the GnuPG key

{% highlight bash %}
    wget http://www.dotdeb.org/dotdeb.gpg
    cat dotdeb.gpg | sudo apt-key add -
    rm dotdeb.gpg
{% endhighlight %}

Apache mod_fcgi is needed to link php-fpm (and not apache-fcgid) so add the non-free repository

{% highlight bash %}
  # need non-free packages for FCGI (not FCGID)
  deb http://ftp.fr.debian.org/debian/ squeeze contrib non-free
  deb-src http://ftp.fr.debian.org/debian/ squeeze contrib non-free
{% endhighlight %}
  
Then add contrib and non-free tags to the squeeze-update line to get:

{% highlight bash %}
  # squeeze-updates, previously known as 'volatile'
  deb http://ftp.fr.debian.org/debian/ squeeze-updates main contrib non-free
  deb-src http://ftp.fr.debian.org/debian/ squeeze-updates main contrib non-free
{% endhighlight %}

And now that we set all the sources reload the sources informations

{% highlight bash %}
  apt-get update
{% endhighlight %}

###Adding packages###

For PHP we'll need some packages, do that before installing apache packages, simplier

{% highlight bash %}
  apt-get install php5 php5-fpm php-pear php5-common php5-mcrypt \
    php5-mysql php5-cli php5-gd php5-curl php5-apc
{% endhighlight %}

And now enforce Apache with the worker mode (using php-fpm with apache in prefork is useless)

{% highlight bash %}
  apt-get install apache2-mpm-worker libapache2-mod-fastcgi
{% endhighlight %}

###Apache modules configuration###

We activate the apache modules fascgi and actions

{% highlight bash %}
    a2enmod fastcgi actions
{% endhighlight %}

We add some more useful modules, headers, expires, status and rewrite

{% highlight bash %}
   a2enmod expires headers status rewrite
{% endhighlight %}

And while we are working with apache modules let's removed some useles ones (this will reduce the memory footprint of Apache).
But check that in your own installation you do not need them. 
 
 * **autoindex** is this awfull thing listing your directory contents when you forget to protect a directory, 
 * **cgid** is a pure cgi module (still running à perl cgi app from 1995?) 
 * and **negotiation** allows some languages negociation in the HTTP protocol between the browser and the server -- you may need it, I don't--
it could also choose to use a file with same name as the request but not the right extension, strange behavoirs incoming!

{% highlight bash %}
    a2dismod autoindex cgid negotiation
{% endhighlight %}

We add cronolog to avoid apache slowing because of log tasks. But this is not something required for php-fpm :-)

{% highlight bash %}
apt-get install cronolog
{% endhighlight %}
 

Usage of cronolog in your apache configuration is quite simple, instead of writing this:

{% highlight apache %}
ErrorLog /var/www/myproject/var/log/error-myproject.log
CustomLog /var/www/myproject/var/log/access-myproject.log combined
{% endhighlight %}

You will use that:

{% highlight apache %}
ErrorLog "|nice -n 10 /usr/bin/cronolog /var/www/myproject/var/log/%Y/%W/%d-myproject-error.log
CustomLog "|nice -n 10 /usr/bin/cronolog /var/www/myproject/var/log/%Y/%W/%d-myproject-access.log" combined
{% endhighlight %}

###Project Tree###

We'll use the project tree defined in a [previous article]({% post_url 2011-09-02-Tune_your_php_settings_for_drupal %}).
This article was about tunning the PHP configuration, but is also managing project trees,
so that having several Drupal projects running on the same host you encapsulate nicely each project in his own environment.  
We will still try to encapsultate each php-fpm Drupal project **in a separate environment** so everything stated there should
still apply in our new way of working.

In this tree everything was in `/var/www/nameoftheproject`, I'll add a company prefix, so the base of the tree for my projects
are `/var/www/makina/nameoftheproject`. Inside I have a `www/` directory (`documentRoot`),
an `etc/` directory for configuration files, a `var/` directory for logs and temporary files, etc.

###Minimal fastcgi.conf###

The first thing to edit is the `fastcgi.conf` file in `/etc/apache2/mods-available/fastcgi.conf`

{% highlight apache %}
<ifmodule mod_fastcgi.c="">
         FastCgiIpcDir /var/www/makina/mydrupal/var/fcgi/
</ifmodule>
{% endhighlight %}

Which may be smaller than thee default one you may have. Most of these things will be set in the VirtualHost configuration instead.

As you can see we need a `var/fcgi` directory in our project tree.  
It will be used to store the **socket** making the connection between apache and php-fpm.

{% highlight bash %}
    mkdir -p /var/www/makina/mydrupal/var/fcgi/
{% endhighlight %}
    
We will leave the Apache configuration for a while and start the configuration of **php-fpm**,
we'll get back on Apache with the VirtualHost, later.

##FPM configuration##

###Main php-fpm configuration###

Backup conf example

{% highlight bash %}
    mv /etc/php5/fpm/pool.d/www.conf /etc/php5/fpm/pool.d/www.conf.orig
    cp /etc/php5/fpm/php-fpm.conf /etc/php5/fpm/php-fpm.conf.bak
{% endhighlight %}

Now edit the main php-fpm configuration file `/etc/php5/fpm/php-fpm.conf` and alter it to get this content
(the most important thing is to really get the include of the **pool.d directory** at the end, and only files ending in `.conf`):

{% highlight php %}
;;;;;;;;;;;;;;;;;;;;;
; FPM Configuration ;
;;;;;;;;;;;;;;;;;;;;;
 
; All relative paths in this configuration file are relative to PHP's install
; prefix (/usr). This prefix can be dynamicaly changed by using the
; '-p' argument from the command line.
 
; Include one or more files. If glob(3) exists, it is used to include a bunch of
; files from a glob(3) pattern. This directive can be used everywhere in the
; file.
; Relative path can also be used. They will be prefixed by:
;  - the global prefix if it's been set (-p arguement)
;  - /usr otherwise
;include=/etc/php5/fpm/*.conf
 
;;;;;;;;;;;;;;;;;;
; Global Options ;
;;;;;;;;;;;;;;;;;;
 
[global]
; Pid file
; Note: the default prefix is /var
; Default Value: none
pid = /var/run/php5-fpm.pid
 
; Error log file
; Note: the default prefix is /var
; Default Value: log/php-fpm.log
error_log = /var/log/php5-fpm.log
 
; Log level
; Possible Values: alert, error, warning, notice, debug
; Default Value: notice
log_level = notice
 
; If this number of child processes exit with SIGSEGV or SIGBUS within the time
; interval set by emergency_restart_interval then FPM will restart. A value
; of '0' means 'Off'.
; Default Value: 0
;emergency_restart_threshold = 0
 
; Interval of time used by emergency_restart_interval to determine when
; a graceful restart will be initiated.  This can be useful to work around
; accidental corruptions in an accelerator's shared memory.
; Available Units: s(econds), m(inutes), h(ours), or d(ays)
; Default Unit: seconds
; Default Value: 0
;emergency_restart_interval = 0
 
; Time limit for child processes to wait for a reaction on signals from master.
; Available units: s(econds), m(inutes), h(ours), or d(ays)
; Default Unit: seconds
; Default Value: 0
;process_control_timeout = 0
 
; Send FPM to background. Set to 'no' to keep FPM in foreground for debugging.
; Default Value: yes
;daemonize = yes
 
;;;;;;;;;;;;;;;;;;;;
; Pool Definitions ;
;;;;;;;;;;;;;;;;;;;;
 
; Multiple pools of child processes may be started with different listening
; ports and different management options.  The name of the pool will be
; used in logs and stats. There is no limitation on the number of pools which
; FPM can handle. Your system will tell you anyway :)
 
; To configure the pools it is recommended to have one .conf file per
; pool in the following directory:
include=/etc/php5/fpm/pool.d/*.conf
{% endhighlight %}

###php-fpm Pool configuration###

The **pool** is your project.  
php-fpm can run several pools, we'll use one for each separate project.  
So for a project named *mydrupal* we'll use a file `/etc/php5/fpm/pool.d/mydrupal.conf`.

you can read the `/etc/php5/fpm/pool.d/www.conf.orig` file to see what a default pool can contain.
The most important parameters are **prefix** and **chroot**.  
A complete pool configuration is given a few lines below. But before reading it we'll need to understand the **chroot problem**.

###Chrooted php-fpm###

As said before **mod_proxy_fcgi** will soon be the right way to connect Apache and php-fpm, especially if you want chrooted php-fpm instances.

In **mod_fastcgi** we cannot alter `DOCUMENT_ROOT` and `SCRIPT_FILENAME` environment variables,
and these variables contain the **non-chrooted informations**.  
I made a lot of tests with **mod_rewrite**, php **auto_prepend_file**, etc, no way to fix that.  
While waiting for that solution the only *'solution'* is to **rebuild the real path** in the php-fpm's pool chroot
and **link the www directory to the real one**.

Without the chroot things are quite simple, you can try it before if you want.  
With the chroot options in php-fpm we enforce the php-fpm execution in `/var/www/makina/mydrupal` (the pool prefix).  
No way to get to a parent directory. Fine for parallel projects security.  
But php-fpm receive a `DocumentRoot` from apache, telling it should move (cd) into `var/www/makina/mydrupal/www`.  
Well we're already quite there, we would like just a move to `www/`, but for php-fpm this means it needs to go to 
`/var/www/makina/mydrupal/var/www/makina/mydrupal/www`... And no way to alter this document root and script filename received instructions.

So in our working project `/var/www/makina/mydrupal` where php files are in `www/` we do **a symbolic link** of this too long path 
to the short one we would like to have:

{% highlight bash %}
    export $pool=mydrupal
    cd /var/www/makina/$pool
    mkdir -p var/www/makina/$pool
    # warn, not absolute /var... but relative var/....
    cd var/www/makina/$pool
    ln -s ../../../../www/ www
{% endhighlight %}

Yes, **that's ugly**, but at least we can now have a working php-fpm pool which is chrooted in `/var/www/makina/mydrupal`.  
Wait for **mod_proxy_fcgi** or avoid using chroot in php-fpm if you do not want that.

The final tree is:

<pre>
/ ==> [/ for everyone except the chrooted php-fpm]
  \-/var/
    \-www/
      \-makina/
        \-mydrupal/ [base of the chroot for php-fpm (/ for him)
          \-etc/
          \-doc/
          \-www/ ===> [A], DocumentRoot, here is Drupal
          \-var/
            \-tmp/
            \-log
            \-www/ ==> empty
              \-makina/ ==> empty
                \-mydrupal/ ==> empty
                  \-www/ ===> symbolic link to [A]
</pre>

**Warning**: see update at the end of article, there is maybe one way of not doing that

Let's have a look at this pool configuration file (`/etc/php5/fpm/pool.d/mydrupal.conf`):

{% highlight php %}
    ; Start a new pool named 'mydrupal'.
    ; the variable $pool can we used in any directive and will be replaced by the
    ; pool name ('mydrupal' here)
    [mydrupal]

    ; Per pool prefix
    ; It only applies on the following directives:
    ; - 'slowlog', 'listen','chroot','chdir','php_values','php_admin_values'
    prefix = /var/www/makina/$pool

    ; The address on which to accept FastCGI requests.
    ;without prefix: listen = /var/www/makina/$pool/var/fcgi/$pool.sock
    listen = var/fcgi/$pool.sock
    listen.allowed_clients = 127.0.0.1
    listen.owner = www-data
    listen.group = www-data
    listen.mode = 0660
    user = www-data
    group = www-data
    pm = dynamic
    pm.max_children = 50
    pm.start_servers = 20
    pm.min_spare_servers = 5
    pm.max_spare_servers = 35
    ;pm.max_requests = 500
    pm.status_path = /myfpmstatus
    request_terminate_timeout = 30s
    request_slowlog_timeout = 10s
    ; WARNING: chroot does not apply on this setting (??)
    slowlog = /var/www/makina/$pool/var/log/$pool.log.slow
    ; Chroot to this directory at the start. This value must be defined as an
    ; absolute path. When this value is not set, chroot is not used.
    chroot = $prefix
    chdir = /
    catch_workers_output = yes
    env[HOSTNAME] = $HOSTNAME
    env[TMP] = /var/tmp
    env[TMPDIR] = /var/tmp
    env[TEMP] = /var/tmp
    env[DOCUMENT_ROOT] = /www
    
    ; Additional php.ini defines, specific to this pool of workers. These settings
   
    php_admin_value[open_basedir] = ".:/www:/var/tmp"
    php_value[include_path]=".:/www:/www/include"

    ; UPLOAD
    php_admin_flag[file_uploads]=1
    php_admin_value[upload_tmp_dir]="/var/tmp"
    ;Maximum allowed size for uploaded files.
    php_admin_value[upload_max_filesize]="50M"
    php_admin_value[max_input_time]=120
    php_admin_value[post_max_size]="50M"

    ;#### LOGS
    php_admin_flag[log_errors] = on
    php_admin_value[log_errors]=1
    ;php_flag[display_errors] = on
    php_admin_value[display_errors]=0
    php_admin_value[display_startup_errors]=0
    php_admin_value[html_errors]=0
    php_admin_value[define_syslog_variables]=0
    php_value[error_reporting]=6143
    ; Maximum execution time of each script, in seconds (30)
    php_value[max_input_time]="120"
    ; Maximum amount of time each script may spend parsing request data
    php_value[max_execution_time]="300"
    ; Maximum amount of memory a script may consume (8MB)
    php_value[memory_limit]="100M"

    ; Sessions: IMPORTANT reactivate garbage collector on Debian!!!
    php_value[session.gc_maxlifetime]=3600
    php_admin_value[session.gc_probability]=1
    php_admin_value[session.gc_divisor]=100

    ; SECURITY
    php_admin_value[magic_quotes_gpc]=0
    php_admin_value[register_globals]=0
    php_admin_value[session.auto_start]=0
    php_admin_value[mbstring.http_input]="pass"
    php_admin_value[mbstring.http_output]="pass"
    php_admin_value[mbstring.encoding_translation]=0
    php_admin_value[expose_php]=0
    php_admin_value[allow_url_fopen]=1
    php_admin_value[safe_mode]=0
    php_admin_value[expose_php]=0

    ; enforce filling PATH_INFO & PATH_TRANSLATED
    ; and not only SCRIPT_FILENAME
    php_admin_value[cgi.fix_pathinfo]=1
    ; 1: will use PATH_TRANSLATED instead of SCRIPT_FILENAME
    php_admin_value[cgi.discard_path]=0

    ; FASTCGI chrooted - HACKING SCRIPT_FILENAME
    ; if any script in the project try to access some $_SERVER
    ; keys that are not ok in php-fpm mode, then use this
    ; script to alter/move the $_SERVER array
    ; the script should be at the root of the project (before the www)
    ; in the chrooted project
    ;php_admin_value[auto_prepend_file]="/fix_phpfpm_env.php"

    ; APC settings ###################
    ; package given from dotdeb is recent
    ; if you don't like it:
    ; apt-get install php-dev php-pear make libpcre3-dev; pecl install apc;
    ; then : echo "extension=apc.so" >> /etc/php5/conf.d/apc.ini
    ; and : echo "extension=apc.so" >> /etc/php5/fpm/conf.d/apc.ini
    ; enabling apc
    php_admin_value[apc.enabled]=1
    # allow progress upload bars
    php_admin_value[apc.rfc1867]=1
    # better require_once engine
    php_admin_value[apc.include_once_override]=1
    # make all path absolutes
    php_admin_value[apc.canonicalize]=1
    # only on PRODUCTION SERVER: do not check for file updates (0)
    # set it to 1 in DEVELOPMENT servers
    php_admin_value[apc.stat]=1
    # Shared memory size
    # check for max SHM in sysctl: sysctl -a|grep shmmax| awk -F'=' '{print $2/1024/1024 " Mo"}'
    # usually 32M. to get greater (like here 64Mo), do:
    # sysctl -w kernel.shmmax=67108864;sysctl -p /etc/sysctl.conf
    php_admin_value[apc.shm_size]=64M
    # thanks facebook for these 2 ones, lazy usage of function from opcode
    # load only required functions & classes on-demand. Effects should be tested
    # for each app
    php_admin_value[apc.lazy_functions]=1
    # last time I've checked this made a WOD on Drupal...
    php_admin_value[apc.lazy_classes]=0
    # better use cli optimizations in fpm mode, no?
    php_admin_value[apc.enable_cli]=1
{% endhighlight %}

###Application VirtualHost###

Now we are going to create our Apache Virtualhost and our php-fpm project.  
You may need to tests things while creating all theses things. So I'll give you a few commands that could help you

####testing apache configuration:####

{% highlight bash %}
  #loading apache env variables (see the dot-space)
  . /etc/apache2/envvars
  # test apache configuration
  apache2 -t
  # list apache virtualhosts
  apache2 -S
  # list apache modules
  apache2 -M
  # restarting php-fpm (yes, not done via apache restart)
  /etc/init.php5-fpm restart
{% endhighlight %}

We need to creat the Apache VirtualHost for our current project.  
We'll put the source in our project directory `etc/` and link it to the main apache virtualhosts repository.  
But you could edit it directly in `/etc/apache2/sites-available` if you want
(I'm in fact even storing the pool configuration here and linking it to `/etc/php5/fpm/pool.d`).

{% highlight bash %}
    touch /var/www/makina/mydrupal/etc/apache.conf
    ln -s /var/www/makina/mydrupal/etc/apache.conf /etc/apache2/site-available/101-mydrupal
    a2ensite 101-mydrupal
{% endhighlight %}

And now we need to write some content inside this `/var/www/makina/mydrupal/etc/apache.conf`.  
And in this Virtualhost we'll need to connect the PHP scripts to the php-fpm.
So I'll first gives you a complete VirtualHost and then we will detail how the php-fpm is managed inside.

{% highlight apache %}
<virtualHost *:80>
    ServerName mydrupal.example.com
    DocumentRoot /var/www/makina/mydrupal/www
    LogLevel debug
    #LogLevel warn
    #LogLevel notice
 
    # Debug mod_rewrite
    #RewriteEngine On
    #RewriteLogLevel 9
    #RewriteLog /tmp/rewritelog.log
 
    # classic
    #ErrorLog /var/www/makina/mydrupal/var/log/error.log
    #CustomLog /var/www/makina/mydrupal/var/log/access.log combined
    # or via cronolog
    ErrorLog "|nice -n 10 /usr/bin/cronolog /var/www/makina/mydrupal/var/log/%Y/%W/%d-mydrupal-error.log
    CustomLog "|nice -n 10 /usr/bin/cronolog /var/www/makina/mydrupal/var/log/%Y/%W/%d-mydrupal-access.log" combined
 
    <Directory / >
            Order deny,allow
            deny from all
            Options FollowSymLinks
            # PREVENT .htaccess reading
            AllowOverride None
 
            #.svn & .git directories must be avoided!!
            RedirectMatch 404 /\.svn(/|$)
            RedirectMatch 404 /\.git(/|$)
    </Directory>
 
    # phpfpm/fastcgi
    # Here we catch the 'false' Location used to inexistent php5.external
    # and push it to the external FastCgi process via a socket
    # note: socket path is relative to FastCgiIpcDir
    # which is set in Main configuration /etc/apache2/mods-available/fastcgi.conf
    <IfModule mod_fastcgi.c>
        # all .php files will be pushed to a php5-fcgi handler
        AddHandler php5-fcgi .php
 
        #action module will let us run a cgi script based on handler php5-fcgi
        Action php5-fcgi /fcgi-bin/php5.external
 
        # and we add an Alias to the fcgi location
        Alias /fcgi-bin/php5.external /php5.external
 
        # now we catch this cgi script which in fact does not exists on filesystem
        # we catch it on the url (Location)
        <Location /fcgi-bin/php5.external>
            # here we prevent direct access to this Location url,
            # env=REDIRECT_STATUS will let us use this fcgi-bin url
            # only after an internal redirect (by Action upper)
            Order Deny,Allow
            Deny from All
            Allow from env=REDIRECT_STATUS
        </Location>
 
    </IfModule>
     
    FastCgiExternalServer /php5.external -socket mydrupal.sock -appConnTimeout 30 -idle-timeout 60
 
    # Project directory
    <Directory /var/www/makina/mydrupal/www>
        Order allow,deny
        Allow from all
 
        # Follow symbolic links in this directory.
        Options +FollowSymLinks -Indexes -Multiviews
        # Set the default handler.
        DirectoryIndex index.php
 
        # Customized error messages.
        ErrorDocument 404 /index.php
 
       # Various rewrite rules.
        <IfModule mod_rewrite.c>
            RewriteEngine on
                ######### START RULE 1##################################
                # cleanurl is activated so ALL urls
                # MUSt be accessed on /too/titi and MUSN'T be accessed on index.php?q=/toto/titi
                # main reason is that applying url rules (like restricting /admin access is far easier
                # in the cleanurl form than in parameter form (check commented rule on QUERY_STRING
                # below as QUERY_STRING as no url decode done in Apache, see that it's harder)
                # WARNING: need to alter any 'q' parameter that could be present
                # on original QUERY_STRING (part after the ?), or something
                # like /toto?q=admin could become a q=toto&q=admin
                # which is finally a q=admin, so we do not restrict
                # this rule to index.php
                #########################################################
                # WARNING: must prevent real internal redirect of :
                # /toto/titi to q=/toto/titi (done in rule 2)
                # to be forbidden, so the rule apply only
                # if the rewriting process is starting
                RewriteCond %{ENV:REDIRECT_STATUS} ^$
 
                #detect non-blank QUERY_STRING (some parameters are present after the ?
                RewriteCond %{QUERY_STRING} . [NC]
 
                # simplier one: we prevent any query with a q= parameter
                RewriteCond %{QUERY_STRING} (^|&|%26|%20)(q|Q|%71|%51)(=|%3D). [NC]
 
                # 403 FORBIDDEN !
                RewriteRule .* - [F,L]
                ########## END RULE 1 ###################
 
                ########## START RULE 2 ###################
                # cleanurl handling
                # for things which aren't real files or dir then
                # take the given url and giv it to index.php?q=...
                ###########################################
                # all url that didn't match ALL previous rewriteCond are still there
                # squeeze real files or directories, if they really exists
                # then Drupal won't be called  
                RewriteCond %{REQUEST_FILENAME} !-f
                RewriteCond %{REQUEST_FILENAME} !-d
 
                # do not handle the favicon with Drupal bootstrap
                RewriteCond %{REQUEST_URI} !=/favicon.ico
 
                # This one is needed in php-fpm mode to avoid infinite redirects
                RewriteCond %{REQUEST_FILENAME} !=/var/www/makina/mydrupal/www/fcgi-bin/php5.external
                # put everything still there to Drupal index.php
                # [L]= stop rewriting here for matching rules
                # [QSA]=Appends any query string created in the rewrite target
                # to any query string that was in the original request URL
                RewriteRule ^(.*)$ index.php?q=$1 [L,QSA]
                ########## END RULE 2 ###################
        </IfModule>
 
        ### DRUPAL ###
        # Protect files and directories from prying eyes.
        <FilesMatch "\.(engine|inc|info|install|make|module|profile|test|po|sh|.*sql|theme|tpl(\.php)?|xtmpl)$|^(\..*|Entries.*|Repository|Root|Tag|Template)$">
          Order allow,deny
        </FilesMatch>
         
        # Make Drupal handle any 404 errors.
        ErrorDocument 404 /index.php
        # Force simple error message for requests for non-existent favicon.ico.
        <Files favicon.ico>
          # There is no end quote below, for compatibility with Apache 1.3.
          ErrorDocument 404 "The requested file favicon.ico was not found.
        </Files>
         
        # Requires mod_expires to be enabled.
        <IfModule mod_expires.c>
            # Enable expirations.
            ExpiresActive On
            # Cache all files for 2 weeks after access (A).
            ExpiresDefault A1209600
            <FilesMatch \.php$>
                # Do not allow PHP scripts to be cached unless they explicitly send cache
                # headers themselves. Otherwise all scripts would have to overwrite the
                # headers set by mod_expires if they want another caching behavior. This may
                # fail if an error occurs early in the bootstrap process, and it may cause
                # problems if a non-Drupal PHP file is installed in a subdirectory.
                ExpiresActive Off
            </FilesMatch>
        </IfModule>

        # Rules to correctly serve gzip compressed CSS and JS files.
          # Requires both mod_rewrite and mod_headers to be enabled.
          <IfModule mod_headers.c>
            # Serve gzip compressed CSS files if they exist and the client accepts gzip.
            RewriteCond %{HTTP:Accept-encoding} gzip
            RewriteCond %{REQUEST_FILENAME}\.gz -s
            RewriteRule ^(.*)\.css $1\.css\.gz [QSA]
 
            # Serve gzip compressed JS files if they exist and the client accepts gzip.
            RewriteCond %{HTTP:Accept-encoding} gzip
            RewriteCond %{REQUEST_FILENAME}\.gz -s
            RewriteRule ^(.*)\.js $1\.js\.gz [QSA]
         
            # Serve correct content types, and prevent mod_deflate double gzip.
            RewriteRule \.css\.gz$ - [T=text/css,E=no-gzip:1]
            RewriteRule \.js\.gz$ - [T=text/javascript,E=no-gzip:1]
         
            <FilesMatch "(\.js\.gz|\.css\.gz)$">
              # Serve correct encoding type.
              Header append Content-Encoding gzip
              # Force proxies to cache gzipped & non-gzipped css/js files separately.
              Header append Vary Accept-Encoding
            </FilesMatch>
          </IfModule>
    </Directory>
 
   <Directory /var/www/makina/mydrupal/var/tmp>
        AllowOverride None
        Order allow,deny
        Allow from all
        # avoid execution of PHP scripts in upload directory
        AddType text/plain .php
        AddType text/plain .phps
    </Directory>
 

   <Directory /var/www/makina/mydrupal/www/sites/default/files>
        AllowOverride None
        Order allow,deny
        Allow from all
        # avoid execution of PHP scripts in uploaded files
        AddType text/plain .php
        AddType text/plain .phps
    </Directory>
 
    <Location /cron.php>
        Order deny,allow
        deny from all
        allow from 127.0.0.1
    </Location>
</VirtualHost>
{% endhighlight %}

This VirtualHost contains some parts of the [previous article]({% post_url 2011-09-01-better_rewrite_rules_for_drupal %})
(like extended rewrite rules) but the main php-fpm things are:

 * an **handler php5-fcgi** for all `.php` files
 * an **action** catching this php5-fcgi telling apache to push that to a file **/fcgi-bin/php5.external** (keep cool, all theses things are virtual)
 * an **alias** catching this **/fcgi-bin/php5.external** and pushing it to the url **/php5.external**
 * a **Location** directive, handling only the **/php5.external** url, where we enforce the fact this url cannot be accessed directly, only via internal redirects (so from all the previous points here)
 * The connection of a **virtual file name php.external** to a **fastcgi service**, via a given socket. It's the line containing `FastCgiExternalServer`.

So that's all. Any HTTP request for something not static or rejected ends to Drupal's index.php,
which is then redirected internally to the virtual external file (php.external),
where it's connected to a socket mydrupal.sock which is relative to the `FastCgiIpcDir` we defined previously,
so it's `/var/www/makina/mydrupal/var/fcgi/mydrupal.sock`.   
This is the socket used for the communication channel between php-fpm and Apache.  
In the php-fpm pool configuration we defined this same socket with the listen command
(without prefix: `/var/www/makina/mydrupal/var/fcgi/mydrupal.sock` and with the chroot and prefix: `listen = var/fcgi/mydrupal.sock`).

###File access rights###
We need to apply some rights for the apache user.  
Basically the www-user needs **read access** to the Web Document Root and some **write** rights on the `sites/default/files` directory.

Here is a list of commands that should do the trick, could certainly be done in other ways (like more restrictive, I'll update it one day).

{% highlight bash %}
 echo "apply ownership"
 chown -R root:www-data /var/www/makina/mydrupal/*
 echo "default directories read rights"
 find /var/www/makina/mydrupal/www \( -type d -wholename "/var/www/makina/mydrupal/www/sites/default/files" -prune \) -o -type d -exec chmod 2750 {} \;
 echo "default files read rights"
 find /var/www/makina/mydrupal/www  \( -type f -wholename "/var/www/makina/mydrupal/www/sites/default/files" -prune \) -o -type f -exec chmod 0640 {} \;
 echo "directories write rights"
 find /var/www/makina/mydrupal/www/sites/default/files -type d -exec chmod 2770 {} \;
 echo "files write rights"
 find /var/www/makina/mydrupal/www/sites/default/files -type f -exec chmod 0660 {} \;
 chown root:www-data /var/www/makina/mydrupal/
 chown root:www-data /var/www/makina/mydrupal/var/fcgi
 chmod 2770 /var/www/makina/mydrupal/var/fcgi
 chown -R root:www-data /var/www/makina/mydrupal/var/tmp
 chmod 2770 /var/www/makina/mydrupal/var/tmp
{% endhighlight %}

###Starting & Stoping Apache & PHP###

Remember that php-fpm is not anymore linked to apache, so you'have an init script for php as well.

{% highlight bash %}
    /etc/init.d/php5-fpm [start|stop]
{% endhighlight %}

Exactly like mysql or apache2. You may check that the /etc/rc*/ files are there for the startup scripts

{% highlight bash %}
    ls -alh /etc/rc*.d/???php5-fpm
{% endhighlight %}
    
##Final steps, Database & Settings##

No surprises here, I'm quite sure you know how to perform all theses steps. But that's a step by step, so here are the last ones

Well, in fact you may have one surprise in the settings.php

{% highlight bash %}
    apt-get install mysql-server-5.1
{% endhighlight %}

Create database and user for application (alter the default passwords and users of course):

{% highlight sql %}
    mysql -u root -p
    > CREATE DATABASE mydrupal CHARACTER SET utf8 COLLATE utf8_bin;
    > GRANT ALL PRIVILEGES ON mydrupal.* TO mydrupaluser@localhost IDENTIFIED BY 'mydrupaluserpassord';
    > FLUSH PRIVILEGES;
{% endhighlight %}

Alter application conf to use real database user and paths. For drupal it's usually in `[project root]/www/sites/default/settings.php`.

Import the project dump if it's already available, or get to the `http://mydrupal.example.com/install.php` url (or use `drush install`).

{% highlight bash %}
   mysql -u mydrupaluser --password="mydrupaluserpassord" --character-set=utf8 mydrupal < /var/www/makina/mydrupal/sql/dump.sql
{% endhighlight %}

###Where's my surprise in the settings.php?###

Yes, if you defined previously the temporary directory in the settings file, which is a very good place to define it
(I'm not a very good fan of configuration stored in database), you may have something like:

{% highlight php %}
    $conf['file_directory_temp'] = '/var/www/makina/mydrupal/var/tmp';
{% endhighlight %}

Or even

{% highlight php %}
    $conf['file_directory_temp'] = '/tmp';
{% endhighlight %}

But now we're in a chroot, the new path is:

{% highlight php %}
    $conf['file_directory_temp'] = '/var/tmp';
{% endhighlight %}
    
And the same thing apply for any filesystem related setting in drupal (but you should not have a lot of them).


##Update. Avoid chroot symlink hack with doc_root php setting?##

A very nice backtrack.

 * [http://auntitled.blogspot.com/2011/10/chroot-php-fpm-and-apache.html](http://auntitled.blogspot.com/2011/10/chroot-php-fpm-and-apache.html)
 
The autor finally found a useful usage of php [doc_root](http://www.php.net/manual/en/ini.core.php#ini.doc-root) setting and explain it could help avoiding the fake document root symnlink inside the chroot.

###Closely Related articles###


 * [Warning Chrooted php-fpm and Apc with multiple pools]({% post_url 2013-05-16-Warning_chrooted_php_fpm_and_apc%})
 * [Better Rewrite Rules for Drupal]({% post_url 2011-09-01-better_rewrite_rules_for_drupal %})
 * [Tune your php settings for Drupal]({% post_url 2011-09-02-Tune_your_php_settings_for_drupal %})



