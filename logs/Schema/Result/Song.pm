package Radio::Schema::Result::Song;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

Radio::Schema::Result::Song

=cut

__PACKAGE__->table("song");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 title

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=head2 path

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=head2 last_played

  data_type: 'text'
  default_value: '2011-03-07 00:00:00'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "title",
  { data_type => "text", default_value => "", is_nullable => 0 },
  "path",
  { data_type => "text", default_value => "", is_nullable => 0 },
  "last_played",
  {
    data_type     => "text",
    default_value => "2011-03-07 00:00:00",
    is_nullable   => 0,
  },
);
__PACKAGE__->set_primary_key("id");
__PACKAGE__->add_unique_constraint("path_unique", ["path"]);

=head1 RELATIONS

=head2 queues

Type: has_many

Related object: L<Radio::Schema::Result::Queue>

=cut

__PACKAGE__->has_many(
  "queues",
  "Radio::Schema::Result::Queue",
  { "foreign.song_id" => "self.song_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2011-03-07 18:53:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:+3CGUhFOZ+k7Xc8ZR0Ztxg

__PACKAGE__->has_many(queues => 'Radio::Schema::Result::Song');

1;
