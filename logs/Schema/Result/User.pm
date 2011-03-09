package Radio::Schema::Result::User;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

Radio::Schema::Result::User

=cut

__PACKAGE__->table("user");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 name

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=head2 pass

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=head2 salt

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "name",
  { data_type => "text", default_value => "", is_nullable => 0 },
  "pass",
  { data_type => "text", default_value => "", is_nullable => 0 },
  "salt",
  { data_type => "text", default_value => "", is_nullable => 0 },
);
__PACKAGE__->set_primary_key("id");
__PACKAGE__->add_unique_constraint("name_unique", ["name"]);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2011-03-07 18:53:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:jbuJRgiAQD6v4OuzL2geKg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
