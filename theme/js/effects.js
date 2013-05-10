(function ($j) {
  $j(document).ready(function(){
        console.log($j('.effect'));
      $j('.effect').hover(function(){
        console.log($j(".cover-bottom", this));
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
})(jQuery);
