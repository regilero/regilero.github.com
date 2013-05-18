---
layout: post
uuid: d1451e02-926f-432e-8657-ebc323b8ab22
title: Requêtes récursives avec PostgreSQL 8.4 (WITH RECURSIVE)
categories: [PostgreSQL, Francais]
tags: [PostgreSQL, Bash]
pic: spider2.png
excerpt: Obtenir directement un résultat arborescent avec du SQL est un graal qui est désormais accessible sur PostgreSQL, et un exemple détaillé vaut mieux qu'un long discours. 

---

Si vous avez déjà touché à un Oracle vous connaissez peut-être le mot clef `CONNECT BY` qui permet d'effectuer des **requêtes arborescentes**.

Les requêtes arborescentes sont très pratiques pour extraire des données sous forme **d'arbre**, pour, par exemple,
remplir le jeu de données d'un arbre de type [jstree](http://www.jstree.com/) ou autre [plugin jquery d'arbre](http://plugins.jquery.com/?s=tree).

Pour faire simple dès que vous avez une table avec une **relation parent qui est une jointure sur elle-même** vous avez des chances
 d'avoir besoin de requêtes arborescentes.   
Sans cela vous risquez de partir sur des algorithmes assez complexe dans votre language de traitement de données (python, PHP, jsqp, etc).
Et c'est fort dommage quand le SGBD peut vous sauver la vie.  
Or donc sous postgreSQL il n'y avait pas d'équivalent du `connect by`, pas de requête arborescente.
Il faudra que dans un billet futur je vous montre mes petits triggers qui permettent de pallier à ça, mais il n'y a rien de simple là-dedans.
Mais depuis la version `8.4`, le mot clef **"WITH RECURSIVE"** nous permet de faire des requêtes récursives.  
Nous allons donc voir comment cela se manipule avec un exemple concret.

##L'exemple: des dossiers et fichiers##

Nous allons partir d'une table qui représente l'ensemble des fichiers et répertoires du disque dur, et essayer de faire des requêtes ordonnées
dessus.

Donc on commence par **la structure de la table qui va acceuillir toutes ces données**, je mets tout ça dans une base `test` accessible avec un user
`testuser` et un mot de passe qui va bien:

{% highlight sql %}
CREATE TYPE FILETYPE AS ENUM ('file', 'directory');
create table FILE (
   FILE_ID              SERIAL              not null,
   FILE_NAME            varchar(256)        not null,
   FILE_FULLNAME        varchar(1024)        not null unique,
   FILE_TYPE            FILETYPE             not null default 'file',
   FILE_PARENT           INT4                 not null default 0 references FILE (FILE_ID) on update restrict on delete restrict,
   CONSTRAINT PK_FILE primary key (FILE_ID)
);
create index FILE_FULLNAME_IDX on FILE (
FILE_FULLNAME
);
create index FILE_NAME_IDX on FILE (
FILE_NAME
);
{% endhighlight %}

On remarque la liaison `"references"` sur `FILE_PARENT` qui pointe sur la table elle-même, c'est tout le principe.  
Maintenant il va falloir remplir cette table. Ce n'est pas la partie la plus simple.
Le mieux serait sans doute un script python mais comme je suis un peu dingue j'ai écrit un script en bash
(vous remarquerez que je limite à 30 caractères dans le nom de directory pour restreindre l'analyse,
mais vous pouvez mettre plus si vous avez le temps d'attendre):

{% highlight bash %}
#!/bin/bash
REP_SOURCE="/";
BASE="test";
HOST="localhost";
USER="testuser";
MAXLENGHT=30;

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

function ctrl_c() {
    echo "** Trapped CTRL-C";
    exit 1;
}

function normalize {
    echo $(echo "$1"|sed "s/\"/_/g"|sed "s/'/_/g"|sed "s/ /_/g");
}
function treeanalyse {
    DIR=$1;
    # shorten duration of this script with path greater than MAXLENGHT chars
    len=`expr length "$DIR"`;
    if [ $len -lt $MAXLENGHT ]; then
        #echo "DIR $DIR"
        nDIR=$(normalize "$DIR");
        # files detection
        find "$DIR" -maxdepth 1 -type f | while read FIL ; do
            FILENAME=`basename "$FIL"`;
            nNAME=$(normalize "$FILENAME");
            nFIL=$(normalize "$FIL");
            SQL="INSERT INTO FILE (FILE_NAME,FILE_FULLNAME,FILE_TYPE,FILE_PARENT) SELECT '$nNAME','$nFIL','file', FILE_ID FROM FILE WHERE FILE_FULLNAME='$nDIR';"
            echo "${SQL}" >> /tmp/insert.sql
        done
        # directory detection
        find "${DIR}" -maxdepth 1 -type d | while read SUBDIR ; do
            echo "$SUBDIR";
            DIRNAME=`basename "$SUBDIR"`;
            if [ "$SUBDIR" != "$DIR" -a "$DIRNAME" != "proc" -a "$DIRNAME" != "sys" -a "$DIRNAME" != "mnt" -a "$DIRNAME" != "." -a "$DIRNAME" != ".." ]; then
                CLEANDIRNAME=$(echo $DIRNAME|sed "s/\"/_/g"|sed "s/'/_/g"|sed "s/ /_/g");
                nDIRNAME=$(normalize "$DIRNAME");
                nDIR=$(normalize "$DIR");
                nSUBDIR=$(normalize "$SUBDIR");
                SQL="INSERT INTO FILE (FILE_NAME,FILE_FULLNAME,FILE_TYPE,FILE_PARENT) SELECT '$nDIRNAME','$nSUBDIR','directory',FILE_ID FROM FILE WHERE FILE_FULLNAME='$nDIR';"
                echo "${SQL}" >> /tmp/insert.sql;
                DIRBACKUP=$DIR; # prevent variable overlap in bash
                treeanalyse $SUBDIR;
                DIR=$DIRBACKUP; # prevent variable overlap in bash
            fi
        done
    fi
}

PARENTDIR="0"
SQL="TRUNCATE FILE;"
echo "${SQL}" > /tmp/insert.sql;
SQL="INSERT INTO FILE (FILE_ID,FILE_NAME,FILE_FULLNAME,FILE_TYPE,FILE_PARENT) VALUES ($PARENTDIR,'$REP_SOURCE','$REP_SOURCE','directory',$PARENTDIR);"
PARENTDIR=$REP_SOURCE;
DIR=$REP_SOURCE;
echo "${SQL}" >> /tmp/insert.sql;
echo "Analysing";
treeanalyse $DIR;

echo "STARTING SQL INSERTION:"
#PGCOMMAND="psql -d $BASE -h $HOST -U $USER --single-transaction -f "
PGCOMMAND="psql -d $BASE -h $HOST -U $USER -f "
$PGCOMMAND /tmp/insert.sql;
echo "Done"
{% endhighlight %}

En exécutant ce script (n'oubliez pas le chmod u+x) on obtient un gros fichier `/tmp/insert.sql` (109 382 lignes chez moi)
qui est ensuite importé dans un grosse transaction postgreSQL si tout se passe bien.  
Bon, il supporte encore assez mal les noms de dossiers avec ' ou des " dedans, mais même si la transaction echoue vous avez
votre /tmp/insert.sql dans lequel vous pouvez peut-être supprimer les dossiers et fichiers embétants.

##Tester les requêtes récursives##

Voyons ensuite la requête récursive, la [documentation postgreSQL](http://www.postgresql.org/docs/8.4/static/queries-with.html)  nous donne un modèle:

{% highlight sql %}
WITH RECURSIVE t(n) AS (
    VALUES (1)
  UNION ALL
    SELECT n+1 FROM t WHERE n < 100
)
SELECT sum(n) FROM t;
{% endhighlight %}

Qui sur notre table des fichiers va donner:

{% highlight sql %}
WITH RECURSIVE rectable(FILE_ID,FILE_NAME,FILE_FULLNAME,FILE_TYPE) AS (
    SELECT FILE_ID,FILE_NAME,FILE_FULLNAME,FILE_TYPE
    FROM FILE
    WHERE FILE_FULLNAME='/usr/local'
  UNION ALL
    SELECT orig.FILE_ID,orig.FILE_NAME,orig.FILE_FULLNAME,orig.FILE_TYPE
    FROM rectable rec,FILE orig
    WHERE orig.FILE_PARENT=rec.FILE_ID
)
SELECT FILE_ID,FILE_NAME,FILE_FULLNAME,FILE_TYPE
FROM rectable
ORDER BY FILE_FULLNAME;
{% endhighlight %}

Pour par exemple obtenir le sous arbre de `/usr/local`.

Remarquez la façon dont la table `FILE` se voit renommée **3 fois** pour la requête, `rectable` devient la requête récursive,
une "fausse table" sur laquelle on fait notre requête finale.  
A l'intérieur nous avons une première partie qui initialise la récursion en sélectionnant une ligne de la table `FILE`,
et après le `UNION ALL` nous utilisons `rectable` qui contient au départ **l'initialisation** et plus tard les **résultats**
des récursions passées que nous joignons avec la table `FILE` renommée pour l'occasion `orig`, jointe sur la relation parent.  
C'est différent de la syntaxe du `CONNECT BY` de oracle, mais je ne suis pas loin de penser que c'est plus élégant
(<strike>peut-être pas encore aussi puissant, pas de détection de cycle, de leaf ou de level
-- quoique en lisant bien la doc je dois pouvoir le faire</strike>).

Alors vous me direz que faire un `order by` sur le `FILE_FULLNAME` pour avoir la requêtre triée c'est un peu de la triche,
parce qu'on aurait pu alors tout aussi juste stocker le `FULLNAME` et se servir du tri sans la récursion.  
C'est un peu vrai, mais là j'ai mis le `FILE_FULLNAME` pour faire **joli**, je ne suis pas du tout obligé de stocker cette information.
Donc voici la même mais ordonnée sur la relation parent:

{% highlight sql %}
WITH RECURSIVE rectable(FILE_ID,FILE_NAME,FILE_FULLNAME,FILE_TYPE,FILE_PARENT) AS (
    SELECT FILE_ID,FILE_NAME,FILE_FULLNAME,FILE_TYPE,FILE_PARENT
    FROM FILE
    WHERE FILE_FULLNAME='/usr/local'
  UNION ALL
    SELECT orig.FILE_ID,orig.FILE_NAME,orig.FILE_FULLNAME,orig.FILE_TYPE,orig.FILE_PARENT
    FROM rectable rec,FILE orig
    WHERE orig.FILE_PARENT=rec.FILE_ID
)
SELECT FILE_ID,FILE_NAME,FILE_FULLNAME,FILE_TYPE,FILE_PARENT
FROM rectable
ORDER BY FILE_PARENT,FILE_NAME;
{% endhighlight %}

Problème on perd notre tri d'arbre.  
On a d'abord les répertoires et ensuite seulement les fichiers de ces répertoires.
Si on veut trier proprement sans avoir le `FILE_FULLNAME` il faut en fait le récréer dans la récursion:

{% highlight sql %}
WITH RECURSIVE rectable(FILE_ID,FILE_NAME,FILE_TYPE,FILE_PARENT,rorder) AS (
    SELECT FILE_ID,FILE_NAME,FILE_TYPE,FILE_PARENT,'/'||FILE_NAME as rorder
    FROM FILE
    WHERE FILE_FULLNAME='/usr/local/nagios'
  UNION ALL
    SELECT orig.FILE_ID,orig.FILE_NAME,orig.FILE_TYPE,orig.FILE_PARENT,rec.rorder||'/'||orig.FILE_NAME as rorder
    FROM rectable rec,FILE orig
    WHERE orig.FILE_PARENT=rec.FILE_ID
)
SELECT FILE_ID,FILE_NAME,FILE_TYPE,FILE_PARENT,rorder
FROM rectable
ORDER BY rorder;
 file_id |              file_name               | file_type | file_parent |                        rorder                       
---------+--------------------------------------+-----------+-------------+------------------------------------------------------
   80764 | nagios                               | directory |       80760 | /nagios
   80782 | bin                                  | directory |       80764 | /nagios/bin
   80785 | nagios                               | file      |       80782 | /nagios/bin/nagios
   80784 | nagiostats                           | file      |       80782 | /nagios/bin/nagiostats
   80786 | ndo2db                               | file      |       80782 | /nagios/bin/ndo2db
   80783 | ndomod.o                             | file      |       80782 | /nagios/bin/ndomod.o
   80765 | etc                                  | directory |       80764 | /nagios/etc
   80767 | cgi.cfg                              | file      |       80765 | /nagios/etc/cgi.cfg
   80770 | htpasswd.users                       | file      |       80765 | /nagios/etc/htpasswd.users
   80766 | nagios.cfg                           | file      |       80765 | /nagios/etc/nagios.cfg
   80769 | ndo2db.cfg                           | file      |       80765 | /nagios/etc/ndo2db.cfg
{% endhighlight %}

Et là où ce type de requête devient **magique**, je vais aussi pouvoir filtrer pour avoir uniquement les directory,
par exemple,
puis filtrer les résultats pour ne garder que les sous-sous répertoires qui commencent par un `"."`:

{% highlight sql %}
WITH RECURSIVE rectable(FILE_ID,FILE_NAME,FILE_FULLNAME,FILE_TYPE,FILE_PARENT) AS (
    SELECT FILE_ID,FILE_NAME,FILE_FULLNAME,FILE_TYPE,FILE_PARENT
    FROM FILE
    WHERE FILE_FULLNAME='/usr/local'
  UNION ALL
    SELECT orig.FILE_ID,orig.FILE_NAME,orig.FILE_FULLNAME,orig.FILE_TYPE,orig.FILE_PARENT
    FROM rectable rec,FILE orig
    WHERE orig.FILE_PARENT=rec.FILE_ID
    AND orig.FILE_TYPE='directory'
)
SELECT FILE_ID,FILE_NAME,FILE_FULLNAME,FILE_TYPE,FILE_PARENT
FROM rectable
WHERE rectable.FILE_NAME LIKE '.%'
ORDER BY FILE_FULLNAME;
file_id | file_name |                      file_fullname                      | file_type | file_parent
---------+-----------+---------------------------------------------------------+-----------+-------------
   31058 | .deps     | /usr/local/src/nagios-plugins-1.4.14/plugins-root/.deps | directory |       31047
   31059 | .libs     | /usr/local/src/nagios-plugins-1.4.14/plugins-root/.libs | directory |       31047
   31112 | .deps     | /usr/local/src/nagios-plugins-1.4.14/tap/.deps          | directory |       31105
   31502 | .deps     | /usr/local/src/nagios-plugins-1.4.14/gl/.deps           | directory |       31243
   31627 | .deps     | /usr/local/src/nagios-plugins-1.4.14/lib/.deps          | directory |       31565
   31616 | .deps     | /usr/local/src/nagios-plugins-1.4.14/lib/tests/.deps    | directory |       31586
   31766 | .deps     | /usr/local/src/nagios-plugins-1.4.14/plugins/.deps      | directory |       31645
   31812 | .libs     | /usr/local/src/nagios-plugins-1.4.14/plugins/.libs      | directory |       31645
(8 lignes)
{% endhighlight %}

Si vous voulez garder les fonctionnalités avancées du `CONNECT BY` comme les détection de **levels** et de **cycles**
il y a (en dehors de la méthode expliquée ci-dessous) la solution des **triggers** à l'insertion, que je rédigerai dès que j'en aurais le temps...  
Mais déjà nous pouvons ajouter facilement le niveau de profondeur en nous basant sur le premier modèle:

{% highlight sql %}
WITH RECURSIVE rectable(FILE_ID,FILE_NAME,FILE_FULLNAME,FILE_TYPE,FILE_PARENT,level) AS (
    SELECT FILE_ID,FILE_NAME,FILE_FULLNAME,FILE_TYPE,FILE_PARENT,1 as level
    FROM FILE
    WHERE FILE_FULLNAME='/usr/local/nagios'
  UNION ALL
    SELECT orig.FILE_ID,orig.FILE_NAME,orig.FILE_FULLNAME,orig.FILE_TYPE,orig.FILE_PARENT,rec.level+1 as level
    FROM rectable rec,FILE orig
    WHERE orig.FILE_PARENT=rec.FILE_ID
)
SELECT FILE_ID,FILE_NAME,FILE_FULLNAME,FILE_TYPE,FILE_PARENT,level
FROM rectable
ORDER BY FILE_FULLNAME;
{% endhighlight %}

##Essayons de casser un peu tout ça.##

Nous allons tester la **détection de cycle** proposée dans la documentation.
<pre>
  80764 | nagios   | directory | 80760 | /usr/local/nagios
  80782 | bin      | directory | 80764 | /usr/local/nagios/bin
  80772 | objects  | directory | 80765 | /usr/local/nagios/etc/objects
</pre>

Créeons un **bug**, On va chercher à partir de `/usr/local/nagios-80764` et donner un répertoire parent (`/usr/local-80760`)
comme fils d'un des sous répertoires (`/usr/local/nagios/etc/objects-80765`)

{% highlight sql %}
UPDATE FILE SET FILE_PARENT=80765 WHERE FILE_ID=80760;
{% endhighlight %}

Utilisons le chemin recomposé et non le `FILE_FULLNAME`:

{% highlight sql %}
WITH RECURSIVE rectable(FILE_ID,FILE_NAME,rorder,FILE_TYPE,FILE_PARENT,level) AS (
    SELECT FILE_ID,FILE_NAME,'/'||FILE_NAME as rorder,FILE_TYPE,FILE_PARENT,1 as level
    FROM FILE
    WHERE FILE_FULLNAME='/usr/local/nagios'
  UNION ALL
    SELECT orig.FILE_ID,orig.FILE_NAME,rec.rorder||'/' ||orig.FILE_NAME as rorder,orig.FILE_TYPE,orig.FILE_PARENT,rec.level+1 as level
    FROM rectable rec,FILE orig
    WHERE orig.FILE_PARENT=rec.FILE_ID
)
SELECT FILE_ID,FILE_NAME,rorder,FILE_TYPE,FILE_PARENT,level
FROM rectable
ORDER BY rorder;
{% endhighlight %}

==> oups ça ne réponds plus (boucle infinie) faire un CTRL-C  
On va donc ajouter la détection de cycle, notre chemin recomposé va se doubler d'un **tableau des identifiants parcourus**
et nous ferons une **recherche** dans cet `array` pour détecter le cycle:

{% highlight sql %}
WITH RECURSIVE rectable(FILE_ID,FILE_NAME,rorder,FILE_TYPE,FILE_PARENT,level,path,cycle) AS (
    SELECT FILE_ID,FILE_NAME,'/'||FILE_NAME as rorder,FILE_TYPE,FILE_PARENT,1 as level,ARRAY[FILE_ID],false
    FROM FILE
    WHERE FILE_FULLNAME='/usr/local/nagios'
  UNION ALL
    SELECT orig.FILE_ID,orig.FILE_NAME,rec.rorder||'/' ||orig.FILE_NAME as rorder,orig.FILE_TYPE,orig.FILE_PARENT,
        rec.level+1 as level,rec.path||orig.FILE_ID,orig.FILE_ID=ANY(rec.path)
    FROM rectable rec,FILE orig
    WHERE orig.FILE_PARENT=rec.FILE_ID
    AND NOT cycle
)
SELECT FILE_ID,FILE_NAME,rorder,FILE_TYPE,FILE_PARENT,level,cycle
FROM rectable
ORDER BY rorder;
{% endhighlight %}

Et ça fonctionne, on a beaucoup trop de résultats (une partie de `/usr/local` branché dans `/usr/local/nagios/etc/configObjects`) -- à cause du bug introduit --
mais au moins la requête réponds et ne fais pas une boucle infinie.
La détection de cycle se base ici sur l'array des Identifiants parcourus, des exemples plus complexes sont données dans la documentation
posgreSQL citée plus haut. **Attention** à ne pas oublier le `AND NOT cycle` dans la sous-requête.