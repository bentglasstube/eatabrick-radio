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

    $.post('/skip', null, function(data) {
      if (data.status == 'error') alert(data.message);
    });
  });

  var adjusting = false;
  var set_volume = function(volume) {
    $('#radio')[0].volume = volume;
    $('#volume p').css('width', volume * 100 + '%');
  };

  $('#volume').mousedown(function(e) {
    e.preventDefault();
    adjusting = true;
    set_volume(e.offsetX / $(this).width());
  }).mouseup(function(e) {
    e.preventDefault();
    adjusting = false;
  }).mouseleave(function(e) {
    e.preventDefault();
    adjusting = false;
  }).mousemove(function(e) {
    if (adjusting) set_volume(e.offsetX / $(this).width());
  });

  var song_id;
  setInterval(function() {
    $.get('/metadata', function(data) {
      if (song_id != data.Id) {
        song_id = data.Id;

        var album = data.Album || '<em>Unknown Album</em>';
        var title = data.Title || '<em>Untitled</em>';

        $('#metadata').attr('title', album + ' - ' + title);
        $('#album').html(album);
        $('#title').html(title);
        $('#thumb').attr('src', '/art?' + new Date().getTime())
      }
    });
  }, 1000);
});
