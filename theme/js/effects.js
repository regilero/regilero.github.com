(function ($j) {

  // add TOC for posts
  $j(document).ready(function(){
    var $toc=$j("#post-toc");
    if ($toc.length > 0) {
      $toc.toc({
        'selectors': 'h1,h2,h3,h4', //elements to use as headings
        'container': '#post-full', //element to find all selectors in
        'smoothScrolling': true, //enable or disable smooth scrolling on click
        'prefix': 'toc', //prefix for anchor tags and class names
        'onHighlight': function(el) {}, //called when a new section is highlighted 
        'highlightOnScroll': false, //add class to heading that is currently in focus
        'highlightOffset': 100, //offset to trigger the next headline
        'anchorName': function(i, heading, prefix) { //custom function for anchor name
            return prefix+i;
        },
        'headerText': function(i, heading, $heading) { //custom function building the header-item text
            return $heading.text();
        },
        'itemClass': function(i, heading, $heading, prefix) { // custom function for item class
            return $heading[0].tagName.toLowerCase();
        }
      });
    }
  });

  // roll effects
  $j(document).ready(function(){
      $j('.effect').hover(function(){
          $j(".cover-bottom", this).stop().animate(
              { top: '25px' }
              ,{ queue: false , duration:300 }
              );
          $j(".cover-right", this).stop().animate(
              { left: '180px' }
              ,{ queue: false , duration:300 }
              );
      }, function() {
          $j(".cover-bottom", this).stop().animate(
              { top:'221px' }
              ,{ queue:false , duration:300 }
          );
          $j(".cover-right", this).stop().animate(
              { left: '320px' }
              ,{ queue: false , duration:300 }
          );
      });
  });
  
  // tooltips
  $j(document).ready(function(){
    // allow tooltips on links
    $j('a[data-toggle=tooltip]').tooltip({});
  });
  
})(jQuery);
