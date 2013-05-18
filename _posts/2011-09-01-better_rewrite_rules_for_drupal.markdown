---
layout: post
uuid: 4323720b-b870-4f95-8938-ef0c2dc355d6
title: Better rewriteRules for Drupal
categories: [Drupal, English]
tags: [Drupal, Performance, Apache, PHP, mod_rewrite, Security]
pic: redflower2.png
excerpt: A big re-think of rewrite rules for Drupal, preventing acess from index.php?q=foo default url, no .htaccess, and some other security stuff 

---
Drupal comes with a default set of `Rewrite Rules` in the `.htaccess` file given by the project.

In this article I'll try to provides some recipes for an enhanced mod-rewrite set.

 * getting rid of .htaccess
 * forbid usage of direct requests to `index.php?q=foo` (when clean url is activated)
 * forbid usage of 'new' unwanted PHP scripts appearing in the website (attackers?)
 
###Oh my God, a .htaccess!###

So this will be the first thing, a **must-do**. Drupal Apache configuration is on a `.htaccess` file, and there is a reason for that.
On most places you wont be allowed to alter apache configuration, as **you do not own the server**, and the `.htaccess` file is the
only way for this PHP application to set some apache Directives.  
But let's say this is **your** server, you have **access to Apache configuration**, then a `.htaccess` is the **worst place to put
some configurations details**.  
For each received requests Apache must check existence of `.htaccess` files on the requested file directory and on all the parent
directories, this means a lot of file access, so it's quite **slow**. If you own the server you do not need or want this slowdown.

The rule is quite simple **"Everything found in a `.htaccess` in directory `/this/is/my/dir` can be set in a `<Directory /this/is/my/dir></Directory>`
section in an apache Virtualhost or global configuration."**.  
So first create your **VirtualHost** for this Drupal website (please do not use global configuration,
you do not need to share directives for all your websites). Then we'll make 2 things:

 * prevent the read of any `.htaccess` from the filesystem root, so for all the descendant of `/`
 * transfer the `.htaccess` content in a `Directory` directive
 
For the first thing simply add this (wel I've added the `.svn` and `.git` things as well):

{% highlight apache %}
<Directory  /  >
    Order deny,allow
    deny from all
    Options FollowSymLinks
    # PREVENT .htaccess reading
    AllowOverride None
 
    #.svn & .git directories must be avoided!!
    RedirectMatch 404 /\.svn(/|$)
    RedirectMatch 404 /\.git(/|$)
</Directory>
{% endhighlight %}

Notice that this does not concern the `'/'` url (that would be `<Location />`) but the `'/'` **directory on the server**,
means the `'C:\'` if you were a windows user.  
`Location` directives works on the url, `Directory` directives works on the **filesystem tree** (absolute path).

Then add another `Directory` directive, with the absolute path of your project web root
(this should be the same as the `DocumentRoot` directive of this Virtualhost). And put inside the `.htaccess` content.

{% highlight apache %}
<Directory /var/www/mydrupalproject/www>
        #Order allow,deny
        Allow from all
 
        # Follow symbolic links in this directory.
        Options +FollowSymLinks -Indexes -Multiviews
         
        # Set the default handler.
        DirectoryIndex index.php
 
        # Protect files and directories from prying eyes.
        <FilesMatch "\.(engine|inc|info|install|make|module|profile|test|po|sh|.*sql|theme|tpl(\.php)?|xtmpl)$|^(\..*|Entries.*|Repository|Root|Tag|Template)$">
          Order allow,deny
        </FilesMatch>
         
        # Force simple error message for requests for non-existent favicon.ico.
        <Files favicon.ico>
          # There is no end quote below, for compatibility with Apache 1.3.
          ErrorDocument 404 "The requested file favicon.ico was not found.
        </Files>

        etc
        (...)
         
</Directory>
{% endhighlight %}

What does this as to do with **mod-rewrite**? Well mod-rewrites behave quite the same in a `Directory` directive and in a `.htaccess`,
but faster here, and without the need of any `rewriteBase` prefix.  
You could even use mod-rewrite in the VirtualHost, in a global way, not in the `Directory` section, that would even be faster.  
But for Drupal rules we need the `SCRIPT_FILENAME` and even using `LUA` hacks on mod-rewrite we would not get a big gain.
So we'll keep the mod-rewrite rules in this Directory `/var/www/mydrupalproject/www` section.

###Let's check what are the default rules###

So, if we do not care about the final mod-rewrite rules about gzip contents the main rules defined by Drupal are:

{% highlight apache %}
# always activate modRewrite on this directory
# (do not forget it, even if you activated it on the Virtualhost)
RewriteEngine on
 
# test the requested document is not a real file (like a css or js or even index.php or update.php)
RewriteCond %{REQUEST_FILENAME} !-f
 
# test the requested document is not a real directory
RewriteCond %{REQUEST_FILENAME} !-d
 
# test the requested document is not the favicon.ico (if you do not have one,
# else it would have been catched by the first test). As we do not want to launch
# the whole Drupal environment to imply return a 404 for the favicon.
# you could see other apache rules for this with the File directive
RewriteCond %{REQUEST_URI} !=/favicon.ico
 
# still there, ok so take the whole request things (without the hostname) and give it to
# the index.php file in the 'q' GET argument. Then stop the rewriting process (L) and add any
# GET argument after a ? in the request after this q argument (QSA)
RewriteRule ^(.*)$ index.php?q=$1 [L,QSA]
{% endhighlight %}

in Drupal 6. And Drupal7 added a new rule before this one which is:

{% highlight apache %}
# catch anything starting with a dot and return a 403 Forbidden
RewriteRule "(^|/)\." - [F]
{% endhighlight %}

The only goal of this rule is to avoid access on directory with a dot in the name (such as .git or .svn).  
So if you used the `Redirect` instructions on the root directory section as I did you do not need to activate this rule.
Always remember that simple `Redirect`, `RedirectMatch`, `Alias`, `File`, `FileMatch` directives in Apache may perform really
faster than a `rewriteRule`, check this official ["when not to use mod-rewrite" section](http://httpd.apache.org/docs/current/rewrite/avoid.html) in mod-rewrite documentation.

So, this default **'everything not existing to index.php'** rule does the job, of course.  
When **clean url** is not activated all your url are already in the `index.php?q=foo` form and when clean url is activated
this rule make the transformation.

But we still have some things to make better:

##We have clean url, we want to force usage of clean urls##

Now that you have activated clean url in Drupal (or you should, really).  
Instead of requesting `http://example.com/index.php?q=/admin` you can request `http://example.com/admin`.  
That's cool, and you could apply some url-based settings with your proxy or directly in apache,
let's say everything in `/admin` or `/user` is restricted to some IP only, etc.

But **nothings prevents a malicious user to use the direct `?q=foo` form of the url**.
And if we're talking about security, access to `/admin` could be done via several urls:

 * http://example.com/index.php?q=/admin
 * http://example.com/index.php?q=/////admin
 * http://example.com/index.php? %71=/////%61dmin
 * http://example.com/index.php?q=titi& %71=/////%61dmin
 * ...

Benoit once tried to prevent all theses access with mod-rewrite in this [article](http://www.makina-corpus.org/blog/how-prevent-access-drupal-admin-url-apache-and-mod-rewrite).
But a condition filtering theses requests, only on `/admin`, would be (AFAIK):

{% highlight apache %}
RewriteCond %{QUERY_STRING} (^|&|%26|%20)(q|Q|%71|%51)(=|%3D)(/|%2F)+?(a|A|%61|%41)(d|D|%64|%44)(m|M|%6D|%4D)(i|I|%69|%49)(n|N|%6E|%4E)(/|%2F|&|%26|$) [NC]
{% endhighlight %}

Which is pretty **awfull**.

The **real solution** is **to prevent any direct via the `q=xxx` argument**.  
But that mean as well without restricting the real final Drupal request on `index.php` with this `q=xxx` argument. This is the way to do it:

{% highlight apache %}
# always activate modRewrite on this directory
# (do not forget it, even if you activated it on the Virtualhost)
RewriteEngine on
######### START RULE 1 ##################################
# clean url is activated so ALL urls
# MUST be accessed on /too/titi and MUSN'T be accessed on index.php?q=/toto/titi
# main reason is that applying url rules (like restricting /admin access is far easier
# in the clean url form than in parameter form
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
 
#detect non-blank QUERY_STRING (some parameters are present after the ?)
# else we have nothing to fear about blank queries
RewriteCond %{QUERY_STRING} . [NC]
 
# we prevent any query with a q= parameter
RewriteCond %{QUERY_STRING} (^|&|%26|%20)(q|Q|%71|%51)(=|%3D). [NC]
 
# 403 FORBIDDEN !
RewriteRule .* - [F,L]
########## END RULE 1 ###################
 
########## START RULE 2 ###################
# Clean url handling
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
 
# put everything still there to Drupal index.php
# [L]= stop rewriting here for matching rules
# [QSA]=Appends any query string created in the rewrite target
# to any query string that was in the original request URL
RewriteRule ^(.*)$ index.php?q=$1 [L,QSA]
########## END RULE 2 ###################
{% endhighlight %}

Without the comments, for reference:

{% highlight apache %}
RewriteEngine on
 
RewriteCond %{ENV:REDIRECT_STATUS} ^$
RewriteCond %{QUERY_STRING} . [NC]
RewriteCond %{QUERY_STRING} (^|&|%26|%20)(q|Q|%71|%51)(=|%3D). [NC]
RewriteRule .* - [F,L]
 
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteCond %{REQUEST_URI} !=/favicon.ico
RewriteRule ^(.*)$ index.php?q=$1 [L,QSA]
{% endhighlight %}

###WTF: what is this hackme.php file in this javascript library?###

So, Drupal needs only direct access to the index.php file, usually.  
We could see as well some other php files that could be used to bootstrap Drupal:

 * cron.php
 * xmlrpc.php
 * install.php
 * update.php

Remember the Condition `RewriteCond %{REQUEST_FILENAME} !-f`?  
That means any request done directly on one of these 4 files will be allowed.  
You should really use some Location directives to restrict access to `cron.php` to `127.0.0.1`,
and maybe filter `update.php` and `install.php` to some IP as well.  
And do you need `xmlrpc.php`? I'm not saying these files have known security issues, but if someone
someday fond one ... And for the `cron.php` file, this is a good script to request to perform a
nice `DOS` with a few requests. This is an example of restrictions for cron.php:

{% highlight apache %}
# Limit cron.php access to localhost only
<Location /cron.php>
    Order deny,allow
    deny from all
    allow from 127.0.0.1
</Location>
{% endhighlight %}

But if you think you'll never need to access the other files (or that you will alter apache configuation when needed),
you can also add in the VirtualHost (see, no need of mod-rewrite for simple redirects):

{% highlight apache %}
 Redirect temp /update.php http://www.example.com/index.php
 Redirect temp /install.php http://www.example.com/index.php
 Redirect temp /xmlrpc.php http://www.example.com/index.php
{% endhighlight %}

But now, let's perform a little find on your Drupal project to see if some other php files aren't there in the web directory
root (so allowing direct access):

{% highlight bash %}
find /var/www/mydrupalproject/www -name \*.php
{% endhighlight %}

Ouch, at least **62 files**, from a basic **nude** Drupal.  
We're not in a Zend Framework project here (result would be 1), every library is on the document root, like in the 90's !  
So... well each of these files can be requested, but the code is clean and they will not hurt you.
But now you should check very carefully this list, are all these PHP files done by Drupal coders?  
The bad news is that you can sometime find php file with javascript libraries, containg 10 or 20 lines of PHP to make some demos
in the `/example` subdirectory of the js lib. And things in these files can be very awfull in term of security.  
On a production server you may also find some new php files, coming from an infected FTP software, that's really bad,
in a short time google will prevent any browser access to your website!

So the solution? **prevent any access to a php file which is not one of index.php, cron.php, update.php and install.php (and maybe xmlrpc.php)**  
Just add this last rule:

{% highlight apache %}
########## START RULE 3 ###################
# deny direct access to php files which aren't
# index.php or update.php or install.php or xmlrpc.php or cron.php
# (like an injected phpinfo.php)
###########################################
RewriteCond %{ENV:REDIRECT_STATUS} ^$
RewriteCond %{REQUEST_FILENAME} -f
RewriteCond %{REQUEST_FILENAME} .*\.php
RewriteCond %{REQUEST_FILENAME} !(update\.php|index\.php|install\.php|xmlrpc\.php|cron\.php)
RewriteRule .* - [F,L]
########## END RULE 3 ###################
{% endhighlight %}

###Need to debug? Questions?###

First, notice that you should **not** use **Rule1** while clean url is not activated
(as it forbid direct usage of Drupal without clean url urls).  
If you want to make some more rules, or debug what mod-rewrite is doing for one request add theses settings in the VirtualHost
(**not** on the `Directory` section like the rules):

{% highlight apache %}
RewriteEngine on
# debug mod_rewrite
RewriteLogLevel 9
RewriteLog /tmp/rewritelog.log
{% endhighlight %}

Then a `"tail -f /tmp/rewritelog.log"` will show you a lot of things.
Do not do that on a production server.  
You may get too much informations when using a classical browser, you'll get the gzipped content, extra rules applied,
and all static file requests.  
Check [this previous article]({% post_url 2009-11-05-use_rewrite_map_to_prevent_proxying_for_some_static_contents %}) on how to perform a single request for a single page with a one-liner.

For any other help check theses links (or comment, or send me an email)

 * [Mod rewrites pages (all languages)](http://httpd.apache.org/docs/current/rewrite/)
 * [Server Fault (en)](http://serverfault.com/)
 * [Stack Overflow (en)](http://stackoverflow.com/)
 * [Drupal Answers (en)](http://drupal.stackexchange.com/)
 
###Closely Related articles###

 * [Tune your php settings for Drupal]({% post_url 2011-09-02-Tune_your_php_settings_for_drupal %})
 * [Drupal with Apache & chrooted php-fpm]({% post_url 2011-09-03-Install_drupal_in_php_fpm_fastcgi_and_apache_chroot %})
