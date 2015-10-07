---
layout: post
uuid: 91ecd42e-adc8-4dqq-a2ff80deaa8d000ff
title: Checking HTTP Smuggling issues in 2015 - Part1
categories: [Security, English]
tags: [Security, Apache, Varnish, Nginx, HAProxy, Smuggling]
pic: wookie1.jpg
excerpt: First part of the 2015 HTTP Smuggling articles. Injecting HTTP in HTTP, the theory.
---

<small> **English version** (**Version Française** disponible sur [makina corpus][FRENCH].)</small>

The goal of this serie of articles is to explain clearly what are HTTP smuggling
issues and why I think this sort of security issues are critically important and
could be used in massive attacks against modern web services.

In the last 6 months I've been struggling with the state of several open source HTTP
servers, and helped fixing several issues. The main problem encountered was,
usually, to explain the problem.

A first big study on smuggling was done in 2005 and lead to several corrections.
This was was done by **Chaim Linhart**, **Amit Klein**, **Ronen Heled** and **Steve Orrin**,
published by Watchfire and [still worth a read ten years after][2005WATCHFIRE].
Today even the HTTP/1.1 RFC 7230 contains [protections][RFC_REQUEST_SMUGGLING_2]
and [warnings][RFC_REQUEST_SMUGGLING_1] against Request Smuggling, but
an RFC is just a reference, things are really different when you check the
implementations. And a lot of people are now starting their own implementations.
Seems that a refresh was needed.

Most of the links provided in this article should be easier to understand
*after* reading this first part. This is gonna be a long serie, starting from
simple HTTP requests to very strange ones, with details about recently fixed
flaws on  several tools (and some CVE also). On this first article there is
nothing **new**, just another way of explaining the problems. I hope this will
at least help refreshing memories on the problems.

If you use HTTP servers, and especially if you use several HTTP agents (Reverse
Proxies, SSL Terminators, Load balancers, etc.), you should be interested by this.
If you build an HTTP agent you should master it, best thing would be knowing all
this better than me, if you spot any error, do not hesitate to comment or
<a href="mailto:regis.leroy@makina-corpus.com">contact me</a>.


## HTTP Smuggling: What?

### Hiding HTTP queries in HTTP, Injection

That's it, the main idea is to hide HTTP in HTTP.

To hide a message in a protocol you need to find a flaw, an issue, in the way an
agent is interpreting (reading) the message.

HTTP Request smuggling is simply an injection of HTTP protocol into the HTTP
protocol. As always with security the main problem is **injection**. If you can
inject SQL into SQL, HTML, javascript or css into an HTML response... you have
problems.

When injecting javascript in a an HTML page you need to find a flaw in the
application outputing some user content. Here the players will **tracks flaws in
the parsing of HTTP messages**.

Some security problems closely related to HTTP smuggling are **HPP** (HTTP
parameters pollution) that you can read on the
[Stefano di Paola & Luca Carettoni paper in OWASP 09][HPP] and
[**HTTP Response splitting**][RESPONSE_SPLITTING].

**HPP** is a very specific
part of HTTP Smuggling, considering only the parameters used on the location and
 the problems arising from differences in the interpretations of strange
parameters (like repetitions of same url parameter).

**Response splitting** is an attack used on an application (on the final backend)
where the backend will send more HTTP responses than expected. It's a tool that
could be used in HTTP Smuggling, but flaws are uncommon (they were problems with
newlines injections in PHP redirections or in Digest authentication username,
but this was a long time ago).

Here I will mostly talk about *regular* HTTP Smuggling, flaws coming from HTTP
syntax mistakes and protocol approximations.

### Why?

We'll study in details the 3 main kinds of attacks below. But if you can hide
HTTP in HTTP you can perform various forms of attack, going from bypassing
security checks to hijacking user sessions or defacing content in caches.

This is the story of several HTTP queries. Let's say we have at least 3 
different queries, we'll name theses queries for clarity:

 * **Suzann**: the **S**muggler query,
 * **Ivan**: the **I**nnocent query,
 * **Walter**: the **W**ookie, accomplice of the smuggler, usually a Forbidden
 query. And, yes, it's a wookie. Because usually smugglers are working with
wookies.

They will transit from one starting point, the attacker computer, to an HTTP
server (your HTTP server). And sometimes they will encounter a middleware server,
which is also reading and emitting HTTP. This could be a Load Balancer, an SSL
terminator, a reverse proxy cache, as static cache, etc.

Suzann the smuggler is **evil**, the goal of this query is to attack Ivan the
innocent.

Suzann will not be a regular HTTP query like this:

    GET /suzann.html HTTP/1.1\r\n
    Host: www.example.com\r\n
    Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\n
    Accept-Encoding: gzip, deflate\r\n
    Cache-Control: max-age=0\r\n
    Connection: keep-alive\r\n
    User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:33.0) Gecko/20100101 Firefox/33.0\r\n
    \r\n

Instead it could be something like that (not all in the same time :-) ):

    GET http://www.example.com/suzann.html?foo=%00\tHTTP/11111111111.2\r\n
         HOST: www.evil1.com\r\n
    HOST: www.evil2.com\r\n
    Content-length: 0\r\n
    ContenT-length :\t100\r\n
    Connection: keep-alive\n
     Content-length:\t10\r
     Transfer-eNCODIng\t\t:chunked\t\r\n
    \r\n
    (...)

And your server should reject most of the strange things present in this request
 example (this one is soo bad that I do not think any server would accept it).
If a flaw is found in the server it *could* be used for smuggling and the
attacker could start to think about exploitations of the flaw.

We'll start by a big rollback and give some details about HTTP to understand
all this.

## HTTP

Back in the old time they were only a very old version of HTTP available (that
we call HTTP/0.9). Smuggling was not available. The only way to send 3
queries was opening 3 time a tcp/ip connection to the server and each time
asking for the targeted document:

    --> open tcp/ip conn1
    GET /Suzann.html\r\n
    \r\n
    <-- receive Suzann.html document
    <html>\r\n
    <head></head>\r\n
    <body>Suzann</body>\r\n
    </html>\r\n
    <-- conn1 is closed

    --> open tcp/ip conn1
    GET http://your.server.com/ivan.html\r\n
    \r\n
    <-- receive ivan.html document
    <html>\r\n
    <head></head>\r\n
    <body>Ivan</body>\r\n
    </html>\r\n
    <-- conn1 is closed

    --> open tcp/ip conn1
    GET /walter.html\r\n
    \r\n
    <-- receive walter.html document
    <html>\r\n
    <head></head>\r\n
    <body>Walter</body>\r\n
    </html>\r\n
    <-- conn1 is closed

HTTP is a quite simple protocol, especially at this time. Note that I'm using
`\r\n` to represent the CR and LF characters end-of-line markers.
This will get important later.

Then comes HTTP/1.0, with one important thing added, the **headers**. You *can*
add them in the request, and the response will always contains headers.  

The first query became:

    --> open tcp/ip conn1
    GET /suzann.html HTTP/1.0\r\n
    Host: your.server.com\r\n
    User-agent: information gateways navigator 0.8\r\n
    Accept: text/html\r\n
    Foo Bar\r\n
    \r\n
    <-- receive Suzann.html document
    HTTP/1.0 400 Bad Request\r\n
    Server: Apache\r\n
    Date: Fri, 24 Jul 1612 16:24:10 GMT\r\n
    Content-Type: text/html\r\n
    Content-Length: 138\r\n
    Connection: close\r\n
    \r\n
    <html>\r\n
    <head><title>400 Bad Request</title></head>\r\n
    <body bgcolor="white">\r\n
    <center><h1>400 Bad Request</h1></center>\r\n
    </body>\r\n
    </html>\r\n
    <-- conn1 is closed

In this response the important thing to note is **Content-Length: 138**. If you
count all characters, starting at `<html`, including the end-of-line characters,
you have exactly 138 characters, with one byte for each ascii7 character, 138
bytes. It seems size matters, and we'll see that **size is everything** in our
problem. Here we also have an error code (400), the server said we made a
mistake in our query, this is not a problem, it's a nice thing to have in a
protocol (error messages). The error was a missing ':' between Foo and Bar.

Let's go quickly to HTTP/1.1, the real HTTP protocol, still used almost
everywhere. The new HTTP/2 protocol is just starting to replace it on some
very limited places.

We have several new features on HTTP/1.1 that will allow very bad behaviors for
*Suzann the smuggler*, with some other features, less important for
smugglers (like the Host Header which is now required, it was optional before).

 * **Keep Alive** mode
 * **Pipelined** queries
 * **Chunked** queries and responses

### Keep Alive

With keep Alive we can open a connection to the server, request Suzann, receive
Suzann, then request Ivan and receive it, and at lastly request Walter and
receive it, in the same TCP/IP connection.

As an HTTP client you can ask for keepAlive mode, but it's usually enabled by
default by the server even if you do not ask for it. You do it by adding this
header on the request:

    Connection: keepalive

On the server side, the keep alive connection can be cut at any time (and most
servers should try to avoid long opened keep alive connections, especially if
they keep one dedicated process for each connection and cannot afford more than
a few hundred processes like the Apache httpd prefork mpm).

On the response headers you will find:

    Connection: close # means we're closing, easy
    Connection: keep-alive # means we'll try to maintain this open a few seconds

Usually, after a `close` the server will close the tcp/ip connection.

The goal of this was to retrieve faster all assets coming with an HTML page, by
reusing the tcp/ip connection opened for the document, avoiding the slow tcp/ip
connection opening.

This keep-alive mode in the protocol is what things like Comet are trying to
exploit to maintain pseudo-infinite-time push/pull connections over HTTP. But
even without this advanced mode, keep-alive is used a lot in HTTP
environments, especially between the end-user and the first part of the
middleware. Usage of keep-alive between HTTP servers and proxies (in the
middleware or between the middleware and the backend) is less common.

### Pipelines \o/

The other big thing in HTTP/1.1 is pipelining. Pipelining is sending several
queries **before** having the responses of theses requests.

Here's a schema of basic pipelining:

        [Client]                  [End Server]
            |                         |
            >-requ. Suzann ---------->|
            >-requ. Ivan ------------>|
            >-requ. Walter----------->|
            |<---------- resp. Suzann-<
            |<------------ resp. Ivan-<
            |<---------- resp. Walter-<

With only Keep Alive the schema was:

        [Client]                  [End Server]
            |                         |
            >-requ. Suzann ---------->|
            |<---------- resp. Suzann-<
            >-requ. Ivan ------------>|
            |<------------ resp. Ivan-<
            >-req. Walter------------>|
            |<---------- resp. Walter-<

With an HTTP proxy in the middle the schema is, usually:

        [Client]             [Middleware]          [End Server]
            |                     |                     |
            >-requ. Suzann ------>|                     |
            >-requ. Ivan -------->|                     |
            >-req. Walter ------->|                     |
            |                     >-requ. Suzann ------>|
            |                     |<------ resp. Suzann-<
            |<------ resp. Suzann-<                     |
            |                     >-requ. Ivan -------->|
            |                     |<-------- resp. Ivan-<
            |<-------- resp. Ivan-<                     |
            |                     >-req. Walter-------->|
            |                     |<------- resp Walter-<
            |<------ resp. Walter-<                     |

You can see that the connection between the middle agent (a reverse proxy cache
or an SSL terminator) and the end server is usually not using pipelining
(because that's an awfully complex thing to do well with HTTP).

Sometimes the connection between the middleware and the end server is even not
using Keep Alive connections. Some other times it's reusing a pool of tcp keep
alive connections. But the first protection against HTTP smuggling applied here
is breaking your pipeline of requests in several requests, waiting for the
end of a first request before handling the next one.

Eventually, the server is **never** expected to respond to all requests in a
pipeline. You can get the first response with a `Connection: close` header,
cutting the Keep Alive connection right after the response.


        [Client]             [Middleware]          [End Server]
            |                     |                     |
            >-requ. Suzann ------>|                     |
            >-requ. Ivan -------->|                     |
            >-req. Walter ------->|                     |
            |                     >-requ. Suzann ------>|
            |                     |<------ resp. Suzann-<
            |<------ resp. Suzann-<                     |
    [ client is expected to re-send Ivan & Walter queries]

And this is the second big protection against smuggling. As soon as the
middleware detects a bad Suzann query, it should send a **400 bad request**
 response **and** close the connection (but if you really search you'll find
examples of proxies which does not close the keep alive after an error).

### Chunks

Chunked transfer is an alternate way of transmitting long HTTP messages. Instead
of a transmission starting with a `Content-length` header announcing the full
message size you can transmit the message by small (or not) chunks, each one
annoucing a size (in hexadecimal format).

A special **last-chunk** empty chunk marks the end of the message.

We'll certainly study in detail chunks in next articles. The important thing
with chunks is that's it is another way of manipulating the size of the message.

Chunks can be used on HTTP responses (usually) but also on queries.

For an example you can read the [Wikipedia page][WIKI_CHUNK] explaining how
chunks can be used to transfer this:

    Wikipedia in\r\n\r\nchunks.

as:

    4\r\n
    Wiki\r\n
    5\r\n
    pedia\r\n
    e\r\n
     in\r\n\r\nchunks.\r\n
    0\r\n
    \r\n

So much fun :-)

## The key: Size matters

I said it several times. But, yes, size matters. To inject HTTP in HTTP the
key is usually to trick the HTTP agent reader about the size of your message.

HTTP queries and responses are mostly a list of strings separated by end of lines.
And we saw with pipelines that you could send several queries, one after another.

The HTTP agent reading the queries or parsing the responses MUST know where this
list of strings ends. this way, the agent can check if what's coming after is
another query (or response if it's a backend stream).

The tools used by the HTTP reader is either the **chunks mecanism** or the
**Content-Length** header.

And if something goes wrong **here** you can start hiding some queries or
responses. One of the composants will parse the stream and will not understand the
incoming characters as new requests but as the previous request body, or will not
understand the stream as the first request response but as a new one.

That's the key of HTTP Smuggling.

    GET /suzann.html HTTP/1.1\r\n
    Host: example.com\r\n
    Content-Length: 0\r\n
    Content-Length: 46\r\n
    \r\n
    GET /walter.html HTTP/1.1\r\n
    Host: example.com\r\n
    \r\n

Here if you accept the first Content-length header you have 2 requests. If you
take the second one as the right one instead, then you have one GET query, with
a body containing some bytes that you do not care about -- even if it looks like
 a query-- (a GET query with a body is something strange, POST query have bodies
and usually GET queries have only parameters, but it is allowed).

Ok, so it's one OR two queries, no problem, but if you are a proxy seing one
query and transmitting this unique query to a backend which then sends you 2
responses you'd better know what to do with this second response. Or maybe it
would have been better to detect a bad HTTP request and avoid this problem.


## HTTP Smuggling: the basics

HTTP smuggling may be used in 3 sort attacks (mainly).

### Attack 1 : Bypass security filters

The first type of attack is **bypassing security filters on Walter forbidden
query**. In this type of attack the Walter query is forbidden (Wookies is a 
forbidden species), but Suzann is
hiding Walter from the middleware filters (storm troopers filtering the docks).  
Eventually Walter is executed on the target, behind the filters (was hidden in
the cargo).

        [Attacker]              [Middleware]             [End Server]
            |                       |                        |
            >-req. Suzann(+Walter)->|                        |
            |                       >-requ. Suzann(+Walter)->|
            |                       |             \-Suzann-->|
            |                       |<--------- resp. Suzann-<
            |<-------- resp. Suzann-<                        |
            |                       |             \-Walter-->| [*]
            |                       |<---X----- resp. Walter-<

The problem occurs at `[*]`

Note here the `<--X---` arrow, the middleware may not be really aware that a
Walter query was emitted, and can reject the response (and close it). But the 
query has already been emitted, and this enough *could* be a problem.

You have an example of such issue in [my previous blog post][PREVIOUS_NGINX_ISSUE]
with Nginx as end server, Varnish as middleware, and very huge queries. In this
variant the Middleware receive a response while it still thinks the 1st query is
not even completly transmitted (just to say that between theory and real
exploits things can get quite complex).

To avoid loosing the response from Walter the attacker can sometimes try to
pipeline some other queries. But the attacker goal is maybe just to run the
Walter query without being filtered (like accessing known security exploit on a
CMS where an HTTP filter prevents regular access to the backoffice).

### Attack 2 : Replacement of regular response

The second type is **defacement of Ivan**. On a successful attack by Suzann,
anyone requesting Ivan would get a Walter response. This can be used to prevent
regular use of Ivan (Deny of Service), but could also be worst, Walter the
wookie could contain some very dangerous content (like javascript code). Just
imagine Ivan is a regular javascript library on a CDN used by several thousands
of people daily, if the CDN sends the Walter javascript in place of this one...  

Queries have to be **pipelined** by the attacker for this sort of attack.

        [Attacker]              [Middleware]             [End Server]
            |                        |                        |
            >-req. Suzann(+Walter) ->|                        |
            |-req. Ivan ---#2------->|                        |
            |                        >--req. Suzann(+Walter)->| [*1*]
            |                        |         \_req. Suzann->|
            |                        |<-------- resp. Suzann -<
            |<----#1--- resp. Suzann <                        |
            |                        |         \_req. Walter->| t1
            |                        >--req. Ivan ----------->| t2
            |                  [*2*] |<-------- resp. Walter -< t3
            |<----#2--- resp. Walter |                        |
            |                        |<---X-------- resp Ivan |


`Suzann(+Walter)` means that for the Middleware this is a simple `Suzann`
request but for the backend this is two pipelined queries.  
The middleware see a pipeline of 2 queries (Suzann/Ivan) but the backend
receive a pipeline of two queries (Suzann/Walter) and a third query (Ivan).

In the timeline you also have 3 times, t1, t2 and t3.  
The attack will fail if t2 occurs after t3 (for this the first Suzann may
sometimes be choosen to be slow enough to avoid sending the Walter response too
early).

The regular Ivan response may be rejected by the middleware (which already have
2 responses), that's just a side effect.

Here the biggest issue is at `[*2*]`, the middleware receive a Walter response
which is assigned to ivan request (request #2).

Suzann has performed some kind of Jedi trick on the empire dock's guards and
they feed the next ship requesting something from the docks with one or more
wookies instead of the regular cargo.

### Wait, how do other requests/people get impacted in the second type of attack?

That's a very important question. In the first type of attack the goal was to
bypass a security, so the role of the attacker was obvious.

On the second defacement type of attack the attacker seems the only guy impacted
by the defacement. But you need to get a large view of the picture.

First usage is to get a response on the Walter query (if Walter was a forbidden
query like in type 1 attack).

Second usage, if the middleware is a **cache server** the goal of the attack is
**cache poisoning**, where the faked response is stored on the wrong cache entry.
A successful attack will deface the responses for everybody, not only for the
attacker. This is the *obvious* attack, very dramatic (Ivan was replaced by
Walter in the cache and this will be for the cache lifetime duration).

But even without a caching problem an attacker can make a proxy server becomes
**crazy**. On some successful attacks the proxy will mix queries from several
clients. The attacker queries will be mixed with some other innocent queries
from innocent clients, even without a cache, remember this point. Most 
middlewares have to trust the backend responses timeline and when backend
responses goes wild strange things happen. This mix of communications between
different users is also in the last attack type (type 3, credential hijacking).
But we'll see in a coming article how user mix can happen without going to type
3.

### Attack 3 : Credentials Hijacking

This third type of attack was referenced in the 2005 Watchfire study. Most proxy
are now engineered well enough to prevent this from hapenning. It is now very
hard to have a proxy sending a query to a backend, reusing the same connection
as the one used on a previous unclosed communication  (or I did not try
hard enough, maybe).

The trick was to inject a partial query in the stream, and wait for the regular
user query, coming in the same backend connection and added to the partial
request. It means the proxy is able to add some data in `[+]` to a tcp/ip 
connection with the backend that was unfinished in `[-]`. But the proxy does not
know two queries were send, for the proxy there was only one query and the
response is already received.

               [Attacker]               [Middleware]          [End Server]
                    |                         |                     |
                    >-req. Suzann[+Walter] -->|                     |
                    |                         >-requ. Suzann ------>|
                    |                         |<----- resp. Suzann  |
                    |<---------- resp. Suzann |                     |
                    |                         | [*]                 |
     [Innocent]     |                         | \-requ. Walter ---->|
         |          |                         | (unterminated)      | [-]
         >--------------------- req. Ivan --->|                     |
         |                                    >-req. Ivan --------->| [+]
         |                                    |<----- resp. Walter -<
         |<-------------------- resp. Walter -<                     |

This was a complexe scheme, but for example the Ivan request could contain a
valid session that Walter did not have (**cookies**, **HTTP Authentication**).
Also this valid session was needed for Walter query to succeed.
Credentials used in Ivan query are stolen (**hijacked**) for a `Walter` query.

Damages of such issues are very high (you can make user perform unwanted POST
actions, using his own credentials and rights). Keep alive and pipelines are not used
in most proxies while communicating with backends.  
Implementing shared backends connections or pools is a dangerous thing.

### Transmitters and Splitters

In smuggling attacks you will need mainly two types of actors behaving
differently on some HTTP protocol issues.

On the first part you need **transmitters*.

A transmitter is an HTTP agent, a proxy, which receive an altered HTTP query and
transmits the alteration to an HTTP backend. When testing HTTP proxies you will
encounter a lot of proxies which are cleaning up strange queries (like you were
using tabulations as space separators, but the proxy is replacing tabulations
with spaces when talking to the backend). Here the transmitters, by definition,
is not cleaning up the *strange part* of the request. The transmitters, also,
see the altered HTTP request as an unique query.

The second actor of the attack is a **splitter**, an involuntary accomplice.
This agent receive the evil request from the **transmitter**.
For the splitter this transmitted request is not unique, it's a multiple request
(a pipeline) and this actor will emit several HTTP responses. This agent is 
**splitting** the request.  
Sending 2 responses for one query is enough, but it may also be one hundred.  
The splitter made a parsing error and detects a pipeline of queries (or the
transmitters made this error, not detecting it was really a pipeline).

We'll use a typology for the next schemas:

    >----qA-----> : HTTP query for request A
    <-----rAqA--< : HTTP response A matched with request A
    <-X---rAqA--< : HTTP response A rejected (connection close for example)
    <----*rAqB*-< : HTTP response A matched with request B (very Bad thing)
    >--qA+(qB)--> : HTTP query for request A, Hiding a query B
           [*CP*] : Cache poisoning
           [*RS*] : Response Splitting

The basic schema is:

        [Origin]            [transmitter]         [Splitter]
            |                    |                    |
            >-----qA+(qB)------->|                    |
            |                    >-----qA+(qB)------->| [*RS*]
            |                    |<-----------rAqA----<
            |<-----------rAqA----<                    |
            |                    |<-----------rBqB----<

Here we have a security issue in `[*RS*]` where a request splitting occurs.

If the Splitting attack can be issued by an application issue **you do not need
a transmitter** communicating an altered HTTP query.

In terms of **responsability** the HTTP splitter is having a real security issue.
Or at least that's what we could assume, when talking with project maintainers
it could be quite hard to have HTTP splitting issues considered as security
issues (let's hope this attitude will change in the future).  
The transmitter **could** detect the smuggling tentative and **should** clean up
the query before transmitting, but that's usually not considered a security
issue, unless every other actor implementing the HTTP RFC would see 2 queries
when the transmitter is only seing one (something like an *inverted splitter*).

Using this sort of schema attack of type 1 (filters bypass) is already achieved
with the simple case.

Attack of type 2 (defacement) needs a pipeline of queries. It also need a third
actor, a  **target**. The target is something like a cache which will be the
final victim.  
The target is usually also the transmitter.

Here is a type2 issue:

        [Origin]        [transmitter-target]         [Splitter]
            |                    |                    |
            >-----qA+(qB)------->|                    |
            >-----qC------------>|                    |
            |                    >-----qA+(qB)------->| [*RS*]
            |                    |<-----------rAqA----<
            |<-----------rAqA----<                    |
            |                    >-----qC------------>|
            |             [*CP*] |<-----------rBqB----<
            |<-----------*rBqC*--<                    |
            |                    |<-X---------rCqC----<

This sort of behavior can also go wrong without caching (no `[*CP*]`) if you can
make the `<--*rBqC*--<` response redirected to another user than the original
attacker (obviously this should never happen...).

If the Splitting attack can be issued by an application issue **you still do not
need a transmitter** but you need this actor to be a **target**.

### Encapsulating and Fingerprinting

In real life, the attacker may need to navigate through several
transmitters. Like hiting an HAProxy first, then an Apache mod_proxy, then a
Varnish and finally an Nginx (yes, that happens).

The first job of the attacker is **fingerprinting** the middleware. To identify
the layers present in the middleware you have some Headers in the responses
(like the `Server` header or somes variations on `X-Cache`). But you also have
the ability of checking the behaviors of the agents for each HTTP protocol error.

Every agent can have is own list of rejected syntax errors. For example Nginx
will always reject an HTTP request using CR as line terminator instead of CRLF.
Apache would not. Varnish3 will understand CR end of lines, Varnish 4 would not,
etc.

You can build a fingerprinting test to identify who is rejecting you (and
sometimes you'll get lucky and have the server signature in the error page).

And you can also use encapsulation to target the fingerprinting test at a
precise level. 

**Encapsulation**, is the ability to hide your HTTP query in several layers of
HTTP smuggling issues. Usually the first layers are applying some strict rules
on the HTTP headers or location, but if you find a transmitter issue in the layer
you can carry in the request body another type of smuggling issue (one that 
would be detected if used directly on this layer). The encapsulation is
available because usually the Proxy will not filter the request body (and
against a filter trying to decode the request body, you could use several layers
of Content-Transfer encoding).

In this example Middleware1 is a transmitter to a first type of smuggling noted
"()" but would prevent any smuggling of a second type "{}".
 We could say for example that the "()" smuggling issue is using a chunked 
encoding issue and that the "{}" one is based on doubling Content-Length headers.  
Middleware2 is a transmitter of the second type "{}" of smuggling (double
`Content-Length` headers).  
The End server is very sensible to the "{}" issue and is splitting the query.  

Goal of the attack is cache poisonning in Middleware2 with a `W` query response
on a `I` request. `W` is **forbidden** on Middleware 1 and also on Middleware 2.

    [Attacker]         [Middleware1]     [Middleware2]   [End Server]
        |            [transmitter ()]  [transmitter {}]  [ Splitter ]
        |                   |                |               |
        >-qS(+qA{+qW})----->|                |               |
        >-qB -------------->|                |               |
        >-qI--------------->|                |               |
        |                   >-qS(+qA{+qW})-->| [*RS*]        |
        |                   |                >----qS-------->|
        |                   |                |<-----rSqS-----<
        |                   |<----rSqS-------<               |
        |<---------rSqS-----<                |               |
        |                   >-qB------------>|               |
        |                   |                >--qA{+qW}----->| [*RS*]
        |                   |         [*CP*] <---------rAqA--<
        |                   |<---*rAqB*------<               |
        |<--------*rAqB*----<                |               |
        |                   >-qI------------>|               |
        |                   |         [*CP*] <---------rWqW--<
        |                   |<---*rWqI*------<               |
        |<--------*rWqI*----<                |               |
        |                   |                >--qB-->(...)

Just to add one step of complexity you can also imagine a system where an HTTP
response is forged (via a flaw in an application or via a stored attack), and
this HTTP response could contain a **response splitting** attack, 
something like `<--*rAqA(+rWqX)*--<`. Securities are always stronger in request
filters than in response filters on proxies, and most project would reject
theses issues as securty problems ("we have to trust the backend responses, you see, that's a
backend issue").

If the attackers can guess the servers and versions at each step of the
middleware, and if a lot of smuggling issues exists in the ecosystem, a complex
and very targeted attack can be made.

If you understood the previous paragraphs you are ready to test it (or to read
the [2005 Watchfire study][2005WATCHFIRE]).

### SSL/HTTPS as a protection?

Well, no, not really.

SSL is sometimes mentionned as one way of preventing HTTP Smuggling. It's not.

Having your HTTP message transmission encoded in an SSL tunnel is not preventing
bad interpretation of the message by the HTTP agent. HTTP Smuggling occurs 
*after* the transmission. Maybe having SSL tunnelled through a proxy which is
not trying to understand the content of the message (a pipe) could prevent a
Smuggling issue on this proxy, but that's all. Mmmh, yes it could also make the
simple tests more complex to perform (as it's hard to communicate in SSL in a
telnet session) but that's not a real defense for this subject (not that you
should not use https for other reasons).

## Testing HTTP

Usually an HTTP request is made by a browser. You have some really nice tools to
alter HTTP request on the browser for testing purpose. If you already try to
attack yourself (of course yourself) with XSS or HTML injections you certainly
already altered parameters on the queries with tools like Live HTTP Headers (and
 others), or maybe extracted curl queries from live queries.

But for HTTP smuggling you will usually need to test HTTP **without** a browser,
because you will need to make very bad queries, and browsers never does bad
queries. Well, in the past they was an issue end-of-line injections on Digest
 Authentication names or with bad separators on Ajax queries. But finding a flaw
in a browser that allows HTTP smuggling requests coming from *regular* browsers
is an exception. Smuggling does not usually imply that Suzann is an innocent
smuggler using a regular browser.

No, what you will need is the full control of all characters in a query. For 
example you will need to control what characters are used as space separators or
end-of-line.

Hopefully HTTP is a text based protocol, and is quite simple. If you never
tried it you can always try an HTTP session with a telnet on port 80 of your
server.

    $ telnet 127.0.0.1 80
    Trying 127.0.0.1...
    Connected to 127.0.0.1.
    Escape character is '^]'.
    GET / HTTP/1.1                <---start typing here... fast!
    Host: foobar                  <---required header in HTTP/1.1
                                  <--- last enter for end of request
    HTTP/1.1 301 Moved Permanently  <-- and now the server response
    Server: nginx
    Date: Sat, 25 Jul 2015 16:02:21 GMT
    Content-Type: text/html
    Content-Length: 178
    Connection: keep-alive
    Keep-Alive: timeout=15
    Location: http://foobar.example.com/
    X-Frame-Options: SAMEORIGIN
    
    <html>
    <head><title>301 Moved Permanently</title></head>
    <body bgcolor="white">
    <center><h1>301 Moved Permanently</h1></center>
    <hr><center>nginx</center>
    </body>
    </html>


But you need to type fast, and do not have a nice control on characters.
The other method for fast testing is using `printf` to print a query on screen:

    $ printf 'GET / HTTP/1.1\r\nHost:\tfoobar\r\n\r\n'
    GET / HTTP/1.1
    Host:	foobar
    

Or directly to the server (here I use **netcat** instead of telnet for that):

    $ printf 'GET / HTTP/1.1\r\nHost:\tfoobar\r\n\r\n' | nc 127.0.0.1 80
    HTTP/1.1 301 Moved Permanently
    Server: nginx
    Date: Sat, 25 Jul 2015 16:02:21 GMT
    Content-Type: text/html
    Content-Length: 178
    Connection: keep-alive
    Keep-Alive: timeout=15
    Location: http://foobar.example.com/
    X-Frame-Options: SAMEORIGIN
    
    <html>
    <head><title>301 Moved Permanently</title></head>
    <body bgcolor="white">
    <center><h1>301 Moved Permanently</h1></center>
    <hr><center>nginx</center>
    </body>
    </html>

With this sort of queries you can test easily the response of the server to a
degraded HTTP query, let's for example try to replace all CR-LF (`\r\n`) end of
lines with just CR (`\r`).

    $ printf 'GET / HTTP/1.1\rHost:\tfoobar\r\r' | nc 127.0.0.1 80
    <html>
    <head><title>400 Bad Request</title></head>
    <body bgcolor="white">
    <center><h1>400 Bad Request</h1></center>
    <hr><center>nginx</center>
    </body>
    </html>

And you can do advanced queries with printf alone. Like a simple pipeline of
queries:

    $ printf 'GET /Suzann.html HTTP/1.1\r\nHost: example.com\r\n\nGET /ivan.html HTTP/1.1\nHost:example.com\r\n\r\n' | nc 127.0.0.1 80

Which becomes hard to read (and here we have only the strict minimum headers).

Next step is to build your own tool. For my extensive tests I've build my tools
with **python**, using the `socket` library you have a very nice low level HTTP
client where all the strange things are allowed, and you have an high level
language to compute sizes (hiding queries in chunks, counting bytes, etc),
 or to add SSL support.

If you really want to study smuggling you will have to use **tcpdump** or
**wireshark** to study the transmission of the signal between the actors, who is
cleaning up the messages, what is not cleaned up, how does timers and size
thresholds alter the behaviors, etc.

The final tool, **the best one**, is **the code**, do not be afraid of reading
the code (when available). Learn the protocol and check implementations, that's
the reason of open source code, open source needs critical eyes studying the
code. That's the reason of superior robustness for open source code, but you
will certainly discover that a lot of code still need to be fixed.

## First final words

I'll end this article here, next things to come soon, with real world issues.
But while waiting for new contents you can already try to read some posts
and test your tools.

If you are using HTTP (and who isn't?), and usually use reverse proxies, SSL
terminators, reverse proxy caches, my first advice is to check that you have
recent versions.
Smuggling issues are real, some have been fixed in 2015, avoid keeping old
versions in production.

But I know this can be a hard task. So my second advice is to add an HTTP
cleaner in front of your infrastructure. Something like [HAProxy][HAPROXY]. This
tool is very strong to protect against smugglers (but take recent versions, of
 course). Simply reading the [configuration documentation][HACONF] of this
product you can find an excellent introduction to the HTTP protocol, with common
pitfalls documented.

  [2005WATCHFIRE]: http://www.cgisecurity.com/lib/HTTP-Request-Smuggling.pdf "HTTP Request Smuggling - watchfire (pdf)"
  [RFC_REQUEST_SMUGGLING_1]: https://tools.ietf.org/html/rfc7230#section-9.5 "9.5. Request Smuggling"
  [RFC_REQUEST_SMUGGLING_2]: https://tools.ietf.org/html/rfc7230#section-3.3.3 "3.3.3. Message Body Length"
  [PREVIOUS_NGINX_SMUGGLING]: http://regilero.github.io/security/english/2015/03/25/nginx-integer_truncation "Nginx Integer Truncation"
  [HPP]: https://www.owasp.org/images/b/ba/AppsecEU09_CarettoniDiPaola_v0.8.pdf "HTTP Parameter Pollution"
  [RESPONSE_SPLITTING]: https://www.owasp.org/index.php/HTTP_Response_Splitting "HTTP Response Splitting"
  [HAPROXY]: http://www.haproxy.org "HAProxy"
  [HACONF]: http://www.haproxy.org/download/1.6/doc/configuration.txt "HAProxy configuration"
  [WIKI_CHUNK]: https://en.wikipedia.org/wiki/Chunked_transfer_encoding "Chunked transfer encoding"
  [FRENCH]: http://makina-corpus.com/blog/metier/2015/problemes-de-http-smuggling-contrebandede-http-en-2015-partie-1
