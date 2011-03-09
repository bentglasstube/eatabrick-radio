create table user (
  id integer primary key,
  name varchar(16) not null default '' constraint unique_user_name unique,
  pass char(27) not null default '',
  salt char(27) not null default ''
);

insert into user (name, salt, pass) values 
  ('alan', 'qEWBTdbFUs+e/c7ATO3deoK+rzc', 'ujUDARh4xQZcXfGCBKz+HjBjCw4');


create table song (
  id integer primary key,
  title varchar(100) not null default '',
  path varchar(255) not null default '' constraint unique_song_path unique, 
  last_played char(19) not null default '2011-03-07 00:00:00'
);

insert into song (title, path) values ('Song ' || abs(random()), random());
insert into song (title, path) values ('Song ' || abs(random()), random());
insert into song (title, path) values ('Song ' || abs(random()), random());
insert into song (title, path) values ('Song ' || abs(random()), random());
insert into song (title, path) values ('Song ' || abs(random()), random());
insert into song (title, path) values ('Song ' || abs(random()), random());
insert into song (title, path) values ('Song ' || abs(random()), random());
insert into song (title, path) values ('Song ' || abs(random()), random());
insert into song (title, path) values ('Song ' || abs(random()), random());
insert into song (title, path) values ('Song ' || abs(random()), random());

create table queue (
  id integer primary key,
  song_id integer not null constraint fk_song_id REFERENCES song(id),
  position integer not null constraint unique_queue_position unique
);

insert into queue (position, song_id) select -2, id from song order by random() limit 1;
insert into queue (position, song_id) select -1, id from song order by random() limit 1;
insert into queue (position, song_id) select 0, id from song order by random() limit 1;
insert into queue (position, song_id) select 1, id from song order by random() limit 1;
insert into queue (position, song_id) select 2, id from song order by random() limit 1;
