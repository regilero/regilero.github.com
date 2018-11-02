---
layout: post
uuid: f2b47778-a8de-4cec-9c9e-75f9ae93c696
title: Temps de réponse réél d'une page web avec ... netcat
categories: [francais, Monitoring]
tags: [Linux, HTTP, Monitoring, Apache, Nginx]
pic: old1.jpg
excerpt: Comment obtenir le temps de réponse d'un site avec une ligne de commande concise, sans wget et sans telnet (mais avec netcat) 

---

Bon, j'imagine que la plupart des gens (heu.. d'un certain type) savent qu'on peut faire du web **à la main** avec telnet ou netcat.
Et bien on peut. Donc.
Je voulais me servir de cela pour tracer quelques temps de réponse de pages html précises.
Le tout en une seule ligne histoire de se servir de l'historique et pas de mon cerveau pour la retaper.

Commencons par un telnet sur [www.google.com](http://www.google.com) sur le port 80 (web).
On tape la requète comme si nous étions un navigateur web (très basique le navigateur). La requète HTTP va donc être:

{% highlight http %}
  GET / HTTP/1.0
  
{% endhighlight %}

Remarquez qu'il y a une ligne vide (donc deux fois entrée).

Cela donne en résultat une page de redirection vers le site français de google, parfait.

{% highlight bash %}
  nii:~$ telnet www.google.com 80
  Trying 209.85.129.147...
  Connected to www.l.google.com.
  Escape character is '^]'.
  GET / HTTP/1.0
  .
  HTTP/1.0 302 Found
  Location: http://www.google.fr/
  (.. je vous passe le reste ...)
  Connection closed by foreign host.
  nii:~$
{% endhighlight %}

Bon, maintenant je veux mesurer le temps de réponse. Avec tout bètement la commande 'time'.
Pour faire cela l'idéal est de taper ma commande en une seule fois,
et là telnet n'est plus très souple pour automatiser la saisie utilisateur On va commencer par tester la même chose avec netcat (nc)

{% highlight http %}
  nii:~$ printf 'GET / HTTP/1.0\n\n' | \
  nc -w 10 www.exemple.com 80
{% endhighlight %}

On avance. Par contre on a de fortes chances de ne pas tomber sur la page web que l'on recherche vraiment.
On a de très fortes chances de tomber sur le VirtualHost par défaut du serveur HTTP
à l'autre bout.
Mais pour servir le bon site il faut taper du **HTTP/1.1** au lieu de 1.0 et ajouter un header à notre
requète indiquant au serveur le nom du site que l'on veut (parmi ceux qu'il héberge),
revoyez le protocole [http version 1.1](http://en.wikipedia.org/wiki/HTTP#Request_Message) si vous ne comprenez rien à ce que je dis.

{% highlight http %}
  nii:~$ printf 'GET / HTTP/1.1\nHost:www.exemple.com\n\n' | \
  nc -w 10 -q 10 www.exemple.com 80
{% endhighlight %}

Et maintenant pour avoir le temps de la commande je rajoute time au début et je fais sauter le temps d'affichage de la réponse...

{% highlight http %}
  nii:~$ time printf 'GET / HTTP/1.1\nHost:www.exemple.com\n\n' | \
  nc -w 10 -q 10 www.exemple.com 80 1>/dev/null
  .
  real    0m0.627s
  user    0m0.000s
  sys     0m0.004s
  nc -w 10 -q 10 www.exemple.com 80
{% endhighlight %}

**Mais...**  
Il y a une grosse erreur.
On se prends **le temps d'une requète DNS** de la machine sur laquelle on est qui cherche l'adresse IP de l'hôte
que l'on a donné à netcat (après le nc -w 10) pour aller ouvrir une connexion tcp sur le port 80 de cet hôte.
Ce temps DNS ne sert à rien, il fausse notre résultat (et c'est souvent très long le DNS).
Il faut utiliser l'adresse IP du serveur web directement.
De toutes façons c'est à l'intérieur du protocole HTTP, avec notre entête **Host:** que l'on indique le site web
demandé au serveur, et pas du tout avec le nom DNS utilisé pour résoudre l'adresse IP du serveur web.

{% highlight http %}
  nii:~$ nslookup ww.exemple.com
  66.116.125.121
  nii:~$ time printf 'GET / HTTP/1.1\nHost:www.exemple.com\n\n' | \
  nc -w 10 -q 10 66.116.125.121 80 1>/dev/null
  .
  real    0m0.408s
  user    0m0.004s
  sys     0m0.000s
{% endhighlight %}

**0.408s** est déjà plus proche du temps de réponse réèl du site (depuis le point du réseau où on se trouve,
 il y a des pertes dues au réseau, forcément).
 
PS: vive les sites [Best Viewed with telnet to port 80](http://www.dgate.org/~brg/bvtelnet80/)
