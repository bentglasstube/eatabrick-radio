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
  
  $(window).keypress(function(e) {
    if (e.which == 32) {
      e.preventDefault();
      $('#play').click();
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

  var make_song_item = function(data) {
    var album = data.Album || '<em>Unknown Album</em>';
    var artist = data.Artist || '<em>Unknown Artist</em>';
    var title = data.Title || '<em>Untitled</em>';

    var image = $('<img>');
    image.attr('src', '/art?album=' + album + '&artist=' + artist);
    image.attr('alt', 'Album Art');
    image.addClass('thumb');

    var item = $('<li></li>');
    item.append(image);
    item.append(album + '<br>' + title);

    return item;
  };

  var song_id;
  setInterval(function() {
    $.get('/metadata', function(data) {
      if (song_id != data.Id) {
        song_id = data.Id;

        var album = data.Album || '<em>Unknown Album</em>';
        var title = data.Title || '<em>Untitled</em>';

        $('#metadata').animate({ opacity: 0 }, 1000, function() {
          $('#metadata').attr('title', album + ' - ' + title);
          $('#album').html(album);
          $('#title').html(title);
          $('#thumb').attr('src', '/art?' + new Date().getTime());

          $('#metadata').animate({ opacity: 1 }, 1000);
        });

        $.get('/playlist', function(data) {
          var item = make_song_item(data[data.length - 1]);
          $('#playlist').prepend(item);
          item.animate({ opacity: 1 }, 1000);

          $('#playlist li:last-child').animate({ opacity: 0 }, 1000, function() {
            $('#playlist li:last-child').remove();
          });

          $('#playlist li.active').removeClass('active');
          $('#playlist li:nth-child(2)').addClass('active');
        });
      }
    });
  }, 1000);

  $.get('/playlist', function(data) {
    var playlist = $('#playlist');
    for (var i = data.length - 2; i >= 0; --i) {
      var item = make_song_item(data[i]);
      if (i == data.length - 2) item.addClass('active');
      playlist.append(item);
      item.animate({ opacity: 1 }, 1000);
    }
    playlist.append('<li></li>');
  });
});
