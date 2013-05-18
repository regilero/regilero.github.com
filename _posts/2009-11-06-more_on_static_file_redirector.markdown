---
layout: post
uuid: 6eab1ca2-20a3-4051-8880-57776d835d35
title: More on Static file redirector
categories: [Apache, English]
tags: [HTTP, Plone, Performance, Proxy, mod_rewrite, RewriteMap, Security]
pic: blueflower.png
excerpt: Complements on the previous article. hash the file map, use a /static url, and avoid security problems with tis new mode.  
previous: 2009-11-05-use_rewrite_map_to_prevent_proxying_for_some_static_contents

---

So On [a previous blog entry]({% post_url 2009-11-05-use_rewrite_map_to_prevent_proxying_for_some_static_contents %})
I presented the basics for a rewriteRule settings to serve some targeted plone static files directly from apache and
without proxying to Plone.

This article, in short introduce apache as a proxy for most pages but as a direct file server for static ressources,
having a map of application url to filesystem real files stored in a text file and served via RewriteMap.

No let's make this solution even better. 

 * use a **hash map** for url mappings
 * create a virtual `/static` url and apply some cache managment rules on his contents
 * allow the use of the `/satic/` url directly
 * ensure only mapped static files are served via this static directory

So first thing to change, we used a simple text file for the mapping, mod_rewrite allows us to use a **hash file**.  
Simply change:

{% highlight apache %}
RewriteMap statics txt:/var/www/proxyplone/etc/staticplonefiles.txt
{% endhighlight %}

by:

{% highlight apache %}
# RewriteMap statics txt:/var/www/proxyplone//etc/staticplonefiles.txt
# to generate hash version of previous file use (do not forget the rm):
# rm /var/www/proxyplone//etc/staticplonefiles.map; 
# httxt2dbm -i /var/www/proxyplone/etc/staticplonefiles.txt -o /var/www/proxyplone/etc/staticplonefiles.map
RewriteMap statics dbm:/var/www/proxyplone/etc/staticplonefiles.map
{% endhighlight %}

And to generate the .map file simply read the comments.   
One important point, if you do not remove the old map before generating the new one,
old entries are still in the .map, to see it without too much garbage use :

{% highlight apache %}
strings /var/www/proxyplone/etc/staticplonefiles.map
{% endhighlight %}

Ok, so now let's look the current RewriteRule,
for matched elements the rewrite is done and the file is directly served.
We would like to add some apache settings to theses files,
the solution is to add the `[PT]` (pass-through) option to the rewrite rule.  
Then Apache will continue to analyse the resulting url as if it were an original
requested url.   
That mean the proxy settings for example will be applied on it.  
So we will as well add a `/satic` on the resulting url and prevent `/static` to be served by the Proxy.  
The rewriteRule is now:

{% highlight apache %}
RewriteRule ^/(.*\.(ico|png|gif|jpg|jpeg|bmp|css|js)) /static/${statics:$1} [NC,L,handler=default-handler,PT]
{% endhighlight %}

And we add this ProxyPass exception:

{% highlight apache %}
ProxyPass       /static  !
{% endhighlight %}

We now have a virtual `/static` directory with all theses mapped contents inside.
We can use it to getBack the original DocumentRoot,
and to use an alias to point `/static` to our webapp sources (here `/opt/plone/source`).
And then we can add Expires settings from mod_expires on this `/static` location...   
well in fact mod_expires requires a Directory directive so it will be on the `/opt/plone/source` directory.  

Reset DocumentRoot:

{% highlight apache %}
DocumentRoot /var/www/proxyplone/htdocs
{% endhighlight %}

Remove this line:

{% highlight apache %}
Alias / /opt/plone/source/
{% endhighlight %}

And add theses settings:

{% highlight apache %}
Alias /static /opt/plone/source/
<Location /static>
    Options FollowSymLinks
    Order deny,allow
    Allow from all
    DirectoryIndex index.html
    # avoid execution of PHP  scripts
    AddType text/plain .php
    AddType text/plain .php3
    AddType text/plain .phps
</Location>
# adding some cache handling for static files
<Directory /opt/plone/source>
    order allow,deny
    allow from all
    ExpiresActive On
    ExpiresDefault "access plus 1 month"
    ExpiresByType text/css "access plus 1 day"
    ExpiresByType text/javascript "access plus 1 day"
</Directory>
{% endhighlight %}

That's done. **Now we have a big security Hole :-(**.  
Most files from `/opt/plone/source` are available via the `/static` url.   
As `/static` is not proxied anymore and is now an alias on the filesystem directory where we have an allow from all ...  
So we should add some rewriteRules to check which files are allowed via direct access on static.
And by default it should be *none**.
But that's sad, it would be nice to promote good behaviour for theses wtf programmers which aren't admins,
we should let them use `/static` urls for files known to be static.
And maybe one day they'll think it's a good idea to make the distinction between known static files and dynamic content...   
So we'll ask developpers to add some entries in the **staticplonefiles.txt** making a mapping from static/files to real files this way (see, every entry is present 2 times):

{% highlight apache %}
# staticplonefiles.txt
# url => real filesystem file, from an arbitray root
zonea/images/clean.png foo/bar/img/clean.png
/static/foo/bar/img/clean.png foo/bar/img/clean.png
zonea/images/logo.jpg foo/src/module/foo/images/logo.png
/static/foo/src/module/foo/images/logo.png foo/src/module/foo/images/logo.png
/module/bar/images/people.png foo/src/module/bar/v1.2.5-5/images/people.png
/static/foo/src/module/bar/v1.2.5-5/images/people.png foo/src/module/bar/v1.2.5-5/images/people.png
# ... to be continued
{% endhighlight %}

And now our 3 static examples are available as well with the /static url. Well in fact do not forget to add this rule:

{% highlight apache %}
# Security for uri containing our /static shortcut we should check only
# listed files from rewritemap are served, as
# in this current case the static directory contins as well
# some unsecure files... yep.
RewriteCond %{REQUEST_URI} ^/static/ [NC]
RewriteCond ${statics:$1} =""
# F : force forbidden 403 response
RewriteRule ^(.*)$ - [F,L]
{% endhighlight %}

This will check that all directly accessed files via `/static` are present in our mapping.
And it's all done.
Like for the previous post you should really activate `RewriteLog` and look at what he does
for several different files, but now you should as well adjust Apache logLevel for this
VirtualHost and check the errorLog to observe what is done After the rewrite.

As an example of debug here are some debug outputs for:

 * a matched image

{% highlight apache %}
(2) init rewrite engine with requested uri /images/people.png
(3) applying pattern '^/(.*\.(ico|png|gif|jpg|jpeg|bmp|css|js))' to uri '/images/people.png'
(6) cache lookup FAILED, forcing new map lookup
(5) map lookup OK: map=statics[dbm] key=images/people.png -> val=test/img/clean.png
(4) RewriteCond: input='test/img/clean.png' pattern='!=' => matched
(5) cache lookup OK: map=statics[dbm] key=images/people.png -> val=test/img/clean.png
(2) rewrite '/images/people.png' -> '/static/test/img/clean.png'
(2) remember /static/test/img/clean.png to have Content-handler 'default-handler'
(2) forcing '/static/test/img/clean.png' to get passed through to next API URI-to-filename handler
(1) force filename /tmp/htdocs/test/img/clean.png to have the Content-handler 'default-handler'
{% endhighlight %}

* index.php which wont be proxified after

{% highlight apache %}
(2) init rewrite engine with requested uri /index.php
(3) applying pattern '^/(.*\.(ico|png|gif|jpg|jpeg|bmp|css|js))' to uri '/index.php'
(3) applying pattern '^(.*)$' to uri '/index.php'
(4) RewriteCond: input='/index.php' pattern='^/static/' [NC] => not-matched
(1) pass through /index.php
{% endhighlight %}

* the / base uri, which will be proxified

{% highlight apache %}
(2) init rewrite engine with requested uri /
(3) applying pattern '^/(.*\.(ico|png|gif|jpg|jpeg|bmp|css|js))' to uri '/'
(3) applying pattern '^(.*)$' to uri '/'
(4) RewriteCond: input='/' pattern='^/static/' [NC] => not-matched
(1) pass through /
{% endhighlight %}

* an unmapped image

{% highlight apache %}
(2) init rewrite engine with requested uri /images/crystal/32/personal.png
(3) applying pattern '^/(.*\.(ico|png|gif|jpg|jpeg|bmp|css|js))' to uri '/images/crystal/32/personal.png'
(6) cache lookup FAILED, forcing new map lookup
(5) map lookup FAILED: map=statics[dbm] key=images/crystal/32/personal.png
(4) RewriteCond: input='' pattern='!=' => not-matched
(3) applying pattern '^(.*)$' to uri '/images/crystal/32/personal.png'
(4) RewriteCond: input='/images/crystal/32/personal.png' pattern='^/static/' [NC] => not-matched
(1) pass through /images/crystal/32/personal.png
{% endhighlight %}

* a direct access via /static for a forbidden file

{% highlight apache %}
(2) init rewrite engine with requested uri /static/config/config.ini
(3) applying pattern '^/(.*\.(ico|png|gif|jpg|jpeg|bmp|css|js))' to uri '/static/config/config.ini'
(3) applying pattern '^(.*)$' to uri '/static/config/config.ini'
(4) RewriteCond: input='/static/config/config.ini' pattern='^/static/' [NC] => matched
(6) cache lookup FAILED, forcing new map lookup
(5) map lookup FAILED: map=statics[dbm] key=/static/config/config.ini
(4) RewriteCond: input='' pattern='=' => matched
(2) forcing responsecode 403 for /static/config/config.ini
{% endhighlight %}

Quite readable isn't it? But **do not forget to remove debug** for production env.

###Closely Related articles###

 * [Use RewriteMap to prevent proxying for some static contents]({% post_url 2009-11-05-use_rewrite_map_to_prevent_proxying_for_some_static_contents %})