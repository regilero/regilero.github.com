---
layout: post
uuid: 21c84958-8e55-11f8-bae8-0842200c9a55
title: Details of DRUPAL_SA_CORE_2014_003 Deny Of Service
categories: [Security, English]
tags: [Drupal, Security, Apache, PHP]
pic: long_name.jpg
excerpt: Analysis of the new DRUPAL_SA_CORE_2014_003 DOS vulnerability (CVE-2014-5019)
---

## SA_CORE_2014_003

This summer Drupal versions [6.x][DRUPAL_6] and [7.29][DRUPAL_7_29] & [7.31][DRUPAL_7_31] have been released with some critical security fixs. Enough time as passed, so I will give some details one of the issues from [SA-CORE-2014-003 - Drupal core - Multiple vulnerabilities][SA_CORE_2014_003]. It contains 3 issues. The one we will study here is the Core **Deny of Service** (DOS) issue which is also available in the CVE database as [CVE-2014-5019][CVE_DOS]. This post is a detailled explanation of how drupal is using the Host header of the http request to find the configuration file, and why this was usable in a deny of service attack even for websites not using the multisite feature. It contains some not very well known things on Host header manipulations, so I hope this will help other projects from avoiding theses issues.

Note that there were a regression Drupal 7.29, with images and files attached to taxonomy terms which has been fixed on the next release 7.30 (the regression was not about the patch discussed here).

Note also that another core security issue has been fixed right after this one ([SA-CORE-2014-004 - Drupal core - Multiple vulnerabilities][SA_CORE_2014_004], which was another DOS issue coming from `xmlrpc.php`, so if you do not have something preventing remote access to this php file you should really upgrade your drupal code version to version `7.31`. My own advice is to alter your Apache/Nginx configuration to only allow one PHP file, `index.php`, this will prevent a loooot of problems.

If you have some fears on updating the Core you can at least apply [the DOS patch][DOS_patch] for this first DOS issue (this is not the patch for the xmlrpc.php issue), which is quite simple:

    diff --git a/includes/bootstrap.inc b/includes/bootstrap.inc
    index 0b81dc0..dc08dd6 100644
    --- a/includes/bootstrap.inc
    +++ b/includes/bootstrap.inc
    @@ -700,7 +700,14 @@ function drupal_environment_initialize() {
      *  TRUE if only containing valid characters, or FALSE otherwise.
      */
     function drupal_valid_http_host($host) {
    -  return preg_match('/^\[?(?:[a-zA-Z0-9-:\]_]+\.?)+$/', $host);
    +  // Limit the length of the host name to 1000 bytes to prevent DoS attacks with
    +  // long host names.
    +  return strlen($host) <= 1000
    +    // Limit the number of subdomains and port separators to prevent DoS attacks
    +    // in conf_path().
    +    && substr_count($host, '.') <= 100
    +    && substr_count($host, ':') <= 100
    +    && preg_match('/^\[?(?:[a-zA-Z0-9-:\]_]+\.?)+$/', $host);
     }

## So, what was the problem?

### Spoofable Hostnames

By simply checking the patch we can see that the goal is to prevent :

 * hostnames longer than 1000 characters
 * hostnames with more than 100 dots (or subdomains)
 * hostnames with more than 100 `:` (used on ports and sometimes for IPv6)

The **hostname** is a very important part of the client HTTP request. When you are requesting a website, which could be a drupal website, your client HTTP request will send several headers and on of theses headers is the hostname, it is the **Host:** header:

    GET /page/foo?z=42 HTTP/1.1
    Host: www.example.com
    (other headers)

The HTTP server receiving this request will decide which VirtualHost will have to handle the request, usually using the Host header to choose between several VirtualHosts (sometimes a same HTTP server is used to manage hundreds of websites). Usually this Host header should contain your website **DNS**. This header is required for HTTP/1.1 and can also be used with HTTP/1.0.

But this header is **spoofable** by the client, so it could contain anything. Hopefully (or at least that's what you usually hope) having a bad Host header should prevent the request from reaching your valid Drupal installation because of several facts:

 * really bad injections (like null-bytes) are detected by the HTTP server and the connection is closed
 * Headers cannot use more than 8000 characters (more or less), this limits the size of the spoofed header (but, hey, 8000 is quite huge)
 * unrecognized hostnames goes to the default Virtualhost, which may not be your Drupal website
 * Drupal also ensure this Hostname only contains a small subset of valid characters
 * multiple Host headers are concatenated with `, ` (comma and space -- and drupal rejects spaces in headers)

In 2013 an excellent paper on [Practical Host headers attacks][PRACTICAL_HOSTNAME_ATTACKS] have been published by [James Kettle][KETTLE] and we can see several very important facts in this paper:

 * the **default Virtualhost protection does not work**, more on that at the end of this page. This is valid for both **Nginx** and **Apache**.
 * any application having too much trust on this spoofable Header may suffers from issues.

This paper was studied by the drupal security team, [you can check the discussions here][DRUPAL_PRACTICAL_HOSTNAME_ATTACKS], and one fact to remember about this discussion is that **you should always enforce the `$base_url` setting** when running Drupal in production to avoid attacks based on password renewable mails.

So far so good, no real problems.

### conf_path settings file search

Drupal already had a `drupal_valid_http_host` function ensuring the hostnames did not contain bad characters like `/`,`\`,`%`,` ` or `&`. Only letters, digits, dots and `:`. Not relying on the HTTP server to ensure a really clean Hostname, always good to add some security layers in the application.

This was a good security point, because this hostname is used in `conf_path()` function, and this is a very early function in the drupal bootstraping process.

One of the early step done while bootstraping Drupal is to load the configuration file. This file will give you, for example, access to the database, or the `$base_url` enforced setting.

{% highlight php %}
    <?php
    /**
     * Sets the base URL, cookie domain, and session name from configuration.
     */
    function drupal_settings_initialize() {
      global $base_url, $base_path, $base_root;
    
      // Export these settings.php variables to the global namespace.
      global $databases, $cookie_domain, $conf, $installed_profile,     $update_free_access, $db_url, $db_prefix, $drupal_hash_salt, $is_https, $base_secure_url, $base_insecure_url;
      $conf = array();
    
      if (file_exists(DRUPAL_ROOT . '/' . conf_path() . '/settings.php')) {
        include_once DRUPAL_ROOT . '/' . conf_path() . '/settings.php';
      }
{% endhighlight %}

So here we see that the settings path depends on the `conf_path()` call. This function is quite short, there's a `drupal_static` thing which is simply a way to avoid re-doing stuff after the first call (in the same HTTP request), it's basically a lazy-loading-run-only-once shortcut.

{% highlight php %}
    <?php
    function conf_path($require_settings = TRUE, $reset = FALSE) {
      $conf = &drupal_static(__FUNCTION__, '');
    
      if ($conf && !$reset) {
        return $conf; //<-- here is the run-only-once thing I was talking about
      }
    
      $confdir = 'sites';
    
      $sites = array();
      if (file_exists(DRUPAL_ROOT . '/' . $confdir . '/sites.php')) {
        // This will overwrite $sites with the desired mappings.
        include(DRUPAL_ROOT . '/' . $confdir . '/sites.php');
      }
    
      $uri = explode('/', $_SERVER['SCRIPT_NAME'] ? $_SERVER['SCRIPT_NAME'] : $_SERVER['SCRIPT_FILENAME']);
      $server = explode('.', implode('.', array_reverse(explode(':', rtrim($_SERVER['HTTP_HOST'], '.')))));
      for ($i = count($uri) - 1; $i > 0; $i--) {
        for ($j = count($server); $j > 0; $j--) {
          $dir = implode('.', array_slice($server, -$j)) . implode('.', array_slice($uri, 0, $i));
          if (isset($sites[$dir]) && file_exists(DRUPAL_ROOT . '/' . $confdir . '/' . $sites[$dir])) {
            $dir = $sites[$dir];
          }
          if (file_exists(DRUPAL_ROOT . '/' . $confdir . '/' . $dir . '/settings.php') || (!$require_settings && file_exists(DRUPAL_ROOT . '/' . $confdir . '/' . $dir))) {
            $conf = "$confdir/$dir";
            return $conf;
          }
        }
      }
      $conf = "$confdir/default";
      return $conf;
    }
{% endhighlight %}

What this code does is testing the requested hostname to see if a specific settings directory exists for this Host; this is the **core functionality of drupal multisites**. By default you have the *default* settings in the directory `<www>/sites/default`, you can then use a `<www>/sites/sites.php` file to map hostnames with other settings files -- but this will only cover names that you **do** have, not the bad ones --, and you *can* also have some directories based on the hostname, or part of it, containing a `settings.php` file. Note that you **cannot suspend this multisite feature**, it's always there, no opt-in or opt-out until Drupal 8 release.

If the hostname is `www.example.com:8080` and the bootstraped drupal file is `<www>/index.php`, Drupal will check for theses files (in this order):

 * `www/sites/8080.www.example.com/settings.php`
 * `www/sites/www.example.com/settings.php`
 * `www/sites/example.com/settings.php`
 * `www/sites/com/settings.php`
 * `www/sites/www.example.com/settings.php`
 * `www/sites/default/settings.php`

If the hostname is `www.example.com:8080` and the bootstraped drupal file is `www/modules/statistics/statistics.php`, Drupal will check theses files:

 * `www/sites/8080.www.example.com.modules.statistics/settings.php`
 * `www/sites/www.example.com.modules.statistics/settings.php`
 * `www/sites/example.com.modules.statistics/settings.php`
 * `www/sites/com.modules.statistics/settings.php`
 * `www/sites/8080.www.example.com.modules/settings.php`
 * `www/sites/www.example.com.modules/settings.php`
 * `www/sites/example.com.modules/settings.php`
 * `www/sites/com.modules/settings.php`
 * `www/sites/8080.www.example.com/settings.php`
 * `www/sites/www.example.com/settings.php`
 * `www/sites/example.com/settings.php`
 * `www/sites/com/settings.php`
 * `www/sites/default/settings.php`

Yep, I'm not sure anyone is really using that feature, but that's what this code does.

If one file is found before the default one, then it is used, you can alter settings in this file to connect another database, or use another `base_url` or `database_prefix`, or alter any setting in fact, the multisites feature things.

As you can see using the `sites/sites.php` to set your hostname-to-directory mapping is quite certainly a good thing to do in terms of performances (this search loop is avoided). Remember that theses file checks are done for **every** HTTP requests received by Drupal.

So now re-read the patch, before this patch very long hostnames could be used, and you could use a very big number of subdomains... and for each subdomain you add several locations to check for a setting file...

This is where I came and then I made some evil tests to see how this multisite code would react with bad hostnames. Working only with the allowed characters (alphabetical letters, digits, dots, `:`) we can at least play with this deep settings files search. And the `sites.php` map shortcuts won't be used for bad hostnames.

### And then the DOS issue

So, you may think the issue is on the `file_exists` calls, as we will run several thousands of file_exists, searching for the first match if we set a hostname with a lot of subdomains. Strangely this is usually quite fast.

The real issue is on `array_slice`, performing several thousands of inverted array_slice is *really very very slow*. the first ones are quite fast but the last steps are longer, and we will make several thousands of array_slice operations.

{% highlight php %}
    <?php
    function test_array_slice($server,$j) {
      print "ARRAY_SLICE array of " . count($server) . " elts => ";
      $time_start = microtime(true);
      array_slice($server,$j);
      $time_end = microtime(true);
      $time = $time_end - $time_start;
      print "time for array_slice to $j : $time (s)\n";
    }
    /*
    ARRAY_SLICE array of 16000 elts => time for array_slice to -10    : 0.0004069805 (s)
    ARRAY_SLICE array of 16000 elts => time for array_slice to -100   : 0.0004091262 (s)
    ARRAY_SLICE array of 16000 elts => time for array_slice to -500   : 0.0004727840 (s)
    ARRAY_SLICE array of 16000 elts => time for array_slice to -1000  : 0.0005030632 (s)
    ARRAY_SLICE array of 16000 elts => time for array_slice to -4000  : 0.0010337829 (s)
    ARRAY_SLICE array of 16000 elts => time for array_slice to -8000  : 0.0016450881 (s)
    ARRAY_SLICE array of 16000 elts => time for array_slice to -12000 : 0.0018289089 (s)
    ARRAY_SLICE array of 16000 elts => time for array_slice to -14000 : 0.0025160312 (s)
    ARRAY_SLICE array of 16000 elts => time for array_slice to -16000 : 0.0032360553 (s)
    */
{% endhighlight %}

0.003s seems quite fast, but that's already 7.5 times more than the first array_slices. I made a simple graph to show theses times growth.

<img src="/theme/img/posts/graph_array_slice.png" width="600" height="463" alt="array_slice time graph for 16000 elements"/>

And each of theses times are computed for **1 extraction** -- like extracting the array of 16 000 elements to index -12 000 --, but the loop is extracting all values. One at each call of the loop.

The loop is **stacking** each of theses times, with 16 000 elements the last array_slice is 0.003s but the sum of all theses `array_slice` calls is ... **52 seconds!**

My first fix used an `array_walk` call to prepare all names that should be checked, instead of rebuilding this name on the loop, this way:

{% highlight php %}
    <?php
    /**
     * Apply this function with an array_walk to obtain an array with names that
     * need to be tested.
     */
    function prepare_name(&$val, $key, &$current) {
      if (''!==$current) {
        $val = $val.".".$current;
      }
      $current = $val;
    }
    (...)
    $rev_server = array_reverse($server);
    $current='';
    array_walk($rev_server, 'prepare_name', $current);
    $work_server = array_reverse($rev_server);
    // --end new
    for ($i = count($uri) - 1; $i > 0; $i--) {
      // now the loop is a simple foreach name on first array
      foreach($work_server as $k => $name) {
        $dir = $name . implode('.', array_slice($uri, 0, $i));
      }
    }
{% endhighlight %}

And this fixed the performance issue (when `file_exists` is fast). But preventing bad hostnames as we have in the final fix is a better fix, more radical, no good reason to manage several thousand of subdomains.

Is this a real DOS issue? Well, on real life production servers, with a lot of memory and very fast CPUs we've made exploits which usually made any (unique) request run in this loop for more than **2 minutes**. So with an attacker running parallel requests or reaching some cheaper hosts, this could really become a problem.

## Protect your website

Things that **DO NOT** protect you, **theses things will not protect your Drupal website from being attacked**:

 * Not having a **multisite drupal**, this happens on the multisite check and you cannot suspend it on D5, D6 and D7 (opt-in for D8, at last), you **always** have this `conf_path()` running, on every request, and you cannot do anything before the settings are loaded.
 * Not having drupal on the **Default Virtualhost**, the **absolute-URI** trick will hit you, see last part.
 * **Old Drupal**, this issue is present from a very very long time, also present in Drupal5 for example.
 * **Varnish, Nginx, Apache** (and maybe others): no default protection.
 * Using the `www/sites.php` hostname location mapping file, as you will not have the bad hostnames there and you have no way in drupal to reject undefined names.

Things **THAT MAY WORK** to protect yourself (untested):

 * using **mod_security** or some other security tool checking for some strange Host headers, but you should check the behavior of theses tools with the absolute-URI trick (see last part).

Things **THAT DO WORK** to protect yourself (choose one):

 * Upgrade [D6][DRUPAL_6] or [D7][DRUPAL_7] to the last versions *OR*
 * Apply the [DOS patch][DOS_patch] *OR*
 * use a default catch-all non-drupal Virtualhost **and** [patch Apache][APACHE_HTTPD_PATCH] (see at the end) *OR*
 * Add a **mod_rewrite** *Hostname check* :

The Mod_rewrite Apache module will receive the same **HOSTNAME** as PHP in the **HTTP_HOST** variable. If the Absolute-URI trick is used mod_rewrite could detect bad hostname and reject the request. Let's say you have one or two valid DNS for your Drupal websites (here `foo.example.com` and `bar.example.com`), then check Apache made the right job and reached your Drupal with theses valid names:

{% highlight apache %}
    # Reject with a 403 any hostname wich is not in our list of supported domains
    RewriteCond %{HTTP_HOST} !^foo\.example\.com$
    RewriteCond %{HTTP_HOST} !^bar\.example\.com$
    RewriteRule .* - [F,L]
{% endhighlight %}

## The absolute-URI trick?

So, as I said before the default Virtualhost method does not protect you, that's sad because it's usually a good practice, you add a default Virtualhost with default simple pages (like an "It Works" page) and anyone doing bad things with HOST headers would end there.

But this can be bypassed with both Apache and Nginx by using the absolute-URI trick describe at the end of the [Practical Host Header attacks paper][PRACTICAL_HOSTNAME_ATTACKS] that I linked before.

The trick is to use an absolute URI in the first part of the HTTP query. Instead of the classical HTTP 1.1 request :

    GET /page/foo?z=42 HTTP/1.1
    Host: www.example.com
    (other headers)

You do:

    GET http://www.example.com/page/foo?z=42 HTTP/1.1
    Host: something.else
    (other headers)

And the RFC 2616 says this request should be managed by the `www.example.com` virtualhost, that's OK. And it also states that the Host Header should then be **ignored**. Cool. But in both Apache and Nginx this does not means the used Host headers will not be sent to the final application (here PHP).

So at the end Drupal receive the Host header (here `something.else`). I think this is an issue on the HTTP server side. This header should be overwritten and should look like `www.example.com`. What's worse is that classical bad characters that are usually detected in the Host headers are not checked in Apache when you use the Abolute-URI trick. On the drupal side we have the regex cleanup on the Host header, that's a very good thing ([defense in depth][DEFENSE_IN_DEPTH] applied). On the drupal side using the absolute-URI trick will produce a 404 page, the URL does not match any known Drupal path, but this 404 is not a problem for the DOS attack which occurs on the settings file search, very early.

If you think this is an Apache issue please vote for this [Apache patch][APACHE_HTTPD_PATCH] on the httpd bugtracker, which overwrite the HTTP_HOST with the absolute-uri host :

    --- server/protocol.c	2014-03-10 14:04:03.000000000 +0100
    +++ server/protocol.c.new	2014-06-05 23:41:38.233573966 +0200
    @@ -1063,6 +1063,21 @@
     
         apr_brigade_destroy(tmp_bb);
     
    +    /*
    +    * rfc2616: If Request-URI is an absoluteURI, the host is part of the
    +    * Request-URI. Any Host header field value in the request MUST be
    +    * ignored.
    +    * We are currently ignoring it, but the Host headers are still present
    +    * and may get use by naive programs as the one used for vhost choice
    +    * or like a valid hostname. So enforce the 'ignore' behavior by
    +    * overwritting any present Host header.
    +    * Note that this is made just before the fixHostname(r) call, so this
    +    * Host header entry is still not as safe as the hostname.
    +    */
    +    if (r->hostname && apr_table_get(r->headers_in, "Host")) {
    +        apr_table_set(r->headers_in, "Host", r->hostname);
    +    }
    +
         /* update what we think the virtual host is based on the headers we've
          * now read. may update status.
          */

With this patch applied the only way to get a strange Hostname targeted to your Drupal would be having the Drupal Apache Virtualhost used as default Virtualhost, something usually quite easy to fix.

Nginx may also need a fix one day.

 * [Stay tuned on twitter, @regilero][TWITTER], [@makinacorpus][TWITTERMAK]

[KETTLE]: https://plus.google.com/+JamesKettle/about
[APACHE_HTTPD_PATCH]: https://issues.apache.org/bugzilla/show_bug.cgi?id=56718
[PRACTICAL_HOSTNAME_ATTACKS]: http://www.skeletonscribe.net/2013/05/practical-http-host-header-attacks.html
[DRUPAL_PRACTICAL_HOSTNAME_ATTACKS]: https://www.drupal.org/node/2221699
[DOS_patch]: https://www.drupal.org/files/issues/sec-D7-conf-path-dos-105258-23.patch
[7_29_issue]: https://www.drupal.org/node/2305017
[DRUPAL_7_29]: https://www.drupal.org/drupal-7.29-release-notes
[DRUPAL_7_31]: https://www.drupal.org/drupal-7.31-release-notes
[DRUPAL_6]: https://www.drupal.org/drupal-6.32-release-notes
[SA_CORE_2014_003]: https://www.drupal.org/SA-CORE-2014-003
[SA_CORE_2014_004]: https://www.drupal.org/SA-CORE-2014-004
[CVE_DOS]: http://www.cvedetails.com/cve/CVE-2014-5019/
[DEFENSE_IN_DEPTH]: http://en.wikipedia.org/wiki/Defense_in_depth_%28computing%29
[TWITTER]: https://twitter.com/regilero
[TWITTERMAK]: https://twitter.com/makinacorpus


