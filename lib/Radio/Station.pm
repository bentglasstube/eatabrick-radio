package Radio::Station;

use strict;
use warnings;

use base 'Audio::MPD';

use MP3::Tag;
#use Dancer ':syntax';

sub promote {
  my $class = shift;
  my $object = shift;

  bless $object, $class;
}

sub albums {
  my $self = shift;

  return [map $self->_album($_), sort $self->collection->all_albums];
}

sub album {
  my $self = shift;
  my $uri = shift;

  foreach ($self->collection->all_albums) {
    return $self->_album($_) if _uri($_) eq $uri;
  }

  return undef;
}

sub song {
  my $self = shift;
  my $album_uri = shift;
  my $track = shift;

  if (my $album = $self->album($album_uri)) {
    return $album->{tracks}[$track];
  }

  return undef;
}

sub current {
  my $self = shift;

  return undef unless $self->status->state eq 'play';
  return $self->_song($self->SUPER::current());
}

sub queue {
  my $self = shift;

  return [map $self->_song($_), $self->playlist->as_items];
}

sub enqueue {
  my $self = shift;

  $self->playlist->add(grep {$_} map $_->file, @_);
}

sub random_song {
  my $self = shift;

  my @songs = $self->collection->all_songs;
  return $songs[$#songs * rand];
}

sub updatedb {
  my $self = shift;

  $self->{_albums} = {};
  $self->SUPER::updatedb;
}

sub search {
  my $self = shift;
  my $search = shift;

  return [
    map $self->_song($_),
    $self->collection->songs_with_title_partial($search),
    $self->collection->songs_by_artist_partial($search),
    $self->collection->songs_from_album_partial($search),
  ];
}

sub _uri {
  my $string = lc shift;
  $string =~ s/\s+/_/g;
  $string =~ s/\W//g;
  $string =~ s/^_|_$//g;
  $string =~ s/_+/_/g;

  return $string;
}

sub _album {
  my $self = shift;
  my $title = shift;

  return $title if ref $title;
  return $self->{_albums}{$title} if exists $self->{_albums}{$title};

  # basic information
  my $album = { title => $title, uri => _uri($title) };

  # get song list
  my @songs = $self->collection->songs_from_album($title);

  # get album artist
  $album->{artist} = $songs[0]->artist;

  foreach (@songs) {
    # check for Various Aritsts album
    $album->{artist} = 'Various Artists' unless $album->{artist} eq $_->artist;

    my $song = $self->_song($_, $album);
    $album->{tracks}[$song->{track}] = $song;
  }

  # album art
  my $path = '/var/lib/mpd/music/' . $songs[0]->file;
  if (my $mp3 = MP3::Tag->new($path)) {
    if (my $apic = $mp3->select_id3v2_frame('APIC')) {
      $album->{art} = {
        data => $apic->{_Data},
        type => $apic->{'MIME Type'} || 'image/jpeg',
      };
    }
  } else {
    warn "Error reading $path: $!";
  }

  return $self->{_albums}{$title} = $album; 
}

sub _song {
  my $self = shift;
  my $song = shift;
  my $album = shift;

  return unless $song;

  $song->{track} =~ s/\D.*//g;
  $song->{album} = $album || $self->_album($song->album); 
  $song->{uri} = join('/', $song->{album}{uri}, $song->{track});

  return $song;
}

1;

