$(function() {
  var playing = false;

  var set_page_title = function() {
    if (playing) {
      document.title = $('#title').text();
    } else {
      document.title = 'eatabrick radio';
    }
  }

  var colors = [ '#df0', '#eab', '#b22', '#2b2', '#22b', '#222', '#27c' ];
  var current_color = 0;

  var set_colors = function(bg) {
    console.log('Color ' + bg);

    var r = parseInt(bg[1], 16);
    var g = parseInt(bg[2], 16);
    var b = parseInt(bg[3], 16);

    var a = 1 - (0.299 * r + 0.587 * g + 0.114 * b) / 16;
    var fg;
    if (a < 0.5) fg = '#333';
    else fg = '#eee';

    $('#header').animate( {'background-color': bg, 'color': fg}, 1000);
    $('#controls a').animate({'color': fg}, 1000);
    $('#volume p').animate({'background-color': fg}, 1000);
  };

  var cycle_colors = function() {
    current_color = (current_color + 1) % colors.length;
    set_colors(colors[current_color]);
  };

  var random_colors = function() {
    var r = Math.floor(Math.random() * 16).toString(16);
    var g = Math.floor(Math.random() * 16).toString(16);
    var b = Math.floor(Math.random() * 16).toString(16);
    set_colors('#' + r + g + b);
  };

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

      // TODO wait to set playing until actually playing
      playing = true;
      $('#play i').removeClass('fa-play');
      $('#play i').addClass('fa-stop');
    }

    set_page_title();
  });

  $(document).keydown(function(e) {
    if (e.which == 32) {
      e.preventDefault();
      $('#play').click();
    } else if (e.which == 34) {
      e.preventDefault();
      $('#skip').click();
    } else if (e.which == 67) {
      e.preventDefault();
      cycle_colors();
    } else if (e.which == 82) {
      e.preventDefault();
      random_colors();
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

          set_page_title();
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
