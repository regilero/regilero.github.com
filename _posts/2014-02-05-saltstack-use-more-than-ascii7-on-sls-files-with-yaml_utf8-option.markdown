---
layout: post
uuid: 21a85098-8e55-11e3-baa8-0800200c9a66
title: SaltStack, Use more than ascii7 on sls files with yaml_utf8 option
categories: [SaltStack, English]
tags: [SaltStack, jinja]
pic: u202e.png
excerpt: If using special characters breaks your salt execution, the yaml_utf8 new option should be enabled.
---

**Warning**: *this option is only available on the ``2014-01`` branch or the ``develop`` branch, it's not yet available on the 0.17 releases branch.*

Special characters?
-------------------

DevOps, developpers and sysadmins are usually nice people. They usually knows that most of the computer's tools they use are made by US people and that using nasty things such as spaces or, nastier, special characters like ``é`` or ``한`` may break their tools.

This is why most databases names will ends up as nice ascii7 names with spaces replaced by underscores, and most of the filesystem files follows the same rules.

But we are not anymore in the 60s. Every filesystem allows for utf-8 in file names, even the databases -- on a next post we'll show how salt mysql module has been improved to allow almost any character combination --. So salt-stack should support this fact.

But you may wonder why your salt-stack installation should support 'strange' characters?
You should take care of that because you usually provide states that you have tested with very simple hello-world level tests. And as a nice and polite computer guy, you did not add any nasty characters in your tests.
And your sls files may contain jinja variables, which may be used with data coming from external sources. You may even have a full PaaS or SaaS system running. And sooner or later you will have a user that will feed an input field with something like a company name. This company name will contain spaces and maybe Korean characters... This user entry will maybe end up in a configuration file's name, in a database's name, in a managed file's content. Chances are great that some of **theses strange characters will end up somewhere in your salt's sls files**.

The [new yaml_utf8 option][DOC_YAMLUTF8] should be enabled on your salt-stack installation to manage these cases. This is not activated by default, it's a new option, and is waiting for some positive and negative feedbacks (use [this github pull request][ISSUE_FEEDBACK] for example, or make new issues). So feel free to experiment.

Let's see why you need it and what this option is really doing.

See it in action
-------------------

What happens if my yaml sls file contains some utf-8 characters? Well, bad things :-).

Let's try it. We'll make a very simple state, doing some echo, and we'll do that in a ``testchar.sls`` file on the salt tree root.

    # -*- coding: utf-8 -*-
    test-characters:
      cmd.run:
        - name: echo "¿Me pones un café, por favor?"
  
You can see the python utf-8 markers on the top of the sls file, this makes sure that the characters in this sls file are valid utf-8 characters. Two characters here are not in ascii7 ``¿`` and ``é``. Let's now run this single state:

    #$ salt-call state.sls testchar
    [ERROR   ] An un-handled exception was caught by salt's global exception handler:
    UnicodeEncodeError: 'ascii' codec can't encode character u'\xbf' in position 6: ordinal not in range(128)
    Traceback (most recent call last):
      File "/usr/local/bin/salt-call", line 44, in <module>
        sys.exit(salt.scripts.salt_call())
      File "/usr/local/salt/scripts.py", line 82, in salt_call
        client.run()
      File "/usr/local/salt/cli/__init__.py", line 314, in run
        caller.run()
      File "/usr/local/salt/cli/caller.py", line 142, in run
        ret = self.call()
      File "/usr/local/salt/cli/caller.py", line 80, in call
        ret['return'] = func(*args, **kwargs)
      File "/usr/local/salt/modules/state.py", line 383, in sls
        ret = st_.state.call_high(high_)
      File "/usr/local/salt/state.py", line 1701, in call_high
        chunks = self.compile_high_data(high)
      File "/usr/local/salt/state.py", line 976, in compile_high_data
        chunks = self.order_chunks(chunks)
      File "/usr/local/salt/state.py", line 920, in order_chunks
        chunks.sort(key=lambda k: (k['order'], '{0[state]}{0[name]}{0[fun]}'.format(k)))
      File "/usr/local/salt/state.py", line 920, in <lambda>
        chunks.sort(key=lambda k: (k['order'], '{0[state]}{0[name]}{0[fun]}'.format(k)))
    UnicodeEncodeError: 'ascii' codec can't encode character u'\xbf' in position 6: ordinal not in range(128)

Ouch.

Now let's find the ``yaml_utf8`` option in your master salt configuration file, for me it was in ``/etc/salt/master.d/00_global.conf``, and set it to True. Then restart the master and test again:

    #$ service salt-master restart
    salt-master stop/waiting
    salt-master start/running, process 5471
    #$ salt-call state.sls testchar
    local:
    ----------
              ID: test-characters
        Function: cmd.run
            Name: echo "¿Me pones un café, por favor?"
          Result: True
         Comment: Command "echo "¿Me pones un café, por favor?"" run
         Changes:   
                  ----------
                  pid:
                      5053
                  retcode:
                      0
                  stderr:
                      
                  stdout:
                      ¿Me pones un café, por favor?
    
    Summary
    ------------
    Succeeded: 1
    Failed:    0
    ------------
    Total:     1

Great.

Note that the main problem here, in the first example, was that special characters were used on the state **name**. But it could also happen with harmless attributes. Let's try with a **text** attribute, and without the ``yaml_utf8`` option set:

    # -*- coding: utf-8 -*-
    test-characters1:
      file.touch:
        - name: /tmp/foobar
    test-characters2:
      file.append:
        - name: /tmp/foobar
        - text: "¿Me pones un café, por favor?"
        - require:
          - file: test-characters1

It will also fail:

    #$ salt-call state.sls testch
    local:
    ----------
              ID: test-characters1
        Function: file.touch
            Name: /tmp/foobar
          Result: True
         Comment: Updated times on file /tmp/foobar
         Changes:   
    ----------
              ID: test-characters2
        Function: file.append
            Name: /tmp/foobar
          Result: False
         Comment: An exception occurred in this state: Traceback (most recent call last):
                    File "/usr/local/salt/state.py", line 1370, in call
                      **cdata['kwargs'])
                    File "/usr/local/salt/states/file.py", line 2519, in append
                      name, salt.utils.build_whitespace_split_regex(chunk)):
                    File "/usr/local/salt/utils/__init__.py", line 772, in     build_whitespace_split_regex
                      parts = [re.escape(s) for s in __build_parts(line)]
                    File "/usr/local/salt/utils/__init__.py", line 761, in     __build_parts
                      lexer = shlex.shlex(text)
                    File "/usr/lib/python2.7/shlex.py", line 25, in __init__
                      instream = StringIO(instream)
                  UnicodeEncodeError: 'ascii' codec can't encode character u'\xbf' in position 0: ordinal not in range(128)
         Changes:   
    
    Summary
    ------------
    Succeeded: 1
    Failed:    1
    ------------
    Total:     2

But here, at least, you have a catched exception.

Obviously, after using the ``yaml_utf8`` option this state will work.


    local:
    ----------
              ID: test-characters1
        Function: file.touch
            Name: /tmp/foobar
          Result: True
         Comment: Updated times on file /tmp/foobar
         Changes:   
    ----------
              ID: test-characters2
        Function: file.append
            Name: /tmp/foobar
          Result: True
         Comment: Appended 1 lines
         Changes:   
                  ----------
                  diff:
                      --- 
                      +++ 
                      @@ -0,0 +1 @@
                      +¿Me pones un café, por favor?
    Summary
    ------------
    Succeeded: 2
    Failed:    0
    ------------
    Total:     2

What happened exactly?
-------------------

If you want to understand this better I'll give some details. You do not need to understand the details, but it could be useful, especially if you are american (or part of the subset of humanity using pounds, miles and ascii7).

The error was there:

      File "/usr/local/salt/state.py", line 920, in <lambda>
        chunks.sort(key=lambda k: (k['order'], '{0[state]}{0[name]}{0[fun]}'.format(k)))
    UnicodeEncodeError: 'ascii' codec can't encode character u'\xbf' in position 6: ordinal not in range(128)

Salt is ordering the states and the states' name are used to do the sorting. Here we have special characters on these names and the sort method emits an uncatched exception.

A fix would be replacing ``'{0[state]}{0[name]}{0[fun]}'`` with ``u'{0[state]}{0[name]}{0[fun]}'``. But you would need this sort of fix in a thousand places. You would have to fix pretty much every string in salt :-(

By default, with python 2.x, there are two types of string objects:

 * str : the default string object, allow utf-8 encoded strings (a byte string)
 * unicode : an unicode string

An example is worth a thousand words:

    #$ python
    >>> foo="foo"
    >>> foo
    'foo'
    >>> type(foo)
    <type 'str'>
    >>> bar="準"
    >>> bar
    '\xe6\xba\x96'
    >>> type(bar)
    <type 'str'>
    >>> baz=u"準"
    >>> baz
    u'\u6e96'
    >>> type(baz)
    <type 'unicode'>

So the special character ``準`` is ``\xe6\xba\x96`` in utf-8 encoding and ``\u6e96`` in unicode encoding. Unicode and utf-8 are not the same things. And by default string objects are utf-8 encoded strings.

The funny thing is that this is not the case in python 3.

    #$ /usr/bin/python3.2
    >>> foo="foo"
    >>> foo
    'foo'
    >>> type(foo)
    <class 'str'>
    >>> bar="準"
    >>> bar
    '準'
    >>> type(bar)
    <class 'str'>
    >>> baz=bar.encode('utf-8')
    >>> baz
    b'\xe6\xba\x96'
    >>> type(baz)
    <class 'bytes'>

In python3 the default string class will be unicode (as if you had prefixed all your python2 string with ``u``), and the old python default str type will be the byte string class. You will need to prefix with ``b`` to get that sort of utf-8 encoded strings.

You can find a very detailled explanation on [python's unicode documentation][PYTHON_UNICODE] and on [this slide explaining the difference of string encoding in python2 and 3][SLIDE_PYTHON2_3].

Talking about **[Salt-stack][SALTSTACK]** we are working in a python2 world. And in pretty every string usage inside salt-stack default strings are used, so byte strings, allowing utf-8 encoding but not unicode. This should allow every special character, if they are well transformed to an utf-8 encoded string. If our special string is managed in this form:

    '\xc2\xbfMe pones un caf\xc3\xa9, por favor?'

Everything should be fine.

The problem comes from the sls yaml transcription. Salt works with low states, highstates, etc. This is generated from the sls files with a yaml transcription. And this task is made by a yaml library.

This **yaml parser library** is python3-ready, and the result of the yaml parsing is always **unicode strings** if special characters are encountered, not str default strings. So as soon as you have a special character in the sls salt receive unicode u'foo' strings while everything is made to handle utf-8 encoded strings. This yaml_utf8 option is there to ensure that after the yaml load is made, every unicode string is decoded to utf-8, you can see it in the code [right here][SHOW_CODE].


 * [Stay tuned on twitter, @regilero][TWITTER], [@makinacorpus][TWITTERMAK]

[DOC_YAMLUTF8]: http://docs.saltstack.com/ref/configuration/master.html#yaml-utf8
[ISSUE_FEEDBACK]: https://github.com/saltstack/salt/pull/9053
[PYTHON_UNICODE]: http://docs.python.org/3.3/howto/unicode.html
[SLIDE_PYTHON2_3]: http://wolfprojects.altervista.org/talks/unicode-and-python-3/
[SHOW_CODE]: https://github.com/saltstack/salt/blob/2014.1/salt/renderers/yaml.py#L70-92
[SALTSTACK]: http://www.saltstack.com/
[TWITTER]: https://twitter.com/regilero
[TWITTERMAK]: https://twitter.com/makinacorpus


