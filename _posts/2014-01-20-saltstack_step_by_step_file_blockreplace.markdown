---
layout: post
uuid: 013a442e-81e0-11e3-baa7-0800200c9a66
title: SaltStack, Manage entries in unmanaged files with File Blockreplace
categories: [SaltStack, English]
tags: [SaltStack, BlockReplace]
pic: spider2.png
excerpt: This is a presentation on how to use the saltstack's core file.blockreplace
---

Makina Corpus recently started to use Salt-stack, and by using it I mean we also started some contributions.
Salt-stack is a great set of tools, but sometimes your needs aren't covered yet, and in theses cases you'll find that salt-stack is also very easy to improve. The community is very open to contributions, on this blog post we'll study one of out first addition, [``file.blockreplace``][FILEBLOCKREPLACE].

Managed files and unmanaged ones
-----------------------------------

When using salt-stack, one of the most important task is usually to **set some configuration parameters** for your system services. To do that one of the very useful tool available in the salt-stack toolkit is the 
[``file.managed``][FILEMANAGED]. This let you use a file, retrieved from the salt server, computed with a template language like jinja. And you can do almost everything with that, you have a very flexible language, some variables coming from your state, and you create the final setting file. You even have some magic tools like [``file.accumulated``][FILEACCUMULATED] that I will explain in a next post.

But using this implies that salt will be the **only master** on this file. On every highstate run from salt the file could be recreated, updated or even removed (not with the managed state, but ``file.absent`` would do that).

So sometimes *managing the whole file is not what you want to do*. Let's see some examples of files that I would not manage with ``managed``:

 * A file inherited from a package, and having a lot of different forms depending on the host, like an apache central configuration file, compare RedHat and Debian versions, Trying to handle that with ``managed`` would maybe mean re-doing the package maintainers job
 * A file where salt is not the only actor, like ``~/.ssh/authorized_keys`` or ``/etc/hosts``. Theses files may contain previous entries from humans and may get edited later by theses same people.

In most cases you have one simple solution for that, a lot of daemons and services allows for an directory-inclusion of configuration files, usually this means a directory ``foo.d/``.

If you have a look at a debian system you have for example:

 * ``/etc/mysql/conf.d``
 * ``/etc/apache2/conf.d``
 * ``/etc/apt/sources.list.d/``
 * ``/etc/cron.d/``
 * ``/etc/cron.daily/``
 * (...)

And this would let you use a ``file.managed`` state to add your local configuration, without altering the package maintained files. Good thing.

But still not covering all the needs, there is no ``/etc/hosts.d/`` and no ``/etc/postgresql/pg_hba.conf.d/``. To edit the postgresql access file or your local hosts file you must work on the existing files.

You need a way to edit some files, to replace some key values, **while not managing the whole file**.

The file module has two tools for such needs:

 * [``file.replace``][FILEREPLACE]
 * [``file.blockreplace``][FILEBLOCKREPLACE]

The first one is a python based replacement for the old ``file.sed`` function, it let you use some regex to find a content and replace it. But there's some drawbacks in its usage, at least on my point of view:

 * MULTILINE regex are not supported, even if the documentation says it works, @see [issue #7999][ISSUE7999]
 * the file is altered at each salt run, errors may break it badly (empyt or partially empty), and access to the file whil salt is editing it should not happen (partial content), @see [issue #8051][ISSUE8051]

the MULTILINE regex issue was a big problem for us, because our first usage of unmanaged files edition was managing hosts files, with several lines added and *managed*.
So we wanted to add a simple way to manage several lines in a file, without regex support (using replace for that), and we made it with blockreplace.

File.blockreplace
------------------

The main idea under **blockreplace** is to **manage blocks of edited contents** in files where everything outside of theses blocks is ignored by Salt-stack.

With this module and/or state salt-stack can :
 
 * **Add** the block of content (on top or on bottom) if it is not present
 * manage **several lines** inside the block
 * **remove** content from a block
 * identify **several different blocks** in the same file
 
Block identity targeting and delimitation is done by a comment. By default it use a ``bash`` type of comment with ``#`` characters. But you can alter it, if your target is an html file you could use ``<!-- -->`` comments, if it's a code file you could use ``/* */`` comments, etc.
  
If you need several blocks in the same file you will need a way to identify theses different blocks, so inside theses comments there should be a unique block identifier. The whole marker line is searched, so the whole marker is this unique identifier. But if you make several blocks from the same marker model you should maybe add inside a unique variation, this is why the [state documentation][FILEBLOCKREPLACE] example show usage of a jinja ``myvar`` variable present in the state id and in the block marker (imagine theses states running in a jinja for loop, with ``myvar`` taking severa values.

The module documentation shows an example of a managed block content in a file (the result):

    (...)
    # START managed zone 42 -DO-NOT-EDIT-
    First line of content
    text 2
    text 3
    text 4
    # END managed zone 42 --
    (...)

Here the block is delimited by the 'markers', the starting marker is ``# START managed zone 42 -DO-NOT-EDIT-`` and the ending one is ``# END managed zone 42 --``. And the job of the state writer (you) is to keep theses markers unique in the file so that salt could indentify the block without any mistakes. Use long markers, short ones could work, of course, but with long markers you will avoid more easily the bad situation in which a part of your block content may contain the same thing as you end marker.

Step by step: Blockreplace real example with hosts
--------------------------------------------------

So now, to get a little deeper, we'll have a look at a real complete example. All theses examples are available in a github repository [here][GITHUBEXAMPLES].

Note that you can find other examples of usage [in the module unit test cases][TESTCASES], search for ``FileBlockReplaceTestCase`` class. And feel free to add your test cases (and issues) if you find something wrong.

Back on our step by step, let's say I want to add some entries in a hosts file. In this example we'll say that the salt minion is building some services and knows several aliases for theses services (db.local.net, http.local.net, etc) that should be added on the hosts file, all targeting the 127.0.0.1 IP.

The first step is to start with a very simple state, we will use it to see if at least salt can create the block in ``/etc/hosts``. This state is written in a `hostsedit1.sls` file which should be on your salt states root directory (if it's not directly on the root, add ``path.to.this.state.directory`` in the salt-call calls). Here is this state:

    test-etc-hosts-blockreplace-services:
      file.blockreplace:
        - name: /etc/hosts
        - marker_start: "# BLOCK TOP : salt managed zone : local services : please do not edit"
        - marker_end: "# BLOCK BOTTOM : end of salt managed zone --"
        - content: '# here be dragons'
        - show_changes: True

Here you can see I used a full name for the **state id** (1st line), and not just the file path, as using full descriptive and unique ids is a very good habit. And using the name shortcut as a state id is maybe more readable in examples but it can lead to states overwrites, bad things. So I won't do that.

The content is a comment, it's a test. I did **not** alter manually the ``/etc/hosts`` file to add my markers inside.

Let's run the test (and not a highstate, only this simple sls), run it with a user having write access on the targeted hosts file, like the root user:

    #$: salt-call state.sls hostsedit1    
    local:
    ----------
        State: - file
        Name:      /etc/hosts
        Function:  blockreplace
        Result:    False
        Comment:   An exception occurred in this state: Traceback (most recent call last):
      File "/path/to/salt/state.py", line 1325, in call
        *cdata['args'], **cdata['kwargs'])
      File "path/to/salt/states/file.py", line 1882, in blockreplace
        show_changes=show_changes)
      File "path/to/salt/modules/file.py", line 1105, in blockreplace
        raise CommandExecutionError("Cannot edit marked block. Markers were not found in file.")
    CommandExecutionError: Cannot edit marked block. Markers were not found in file.
        Changes:   
    
    Summary
    ------------
    Succeeded: 0
    Failed:    1
    ------------
    Total:     1

And if fails. Because the block is not found in the file. We need to tell salt that in this case the block should be added on top (``append_if_not_found``) or on the bottom of the file (``prepend_if_not_found``). You're maybe wondering why the state fails badly instead of creating the block by default. The reason is that you may have edited the marker (to add some variables) or you may have edited the file and remove an important thing (like the bottom marker), and you would not want the state to overwrite a part of your file or to duplicate the block. I prefer having exception when something bad happens, and no changes on the targeted file.
We need to add the append instruction, this is done in hostsedit2 (on this step by step I use different states, but you could edit the same state file)

    test-etc-hosts-blockreplace-services:
      file.blockreplace:
        - name: /etc/hosts
        - marker_start: "# BLOCK TOP : salt managed zone : local services : please do not edit"
        - marker_end: "# BLOCK BOTTOM : end of salt managed zone --"
        - content: '# here be dragons'
        - show_changes: True
        - append_if_not_found: True

Run it:

    #$: salt-call state.sls hostsedit2
     local:
    ----------
        State: - file
        Name:      /etc/hosts
        Function:  blockreplace
            Result:    True
            Comment:   Changes were made
            Changes:   Invalid Changes data: --- 
    +++ 
    @@ -45,3 +45,6 @@
     192.168.1.52.3 toto3.foo.com
     192.168.1.52.4 toto4.foo.com
     192.168.1.52.5 toto5.foo.com
    +# BLOCK TOP : salt managed zone : local services : please do not edit
    +# here be dragons
    +# BLOCK BOTTOM : end of salt managed zone --
    
    
    Summary
    ------------
    Succeeded: 1
    Failed:    0
    ------------
    Total:     1

The `Invalid Changes data` is a known bug that should get fixed soon, is a false positive (changes should be a list of changes and not just the string I think, something like that), the changes are in fact OK. You can chek the hosts file, the block of text was added at the end of the file.

And if you launch the state a second time you will see that no changes were detected, so the file is untouched.

    local:
    ----------
        State: - file
        Name:      /etc/hosts
        Function:  blockreplace
            Result:    True
            Comment:   No changes were made
            Changes:   

Note that using an empty content argument would empty your block in /etc/hosts, while leaving in place the block markers comments.

So now we'll add some more realistic content in the hosts file, some IP and DNS data. We'll do that in a ``hostedit3.sls`` file:

    test-etc-hosts-blockreplace-services:
      file.blockreplace:
        - name: /etc/hosts
        - marker_start: "# BLOCK TOP : salt managed zone : local services : please do not edit"
        - marker_end: "# BLOCK BOTTOM : end of salt managed zone --" 
        - content: |
            127.0.0.1 db.local.net
            127.0.0.1 http.local.net
            127.0.0.1 foo bar foo.local.net bar.local.net
            127.0.0.1 foobar # with a comment
        - show_changes: True
        - append_if_not_found: True

Look at the `|` this is used for multiline input in yaml, with newlines preservation. 
Spaces, as always in yaml, are very important, If I show the first spaces with `x` you can see that you need 4 more spaces after this pipe:

    test-etc-hosts-blockreplace-services:
    xxfile.blockreplace:
    xxxx- name: /etc/hosts
    xxxx- marker_start: "# BLOCK TOP : salt managed zone : local services : please do not edit"
    xxxx- marker_end: "# BLOCK BOTTOM : end of salt managed zone --" 
    xxxx- content: |
    xxxxxxxx127.0.0.1 db.local.net
    xxxxxxxx127.0.0.1 http.local.net
    xxxxxxxx127.0.0.1 foo bar foo.local.net bar.local.net
    xxxxxxxx127.0.0.1 foobar # with a comment
    xxxx- show_changes: True
    xxxx- append_if_not_found: True

And run it:

    #$: salt-call state.sls hostsedit3
     local:
    ----------
        State: - file
        Name:      /etc/hosts
        Function:  blockreplace
            Result:    True
            Comment:   Changes were made
            Changes:   Invalid Changes data: --- 
    +++ 
    @@ -46,5 +46,9 @@
     
     #-- end salt managed zoneend --
     # BLOCK TOP : salt managed zone : local services : please do not edit
    -# here be dragons
    +127.0.0.1 db.local.net
    +127.0.0.1 http.local.net
    +127.0.0.1 foo bar foo.local.net bar.local.net
    +127.0.0.1 foobar # with a comment
    +
     # BLOCK BOTTOM : end of salt managed zone --

And we will end this first example by managing two different blocks in the same file.

Let's say we will now manage two different blocks on the file, one with local services, and one with external services, this is ``hostedit4.sls``

    test-etc-hosts-blockreplace-services-local:
      file.blockreplace:
        - name: /etc/hosts
        - marker_start: "# BLOCK TOP : salt managed zone : local services : please do not edit"
        - marker_end: "# BLOCK BOTTOM : local : end of salt managed zone --" 
        - content: |
            127.0.0.1 db.local.net
            127.0.0.1 http.local.net
            127.0.0.1 foo bar foo.local.net bar.local.net
            127.0.0.1 foobar # with a comment
        - show_changes: True
        - append_if_not_found: True
    
    test-etc-hosts-blockreplace-services-central:
      file.blockreplace:
        - name: /etc/hosts
        - marker_start: "# BLOCK TOP : salt managed zone : central services : please do not edit"
        - marker_end: "# BLOCK BOTTOM : central : end of salt managed zone --" 
        - content: |
            8.8.8.8 ns1.dns.net
            8.8.4.4 ns2.dns.net
        - show_changes: True
        - append_if_not_found: True

The states ids are altered with ``-local`` and ``-central`` and the second state uses a different marker message. If I had used the same marker messages the second would have overwritten the first one. You may also see that I have added a  ``central`` and a  ``local`` keyword on the ``marker_end`` sections. This way end markers are also uniques, the states could work with non unique end marker, the block end is detected on the first match of the end marker. But with unique end markers you will detect more easily broken blocks.

And if I do not alter the ``/etc/hosts`` file before running theses states I should see an example of broken block, because I altered the end marker for the first block, and salt cannot find this end marker on the current file, let's test it (let's be mad):


    #$: salt-call state.sls hostsedit4
    local:
    ----------
        State: - file
        Name:      /etc/hosts
        Function:  blockreplace
            Result:    False
            Comment:   An exception occurred in this state: Traceback (most recent call last):
      File "/path/to/salt/state.py", line 1325, in call
        *cdata['args'], **cdata['kwargs'])
      File "/path/to/salt/states/file.py", line 1882, in blockreplace
        show_changes=show_changes)
      File "/path/to/salt/modules/file.py", line 1095, in blockreplace
        raise CommandExecutionError("Unterminated marked block. End of file reached before marker_end.")
    CommandExecutionError: Unterminated marked block. End of file reached before marker_end.
    
     Changes:   
    ----------
        State: - file
        Name:      /etc/hosts
        Function:  blockreplace
            Result:    True
            Comment:   Changes were made
            Changes:   Invalid Changes data: --- 
    +++ 
    @@ -52,3 +52,6 @@
     127.0.0.1 foobar # with a comment
     
     # BLOCK BOTTOM : end of salt managed zone --
        +# BLOCK TOP : salt managed zone : central services : please do not edit
    +8.8.8.8 ns1.dns.net
    8.8.4.4 ns2.dns.net
    
    +# BLOCK BOTTOM : central : end of salt managed zone --
    
    
    Summary
    ------------
    Succeeded: 1
    Failed:    1
    ------------
    Total:     2

Perfect, the second block was added and salt detected that the first state's block was now invalid ``Unterminated marked block. End of file reached before marker_end``. The block was not removed from the hosts file, simply salt is now unable to manage it.

The fix here is either:

 * to edit the /etc/hosts and replace the marker end comment of the first block from ``# BLOCK BOTTOM : end of salt managed zone --`` to ``# BLOCK BOTTOM : local : end of salt managed zone --``
 * to do the contrary in the state, let the first block end on the ``# BLOCK BOTTOM : end of salt managed zone --`` marker.

You can test it, You'll get two working salt states, both editing the same hosts file and managing two different sections of the file.

Next?
-----

On a future post we will have a look at [``file.accumulated``][FILEACCUMULATED] examples with managed files, and also with blockreplace. As accumulated data can be used to collect data on several states, which makes this sort of tools very useful in combination with edited blocks managments.

[Stay tuned on twitter, @regilero][TWITTER], [@makinacorpus][TWITTERMAK]


[FILEBLOCKREPLACE]: http://docs.saltstack.com/ref/states/all/salt.states.file.html#salt.states.file.blockreplace
[FILEREPLACE]: http://docs.saltstack.com/ref/states/all/salt.states.file.html#salt.states.file.replace
[FILEACCUMULATED]: http://docs.saltstack.com/ref/states/all/salt.states.file.html#salt.states.file.accumulated
[FILEMANAGED]: http://docs.saltstack.com/ref/states/all/salt.states.file.html#salt.states.file.managed
[ISSUE7999]: https://github.com/saltstack/salt/issues/7999
[ISSUE8051]: https://github.com/saltstack/salt/issues/8051
[TESTCASES]: https://github.com/saltstack/salt/blob/develop/tests/unit/modules/file_test.py
[GITHUBEXAMPLES]: https://github.com/regilero/regilero-blog-examples/tree/master/blockreplace-step-by-step
[TWITTER]: https://twitter.com/regilero
[TWITTERMAK]: https://twitter.com/makinacorpus



