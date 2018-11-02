---
layout: post
uuid: 9daab43e-eda2-2abba-312dcba518aa8d0808f
title: Web Security, Dompdf security issues details
categories: [english, Security]
tags: [Security, CVE, Injection]
pic: library.jpg
excerpt: details of december 2015's 3 CVE in dompdf, with one RCE.
---

<small>**English version** (**Version Française** disponible sur [makina corpus][FRENCH]).</small>
<small>estimated read time: 5min</small>

## Dompdf?

If you do not know [DomPDF][DOMPDF], that's a really nice library to render PDF document with PHP scripts.
I mean it, for anyone which already have had to use some other HTML to PDF converters, this library looks very nice.

Now, this lib made a thing that I consider a huge mistake for a library,
they provided, for years, a nice gui, directly in the library. From this GUI you
could check your settings, test the library tools, etc.

This looks like a nice tool, and in term of pure marketing (targeted to
developers and integrators), that's a really powerful utility.

But in the past this has lead to some security issues, like this [CVE-2014-2383][CVE2014],
"Information disclosure, arbitrary file read".

And in this post I'll describe 3 new CVE, discovered after this one, first
reported to the project in june 2014, and fixed in version 0.6.2 in december 2015 (so, almost 2016).

Note that the **0.7 branch is not impacted**. Note also that the CVE year is 2014,
but anything downloaded before end of december 2015 was quite certainly impacted.

 * [CVE-2014-5011][CVE1] : Information Disclosure
 * [CVE-2014-5012][CVE2] : DOS (Deny of Service)
 * [CVE-2014-5013][CVE3] : RCE (Remote Code Execution), complement of CVE-2014-2383

### fixed in 0.6.2 ?

if you check the [RELEASES] page of the project, and download versions 0.6.0, 0.6.1 and 0.6.2,
to check the differences, you will lose part of the real history.
Version 0.6.1 has been fixed in github fixed after initial release.
You can have a different 0.6.1 version if you downloaded it before.

The RCE issue has been removed from 0.6.1 but was in fact present in this
version if you downloaded it before (quite certainly before december 2015).

## CVE-2014-5011 : Information Disclosure

This issue is the easy one.

The library has long been releasing a `www` directory, with some PHP files inside.

Most PHP installation will run any PHP set in the web document root (**note that
it's a good security thing to avoid that and restrict PHP execution to the bootstrapper
only -- `index.php` --**, if you can, and if your application is modern you certainly could, unless
it's Drupal8, because, because, I don't know why they keep putting all libraries
and all PHP sources in the document root, please help me close this parenthesis).

So, you have this directory, with a lot of PHP scripts available. And one of these
scripts is `www/setup.php`.

This script is the definition of an **information Disclosure**, with real versions
and paths printed on a public page:

<img src="/theme/img/posts/yes1.png" width="1000" height="648" alt="gimme some data"/>

Look at some of theses settings:

<img src="/theme/img/posts/yes2.png" width="924" height="247" alt="oyeah, gimme more"/>

Various fix has been applied on this issue, mainly restricting access on *setup*
and some other places to localhost only, so that these pages should not be indexed
by google anymore, and that no hacker could use it to inspect your application
security level so easily.

Some other informations leaks were available at `www/debugger.php` and `www/fonts.php`.

We'll see below with the RCE that this disclosure is a really big problem if
some settings are not at the right value.

## CVE-2014-5012: Deny of Service

The library provide an example of implementation, used in the GUI screens,
especially on a demonstration page.

This script is `dompdf.php`.

You can try to use it on some very heavy examples, like the full utf-8 render.
Costly public script, but not enough for a realy DOS vector.

But a real not-nice-at-all-call is requesting the render of the dompdf configuration file (I first
tried it to check if I would get a pdf with the library settings rendered):

    dompdf/dompdf.php?base_path=&options[Attachment]=0&input_file=dompdf_config.inc.php

Something goes wrong while dompdf is trying to render this file, and the
script will never end his task (not until php max memory is reached).

That's a better Deny of Service vector.

## And now a Remote command execution ...

### Back to the old CVE-2014-2383

This previous CVE [CVE-2014-2383][CVE2014] (which is not mine) was available on
version 0.6.0 (now a really old version).

The attack used `php://filter` to extract any file readable by PHP on the server
(open_basedir is a limitation on which file are available, and finding path to files is not always easy, but refer to the
Information Disclosure problem for a full access to open_basedir setting value or paths).

It also used the `dompdf.php` file, present in the library, which is necessary for
the gui demonstrations, but is in fact useless for most dompdf integration (it
means one of the simplest way of fixing this issue, the DOS and the RCE is to
remove this file).

Say, if you want to read the `/etc/passwd` file you can try something like
`/dompdf.php?input_file=php://filter/read=convert.base64-encode/resource=/etc/passwd` and
the result, in a PDF document, is this file, simply base64 encoded (use base64
decode and you have the file content). The *`php://filter+base64`* trick is the
new way of doing local file inclusions with modern PHP.

This issue was fixed in 0.6.1.

The `php://` filter support was removed.

### CVE-2014-5013 RCE: exploit data uri instead of php:// filter

An RCE, or Remote Code Execution is a very bad issue. It means attackers can run
their own PHP code on your server. From that you cannot do a lot of things.

Before giving the details, I'll give the first counter measures.

 * **Do not allow `DOMPDF_ENABLE_PHP`** : that's the default setting, it's forbidden
 by default, if you ever enabled that please remove it, right now. This setting's default
 protected you from the previous `php://` filter attack also.
 * **Do not allow `DOMPDF_ENABLE_REMOTE`** : same thing, default is false, if you
 set true remove it, right now, or set your dompdf version to 0.6.2 or greater.

Note that the Information Disclosure issue **will** reveal theses settings to
everybody, even google.

Let's first have a look at theses strange settings, that you should not allow,
from the config file:


{% highlight php %}
/**
* Enable inline PHP
*
* If this setting is set to true then DOMPDF will automatically evaluate
* inline PHP contained within <script type="text/php"> ... </script> tags.
*
* Attention!
* Enabling this for documents you do not trust (e.g. arbitrary remote html
* pages) is a security risk. Inline scripts are run with the same level of
* system access available to dompdf. Set this option to false (recommended)
* if you wish to process untrusted documents.
*
* @var bool
*/
def("DOMPDF_ENABLE_PHP", false);

/**
 * Enable remote file access
 *
 * If this setting is set to true, DOMPDF will access remote sites for
 * images and CSS files as required.
 * This is required for part of test case www/test/image_variants.html through www/examples.php
 *
 * Attention!
 * This can be a security risk, in particular in combination with DOMPDF_ENABLE_PHP and
 * allowing remote access to dompdf.php or on allowing remote html code to be passed to
 * $dompdf = new DOMPDF(); $dompdf->load_html(...);
 * This allows anonymous users to download legally doubtful internet content which on
 * tracing back appears to being downloaded by your server, or allows malicious php code
 * in remote html pages to be executed by your server with your account privileges.
 *
 * @var bool
 */
def("DOMPDF_ENABLE_REMOTE", false);
{% endhighlight %}

Reading that I wonder **why people would activate these settings** ? In fact the
*`enable_remote`* is the easiest way to have images in your PDF, if you have
absolute domains uri for images you will need to enable this option to have
dompdf fetch the image and render it.

The *`enable_php`* part is worst, it is a way of defining PDF specific tasks in a
php script, using an HTML template. with some provided variables like `$pdf`,
`$PAGE_NUM` and `$PAGE_COUNT`. The new versions use css markup for such tasks.
Using a PHP eval to run this sort of task was a bad idea. It leads to a real call to
`eval()` in the code, that we will exploit.

The `dompdf.php` script can render a pdf, the *input_file* parameter could be a file,
but also a protocol. Anything detected as a remote protocol will only be available
in *enable_remote* mode.

The previous security issue used the `php://` protocol, which was then filtered.

The `data://` protocol is not blocked and is sometime used to embed images in the
PDF by giving the full encoded image as a data uri parameter.

The old trick for dompdf images was using HTML sources in this form:

{% highlight html %}
<img src="data:image/jpeg;base64,HERE_SOME_BASE64_ENCODED_BINARY_THINGS">
{% endhighlight %}

Using **data** to embed images in the PDF is a nice hack, if you have never seen a
data-uri image check github's 404 pages HTML sources.

But the [data-uri][DATAURI] protocol is not limited to images support.
It can embed any mime document. A php script for example is a document with
mime type `application/x-httpd-php` (you could also try XML files for XXE issues).

Let's say I have this small PHP script:

{% highlight php %}
<?php
echo 'PHP RCE : ' . phpversion();
echo "bye";
?>
{% endhighlight %}

Note that I could do some other things in PHP, that's just an example.

In a data URI source this same PHP script content can be written like that (base64 encoding is just a way of rewritting something in ascii-7):

{% highlight html %}
data:application/x-httpd-php;charset=utf-8;base64,PD9waHANCmVjaG8gJ1BIUCBSQ0UgOiAnIC4gcGhwdmVyc2lvbigpOw0KZWNobyAiYnllIjsNCj8+
{% endhighlight %}

With some url encoding (because we'll use that on an url) that is:

{% highlight html %}
data%3Aapplication%2Fx-httpd-php%3Bcharset%3Dutf-8%3Bbase64%2CPD9waHANCmVjaG8gJ1BIUCBSQ0UgOiAnIC4gcGhwdmVyc2lvbigpOw0KZWNobyAiYnllIjsNCj8%2B
{% endhighlight %}

And the final attack is:

{% highlight html %}
http://<target>/<path>/dompdf/dompdf.php?base_path=&options[Attachment]=0&input_file=data%3Aapplication%2Fx-httpd-php%3Bcharset%3Dutf-8%3Bbase64%2CPD9waHANCmluY2x1ZGUgKCcvZXRjL3Bhc3N3ZCcpOw0KZWNobyAiYnllIjsNCj8%2B
{% endhighlight %}

If default settings for `DOMPDF_ENABLE_PHP` and `DOMPDF_ENABLE_REMOTE` are
altered (to true) this attack will successfully run the PHP script and render
the output of this script to a PDF document (which is in fact only an optionnal side-effect).
This Can be used for local or remote
file inclusion, but also to edit or create a php file, run a shell script, etc.
Chances are this exploit would be used to connect your server in a botnet.

## Last words

 * Avoid using `eval()` in your web code
 * Avoid adding demonstrations to your libraries, or ensure that they will not
  run in production
 * Update your dompdf installation. Version 0.7 is a revolution, it may be hard
  to switch to that version, but moving an old 0.6.0 or 0.6.1 version to 0.6.2
  should be straightforward, if it breaks something revert the code and check next
  point.
 * if you use dompdf in a cms, you can safely **remove the `www` subdirectory
 and the `dompdf.php` file** in that library, rename it first if you do not
 believe me, the CMS is quite certainly using the library classes, and not the
 demonstration code and runner.
 * if you enabled the two dangerous settings, then revert it even if it breaks
 something (choose between breaking a features and giving your server to spammers)
 * if you use a modern PHP application, please put PHP libraries outside of the
 web document root.

  [FRENCH]: http://www.makina-corpus.com/blog/metier/2016/securite-web-detail-de-failles-de-securite-dompdf
  [DOMPDF]: https://github.com/dompdf/dompdf
  [CVE2014]: https://www.portcullis-security.com/security-research-and-downloads/security-advisories/cve-2014-2383/
  [CVE1]: http://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2014-5011
  [CVE2]: https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2014-5012
  [CVE3]: https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2014-5013
  [RELEASES]: https://github.com/dompdf/dompdf/releases
  [DATAURI]: https://developer.mozilla.org/fr/docs/Web/HTTP/Basics_of_HTTP/Data_URIs