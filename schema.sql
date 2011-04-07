create table if not exists user (
  id integer primary key,
  name varchar(16) not null default '' constraint unique_user_name unique,
  pass char(27) not null default '',
  salt char(27) not null default ''
);

create table if not exists song (
  id integer primary key,
  title varchar(100) not null default '',
  path varchar(255) not null default '' constraint unique_song_path unique, 
  last_played char(19) not null default '2011-03-07 00:00:00'
);

create table if not exists queue (
  id integer primary key,
  song_id integer not null constraint fk_song_id REFERENCES song(id),
  position integer not null constraint unique_queue_position unique
);

