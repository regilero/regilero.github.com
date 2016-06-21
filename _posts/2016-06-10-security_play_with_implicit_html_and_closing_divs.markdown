---
layout: post
uuid: 9addd55e-aff4-4qdq-a8eef80dfee8d080f8
title: Web Security, using bad HTML to evade from a DIV
categories: [Security, English]
tags: [Security, HTML, Injection]
pic: counting.jpg
excerpt: Break HTML layouts with only bad HTML and the browsers help.
---

<small>**English version** (**Version Française** disponible sur [makina corpus][FRENCH]).</small>
<small>estimated read time: 10min</small>

## Why?

Have you ever wondered why you cannot enter any HTML on Facebook? It seems so
easy on a lot of website to contribute with a small HTML subset, why don't they
allow it?

Or maybe you knew that it was possible in Facebook Notes, before April 2014, you
had a little rich text editor where you could enter some HTML tags (both in
wysiwyg and raw mode). But, you cannot do that anymore, you are enforced in 
wysiwyg mode, and even using the API you will see that the very small part of
HTML you can use will always be very very clean. Very few nested levels,
very strict opening/closing policy for tags, no attributes, etc.

Well, in this article I'll try to explain why. I'll show you how, by simply
playing with **bad HTML syntax** on a very small subset of HTML, it is easy
for contributed HTML to **evade the box** and write everywhere on the page.

This was a 1500 $USD facebook bounty (and a Github T-shirt). So, yes, it's very
simple but it's still very annoying and real.

I like to inspect **very simple things**, and HTML box evasion is something very
very simple. So simple that most people would not even see why it is a problem.

So, before reading, think about HTML contributions and HTML injection, this is
not about XSS or SQL injection. The problem here is:

 * **Can you let the user contribute a small part of your layout with a small subset of HTML?**
 * Can you ensure the contributed content will stay *in the box*, in the dedicated layout subset.

This impacts every markup language where the final destination is HTML (like 
partial HTML, of course, but also markdown, REST, etc.).

## So what?

### Implicit HTML and the browser fixing your errors

When you feed a browser with some HTML, the browser is very kind and will try to
fix a big numbers of errors that could be present in the page.

This behavior was a very important part of the web success. If the browsers made a
*White-Page-Of-Death* at every HTML syntax error, the web would be really
smaller.

**This is cool for the end user.**

**This is cool for the web developper.**

**This is bad in terms of security.**

One of the way the browsers will fix the HTML is by adding closing tags when the
page clearly forgot to close some tags.

So this:

{% highlight html %}
    <!-- initial -->
    <div class="foo">
      <ul>
        <li>foo
        <li>bar
      </ul>
    </div>
{% endhighlight %}

Is automatically rewritten with closing `</LI>`:

{% highlight html %}
    <!-- rendered -->
    <div class="foo">
      <ul>
        <li>foo</LI>
        <li>bar</LI>
      </ul>
    </div>
{% endhighlight %}

But let's look at something nastier, we have an opening `<DIV>` inside the `<LI>`:

{% highlight html %}
    <!-- initial -->
    <div class="foo">
      <ul>
        <li>foo
          <div class="second">
             test
        </li>
        <li>bar<li>
      </ul>
    </div>
{% endhighlight %}

The browser will add the closing DIV:

{% highlight html %}
    <!-- rendered -->
    <div class="foo">
      <ul>
        <li>foo
          <div class="second">
            test
          </DIV>  <!-- implicit HTML -->
        </li>
        <li>bar<li>
      </ul>
    </div>
{% endhighlight %}

Chances are that a **server side output filter**, filtering HTML contributions
would have **detected** this HTML as invalid, if you **count opening and closing
tags** you can detect that a closing tag is missing.

So our bad contributor will instead write this:

{% highlight html %}
    <!-- initial -->
    <div class="foo">
      <ul>
        <li>foo<div class="second"><div class="third">test</li>
        <li>bar<li>
      </ul>
      </div> <!-- end third -->
      </div> <!-- end second -->
    </div>
{% endhighlight %}

And **if you count** the number of closing and opening tags, or if you try to
cleanup this with some regexp (are you crazy?), chances are that this will look
good.

And now the browser result:

{% highlight html %}
    <!-- rendered -->
    <div class="foo">
      <ul>
        <li>foo
           <div class="second">
            <div class="third">test
            </DIV> <!-- implicit HTML - end third-->
           </DIV> <!-- implicit HTML - end second -->
        </li>
        <li>bar<li>
      </ul>
      </div> <!-- end third? no, end foo -->
      </div> <!-- end second? no end foo's parent if any -->
    </div> <!-- end foo's parent's parent if any -->
{% endhighlight %}

Two `</DIV>` are **impliclty added by the browser**, because you cannot close
the `<LI>` without closing the `<DIV>` inside. And now, on the final page, you have
2 extras closing divs !

### Ok, too much closing divs, and then?

If the contributor can enter `<div>` and `</div>`, and if you count the number
of closing and opening divs to assume the HTML is correct, **you are wrong**.

The HTML is correct only if **the order** of the opening and closing tags is
correct, if some tags are closed before some others it may breaks the layout
(it depends of the tags).

For the contibutors, this means writing outside of the controlled zone (the
user-comment box for example) and adding content, with the subset of HTML that
they are allowed to use, on other parts of the page (maybe playing with `<table>`
and `<br/>` to fake content on some parts of your layout that other users will
trust more than a spam comment box (see last examples at the end of this text).

## Demo

Here are some iframes using the implicit DIV closing trick, and writing one
simple line of text on the `main` div, instead of writing it 3 nested DIV
deeper.

A nice thing to do is opening one of theses iframes in a new window and looking
at the source. This is an example for the first iframe, where we cans see in red
that something was detected as wrong.

<img src="/theme/img/posts/t1_html_source.png">

Inspecting the DOM we see the fixed divs

<img src="/theme/img/posts/t1_html_dom.png">

Here:

* the goal is to write something **in red**, in the main div
* somes tests should fail (using `<P>` or `<TD>` `<TR>` we do not break the divs
as would most inline tags like `<span>`, `<strong>`, `<sub>`, etc.)

<table>
<tr><td><small><a href="///theme/resource/t1.html">direct link</a></small></td><td><small><a href="///theme/resource/t1.html">direct link</a></small></td></tr><td>
<iframe src=/theme/resource/t1.html style="height:450px; width: 350px; border: 1px solid #ccc;"></iframe></td><td>
<iframe src=/theme/resource/t2.html style="height:450px; width: 350px; border: 1px solid #ccc;"></iframe></td></tr>
<tr><td><small><a href="///theme/resource/t1.html">direct link</a></small></td><td><small><a href="///theme/resource/t1.html">direct link</a></small></td></tr><td>
<iframe src=/theme/resource/t3.html style="height:450px; width: 350px; border: 1px solid #ccc;"></iframe></td><td>
<iframe src=/theme/resource/t4.html style="height:450px; width: 350px; border: 1px solid #ccc;"></iframe></td></tr>
<tr><td><small><a href="///theme/resource/t1.html">direct link</a></small></td><td><small><a href="///theme/resource/t1.html">direct link</a></small></td></tr><td>
<iframe src=/theme/resource/t5.html style="height:450px; width: 350px; border: 1px solid #ccc;"></iframe></td><td>
<iframe src=/theme/resource/t6.html style="height:450px; width: 350px; border: 1px solid #ccc;"></iframe></td></tr>
<tr><td><small><a href="///theme/resource/t1.html">direct link</a></small></td><td><small><a href="///theme/resource/t1.html">direct link</a></small></td></tr><td>
<iframe src=/theme/resource/t7.html style="height:450px; width: 350px; border: 1px solid #ccc;"></iframe></td><td>
<iframe src=/theme/resource/t8.html style="height:450px; width: 350px; border: 1px solid #ccc;"></iframe></td></tr>
<tr><td><small><a href="///theme/resource/t1.html">direct link</a></small></td><td><small><a href="///theme/resource/t1.html">direct link</a></small></td></tr><td>
<iframe src=/theme/resource/t9.html style="height:450px; width: 350px; border: 1px solid #ccc;"></iframe></td><td>
<iframe src=/theme/resource/t10.html style="height:450px; width: 350px; border: 1px solid #ccc;"></iframe></td></tr>
<tr><td><small><a href="///theme/resource/t1.html">direct link</a></small></td><td><small><a href="///theme/resource/t1.html">direct link</a></small></td></tr><td>
<iframe src=/theme/resource/t11.html style="height:450px; width: 350px; border: 1px solid #ccc;"></iframe></td><td>
<iframe src=/theme/resource/t12.html style="height:450px; width: 350px; border: 1px solid #ccc;"></iframe></td></tr>
<tr><td><small><a href="///theme/resource/t1.html">direct link</a></small></td><td><small><a href="///theme/resource/t1.html">direct link</a></small></td></tr><td>
<iframe src=/theme/resource/t13.html style="height:450px; width: 350px; border: 1px solid #ccc;"></iframe></td><td>
<iframe src=/theme/resource/t14.html style="height:450px; width: 350px; border: 1px solid #ccc;"></iframe></td></tr>
<tr><td><small><a href="///theme/resource/t1.html">direct link</a></small></td><td><small><a href="///theme/resource/t1.html">direct link</a></small></td></tr><td>
<iframe src=/theme/resource/t15.html style="height:450px; width: 350px; border: 1px solid #ccc;"></iframe></td><td>
<iframe src=/theme/resource/t16.html style="height:450px; width: 350px; border: 1px solid #ccc;"></iframe></td></tr>
<tr><td><small><a href="///theme/resource/t1.html">direct link</a></small></td><td>&nbsp;</td></tr><td>
<iframe src=/theme/resource/t17.html style="height:450px; width: 350px; border: 1px solid #ccc;"></iframe></td><td></td></tr>
</table>

**H1, H2, H3, PRE, LI**

Theses are the tags I prefer.

Because chances are that theses tags are in the list of allowed tags for contributors.

### Will it break `<section>` or `<article>` ?

Yes.

First, if you allow `<section>` or `<article>` in allowed contributors tags, it
will obviously allow the contributor to close such tags. But this would be a very
bad move.

More generaly, if you use one `<DIV>` on your layout, closing this tag will also
close any `<section>` or `<article>` embedded inside.

Let's see it in a more complex layout:

Here is a new iframe with a full layout, you can see a div around the article.

<iframe src=/theme/resource/t18.html style="height:450px; width: 700px; border: 1px solid #ccc;"></iframe>

And here is this layout after a bad comment closing the comment and main divs (the real aside section and footers are far in the bottom):

<iframe src=/theme/resource/t19.html style="height:450px; width: 700px; border: 1px solid #ccc;"></iframe>

### What if direct HTML is not allowed?

If the only way to contribute is Markdown, Rest, or others wiki-like syntax, you
cannot directly enter bad HTML.

Well, for markdown it depends of the flavor, because you can always enter raw
HTML in markdown, unless this fonctionnality is removed.

Anyway, with a language generating HTML the game is to find strange syntax in
this language which will generate bad HTML.

Be careful, previews modes are usually made by some js syntax parser, theses
parsers are usually less robust than the real final generators. So a bad syntax
in a preview mode means almost nothing.

I wont give you specific syntax errors example, it depends on the engine, you'll
have to search on your own. 

## Protections

If you want to allow contributions, here are some thoughts:

 * why not simply allowing unformatted text?
 * why allowing `<div>`, if you use `<div>` in your layout you could in fact
   prevent any contributions from using this HTML tag
 * more generally do not allow tags used for your layout (like article or section)
 * check your CMS for functions applying HTML syntax cleanup (there is one in
   Drupal for example)
 * avoid regex to cleanup (filter) the contributed HTML, prefer DOM-based tools
  when they are available,
  theses tools will analyze the contributed text stream, build a dom tree, then
  generate HTML output from the tree, so tags will always be in the right order,
  and can even be filtered for attributes and id cleanup.
 * that said, regexp based filters can also work and perform the same filtering
 task, here is for example [a very good drupal7 module, wysiwyg_filter][WYSIWYGFILTER]

  [WYSIWYGFILTER]: https://www.drupal.org/project/wysiwyg_filter "Drupal WYSIWYG filter"
  [FRENCH]: http://makina-corpus.com/blog/metier/2016/TODO
