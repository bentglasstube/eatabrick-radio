delete from user;

insert into user (name, salt, pass) values 
  ('alan', 'qEWBTdbFUs+e/c7ATO3deoK+rzc', 'yyh2afn36PGhBbpolbP7w/gVSYc');

delete from song;

insert into song (title, path, last_played) values ('Song 1', '1', 1200000000); 
insert into song (title, path, last_played) values ('Song 2', '2', 1290000000);
insert into song (title, path, last_played) values ('Song 3', '3', 1300000000);
insert into song (title, path, last_played) values ('Song 4', '4', 1301000000);
insert into song (title, path, last_played) values ('Song 5', '5', 1302000000);
insert into song (title, path, last_played) values ('Song 6', '6', 1302100000);
insert into song (title, path, last_played) values ('Song 7', '7', 1302180000);
insert into song (title, path, last_played) values ('Song 8', '8', 1302183000);
insert into song (title, path, last_played) values ('Song 9', '9', 1302183600);

delete from queue;

insert into queue (position, song_id) values (-2, 1);
insert into queue (position, song_id) values (-1, 2);
insert into queue (position, song_id) values (0, 3);
insert into queue (position, song_id) values (1, 4);
insert into queue (position, song_id) values (2, 5);

