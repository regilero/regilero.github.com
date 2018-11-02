---
layout: post
uuid: 7440e951-58a7-468a-9cfe-b6dd5335a524
title: SaltStack, Merge dictionaries of settings with grains.filter_by
categories: [english, SaltStack]
tags: [SaltStack, jinja]
pic: old1.jpg
excerpt: Useful in formulas and macros, and now featuring a default attribute.
---

If you read some formulas you may have noticed a nice way of managing settings. The [``grains.filter_by``][SALT_FILTER_BY] function. Values used in salt states are usually dynamic, coming from grains, from the pillar, from variations depending on the host environment. When you have a big number of variables using only the default jinja tools is sometimes frustrating. This is a must-know feature.

There's a nice example in [the Apache formula map.jinja file][FORMULA_APACHE_MAP], which may evolve, so let's show what it looks like:

{% raw  %}
    {% set apache = salt['grains.filter_by']({
        'Debian': {
            'server': 'apache2',
            'service': 'apache2',
    
            'mod_wsgi': 'libapache2-mod-wsgi',
    
            'vhostdir': '/etc/apache2/sites-available',
            'confdir': '/etc/apache2/conf.d',
            'logdir': '/var/log/apache2',
            'wwwdir': '/srv',
        },
        'RedHat': {
            'server': 'httpd',
            'service': 'httpd',
    
            'mod_wsgi': 'mod_wsgi',
    
            'vhostdir': '/etc/httpd/conf.d',
            'confdir': '/etc/httpd/conf.d',
            'logdir': '/var/log/httpd',
            'wwwdir': '/var/www',
        },
    }, merge=salt['pillar.get']('apache:lookup')) %}
{% endraw  %}


This sets an ``apache`` jinja variable, a dictionary containing ``server``, ``service``,``confdir`` or ``wwwdir`` keys (and some more).

The main idea of ``salt['grains.filter_by']`` is to filter a settings dictionary based on a grain: **os_family** (here the value may be 'Redhat' or 'Debian').

Usage of this ``map.jinja`` file can be [seen on the init.sls][FORMULA_APACHE_INIT]:

{% raw  %}
    {% from "apache/map.jinja" import apache with context %}
    
    apache:
      pkg:
        - installed
        - name: {{ apache.server }}
    (...)
{% endraw  %}

Now if you have a pretty recent version (> 0.17.2) of Salt-stack this [``filter_by``][SALT_FILTER_BY] function has some new very interesting features.

    salt.modules.grains.filter_by(lookup_dict, grain='os_family', merge=None, default='default')

* the **lookup dict** is your dictionary of settings where you want a filter to be applied, so at the end you will obtain a subtree of this dictionary.
* the **grain** is by default the *os_family* grain, but you can use any defined grain key (``salt-call grains.items`` to see them).
* the **merge** argument lets you merge another dictionary on top of the end result, this is very useful, as seen on the apache's formula, to retrieve pillar data overriding the default settings dictionary.
* and the new argument is **default**, which lets you specify which key of the *lookup dict* should be used if you did not have the requested grain or if the requested grain value is not present in this *lookup dict*.

So this function is now a really good shortcut for a default settings registry mapping.

{% raw  %}
    {% set settings = salt['grains.filter_by']({
        'unset': { 'foo': 'The coconut's tropical', 'bar': 'King Arthur'},
        'prod': { 'foo': 'Bridgekeeper', 'bar': 'We want a shrubbery' },
        'preprod': { 'foo': 'Sir Lancelot', bar: 'Blue. No, yel…'},
      },
      grain='my_env',
      merge=salt['pillar.get']('apache:lookup')),
      default='unset' 
    %}
{% endraw  %}

 * [Stay tuned on twitter, @regilero][TWITTER], [@makinacorpus][TWITTERMAK]

[FORMULA_APACHE_MAP]: https://github.com/saltstack-formulas/apache-formula/blob/master/apache/map.jinja
[FORMULA_APACHE_INIT]: https://github.com/saltstack-formulas/apache-formula/blob/master/apache/init.sls
[SALT_FILTER_BY]: http://docs.saltstack.com/ref/modules/all/salt.modules.grains.html#salt.modules.grains.filter_by
[TWITTER]: https://twitter.com/regilero
[TWITTERMAK]: https://twitter.com/makinacorpus

