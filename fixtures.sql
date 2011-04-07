delete from user;

insert into user (name, salt, pass) values 
  ('alan', 'qEWBTdbFUs+e/c7ATO3deoK+rzc', 'yyh2afn36PGhBbpolbP7w/gVSYc');

delete from song;

insert into song (title, path) values ('Song 1', '1'); 
insert into song (title, path) values ('Song 2', '2');
insert into song (title, path) values ('Song 3', '3');
insert into song (title, path) values ('Song 4', '4');
insert into song (title, path) values ('Song 5', '5');
insert into song (title, path) values ('Song 6', '6');
insert into song (title, path) values ('Song 7', '7');
insert into song (title, path) values ('Song 8', '8');
insert into song (title, path) values ('Song 9', '9');

delete from queue;

insert into queue (position, song_id) values (-2, 1);
insert into queue (position, song_id) values (-1, 2);
insert into queue (position, song_id) values (0, 3);
insert into queue (position, song_id) values (1, 4);
insert into queue (position, song_id) values (2, 5);

