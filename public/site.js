$(function() {
  var state = 'stopped';

  var set_page_title = function() {
    if (state == 'playing') {
      document.title = 'eatabrick radio - ' + $('#title').text();
    } else {
      document.title = 'eatabrick radio';
    }
  }

  var set_color = function(color) {
    var brightness = 1 - (0.299 * color.red() + 0.587 * color.green() + 0.114 * color.blue()) / 256;
    var text = brightness < 0.5 ? '#333' : '#eee';

    $('#header').animate( {'background-color': color, 'color': text}, 1000);
    $('#controls a').animate({'color': text}, 1000);
    $('#volume p').animate({'background-color': text}, 1000);
  };

  var song_color = function(album, title) {
    var hue = 0;
    for (var i = 0; i < album.length; ++i) {
      hue = (album.charCodeAt(i) + (hue << 4) - hue) % 360;
    }

    var lightness = 0;
    var saturation = 0;
    for (var i = 0; i < title.length; ++i) {
      lightness = (title.charCodeAt(i) + (lightness << 4) - lightness) % 60;
      saturation = (title.charCodeAt(i) + (saturation << 5) - saturation) % 40;
    }

    return jQuery.Color({
      hue: hue,
      saturation: (saturation + 60) / 100,
      lightness: (lightness + 20) / 100,
    });
  };

  var set_state = function(new_state) {
    state = new_state;
    var i = $('#play i');
    if (state == 'playing') {
      i.removeClass('fa-spin fa-play fa-cog');
      i.addClass('fa-stop');
    } else if (state == 'stopped') {
      i.removeClass('fa-spin fa-stop fa-cog');
      i.addClass('fa-play');
    } else if (state == 'loading') {
      i.removeClass('fa-play fa-stop');
      i.addClass('fa-spin fa-cog');
    }
  };

  var show_alert = function(message, timeout) {
    var a = $('<div/>');
    a.addClass('alert alert-warning fade');
    a.text(message);
    a.insertBefore('#playlist');
    a.animate({opacity: 1}, function() {
      setTimeout(function() {
        a.animate({opacity: 0}, function() { a.remove(); });
      }, timeout * 1000);
    });
  };

  $('#play').click(function(e) {
    e.preventDefault();

    var audio = $('#radio')[0];

    if (state == 'playing') {
      audio.pause();
      set_state('stopped');
    } else if (state == 'stopped') {
      audio.load();
      audio.play();
      set_state('loading');
    }

    set_page_title();
  });

  $('#radio').bind('playing', function() {
    set_state('playing');
  });

  $('#radio').bind('error', function(e) {
    show_alert('Audio error: ' + e.target.error);
    set_state('stopped');
  });

  $('#radio').bind('ended', function() {
    console.log('Audio ended');
    set_state('stopped');
  });

  $(document).keydown(function(e) {
    if (e.which == 32) {  // space
      e.preventDefault();
      $('#play').click();
    } else if (e.which == 39) { // right arrow
      e.preventDefault();
      $('#skip').click();
    } else if (e.which == 38) { // up arrow
      e.preventDefault();
      set_volume(get_volume() + 0.05);
    } else if (e.which == 40) { // down arrow
      e.preventDefault();
      set_volume(get_volume() - 0.05);
    }
  });

  $('#skip').click(function(e) {
    e.preventDefault();

    $.post('/skip', null, function(data) {
      if (data.status == 'error') {
        show_alert(data.message, 5);
      }
    });
  });

  var adjusting = false;
  var set_volume = function(volume) {
    $('#radio')[0].volume = volume;
    $('#volume p').css('width', volume * 100 + '%');
  };
  var get_volume = function() {
    return $('#radio')[0].volume;
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

    var item = $('<li id="' + data.uri + '"></li>');
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
        var current = data.uri;

        set_color(song_color(album, title));

        $('#metadata').animate({ opacity: 0 }, 1000, function() {
          $('#metadata').attr('title', album + ' - ' + title);
          $('#album').html(album);
          $('#title').html(title);
          $('#thumb').attr('src', '/art?' + new Date().getTime());

          set_page_title();
          $('#metadata').animate({ opacity: 1 }, 1000);
        });

        // TODO decouple playlist changes from song changes
        $.get('/playlist', function(data) {
          var i = 0;
          var playlist = $('#playlist');
          var items = playlist.children();

          for (var j = items.length - 1; j >= 0; --j) {
            if (i >= data.length) break;
            if (items[j].id == data[i].uri) {
              ++i;
            } else {
              console.log("Removing item " + items[j].id);
              $(items[j]).animate({opacity:0}, 1000, function(){ this.remove(); });
            }
          }

          for (; i < data.length; ++i) {
            console.log("Adding item " + data[i].uri);
            var item = make_song_item(data[i]);
            item.animate({ opacity: 1 }, 1000);
            playlist.prepend(item);
          }

          $('#playlist li.active').removeClass('active');
          $(document.getElementById(current)).addClass('active');
        });
      }
    });
  }, 1000);

  $.get('/playlist', function(data) {
    var playlist = $('#playlist');
    for (var i = 0; i < data.length; ++i) {
      var item = make_song_item(data[i]);
      item.css('opacity', 1);
      playlist.prepend(item);
    }
  });
});
