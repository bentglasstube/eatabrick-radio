$(function() {
  var playing = false;

  $('#play').click(function(e) {
    e.preventDefault();

    var audio = $('#radio')[0];

    if (playing) {
      audio.pause();

      playing = false;
      $('#play i').removeClass('fa-stop');
      $('#play i').addClass('fa-play');
    } else {
      audio.load();
      audio.play();

      playing = true;
      $('#play i').removeClass('fa-play');
      $('#play i').addClass('fa-stop');
    }
  });

  $('#skip').click(function(e) {
    e.preventDefault();

    alert('Sorry, this is not yet implemented');
  });

  $('#volume').click(function(e) {
    var volume = e.offsetX / $(this).width();

    $('#radio')[0].volume = volume;
    $('#volume p').css('width', volume * 100 + '%');
  });
});
 
