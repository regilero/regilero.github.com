---
layout: post
title: Use RewriteMap to prevent proxying for some static contents
categories: [Apache, English]
tags: [HTTP, Plone, Performance, Proxy, mod_rewrite, RewriteMap]
pic: alienflower.png
excerpt: How to use the not well known RewriteMap Apache feature to proxy static resources on a web app without clean url separation between static and dynamic content (here Plone).  
next: 2009-11-06-more_on_static_file_redirector

---


Let's say we would like to prevent an application server to serve static content.
And let's take a complex example, **Plone**.
Plone is a Zope based application server and is not using a clean url-map for static contents.

We'll take Plone as an example but it's not the only app which is not handling static files outside general uri-application-mapping.
With url prefixed by a `/static/` it would be quite easy to redirect apache handler for theses urls on the default-handler
(static content handler) and prevent proxy settings from redirecting theses requests to the application server he is proxying
(as in our case this app server is behind an Apache httpd proxy).

{% highlight apache %}
    Apache-HTTPD
    /            \
filesystem       proxied webapp
static-files     dynamic-pages
{% endhighlight %}

So lets say we know something like 100 or 150 files which are css files,
some js and somes images which are actually served by this plone server,
on a lot of different url `/foo/bar/toto.png`, `/foobar/main.css` which
represents some directories where we do not have only static contents.
And we want to prevent the webapp from handling theses known files.

Here's a nice solution based on **mod_rewrite**, and especially
[rewriteMap](http://httpd.apache.org/docs/current/rewrite/rewritemap.html),
where all theses contents will be served by Apache directly from the filesystem,
with some content-expiration settings and without openning back-doors to neighbour
content which should certainly not be available statically
(like for example python source code files).  
So first let's have a basic plone proxy setting for an apache Virtualhost,
we serve `plone.from.outside.net` which is a proxy on `plone.inside.lan`.

{% highlight apache %}
<VirtualHost *:80>
    ServerName  plone.from.outside.net

    # in case apache is not set in utf-8
    AddDefaultCharset UTF-8

    DocumentRoot /var/www/proxyplone/htdocs

    LogLevel info
    #LogLevel debug
    ErrorLog /var/www/proxyplone/var/log/error.log
    CustomLog /var/www/proxyplone/var/log/access.log combined
    ## uncomment below to enter maintenance mode
    #ErrorDocument 503 /htdocs/err/503.html
    #RedirectMatch 503 ^/(?!err/)

    <IfModule mod_proxy.c>
            #
            # No open proxy
            ProxyRequests off
            <Proxy *>
                    Order allow,deny
                    Allow from all
            </Proxy>
            ProxyTimeout 1200
            #exceptions, do not proxy theses ones
            ProxyPass       /server-status  !
            ProxyPass       /index.php !
            ProxyPass       /err/ !
            #Proxy rewriting
            ProxyPass       /       <a href="http://plone.inside.lan/here/be/dragons/like/virtualhostmonster/settings/" title="http://plone.inside.lan/here/be/dragons/like/virtualhostmonster/settings/">http://plone.inside.lan/here/be/dragons/like/virtualhostmonster/settings/</a>
            ProxyPassReverse /      <a href="http://plone.inside.lan/here/be/dragons/like/virtualhostmonster/settings/" title="http://plone.inside.lan/here/be/dragons/like/virtualhostmonster/settings/">http://plone.inside.lan/here/be/dragons/like/virtualhostmonster/settings/</a>
            ###########
    </IfModule>

    <Directory />
        Options FollowSymLinks
        # prevent .htaccess reads on all the filesystem
        AllowOverride None
        order allow,deny
        deny from all
    </Directory>

    <Directory /var/www/proxyplone/htdocs>
        order allow,deny
        Allow from All
        DirectoryIndex index.php
    </Directory>
</Virtualhost>
{% endhighlight %}
 
Ouch, in fact I've added a few more settings to be able to serve an index.php
page from this same virtualhost, and being a proxy for anything else, just to
have something more 'real-life wtf'.  
Oh and as well I've added a nice trick for maintenance mode via **RedirectMatch**,
for the happy few.  

###And now what about static files handling?###

Let's do it in 2 steps.  
We'll make a simple one first,
redirecting targeted files on direct static handling and then next time we'll add a **virtual /static directory**
(like serious apps). 
So the app dev will build for us a nice rewriteMap file.
This file will map all static urls to the real filesystem file. In this way:

{% highlight apache %}
# staticplonefiles.txt
# url => real filesystem file, from an arbitray root
zonea/images/clean.png foo/bar/img/clean.png
zonea/images/logo.jpg foo/src/module/foo/images/logo.png
/module/bar/images/people.png foo/src/module/bar/v1.2.5-5/images/people.png
# ... to be continued
{% endhighlight %}

We will store this file in **/var/www/proxyplone/etc/staticplonefiles.txt** and reference it in the apache configuration.

{% highlight apache %}
RewriteMap statics txt:/var/www/proxyplone/etc/staticplonefiles.txt
{% endhighlight %}

Then we can pass any url in `${static:/here/the/url}` and obtain the filesystem mapping as the result.
Let's look at a rewriteRule catching potientially static contents
with a regex like that: `^/(.*\.(ico|png|gif|jpg|jpeg|bmp|css|js))`.  
Catched urls will be available in the next part of the rewrite rule,
or in preceding RewriteConds as *$1*.
We will serve the static contents from the plone source code base,
which is available in the server at */opt/plone/source*.
So the *foo/bar/img/clean.png* in the rewritemap file is
in fact */opt/plone/source/foo/bar/img/clean.png*.  
Here you see Apache needs direct access to the files via is filesystem,
if real files aren't directly there you should ensure they will.
You can use **rsync** or **NFS** for example,
but **the apache server must have direct access to theses files**,
as he will not proxy them.

Starting with a rule:

{% highlight apache %}
RewriteRule ^/(.*\.(ico|png|gif|jpg|jpeg|bmp|css|js)) /opt/plone/source/${statics:$1}
{% endhighlight %}

wont work, as the rewrite engine will prefix the final destination with the current documentRoot. So we should better use:

{% highlight apache %}
RewriteRule ^/(.*\.(ico|png|gif|jpg|jpeg|bmp|css|js)) ${statics:$1}
{% endhighlight %}

and change the DocumentRoot to:

{% highlight apache %}
DocumentRoot /opt/plone/source
{% endhighlight %}

And to do it we must fix accordingly previous content like our index.php,
which is not anymore in the documentRoot.
To keep the same fonctionnal DocumentRoot we can add a rule:

{% highlight apache %}
Alias / /var/www/proxyplone/htdocs/ (do not forget last '/')
{% endhighlight %}

Now a finished rule must always contains some flags at the end. here we'll use:

{% highlight apache %}
[NC,L,handler=default-handler]
{% endhighlight %}

 * `NC` will make the match-rule case-insensitive (to catch .PNG for example)
 * `L` will stop rewrite execution on succesfull match
 * and the `handler` is just a security, we force apache to treat static contents as static contents :-)

And last but not least we'll need a RewriteCond juste before this rule, to ensure unmatched documents
(static files not listed in the rewrite map) won't be handled by our rewriteRule
and will still be served by the app server.

{% highlight apache %}
RewriteCond ${statics:$1} !=""
{% endhighlight %}

will do that for us,
it ensure the result is not empty,
and *$1* is the matching content from the related rewriteRule.
Let's note as well the rewriteMap is stored in a cache
and not re-read at each request.

Put it all together we have:

{% highlight apache %}
<VirtualHost *:80>
    ServerName  plone.from.outside.net
    
    # in case apache is not set in utf-8
    AddDefaultCharset UTF-8
 
    DocumentRoot /opt/plone/source
    LogLevel info
    #LogLevel debug
    ErrorLog /var/www/proxyplone/var/log/error.log
    CustomLog /var/www/proxyplone/var/log/access.log combined
    ## uncomment below to enter maintenance mode
    #ErrorDocument 503 /htdocs/err/503.html
    #RedirectMatch 503 ^/(?!err/)

    # REWRITER for Static files managment rules
    # we need:
    RewriteEngine on
    #RewriteLog /var/www/proxyplone/var/log/rewrite.log
    # from 0 to 9
    #RewriteLogLevel 9
    RewriteMap statics txt:/var/www/proxyplone/etc/staticplonefiles.txt
    # only apply the rewriterule for entries listed in the rewritemap, $1 refers to the $1 from next rewriteRule
    RewriteCond ${statics:$1} !=""
    # prevent rewritemap parsing for URI not containing static file extensions
    # NC: case insensitive in comparison of testString and Pattern
    # L: stop rewriting
    RewriteRule ^/(.*\.(ico|png|gif|jpg|jpeg|bmp|css|js)) /${statics:$1} [NC,L,handler=default-handler]

    <IfModule mod_proxy.c>
            #
            # No open proxy
            ProxyRequests off
            <Proxy *>
                    Order allow,deny
                    Allow from all
            </Proxy>
            ProxyTimeout 1200
            #exceptions, do not proxy theses ones
            ProxyPass       /server-status  !
            ProxyPass       /index.php !
            ProxyPass       /err/ !
            #Proxy rewriting
            ProxyPass       /       <a href="http://plone.inside.lan/here/be/dragons/like/virtualhostmonster/settings/" title="http://plone.inside.lan/here/be/dragons/like/virtualhostmonster/settings/">http://plone.inside.lan/here/be/dragons/like/virtualhostmonster/settings/</a>
            ProxyPassReverse /      <a href="http://plone.inside.lan/here/be/dragons/like/virtualhostmonster/settings/" title="http://plone.inside.lan/here/be/dragons/like/virtualhostmonster/settings/">http://plone.inside.lan/here/be/dragons/like/virtualhostmonster/settings/</a>
            ###########
    </IfModule>
    <Directory />
        Options FollowSymLinks
        # prevent .htaccess reads on all the filesystem
        AllowOverride None
        order allow,deny
        deny from all
    </Directory>
    Alias / /var/www/proxyplone/htdocs/
    <Directory /var/www/proxyplone/htdocs>
        order allow,deny
        Allow from All
        DirectoryIndex index.php
    </Directory>
    <Directory /opt/plone/source>
        order allow,deny
        Allow from All
    </Directory>
</Virtualhost>
{% endhighlight %}

And **it works**, at this point you should note the rewriteRule
is a endpoint for matching content,
no other apache rule can be applied,
but at least you need a Directory directive
to allow content from your plone source to be acceded.

**No security Hole**, as some could think with the documentRoot
in plone source,  
asking for `/` url wont serve your source content as:

 * there's an **alias on /** redirecting to /var/www/proxyplone/htdocs/
 * there's a **proxy on /** redirecting to plone app server.
 * but **do not** remove mod_alias and mod_proxy from apache :-)

Do not hesitate to uncomment RewriteLog and RewriteLogLevel directives to see what is done.
Next time we'll make a static virtual directory and we'll be able to apply
some more rule from Apache after the rewrite part.

###Closely Related articles###

 * [More on Static file redirector]({% post_url 2009-11-06-more_on_static_file_redirector %})