---
layout: post
uuid: 671fb11a-8778-11e3-b2e4-d231feb1dc81 
title: SaltStack, Use file.accumulated accumulators with file.managed and file.blockreplace
categories: [english, SaltStack]
tags: [SaltStack, BlockReplace, Managed, Accumulated]
pic: replaceblock2.jpg
excerpt: This is a detailled example of salt-stack's file.accumulated usage.
---

[On the last salt-stack post]({% post_url 2014-01-20-saltstack_step_by_step_file_blockreplace %}) we saw a first step by step usage of [``file.blockreplace``][FILEBLOCKREPLACE]. On this post we'll study usage of state accumulators with [``file.accumulated``][FILEACCUMULATED]. Accumulators are used to collect data on several states and let you use this data on other file states (Actually only the blockreplace and managed states).

You can find the examples used on this post on [this github repository][GITHUBEXAMPLES].

Why using accumulated accumulators?
-----------------------------------

Let's start by the needs. What sort of problems could be solved by accumulators?. In fact, the idea is to use states executed before a final state. And this state ordering can be solved using requisites or orders. On theses first states you **collect data** for later usage. Then, on the final state, you have a dictionary containing this collected data, the *accumulator* dictionary, and you can do what you want with it with jinja, or even without jinja in the blockreplace case. Note that you only collect data in the current highstate execution, so all accumulators must run (be included) if you need the data at the end.

You can use this system to record one or more lists of things likes users, services, addresses, configuration commands or wathever else you want, while running the states. And all theses states recording data will have to run before the one using that data for something (writing theses lists on a targeted file). Doing that you will avoid doing the write operation after each new record, you will wait for the final list before doing the write. This will be faster, but also easier to manage. Inserting, updating and removing data in a file, in one shot.

In this post I will use two examples, one for a managed file and one for a blockreplace edited file. The first example is an apache configuration file with several states adding some inputs inside. The second example will fill a list of DNS IP-name associations that should be added in a hosts file.

States ordering
---------------

As I said before states ordering is very important here. The final step must be final. And used states may be split upon several sls files. You can use the order ``order`` keyword to ensure the final order, this way:

{% highlight yaml linenos %}
    # first.sls
    STATEID1:
      cmd.run:
        name: echo STATEID1
        order: 100
    
    # second.sls
    STATEID2:
      cmd.run:
        name: echo last
        order: 900
    
    # third sls
    STATEID3:
      cmd.run
        name: echo STATEID3
        order: 200
{% endhighlight %}

This will make a final execution order of:

{% highlight yaml linenos %}
    echo STATEID1
    echo STATEID3
    echo last
{% endhighlight %}

But to do that you need an ordering schema for all you states. I do not find that very useful when you have a lot of states.

The second way of ordering states is using [``requisites``][REQUISITES]. Using this method you can declare dependencies between states. But having a list of all the states that collects data into accumulators, and eediting this list on the state using the accumulator would be quite hard. The best thing here is to use the ``*_in`` form of the requisites, to declare the dependency from the dependent state. When adding a new state using the accumulator the dependency will have to be set in this state and not in the previous managed state entry.

So using ``require_in`` the previous example would be:

{% highlight yaml linenos %}
    # first.sls
    STATEID1:
      cmd.run:
        name: echo STATEID1
        require_in:
          - cmd: STATEID2
    
    # second.sls
    STATEID2:
      cmd.run:
        name: echo last
    
    # third sls
    STATEID3:
      cmd.run
        name: echo STATEID3
        require_in:
          - cmd: STATEID2
{% endhighlight %}

**Be careful:** the syntax for a requisite is:

{% highlight yaml linenos %}
    <requisite>:
      - <module>: <state id>
{% endhighlight %}

It is not:

{% highlight yaml linenos %}
    <requisite>:
      - <module>.<function>: <state id>
{% endhighlight %}

So it is not ``cmd.run:`` here but only ``cmd:``. And as soon as you start using requisites you see that using meaningfull states ids and not names shortcuts to declare states is quite important, for clarity at least.

file.managed using file.accumulated
-----------------------------------

All [examples are available on github here][GITHUBEXAMPLES].

In this first example we'll use several states, the last state will install a [managed file][FILEMANAGED] in ``/etc/apache2/sites-available/100-foo.example.com``, it's an apache virtualhost file, in the debian way. The jinja template associated with this file will contain the basic rules, but we want to allow some other states to add instructions on this virtualhost. We'll see theses states later. We start by the end, with this state building a virtualhost file in a ``example_com_apache_virtualhost.sls`` file:

{% highlight yaml linenos %}
    apache-install:
      pkg.installed:
        - pkgs:
          - apache2
    
    100_example_com_virtualhost:
      file.managed:
        - source: salt://files/apache_vhost
        - name: /etc/apache2/sites-available/100-example.com
        - user: root
        - group: root
        - mode: "0664"
        - template: jinja
        - defaults:
            - docroot: /path/to/www
            - servername: example.com
        - require:
            - pkg: apache-install
{% endhighlight %}

This file should be put somewhere on your state tree, in this example I will make the function calls as if it were on the root of this tree (like the top.sls file). But there's also a *source* template for the managed file, which is called ``salt://files/apache_vhost``, this file should be present under the salt master tree, in the directory ``files`` (or alter the used path). This is this very simple basic virtualhost example template content:

{% highlight apache linenos %}
{% raw  %}
    # Main Virtualhost for {{ servername }}
    <VirtualHost *:80>
        ServerAdmin foo@example.com
    
        DocumentRoot {{ docroot }}
    
        ServerName {{ servername }}
    
        LogLevel info
    
      <Directory />
        AllowOverride None
        Order allow, deny
        deny from all
      </Directory>
    
      <Directory {{ docroot }}>
        Options FollowSymLinks
        AllowOverride None
        Order allow,deny
        Allow from all
      </Directory>
    
    </VirtualHost>
{% endraw %}
{% endhighlight %}

Let's test this simple state:

{% highlight bash linenos %}
    $# salt-call -linfo state.sls example_com_apache_virtualhost
{% endhighlight %}

You should en up with two states in success and a ``/etc/apache2/sites-available/100-example.com`` file created.
Now let's say we want other states, an infinite list of other states, to be able to alter this file and add content either in the main Directory section or at the end of the file. This way other states could add some apache configuration (this is an example, another way of doing it could be apache's include directive).

Here comes the **accumulator** jinja variable. It's a dictionnary, with several keys. Each key of this dictionary is the result of **one or more** [``file.accumulated``][FILEACCUMULATED] states. So you may have this variable (or not) and it may contain some keys with text data inside. Let's see how to use this on the jinja template (and at first, we known it's empty, we did not used any accumulated state yet).

{% highlight jinja linenos %}
{% raw  %}
    # Main Virtualhost for {{ servername }}
    <VirtualHost *:80>
        ServerAdmin foo@example.com
    
        DocumentRoot {{ docroot }}
    
        ServerName {{ servername }}
    
        LogLevel info
    
      <Directory />
        AllowOverride None
        Order allow, deny
        deny from all
      </Directory>
    
      <Directory {{ docroot }}>
        Options FollowSymLinks
        AllowOverride None
        Order allow,deny
        Allow from all

        # Here any extra configuration settings if any:
        {% if accumulator|default(False) %}
        {%   if 'extra-settings-example-virtualhost-maindir' in accumulator %}
        {%     for line in accumulator['extra-settings-example-virtualhost-maindir'] %}
        {{ line }}
        {%     endfor %}
        {%   endif %}
        {% endif %}

      </Directory>

    # Here any extra configuration settings if any:
    {% if accumulator|default(False) %}
    {%   if 'extra-settings-example-virtualhost' in accumulator %}
    {%     for line in accumulator['extra-settings-example-virtualhost'] %}
    {{ line }}
    {%     endfor %}
    {%   endif %}
    {% endif %}
  
    </VirtualHost>
{% endraw %}
{% endhighlight %}

If you run the state nothing should move, except maybe the two comments lines. The thing we need to do now is to feed this accumulator variable with [``file.accumulated``][FILEACCUMULATED] states. On theses states the ``name`` of the state will match the accumulator key.

So, for this example, we will use a second sls file ``more-things-for-virtualhost.sls`` :

{% highlight yaml linenos %}
    {# Include dependencies #}
    include:
      - example_com_apache_virtualhost
    
    example-a-first-rewrite-rule:
      file.accumulated:
        - name: extra-settings-example-virtualhost-maindir
        - filename: /etc/apache2/sites-available/100-example.com
        - text: |
            # this is an example of thing added in the middle
            RewriteEngine On
            RewriteCond %{REQUEST_FILENAME}  -d
            RewriteRule ^(.+[^/])$  $1/  [R]
        - require_in:
            - file: 100_example_com_virtualhost
    
    example-some-icons-added:
      file.accumulated:
        - name: extra-settings-example-virtualhost
        - filename: /etc/apache2/sites-available/100-example.com
        - text: |
            # this is an example of thing added at the end'
            Alias /icons /path/to/icons>
            <Directory /path/to/icons
              Order allow,deny
              Allow from all
            </Directory>
        - require_in:
            - file: 100_example_com_virtualhost
    
    example-another-thing:
      file.accumulated:
        - name: extra-settings-example-virtualhost-maindir
        - filename: /etc/apache2/sites-available/100-example.com
        - text: |
            # this is another example of thing added in the middle
            RewriteRule    ^/cgi-bin/imagemap(.*)  $1  [PT]
        - require_in:
            - file: 100_example_com_virtualhost
        - require:
            - file: example-a-first-rewrite-rule
    
    example-another-thing-again:
      file.accumulated:
        - name: extra-settings-example-virtualhost-maindir
        - filename: /etc/apache2/sites-available/100-example.com
        - text: |
            # this is another example of thing added in the middle
            <FilesMatch "\.(gif|jpe?g|png)$">
                ExpiresDefault A2592000
            </FilesMatch>
        - require_in:
            - file: 100_example_com_virtualhost
{% endhighlight %}

Now let's run this new sls:

{% highlight bash linenos %}
    $# salt-call -linfo state.sls more-things-for-virtualhost
{% endhighlight %}

You should get a nice diff showing you that all theses states added content on the right place:

{% highlight apache linenos %}
    +++ 
    @@ -21,9 +21,41 @@
         Allow from all
         # Here any extra configuration settings if any:
         
    +    
    +    
    +    # this is an example of thing added in the middle
    +RewriteEngine On
    +RewriteCond %{REQUEST_FILENAME}  -d
    +RewriteRule ^(.+[^/])$  $1/  [R]
    +
    +    
    +    # this is another example of thing added in the middle
    +RewriteRule    ^/cgi-bin/imagemap(.*)  $1  [PT]
    +
    +    
    +    # this is another example of thing added in the middle
    +<FilesMatch "\.(gif|jpe?g|png)$">
    +    ExpiresDefault A2592000
    +</FilesMatch>
    +
    +    
    +    
    +    
       </Directory>
     
     # Here any extra configuration settings if any:
     
     
    +
    +# this is an example of thing added at the end'
    +Alias /icons /path/to/icons>
    +<Directory /path/to/icons
    +  Order allow,deny
    +  Allow from all
    +</Directory>
    +
    +
    +
    +
    +
     </VirtualHost>
{% endhighlight %}

You can see that some extra spaces were added by my jinja control commands. We can strip down those whitespaces with jinja's``-``. Instead of:

{% highlight jinja linenos %}
{% raw  %}
    {% if accumulator|default(False) %}
    {%   if 'extra-settings-example-virtualhost-maindir' in accumulator %}
    {%     for line in accumulator['extra-settings-example-virtualhost-maindir'] %}
    {{ line }}
    {%     endfor %}
    {%   endif %}
    {% endif %}
{% endraw %}
{% endhighlight %}

Use:

{% highlight jinja linenos %}
{% raw  %}
    {% if accumulator|default(False) -%}
    {%   if 'extra-settings-example-virtualhost-maindir' in accumulator -%}
    {%     for line in accumulator['extra-settings-example-virtualhost-maindir'] -%}
    {{ line }}
    {%-     endfor %}
    {%-   endif %}
    {%- endif %}
{% endraw %}
{% endhighlight %}

And to get the right number of spaces on the resulting file use the indent filter:

{% highlight jinja linenos %}
{% raw  %}
    {{ line|indent(4) }}
{% endraw %}
{% endhighlight %}

file.blockreplace using file.accumulated
-----------------------------------------

Now if you read the [previous post on ``file.blockreplace``]({% post_url 2014-01-20-saltstack_step_by_step_file_blockreplace %}) you may wonder how to use it with accumulators. It will differ a little from the [``file.managed``][FILEMANAGED] usage of accumulators.

With [``file.managed``][FILEMANAGED] you have this *accumulator* jinja variable and several keys inside. With [``file.blockreplace``][FILEBLOCKREPLACE] you have nothing to do.

* If one accumulator is targeted on the same file (the same as the one targeted by the blockreplace), then the blockreplace ``content`` attribute will be filled with all the lines contained on this accumulator. Any data directly set in the content attribute is not loose, accumulator data is only added, but the content attribute is not required so it could also be empty.
* If several accumulators are targeted on this file they will be merged, but if you use several blockreplace states on the same file the accumulators are merged using the requisites dependencies you've made and accumulators names.

This last sentence is maybe weird. We'll make an example to see it, but another way of saying that is that it's magical and it should do the things you think it should do (if not, make bug reports).

So in this example we'll reuse the last example of managing entries in an ``/etc/hosts`` file. But we will manage two blocks of edition. So we have theses two states in an ``hostsedit_acc.sls`` file:

{% highlight yaml linenos %}
    test-etc-hosts-blockreplace-services-local:
      file.blockreplace:
        - name: /etc/hosts
        - marker_start: "# BLOCK TOP : salt managed zone : local services : please do not edit"
        - marker_end: "# BLOCK BOTTOM : local : end of salt managed zone --"
        - show_changes: True
        - append_if_not_found: True
    
    test-etc-hosts-blockreplace-services-central:
      file.blockreplace:
        - name: /etc/hosts
        - marker_start: "# BLOCK TOP : salt managed zone : central services : please do not edit"
        - marker_end: "# BLOCK BOTTOM : central : end of salt managed zone --"
        - show_changes: True
        - append_if_not_found: True
{% endhighlight %}

Same blocks as in the [previous guide]({% post_url 2014-01-20-saltstack_step_by_step_file_blockreplace %}) on blockreplace. But there I removed the content attribute (it *could* work with a content attribute adding more static stuff, but I do not need it).

So now if I want to use [``file.accumulated``][FILEACCUMULATED] to push some content in theses blocks I just need to do two things:

* target the blockreplace state id in a requisite to ensure my current state will run before
* target the same file (name attribute)

Quite simple, but here we have **two** managed blocks, my accumulated content will be set in the block targeted by my requisite.

Let's try it in a second sls file: ``hosts_data.sls``, but you could split that on more files if everything gets included at the end:

{% highlight yaml linenos %}
    {# Include dependencies #}
    include:
        - hostsedit_acc
    
    hostadata1-external-google-dns:
      file.accumulated:
        - filename: /etc/hosts
        - text: |
            8.8.8.8 ns1.google.com
            8.8.8.4 ns2.google.com
        - require_in:
            - file: test-etc-hosts-blockreplace-services-central
    
    hostadata2-external-thing:
      file.accumulated:
        - filename: /etc/hosts
        - text: "93.184.216.119 : www.example.com"
        - require_in:
            - file: test-etc-hosts-blockreplace-services-central
    
    hostdata3-internal-stuff1:
      file.accumulated:
        - filename: /etc/hosts
        - text: "127.0.0.1 foo bar foo.local.net bar.local.net"
        - require_in:
            - file: test-etc-hosts-blockreplace-services-local
    
    hostdata4-internal-stuff2:
      file.accumulated:
        - filename: /etc/hosts
        - text: |
            127.0.0.1 db.local.net
            127.0.0.1 http.local.net
            127.0.0.1 foobar
        - require_in:
            - file: test-etc-hosts-blockreplace-services-local
{% endhighlight %}

Note that I did not use the ``name`` attribute in theses states. Using name I could name the dictionary key, or we could say I would set the accumulator name. I could use names, but using the same accumulator name with the four states, strange things would happen, data from all theses accumulators would be merged in the same accumulator name. So, either avoid name attributes or use it with different names if the targeted blockedit is different. And test your recipes :-)

Now run it with:

{% highlight bash linenos %}
    $# salt-call -linfo state.sls hosts_data
{% endhighlight %}

You should get theses two managed blocks in ``/etc/hosts``, filled from several states:

{% highlight bash linenos %}
    # BLOCK TOP : salt managed zone : local services : please do not edit
    127.0.0.1 foo bar foo.local.net bar.local.net
    127.0.0.1 db.local.net
    127.0.0.1 http.local.net
    127.0.0.1 foobar
    
    # BLOCK BOTTOM : local : end of salt managed zone --
    # BLOCK TOP : salt managed zone : central services : please do not edit    
    93.184.216.119 : www.example.com
    8.8.8.8 ns1.google.com
    8.8.8.4 ns2.google.com
    
    # BLOCK BOTTOM : central : end of salt managed zone --
{% endhighlight %}

Last words
------------

Note that this example is based on the development github repository of salt. You may not be able to run theses examples on versions prior to 0.18.0. The multiple blockreplace case is one of the last fix added by @kiorky. 
If you use accumulators you may need to subscribe on this [reload_module vs accumulated issue][ISSUE8881] on github. It's a quite general issue, but this actually prevents using accumulators on states with too much *distance*, as you may loose the accumulated data if something restarted the minion while your states are running.

[Stay tuned on twitter, @regilero][TWITTER], [@makinacorpus][TWITTERMAK]

[FILEBLOCKREPLACE]: http://docs.saltstack.com/ref/states/all/salt.states.file.html#salt.states.file.blockreplace
[FILEREPLACE]: http://docs.saltstack.com/ref/states/all/salt.states.file.html#salt.states.file.replace
[FILEACCUMULATED]: http://docs.saltstack.com/ref/states/all/salt.states.file.html#salt.states.file.accumulated
[FILEMANAGED]: http://docs.saltstack.com/ref/states/all/salt.states.file.html#salt.states.file.managed
[REQUISITES]: http://docs.saltstack.com/ref/states/requisites.html
[ISSUE8881]: https://github.com/saltstack/salt/issues/8881
[GITHUBEXAMPLES]: https://github.com/regilero/regilero-blog-examples/tree/master/accumulated-blockreplace
[TWITTER]: https://twitter.com/regilero
[TWITTERMAK]: https://twitter.com/makinacorpus


