---
layout: post
title: Warning Chrooted php-fpm and Apc with multiple pools
categories: [Drupal, English]
tags: [Drupal, Performance, PHP-fpm, APC]
pic: flower2.png
excerpt: Using several chrooted php-fpm pools with APC opcode may break all your websites (and chroot jails). Step by step of cloning php-fpm daemons.  

---

PHP-fpm used as a fastgi backend for nginx or Apache is a very nice tool.  
And the ability to chroot the php-fpm pool use a nice way to enforce projects separations.
I once wrote a detailled exemple for Apache (but I really prefer nginx),
with details on `open_basedir` and temporary files
separation for each PHP project.  
You should really use your PHP projets in such way to avoid having the least secure project
on your host used to attack other projects.

But recently I discovered that using several projects on the same host, all using **APC** opcode and **php-fpm chroot** I ended up
with sources files from one project used on the others.. source code **mix** .. and then really bad things happened...  

##WTF: Why are the conf files mixed between projects?##

At first we were working with one php-fpm per host. On configurations where you have several hosts for the same project this
happens more than sharing one host for several projects.

Then one day on some of theses hosts we deployed a clone of the project. On a different directory, with a second php-fpm pool,
where the only difference between the 2 projects were the `prefix` in the php-fpm pool and the project's application settings
(where at least the base url name and database backend were different).

This should be OK, and without APC it was OK. But as soon as APC were used some pages were randomly broken, using domain of
the first project for css files of the second project, or showing pages of second project in the fist one, a big random mess.
In our case the random thing was done by the fact several hosts were load balanced between several hosts and did not used the
same buggy files on each hosts.

The problem is easy (well, it took me long minutes to find it the fist time),
APC is storing a compiled version of each file in his opcode cache, and
**the cache key of this file is  the file name (full path)**.  
If two chrooted projects **share the same file names, only one version of this file is stored in APC!**  
Without the chroot this never happens on a regular filesystem. But, by definition, using
a chroot your projects are using a shorter relative path to files, seing it as the real full path.

So chances are that the configuration files on two projects where one is the production version and one the
test version will both be seen as (this is a Drupal setting for example):
<pre>
  /www/sites/default/settings.php
</pre>
Whereas the real filesystem paths are:
<pre>
  /var/www/app/production/www/sites/default/settings.php
  /var/www/app/test/www/sites/default/settings.php
</pre>

As of course the chroots are `var/www/app/production` and `/var/www/app/test`.

Quite easy te see on projects where key files like configuration files gets the same name.  
But it could also happen with several projects having a lot of differences in file naming,
and where just one or two file names would conflict. It would make the bug harder to detect.

##Solutions? one process per pool?##

There is of course one solution for this problem which is either:

 * to remove APC
 * or only use one php-fpm pool per host
 * or only use one php-fpm pool per php-fpm process, and run **several php-fpm daemons**

So when you want to have 2, 3 or more projects on one host, all using APC and a chrooted php-fpm pools you will duplicate the
php-fpm daemon for each project to ensure each pool is really independent of the other pools, and that a new APC, with a new shared
memory segment will be used on this new PHP daemon. You cannot use the default classical way with one daemon and several pools on this daemon.

You can find examples of this. **But** the process is not a simple a simply creating a new daemon with a new
configuration file. On debian, for example, the start/stop init script will likely kill all the php-fpm process running
on the Hosts, ignoring the fact they are from several different daemons.

So let's study it in details

###Duplicate the php-fpm daemon process###

The first thing to do is to create a new php-fpm configuration for the new php-fpm process. The first process/daemon will be **php-fpm**,
we will call the second **php-fpm-test**. So this new conf file will also have the **-test** extension.

Usually, at least on debian, the main configuration file is loading all pools from the pool diectory with
this instruction:

{% highlight php %}
include=/etc/php5/fpm/pool.d/*.conf
{% endhighlight %}

We alter the configuration file to only include one pool. Then we make the copy and alter this name in the second file,
we also alter the pid setting reference.  
After that a diff should give something like that:

{% highlight bash %}
$ diff -bBNaur /etc/php5/fpm/php-fpm.conf /etc/php5/fpm/php-fpm-test.conf
--- /etc/php5/fpm/php-fpm.conf  2013-04-10 16:48:23.000000000 +0200
+++ /etc/php5/fpm/php-fpm-test.conf  2013-04-10 18:34:12.000000000 +0200
@@ -22,7 +22,7 @@
 ; Pid file
 ; Note: the default prefix is /var
 ; Default Value: none
-pid = /var/run/php5-fpm.pid
+pid = /var/run/php5-fpm-test.pid
 
 ; Error log file
 ; If it's set to "syslog", log is sent to syslogd instead of being written
@@ -118,5 +118,5 @@
 
 ; To configure the pools it is recommended to have one .conf file per
 ; pool in the following directory:
-include=/etc/php5/fpm/pool.d/my-pool.conf
+include=/etc/php5/fpm/pool.d/my-pool-test.conf
{% endhighlight %}

Now we need an init script starting a new php-fpm daemon using this `php-fpm-test.conf` file.  
Copy the main startup script on a new one with test extension and alter it so that at least you obtain this diff:

{% highlight bash %}
$ diff -bBNaur /etc/init.d/php5-fpm /etc/init.d/php5-fpm-test
--- /etc/init.d/php5-fpm  2012-07-23 13:59:30.000000000 +0200
+++ /etc/init.d/php5-fpm-test  2013-04-10 18:56:22.000000000 +0200
@@ -1,24 +1,24 @@
 #!/bin/sh
 ### BEGIN INIT INFO
-# Provides:          php-fpm php5-fpm
+# Provides:          php-fpm-test php5-fpm-test
 # Required-Start:    $remote_fs $network
 # Required-Stop:     $remote_fs $network
 # Default-Start:     2 3 4 5
 # Default-Stop:      0 1 6 
-# Short-Description: starts php5-fpm
-# Description:       Starts PHP5 FastCGI Process Manager Daemon
+# Short-Description: starts php5-fpm-test
+# Description:       Starts PHP5 FastCGI Process Manager Daemon for test
 ### END INIT INFO
 
 # Author: Ondrej Sury <ondrej@debian.org>
 
 PATH=/sbin:/usr/sbin:/bin:/usr/bin
 DESC="PHP5 FastCGI Process Manager"
 NAME=php5-fpm
 DAEMON=/usr/sbin/$NAME
-DAEMON_ARGS="--fpm-config /etc/php5/fpm/php-fpm.conf"
-PIDFILE=/var/run/php5-fpm.pid
+DAEMON_ARGS="--fpm-config /etc/php5/fpm/php-fpm-test.conf"
+PIDFILE=/var/run/php5-fpm-test.pid
 TIMEOUT=30
-SCRIPTNAME=/etc/init.d/$NAME
+SCRIPTNAME=/etc/init.d/$NAME-test
 
 # Exit if the package is not installed
 [ -x "$DAEMON" ] || exit 0
{% endhighlight %}

Do not forget to add this script on start/stop levels if you want it after reboot.

{% highlight bash %}
  update-rc.d default php5-fpm-test defaults
{% endhighlight %}

Start this new php-fpm, it should be ok. 

{% highlight bash %}
 /etc/init.d/php5-fpm-test start
{% endhighlight %}

Test it with this  `ps` command, you sholuld see the two daemons and the children, one pool per daemon
(number of children depends on your pool's settings):

{% highlight bash %}
 ps auxf|grep php
 
 1005     30688  0.0  0.0   9616   904 pts/0    S+   13:47   0:00              \_ grep php
 root     17906  0.0  0.1 667208  5236 ?        Ss   May07   0:13 php-fpm: master process (/etc/php5/fpm/php-fpm-test.conf)
 1005      9753  0.0  3.0 733316 122300 ?       S    04:13   0:06  \_ php-fpm: pool my-pool-test
 1005      9754  0.0  1.9 691336 81188 ?        S    04:13   0:04  \_ php-fpm: pool my-pool-test
 1005     17920  0.0  3.0 733316 123152 ?       S    05:41   0:05  \_ php-fpm: pool my-pool-test                                     
 root     19130  0.0  0.1 667908  5940 ?        Ss   May07   0:14 php-fpm: master process (/etc/php5/fpm/php-fpm.conf)
 1005     10731  0.1  2.7 699296 110940 ?       S    May14   1:30  \_ php-fpm: pool my-pool
 1005     10816  0.1  2.4 688676 99048 ?        S    May14   1:35  \_ php-fpm: pool my-pool
 1005     10817  0.1  2.5 694604 104196 ?       S    May14   1:18  \_ php-fpm: pool my-pool
 1005     10912  0.1  2.6 696708 108364 ?       S    May14   1:27  \_ php-fpm: pool my-pool
{% endhighlight %}

###Watch the nice crash on start/stop###

It's not the end!  

If you try to stop one of the 2 daemons you will have a long running stop, and then after 30s the 2 daemons will be down.  
Redo the ps to see it.

Problem is coming fom the `do_stop` function in the init script:

{% highlight bash %}
#
# Function that stops the daemon/service
#
do_stop()
{
  # Return
  #   0 if daemon has been stopped
  #   1 if daemon was already stopped
  #   2 if daemon could not be stopped
  #   other if a failure occurred
  start-stop-daemon --stop --quiet --retry=QUIT/$TIMEOUT/TERM/5/KILL/5 --pidfile $PIDFILE --name $NAME
  RETVAL="$?"
  [ "$RETVAL" = 2 ] && return 2
  # Wait for children to finish too if this is a daemon that forks
  # and if the daemon is only ever run from this initscript.
  # If the above conditions are not satisfied then add some other code
  # that waits for the process to drop all resources that could be
  # needed by services started subsequently.  A last resort is to
  # sleep for some time.
  start-stop-daemon --stop --quiet --oknodo --retry=0/30/TERM/5/KILL/5 --exec $DAEMON
  [ "$?" = 2 ] && return 2
  # Many daemons don't delete their pidfiles when they exit.
  rm -f $PIDFILE
  return "$RETVAL"
}
{% endhighlight %}

The `start-stop-daemon` command is a first stop on the right daemon, based on the pid.
But after that a second stop is running, ensuring no ghost
child stay alive, and this second `start-stop-daemon` command is running with option `--exec` :

>
> −x, −−exec executable
> 
> Check for processes that are instances of this executable (according to /proc/pid/exe).

Let's see whet is this `/proc/pid/exe`:

{% highlight bash %}
$ cat /var/run/php5-fpm.pid 
1246
$ ls -alh /proc/1246/exe
lrwxrwxrwx 1 root root 0 15 mai   13:30 /proc/1246/exe -> /usr/sbin/php5-fpm
{% endhighlight %}

So this second stop is waiting for **any** process whose executable is `/usr/sbin/php5-fpm`,
and if it do not stop after 30 seconds, a SIGTERM and then a SIGKILL is launched.  
When stopping the php-fpm-test version every other parallel php-daemon running will finally get killed.
Same for the first daemon.

That's not very nice.

###Fix the stop/killal problems###

First step, indicate a different binary in **/etc/init.d/php5-fpm-test**:

{% highlight bash %}
-NAME=php5-fpm
+NAME=php5-fpm-test
{% endhighlight %}

Then this binary should exists, doing a symbolic link from php5-fpm-test to php5-fpm will not fool
the  `/proc/pid/exe` link. So one ugly solution is to make a real copy of the binary:

{% highlight bash %}
cp /usr/sbin/php5-fpm /usr/sbin/php5-fpm-test
{% endhighlight %}

One caveat: when upgrading php5-fpm package you will have to redo this manual copy of the binary.

One other solution is to comment the second start-stop-daemon line, but you'll get a less robust stop script.

If you can think of a third solution send me an email.