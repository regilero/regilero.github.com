(function ($j) {
  $j(document).ready(function(){
      $j('.effect').hover(function(){
          $j(".cover-bottom", this).stop().animate(
              { top: '25px' }
              ,{ queue: false , duration:300 }
              );
          $j(".cover-right", this).stop().animate(
              { left: '118px' }
              ,{ queue: false , duration:300 }
              );
      }, function() {
          $j(".cover-bottom", this).stop().animate(
              { top:'221px' }
              ,{ queue:false , duration:300 }
          );
          $j(".cover-right", this).stop().animate(
              { left: '250px' }
              ,{ queue: false , duration:300 }
          );
      });
  });
  
  $j(document).ready(function(){
    // Fix deco effect height 
    var finalh = parseInt($j('#sideBarContent').css('height'),10);
    $j('.parallax-viewport').css('height',finalh+'px');
    $j('img:first',$j('.parallax-viewport')).attr('height',finalh+30+'px');
    $j('img:first',$j('.parallax-viewport')).css('height',finalh+30+'px');
    // Declare parallax on layers
    $j('.parallax-layer').parallax({
      mouseport: $j("#sideBarContent")
    });
  });
  
})(jQuery);
