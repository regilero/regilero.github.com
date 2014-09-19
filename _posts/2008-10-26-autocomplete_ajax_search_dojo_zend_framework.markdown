---
layout: post
uuid: e1ff7b10-4e59-4762-a294-7dbda908f5a2
title: Autocomplete Ajax search with Dojo and Zend Framework
categories: [Zend Framework, English]
tags: [ZendFramework, Dojo, js, Ajax]
pic: old3.jpg
excerpt: How to build a Dojo autocomplete with ZF 1.6, with a nice json response.

---

With the new Zend Framework 1.6 we've these nice Dojo widgets.

New things lacks documentations most of times.   
So if you want to build something really usefull like theses nice autocomplete search combobox this example could save you a lot of time.

We'll assume you have Dojo already installed and activated on your views,
and that acl verifications are done elsewhere, on your Controller plugins for example.

First let's see HTML code (in your view):

{% highlight html %}
  <script type="text/javascript">
    dojo.require("dojo.parser");
    dojo.require("dojox.data.QueryReadStore");
    dojo.require("dijit.form.ComboBox");
    dojo.require("dijit.form.FilteringSelect");
    dojo.require("custom.FindAutoCompleteReadStore");
    dojo.require("dijit.form.Form");
    dojo.require("dijit.form.Button");
  </script>
  <form id="Find_Form" action="/module/foo/edit" method="get" dojoType="dijit.form.Form">
    <div dojoType="custom.FindAutoCompleteReadStore" jsId="NameStore" url="/module/foo/find/format/json" requestMethod="get"></div>
    <label for="id" class="optional">Recherchez un nom:</label>
    <span class="formelement"><select name="id" id="FindByName" hasDownArrow="" store="NameStore" size="25" tabindex="99" autocomplete="1" dojoType="dijit.form.FilteringSelect" pageSize="10" ></select></span>
    <span class="actionbuttons"><input id="Find_go" name="Find_go" value="Go:" type="submit" label="go:"dojoType="dijit.form.Button" /></span>
  </form>
{% endhighlight %}

As we can see you'll need an additional custom js: **custom.FindAutoCompleteReadStore**.

This is a really simple js to write, create your custom directory in the same level
as dojo or dijit directory and create `FindAutoCompleteReadStore.js` like that:

{% highlight js %}
dojo.provide("custom.FindAutoCompleteReadStore");
dojo.require("dojox.data.QueryReadStore");
dojo.declare("custom.FindAutoCompleteReadStore", dojox.data.QueryReadStore, {
  fetch:function (request) {
    request.serverQuery = { Find:request.query.name };
    // cal superclass fecth
    return this.inherited("fetch", arguments);
  }
});
{% endhighlight %}

Now you'll need to serve the requested Ajax query
(requested by the Dojo store linked with our FilteringSelect or Combobox) : `/module/foo/find/format/json`  
This is the method **'findAction'** in the Controller **'foo'** on module **'module'**.  
But first let's see the preDispatch function of this controller where we handle the `format/json` instruction to switch in Ajax mode:

{% highlight php %}
public function preDispatch()
{
    $contextSwitch =   $this->_helper->getHelper('contextSwitch');
    $contextSwitch->setAutoJsonSerialization( true );
    $contextSwitch->addActionContext('find', 'json');
    $contextSwitch->initContext();
}
{% endhighlight %}

So now let's write the find function:
 
{% highlight php %}
  public function findAction()
  {
      // handle filtering of recieved data
      $replacer = new Zend_Filter_pregReplace('/\*/','%');
      // emulate alpha+num filter with some more characters enabled
      //**** <a href="http://www.regular-expressions.info/unicode.html" title="http://www.regular-expressions.info/unicode.html">http://www.regular-expressions.info/unicode.html</a> ****
      // \p{N} --> numeric chars of any language
      // \s -> withespace
      //\x0027 : APOSTROPHE
      //\x002C : COMMA
      //\x0025% : % in UTF-8 and not in utf-8
      //\x002D : HYPHEN / MINUS
      //\x005F : UNDERSCORE
      //\. DOT
      $mylimit = new Zend_Filter_pregReplace('/[^\p{L}\p{N}\s\x0027\x002C\x002D\x005F\x0025%\.]/u','');
      $filters = array(
              '*' => 'StringTrim'
              ,'Find' => array(
              'StripNewlines'
              ,$replacer
              ,$mylimit
              ,'StripTags'
          )
          ,'start' => 'Int'
          ,'count' => 'Int'
      );
      $validators =array();
      $input = new Zend_Filter_Input($filters, $validators, $_GET);
      $find = $input->getUnescaped('Find');
      if (empty($find)) $find = '%';
      $start = intval($input->getUnescaped('start'));
      if (empty($start)) $start = 0;
      $count = intval($input->getUnescaped('count'));
      if (empty($count)) $count = 3;
      // get the model, here you should adjust with the way you work
      // then make your query with limits
      $this->_modeltable = new My_Zend_Db_Table_Foo($this->db)
      $fieldid = 'my_id_field';
      $fieldident = 'my_name_field';
      $select = $this->_modeltable->select();
      $db = $this->_modeltable->getAdapter();
      $select->where($db->quoteinto($db->quoteIdentifier($fieldident).' LIKE ?', $find));
      $select->limit($count, $start);
      $rows= $this->_modeltable->fetchAll($select);
      $rowsarray = $rows->ToArray();
      $finalarray=array();
      foreach ($rowsarray as $row)
      {
          $key = $row[$fieldid];
          $finalarray[$key] = $row[$fieldident];
      }
      //Zend_Debug::dump($finalarray);
      //die(__METHOD__);
      $this->_helper->autoCompleteDojo($finalarray);
  }
{% endhighlight %}

And it should be sufficient, pffiuu.  
But... there's one remaining problem after that.
We put the search autocomplete inside a form and we wanted the **'go'** button to send a request to something like that:

`/module/foo/edit/id/1245` OR `/module/foo/edit?id=1245`

But we'll have something like:

`/module/foo/edit?id=THE NAME`

too bad...

To get it done I had to change one thing in Zend Framework library on the Zend/Controller/Action/Helper/AutoCompleteDojo.php Helper:

{% highlight php %}
  public function prepareAutoCompletion($data, $keepLayouts = false)
  {
    $items = array();
    foreach ($data as $key => $value) {
      $items[] = array('label' => $value, 'name' => $value, 'key' => $key);
    }
    $final = array(
      'identifier' => 'key',
      'items' => $items,
     );
    return $this->encodeJson($final, $keepLayouts);
  }
{% endhighlight %}

Line 66 `'key'` is added on the item and line 69 `'identifier'` is set to `'key'` and not `'name'`.  
`'identifier'` is used by the Dojo Filtering Select to decide which field will be used for the form,
for more info see [dojo book page](http://dojotoolkit.org/reference-guide/1.9/) and search `'abbreviation'`.

There's also a bug talking about that for Zend Framework,
to get other solutions or info on the way it will be fixed later look [there](http://framework.zend.com/issues/browse/ZF-4494).
