---
layout: post
title: Drupal - Mongodb statistics module published
categories: [Drupal, English]
tags: [Drupal, Performance, Mongodb, Statistics]
pic: flower2.png
excerpt: mongodb-statistics module for drupal is a replacement for core statistics module using an ajax callback tracker. 

---

###What is this about?###
    
Just a few words, as I've other some things to do.

I've just published a development version of [mongodb-statistics](http://github.com/regilero/drupal_mongodb_statistics) on github.
    
This module is a first try on replacing heavy MySQL operations done by the core statistics module.
    
It's copy-and-alter of the core statistics module, with some additions.
So it's not the nicest piece of code I could write :-)
    
On the things added :
    
 * batch migration of previous node_counter statistics if any (not yet for accesslog)
 * post-synchronisation of node_counter mongodb table to a sql table (via cron), so that you could query it via views (not for accesslog, are you mad?)
 * time based caching of the popular content block
 * Still lot of thing to do (see the [TODO](https://github.com/regilero/drupal_mongodb_statistics/blob/master/mongodb_statistics/TODO.txt)) but it was a nice way to learn **mongodb**. I especially like the idea of [mapReduce](http://nosql.mypopescu.com/post/392418792/translate-sql-to-mongodb-mapreduce) functions applied for complex `GROUP BY` equivalents.
