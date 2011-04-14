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
  last_played integer not null default 0
);

create table if not exists queue (
  id integer primary key,
  song_id integer not null constraint fk_song_id references song(id),
  position integer not null constraint unique_queue_position unique
);

create table if not exists news (
  id integer primary key,
  author integer not null constraint fk_user_id references user(id),
  posted integer not null default 0,
  body text not null
);

